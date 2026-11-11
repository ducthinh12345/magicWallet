import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/repo.dart';
import 'classifier.dart';
import 'parser.dart';
import 'statement_import.dart';

/// Sự kiện thô từ một nguồn bất kỳ (S1–S7).
class RawInput {
  final String source; // notification / email / import / ...
  final String package; // tên gói Android, hoặc 'email' / 'import'
  final String title;
  final String text;
  final DateTime receivedAt;
  const RawInput({required this.source, required this.package, this.title = '', required this.text, required this.receivedAt});
}

/// Kết quả xử lý để UI/thông báo nói cho người dùng biết.
sealed class IngestOutcome {}

class Created extends IngestOutcome {
  final String txnId;
  final bool autoConfirmed;
  Created(this.txnId, this.autoConfirmed);
}

class MergedDuplicate extends IngestOutcome {
  final String txnId;
  MergedDuplicate(this.txnId);
}

class PairedTransfer extends IngestOutcome {
  final String txnId;
  PairedTransfer(this.txnId);
}

class Skipped extends IngestOutcome {
  final String reason; // not_whitelisted / sensitive / unknown / no_wallet
  Skipped(this.reason);
}

const _dedupeWindow = Duration(minutes: 5);

class CapturePipeline {
  final AppDb db;
  final Repo repo;
  final InstitutionCatalog catalog;
  CapturePipeline(this.db, this.repo, this.catalog);

  Future<IngestOutcome> ingest(RawInput input, {required Set<String> whitelist, bool autoConfirmEnabled = false}) async {
    // US-02 AC1: chỉ app trong whitelist. Email/nhập file đã do người dùng chủ động chọn.
    if (input.source == 'notification' && !whitelist.contains(input.package)) return Skipped('not_whitelisted');

    final inst = catalog.identify(input.package, input.title);
    final text = input.title.isEmpty ? input.text : '${input.title}\n${input.text}';
    final result = parseNotification(text, inst: inst);
    if (result is DroppedSensitive) return Skipped('sensitive'); // không lưu gì cả

    final rawId = newId();
    Future<void> saveRaw(String status) => db
        .into(db.rawEvents)
        .insert(
          RawEventsCompanion.insert(
            id: Value(rawId),
            source: input.source,
            sourceApp: Value(input.package),
            receivedAt: input.receivedAt,
            content: text,
            parseStatus: status,
            expiresAt: input.receivedAt.add(const Duration(days: 30)),
          ),
        );

    if (result is! Parsed) {
      await saveRaw('unknown'); // 5.4: lưu "Chưa xác định" để người dùng tự điền
      return Skipped('unknown');
    }
    final p = result.txn;

    final wallet = await _matchWallet(p.last4, inst);
    if (wallet == null) {
      await saveRaw('unknown');
      return Skipped('no_wallet');
    }

    // Chống trùng / ghép cặp (mục 5.2 bước 5 và quy tắc ví điện tử 5.5).
    final dup = await _dedupe(p, wallet, input.receivedAt);
    if (dup != null) {
      await saveRaw('duplicate');
      return dup;
    }

    final type = p.direction > 0 ? 'income' : 'expense';
    final text4class = [p.merchant ?? '', p.content].where((s) => s.isNotEmpty).join(' ');
    // Hoàn tiền: ghi là thu nhưng thuộc danh mục chi gốc, báo cáo trừ vào chi (5.4).
    final cls = classify(
      text: text4class,
      type: p.isRefund ? 'expense' : type,
      rules: await db.select(db.classificationRules).get(),
      categories: await repo.allCategories(),
      history: await _history(),
      walletId: wallet.id,
    );
    final confidence = p.confidence < cls.confidence ? p.confidence : cls.confidence;
    final auto = autoConfirmEnabled && confidence >= 0.95;

    await saveRaw('parsed');
    final id = await repo.saveTxn(
      TransactionsCompanion.insert(
        walletId: wallet.id,
        type: type,
        amount: p.amount,
        amountBase: p.amount,
        categoryId: Value(cls.categoryId),
        occurredAt: input.receivedAt,
        note: Value(p.content),
        merchant: Value(p.merchant),
        status: Value(auto ? 'confirmed' : 'pending'),
        source: Value(input.source),
        rawEventId: Value(rawId),
        confidence: Value(confidence),
      ),
    );

    if (p.balance != null) await _checkBalance(wallet.id, p.balance!, auto ? 0 : p.direction * p.amount);
    return Created(id, auto);
  }

  Future<Wallet?> _matchWallet(String? last4, Institution? inst) async {
    final wallets = await (db.select(db.wallets)..where((w) => w.deletedAt.isNull() & w.archived.equals(false))).get();
    if (last4 != null) {
      final m = wallets.where((w) => w.accountLast4 == last4).toList();
      if (m.length == 1) return m.first;
      final sameInst = m.where((w) => _instOf(w)?.id == inst?.id).firstOrNull;
      if (sameInst != null) return sameInst;
    }
    if (inst != null) return wallets.where((w) => _instOf(w)?.id == inst.id).firstOrNull;
    return null;
  }

  Institution? _instOf(Wallet w) => w.sourceAppPackage == null ? null : catalog.identify(w.sourceAppPackage!, '');

  Future<IngestOutcome?> _dedupe(ParsedTxn p, Wallet wallet, DateTime at) async {
    final near =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.status.isIn(['pending', 'confirmed']) &
                  t.amount.equals(p.amount) &
                  t.occurredAt.isBetweenValues(at.subtract(_dedupeWindow), at.add(_dedupeWindow)),
            ))
            .get();
    final dir = p.direction > 0 ? 'income' : 'expense';
    for (final t in near) {
      if (t.walletId == wallet.id && t.type == dir) {
        // Cùng giao dịch đến từ 2 nguồn (vd SMS + thông báo): giữ bản nhiều thông tin hơn.
        await _enrich(t, p);
        return MergedDuplicate(t.id);
      }
      if (t.walletId == wallet.id || t.type == 'transfer') continue;
      final other = await (db.select(db.wallets)..where((w) => w.id.equals(t.walletId))).getSingleOrNull();
      if (other == null) continue;
      final kinds = {other.type, wallet.type};
      if (t.type != dir) {
        // Nạp/rút ví: ngân hàng trừ + ví cộng (hoặc ngược lại) → một chuyển khoản (BR-01).
        final from = dir == 'expense' ? wallet.id : t.walletId;
        final to = dir == 'expense' ? t.walletId : wallet.id;
        await repo.saveTxn(
          TransactionsCompanion(
            id: Value(t.id),
            walletId: Value(from),
            toWalletId: Value(to),
            type: const Value('transfer'),
            categoryId: const Value(null),
            note: Value(t.note.isEmpty ? 'Chuyển giữa ví' : t.note),
          ),
        );
        return PairedTransfer(t.id);
      }
      if (kinds.contains('ewallet') && kinds.difference({'ewallet'}).isNotEmpty) {
        // Thanh toán qua ví liên kết thẳng ngân hàng: chi ghi ở ví ngân hàng, thông báo ví chỉ bổ sung tên nhà bán.
        if (wallet.type != 'ewallet') {
          await repo.saveTxn(TransactionsCompanion(id: Value(t.id), walletId: Value(wallet.id)));
        }
        await _enrich(t, p);
        return MergedDuplicate(t.id);
      }
    }
    return null;
  }

  Future<void> _enrich(Txn t, ParsedTxn p) async {
    final better = (t.merchant == null && p.merchant != null) || (t.note.length < p.content.length);
    if (!better) return;
    await repo.saveTxn(
      TransactionsCompanion(
        id: Value(t.id),
        merchant: Value(t.merchant ?? p.merchant),
        note: Value(t.note.length >= p.content.length ? t.note : p.content),
      ),
    );
  }

  Future<List<LearnedSample>> _history() async {
    final rows =
        await (db.select(db.transactions)
              ..where((t) => t.status.equals('confirmed') & t.categoryId.isNotNull() & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
              ..limit(2000))
            .get();
    return [
      for (final r in rows)
        if ('${r.merchant ?? ''} ${r.note}'.trim().isNotEmpty) LearnedSample('${r.merchant ?? ''} ${r.note}', r.categoryId!),
    ];
  }

  /// S5: nhập sao kê vào một ví đã chọn. Chỉ thêm dòng còn thiếu (cùng ví, cùng ngày, cùng số tiền, cùng chiều
  /// coi như đã có) — sao kê dùng để đối soát và lấp chỗ trống. Trả về số giao dịch chờ duyệt đã tạo.
  Future<int> importStatement(List<StatementRow> rows, String walletId) async {
    final rules = await db.select(db.classificationRules).get();
    final cats = await repo.allCategories();
    final history = await _history();
    var created = 0;
    await db.transaction(() async {
      for (final r in rows) {
        final type = r.direction > 0 ? 'income' : 'expense';
        final day = DateTime(r.date.year, r.date.month, r.date.day);
        final exists =
            await (db.select(db.transactions)
                  ..where(
                    (t) =>
                        t.deletedAt.isNull() &
                        t.status.isIn(['pending', 'confirmed']) &
                        t.amount.equals(r.amount) &
                        (t.walletId.equals(walletId) | t.toWalletId.equals(walletId)) &
                        t.occurredAt.isBetweenValues(day, day.add(const Duration(hours: 23, minutes: 59, seconds: 59))),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (exists != null) continue;
        final cls = classify(
          text: r.description,
          type: type,
          rules: rules,
          categories: cats,
          history: history,
          walletId: walletId,
        );
        await repo.saveTxn(
          TransactionsCompanion.insert(
            walletId: walletId,
            type: type,
            amount: r.amount,
            amountBase: r.amount,
            categoryId: Value(cls.categoryId),
            occurredAt: r.date,
            note: Value(r.description),
            status: const Value('pending'),
            source: const Value('import'),
            confidence: Value(cls.confidence),
          ),
        );
        created++;
      }
    });
    return created;
  }

  /// 5.4: số dư ngân hàng báo lệch số dư app tính → lưu gợi ý đối soát, UI hiện cảnh báo.
  Future<void> _checkBalance(String walletId, int reported, int pendingDelta) async {
    final computed = ((await repo.walletBalances())[walletId] ?? 0) + pendingDelta;
    final key = 'reconcile_hint:$walletId';
    if (computed != reported) {
      await db.setSetting(key, '$reported');
    } else {
      await (db.delete(db.settings)..where((s) => s.key.equals(key))).go();
    }
  }
}
