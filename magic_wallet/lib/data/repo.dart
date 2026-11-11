import 'package:drift/drift.dart';

import 'database.dart';

/// Mọi thao tác ghi đi qua đây để luôn ghi kèm nhật ký thay đổi (mục 6.3 bước 1).
class Repo {
  final AppDb db;
  Repo(this.db);

  Future<void> _log(String entity, String id, String op) =>
      db.into(db.syncLog).insert(SyncLogCompanion.insert(entity: entity, entityId: id, op: op, changedAt: DateTime.now()));

  // ---------------- Giao dịch ----------------

  /// Thêm hoặc sửa giao dịch. `tags` là tên thẻ; null = giữ nguyên.
  Future<String> saveTxn(TransactionsCompanion t, {List<String>? tags}) {
    return db.transaction(() async {
      final isNew = !t.id.present;
      final id = isNew ? newId() : t.id.value;
      var row = t.copyWith(id: Value(id), updatedAt: Value(DateTime.now()));
      if (t.amount.present && !t.amountBase.present) {
        // Số quy đổi = số gốc × tỷ giá (BR-06); UI v1 chỉ VND nên tỷ giá = 1.
        row = row.copyWith(amountBase: Value((t.amount.value * (t.fxRate.present ? t.fxRate.value : 1)).round()));
      }
      if (isNew) {
        await db.into(db.transactions).insert(row);
      } else {
        // Sửa một phần: chỉ ghi các cột có mặt trong companion.
        await (db.update(db.transactions)..where((x) => x.id.equals(id))).write(row);
      }
      if (tags != null) await _setTags(id, tags);
      await _log('transaction', id, isNew ? 'insert' : 'update');
      return id;
    });
  }

  Future<void> _setTags(String txnId, List<String> names) async {
    await (db.delete(db.transactionTags)..where((x) => x.transactionId.equals(txnId))).go();
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      var tag = await (db.select(db.tags)..where((x) => x.name.equals(name))).getSingleOrNull();
      tag ??= await db.into(db.tags).insertReturning(TagsCompanion.insert(name: name));
      await db
          .into(db.transactionTags)
          .insertOnConflictUpdate(TransactionTagsCompanion.insert(transactionId: txnId, tagId: tag.id));
    }
  }

  Future<List<String>> tagsOf(String txnId) async {
    final q = db.select(db.tags).join([innerJoin(db.transactionTags, db.transactionTags.tagId.equalsExp(db.tags.id))])
      ..where(db.transactionTags.transactionId.equals(txnId));
    return (await q.get()).map((r) => r.readTable(db.tags).name).toList();
  }

  Future<void> _touch(String id, TransactionsCompanion c) async {
    await (db.update(db.transactions)..where((x) => x.id.equals(id))).write(c.copyWith(updatedAt: Value(DateTime.now())));
    await _log('transaction', id, c.deletedAt.present && c.deletedAt.value != null ? 'delete' : 'update');
  }

  /// Xoá mềm 30 ngày để đồng bộ và hoàn tác (BR-07).
  Future<void> deleteTxn(String id) => _touch(id, TransactionsCompanion(deletedAt: Value(DateTime.now())));
  Future<void> undoDeleteTxn(String id) => _touch(id, const TransactionsCompanion(deletedAt: Value(null)));
  Future<void> setStatus(String id, String status) => _touch(id, TransactionsCompanion(status: Value(status)));

  Future<void> confirmAllPending() async {
    final ids =
        await (db.selectOnly(db.transactions)
              ..addColumns([db.transactions.id])
              ..where(db.transactions.status.equals('pending') & db.transactions.deletedAt.isNull()))
            .map((r) => r.read(db.transactions.id)!)
            .get();
    await db.transaction(() async {
      for (final id in ids) {
        await setStatus(id, 'confirmed');
      }
    });
  }

  /// Giao dịch "thật" — đưa vào báo cáo và số dư: đã xác nhận, chưa xoá.
  Expression<bool> _live($TransactionsTable t) => t.status.equals('confirmed') & t.deletedAt.isNull();

  Future<List<Txn>> confirmedBetween(DateTime from, DateTime to) => (db.select(
    db.transactions,
  )..where((t) => _live(t) & t.occurredAt.isBiggerOrEqualValue(from) & t.occurredAt.isSmallerThanValue(to))).get();

  Stream<List<Txn>> watchPending() =>
      (db.select(db.transactions)
            ..where((t) => t.status.equals('pending') & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch();

  /// Danh sách giao dịch (SC-05), lọc theo chuỗi tìm kiếm trên ghi chú/nhà bán.
  Stream<List<Txn>> watchTxns({String search = '', String? walletId, String? categoryId, int limit = 200}) {
    final q = db.select(db.transactions)
      ..where((t) {
        var e = _live(t);
        if (search.isNotEmpty) e = e & (t.note.contains(search) | t.merchant.contains(search));
        if (walletId != null) e = e & (t.walletId.equals(walletId) | t.toWalletId.equals(walletId));
        if (categoryId != null) e = e & t.categoryId.equals(categoryId);
        return e;
      })
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
      ..limit(limit);
    return q.watch();
  }

  // ---------------- Ví ----------------

  Future<String> saveWallet(WalletsCompanion w) async {
    final id = w.id.present ? w.id.value : newId();
    final row = w.copyWith(id: Value(id), updatedAt: Value(DateTime.now()));
    if (w.id.present) {
      await (db.update(db.wallets)..where((x) => x.id.equals(id))).write(row);
    } else {
      await db.into(db.wallets).insert(row);
    }
    await _log('wallet', id, w.id.present ? 'update' : 'insert');
    return id;
  }

  Stream<List<Wallet>> watchWallets() =>
      (db.select(db.wallets)
            ..where((w) => w.deletedAt.isNull())
            ..orderBy([(w) => OrderingTerm.asc(w.createdAt)]))
          .watch();

  /// Số dư = số dư đầu + thu − chi ± chuyển khoản. Chỉ tính giao dịch đã xác nhận.
  Future<Map<String, int>> walletBalances() async {
    final wallets = await (db.select(db.wallets)..where((w) => w.deletedAt.isNull())).get();
    final bal = {for (final w in wallets) w.id: w.openingBalance};
    final rows = await db.customSelect('''
      SELECT wallet_id, to_wallet_id, type, SUM(amount_base) AS s FROM transactions
      WHERE status = 'confirmed' AND deleted_at IS NULL
      GROUP BY wallet_id, to_wallet_id, type''').get();
    for (final r in rows) {
      final w = r.read<String>('wallet_id');
      final to = r.readNullable<String>('to_wallet_id');
      final s = r.read<int>('s');
      switch (r.read<String>('type')) {
        case 'income':
          bal[w] = (bal[w] ?? 0) + s;
        case 'expense':
          bal[w] = (bal[w] ?? 0) - s;
        case 'transfer':
          bal[w] = (bal[w] ?? 0) - s;
          if (to != null) bal[to] = (bal[to] ?? 0) + s;
      }
    }
    return bal;
  }

  /// Phát lại mỗi khi bảng giao dịch/ví đổi.
  Stream<Map<String, int>> watchBalances() => db
      .tableUpdates(TableUpdateQuery.onAllTables([db.transactions, db.wallets]))
      .asyncMap((_) => walletBalances())
      .startWith(walletBalances());

  /// Đối soát (SC-08): nhập số dư thực tế → giao dịch điều chỉnh bằng phần chênh.
  Future<String?> reconcile(String walletId, int actual) async {
    final current = (await walletBalances())[walletId] ?? 0;
    final diff = actual - current;
    if (diff == 0) return null;
    return saveTxn(
      TransactionsCompanion.insert(
        walletId: walletId,
        type: diff > 0 ? 'income' : 'expense',
        amount: diff.abs(),
        amountBase: diff.abs(),
        occurredAt: DateTime.now(),
        note: const Value('Điều chỉnh số dư'),
      ),
    );
  }

  Future<String?> lastUsedWalletId() async {
    final t =
        await (db.select(db.transactions)
              ..where((t) => t.deletedAt.isNull() & t.source.equals('manual'))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (t != null) return t.walletId;
    return (await (db.select(db.wallets)
              ..where((w) => w.deletedAt.isNull() & w.archived.equals(false))
              ..limit(1))
            .getSingleOrNull())
        ?.id;
  }

  // ---------------- Danh mục ----------------

  Stream<List<Category>> watchCategories() =>
      (db.select(db.categories)
            ..where((c) => c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
          .watch();

  Future<List<Category>> allCategories() =>
      (db.select(db.categories)
            ..where((c) => c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
          .get();

  Future<String> saveCategory(CategoriesCompanion c) async {
    final id = c.id.present ? c.id.value : newId();
    final row = c.copyWith(id: Value(id), updatedAt: Value(DateTime.now()));
    if (c.id.present) {
      await (db.update(db.categories)..where((x) => x.id.equals(id))).write(row);
    } else {
      await db.into(db.categories).insert(row);
    }
    await _log('category', id, c.id.present ? 'update' : 'insert');
    return id;
  }

  /// Gộp danh mục (M03): chuyển mọi giao dịch, quy tắc, ngân sách sang `intoId` rồi xoá mềm `fromId`.
  Future<void> mergeCategory(String fromId, String intoId) => db.transaction(() async {
    final ids =
        await (db.selectOnly(db.transactions)
              ..addColumns([db.transactions.id])
              ..where(db.transactions.categoryId.equals(fromId)))
            .map((r) => r.read(db.transactions.id)!)
            .get();
    for (final id in ids) {
      await _touch(id, TransactionsCompanion(categoryId: Value(intoId)));
    }
    await (db.update(
      db.classificationRules,
    )..where((r) => r.categoryId.equals(fromId))).write(ClassificationRulesCompanion(categoryId: Value(intoId)));
    await (db.update(db.budgets)..where((r) => r.categoryId.equals(fromId))).write(BudgetsCompanion(categoryId: Value(intoId)));
    await (db.update(db.categories)..where((c) => c.parentId.equals(fromId))).write(CategoriesCompanion(parentId: Value(intoId)));
    await saveCategory(CategoriesCompanion(id: Value(fromId), deletedAt: Value(DateTime.now())));
  });

  /// US-01 AC2: 5 danh mục dùng nhiều nhất trong khung ±1 giờ quanh giờ hiện tại (90 ngày gần nhất).
  Future<List<String>> suggestedCategoryIds(String type, DateTime now) async {
    final rows = await db
        .customSelect(
          '''
      SELECT category_id, COUNT(*) AS n FROM transactions
      WHERE type = ? AND category_id IS NOT NULL AND deleted_at IS NULL AND status = 'confirmed'
        AND occurred_at >= ?
        AND ABS(CAST(strftime('%H', occurred_at, 'unixepoch', 'localtime') AS INTEGER) - ?) <= 1
      GROUP BY category_id ORDER BY n DESC LIMIT 5''',
          variables: [
            Variable.withString(type),
            Variable.withDateTime(now.subtract(const Duration(days: 90))),
            Variable.withInt(now.hour),
          ],
        )
        .get();
    return rows.map((r) => r.read<String>('category_id')).toList();
  }

  // ---------------- Ngân sách ----------------

  Stream<List<Budget>> watchBudgets() => (db.select(db.budgets)..where((b) => b.deletedAt.isNull())).watch();

  Future<String> saveBudget(BudgetsCompanion b) async {
    final id = b.id.present ? b.id.value : newId();
    final row = b.copyWith(id: Value(id), updatedAt: Value(DateTime.now()));
    if (b.id.present) {
      await (db.update(db.budgets)..where((x) => x.id.equals(id))).write(row);
    } else {
      await db.into(db.budgets).insert(row);
    }
    await _log('budget', id, b.id.present ? 'update' : 'insert');
    return id;
  }

  // ---------------- Định kỳ (S7) ----------------

  /// Sinh giao dịch chờ duyệt cho mọi quy tắc đến hạn; bù cả các kỳ bị lỡ khi app không mở.
  Future<int> runRecurring(DateTime now) async {
    var created = 0;
    final rules = await (db.select(
      db.recurringRules,
    )..where((r) => r.deletedAt.isNull() & r.nextRunAt.isSmallerOrEqualValue(now))).get();
    for (final r in rules) {
      var next = r.nextRunAt;
      while (!next.isAfter(now)) {
        await saveTxn(
          TransactionsCompanion.insert(
            walletId: r.walletId,
            type: r.type,
            amount: r.amount,
            amountBase: r.amount,
            categoryId: Value(r.categoryId),
            occurredAt: next,
            note: Value(r.note),
            source: const Value('recurring'),
            status: Value(r.autoConfirm ? 'confirmed' : 'pending'),
            confidence: const Value(1),
          ),
        );
        created++;
        next = nextOccurrence(r.rrule, next);
      }
      await (db.update(db.recurringRules)..where((x) => x.id.equals(r.id))).write(
        RecurringRulesCompanion(nextRunAt: Value(next), updatedAt: Value(DateTime.now())),
      );
    }
    return created;
  }

  // ---------------- Dọn dẹp ----------------

  /// Xoá hẳn: nội dung thô quá 30 ngày (US-02 AC4) và giao dịch xoá mềm quá 30 ngày (BR-07).
  Future<void> purgeExpired(DateTime now) async {
    await (db.delete(db.rawEvents)..where((e) => e.expiresAt.isSmallerThanValue(now))).go();
    final cutoff = now.subtract(const Duration(days: 30));
    final old = db.transactions.deletedAt.isSmallerThanValue(cutoff);
    final ids =
        await (db.selectOnly(db.transactions)
              ..addColumns([db.transactions.id])
              ..where(old))
            .map((r) => r.read(db.transactions.id)!)
            .get();
    if (ids.isEmpty) return;
    await (db.delete(db.transactionTags)..where((x) => x.transactionId.isIn(ids))).go();
    await (db.delete(db.transactions)..where((t) => t.id.isIn(ids))).go();
  }
}

/// shortcut: chỉ hiểu FREQ=DAILY|WEEKLY|MONTHLY|YEARLY và INTERVAL; ngày 31 bị kẹp rồi trôi (31/1→28/2→28/3).
/// Cần BYDAY/BYMONTHDAY/COUNT thì thay bằng thư viện rrule.
DateTime nextOccurrence(String rrule, DateTime from) {
  final parts = {
    for (final p in rrule.split(';'))
      if (p.contains('=')) p.split('=')[0].toUpperCase(): p.split('=')[1].toUpperCase(),
  };
  final n = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
  switch (parts['FREQ']) {
    case 'DAILY':
      return DateTime(from.year, from.month, from.day + n, from.hour, from.minute);
    case 'WEEKLY':
      return DateTime(from.year, from.month, from.day + 7 * n, from.hour, from.minute);
    case 'YEARLY':
      return DateTime(from.year + n, from.month, from.day, from.hour, from.minute);
    case 'MONTHLY':
    default:
      // Giữ ngày trong tháng, kẹp về cuối tháng nếu tháng đích ngắn hơn.
      final last = DateTime(from.year, from.month + n + 1, 0).day;
      return DateTime(from.year, from.month + n, from.day > last ? last : from.day, from.hour, from.minute);
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(Future<T> first) async* {
    yield await first;
    yield* this;
  }
}
