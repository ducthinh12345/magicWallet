import 'package:drift/drift.dart';

import '../capture/pipeline.dart';
import '../data/database.dart';
import '../data/repo.dart';
import 'sheet_io.dart';

const typeLabel = {'expense': 'Chi', 'income': 'Thu', 'transfer': 'Chuyển khoản'};
const sourceLabel = {
  'manual': 'Nhập tay',
  'notification': 'Thông báo',
  'email': 'Email',
  'ocr': 'Biên lai',
  'import': 'Sao kê',
  'recurring': 'Định kỳ',
};

class SchemaMismatch implements Exception {
  final String message;
  SchemaMismatch(this.message);
  @override
  String toString() => message;
}

/// Một dòng mà cả app lẫn Sheet đều đã sửa kể từ lần đồng bộ trước (6.3 bước 4) — người dùng chọn.
class SyncConflict {
  final String id;
  final int row;
  final List<Object?> sheetRow;
  const SyncConflict(this.id, this.row, this.sheetRow);
}

class SyncResult {
  int pushed = 0, pulled = 0, inbox = 0;
  final conflicts = <SyncConflict>[];

  /// Đã từng lên Sheet nhưng nay không còn dòng — có thể bị xoá nhầm (6.3 bước 5).
  final missingOnSheet = <String>[];
}

/// Chặn chèn công thức: chuỗi bắt đầu bằng = + - @ (vd nội dung chuyển khoản do người khác đặt) bị ép thành chữ.
Object? safeCell(Object? v) => v is String && v.isNotEmpty && '=+-@'.contains(v[0]) ? "'$v" : v;

String _fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Đọc ngày từ ô Sheet: "2026-11-11 12:31", "11/11/2026 12:31:00" (en_US) hoặc số serial của Sheets.
DateTime? _parseDate(Object? v) {
  if (v is num) {
    // Serial: số ngày kể từ 30/12/1899, phần lẻ là giờ trong ngày.
    final base = DateTime(1899, 12, 30);
    return base.add(Duration(minutes: (v * 24 * 60).round()));
  }
  final s = '${v ?? ''}'.trim();
  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?').firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4] ?? '0'), int.parse(m[5] ?? '0'));
  }
  m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?').firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m[3]!), int.parse(m[1]!), int.parse(m[2]!), int.parse(m[4] ?? '0'), int.parse(m[5] ?? '0'));
  }
  return null;
}

String _cell(List<Object?> row, int i) {
  final v = i < row.length ? row[i] : null;
  if (v == null) return '';
  if (v is num) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  return v.toString();
}

/// Chữ ký các cột người dùng được sửa: Ngày, Số tiền, Danh mục, Danh mục con, Ghi chú, Thẻ (FNV-1a 32 bit).
String rowSig(List<Object?> row) {
  // Ngày chuẩn hoá trước khi băm: Sheet có thể trả lại định dạng khác với lúc app ghi.
  final d = _parseDate(row.length > 1 ? row[1] : null);
  final s = [
    d == null ? _cell(row, 1) : _fmtDate(d),
    ...[3, 5, 6, 7, 8].map((i) => _cell(row, i)),
  ].join('\u001f');
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16);
}

class SheetsSync {
  final AppDb db;
  final Repo repo;
  final SheetIO io;
  final CapturePipeline? pipeline;
  SheetsSync(this.db, this.repo, this.io, {this.pipeline});

  Future<SyncResult> run({Set<String> whitelist = const {}, bool autoConfirm = false}) async {
    final startedAt = DateTime.now();
    final result = SyncResult();
    await _checkSchema();

    final cats = await repo.allCategories();
    final catById = {for (final c in cats) c.id: c};
    var wallets = {for (final w in await db.select(db.wallets).get()) w.id: w};

    // ---- Kéo về ----
    final sheet = await io.read(tabTxn);
    final rowOf = <String, int>{};
    final valuesOf = <String, List<Object?>>{};
    for (var i = 1; i < sheet.length; i++) {
      final id = _cell(sheet[i], 0);
      if (id.isEmpty) continue;
      rowOf[id] = i + 1;
      valuesOf[id] = sheet[i];
    }

    final logs = await (db.select(db.syncLog)..where((l) => l.entity.equals('transaction'))).get();
    final pending = {
      for (final l in logs)
        if (l.syncedAt == null) l.entityId,
    };
    final everSynced = {
      for (final l in logs)
        if (l.syncedAt != null) l.entityId,
    };

    final locals = {
      for (final t in await (db.select(
        db.transactions,
      )..where((t) => t.id.isIn({...rowOf.keys, ...pending, ...everSynced}))).get())
        t.id: t,
    };

    // Dòng do máy khác (cùng tài khoản Google) ghi lên mà máy này chưa có → nhập về.
    // Bỏ qua id từng đồng bộ rồi mất ở máy này (đã xoá hẳn sau 30 ngày) để không hồi sinh giao dịch đã xoá.
    final createdWallets = <String>{};
    for (final e in valuesOf.entries) {
      if (locals.containsKey(e.key) || everSynced.contains(e.key) || pending.contains(e.key)) continue;
      if (await _importRow(e.key, e.value, cats, wallets, createdWallets)) result.pulled++;
    }
    if (createdWallets.isNotEmpty) {
      await _fixOpeningBalances(createdWallets);
      wallets = {for (final w in await db.select(db.wallets).get()) w.id: w};
    }

    for (final e in valuesOf.entries) {
      final t = locals[e.key];
      if (t == null || t.deletedAt != null) continue;
      final editedOnSheet = _cell(e.value, 11) != rowSig(e.value);
      if (!editedOnSheet) continue;
      if (pending.contains(e.key)) {
        result.conflicts.add(SyncConflict(e.key, rowOf[e.key]!, e.value));
      } else {
        await _applySheetRow(t, e.value, cats);
        pending.add(e.key); // ghi lại để cập nhật chữ ký trên Sheet
        result.pulled++;
      }
    }
    for (final id in everSynced) {
      final t = locals[id];
      if (t != null && t.deletedAt == null && t.status == 'confirmed' && !rowOf.containsKey(id) && !pending.contains(id)) {
        result.missingOnSheet.add(id);
      }
    }

    // ---- Đẩy lên ----
    final conflictIds = {for (final c in result.conflicts) c.id};
    final toPush = pending.difference(conflictIds);
    final fresh = {for (final t in await (db.select(db.transactions)..where((t) => t.id.isIn(toPush))).get()) t.id: t};
    final tagsByTxn = await _tagsFor(toPush);
    final updates = <int, List<Object?>>{};
    final appends = <List<Object?>>[];
    final deletes = <int>[];
    for (final id in toPush) {
      final t = fresh[id];
      // Sheet chỉ chứa giao dịch đã xác nhận; chờ duyệt/bỏ qua mà lỡ có dòng thì gỡ khỏi Sheet.
      if (t == null || t.deletedAt != null || t.status != 'confirmed') {
        if (rowOf[id] != null) deletes.add(rowOf[id]!);
        continue;
      }
      final row = txnRow(t, catById, wallets, tagsByTxn[id] ?? const []);
      if (rowOf[id] != null) {
        updates[rowOf[id]!] = row;
      } else {
        appends.add(row);
      }
    }
    // Ghi đè trước, xoá sau cùng — xoá làm dịch số dòng.
    await io.writeRows(tabTxn, updates);
    await io.append(tabTxn, appends);
    await io.deleteRows(tabTxn, deletes);
    result.pushed = updates.length + appends.length + deletes.length;

    await (db.update(db.syncLog)
          ..where((l) => l.syncedAt.isNull() & l.changedAt.isSmallerOrEqualValue(startedAt) & l.entityId.isNotIn(conflictIds)))
        .write(SyncLogCompanion(syncedAt: Value(DateTime.now())));

    await _writeDerivedTabs(cats, wallets);
    if (pipeline != null) result.inbox = await _pullInbox(whitelist, autoConfirm);
    await io.replaceAll(tabMeta, [
      ['schema_version', schemaVersion],
      ['last_sync', DateTime.now().toIso8601String()],
    ]);
    await db.setSetting('sheets_last_sync', DateTime.now().toIso8601String());
    return result;
  }

  Future<void> _checkSchema() async {
    final meta = await io.read(tabMeta);
    final ver = meta.where((r) => _cell(r, 0) == 'schema_version').map((r) => _cell(r, 1)).firstOrNull;
    if (ver != null && ver != '$schemaVersion') {
      throw SchemaMismatch('Sheet dùng phiên bản cấu trúc $ver, app cần $schemaVersion.');
    }
    final header = await io.read(tabTxn);
    if (header.isEmpty) {
      await io.replaceAll(tabTxn, [txnHeader]);
      return;
    }
    for (var i = 0; i < txnHeader.length; i++) {
      if (_cell(header.first, i) != txnHeader[i]) {
        throw SchemaMismatch(
          'Tab "$tabTxn" đã bị đổi cột ${i + 1} (cần "${txnHeader[i]}"). Hãy khôi phục tiêu đề rồi đồng bộ lại.',
        );
      }
    }
  }

  Future<Map<String, List<String>>> _tagsFor(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final q = db.select(db.transactionTags).join([innerJoin(db.tags, db.tags.id.equalsExp(db.transactionTags.tagId))])
      ..where(db.transactionTags.transactionId.isIn(ids));
    final out = <String, List<String>>{};
    for (final r in await q.get()) {
      (out[r.readTable(db.transactionTags).transactionId] ??= []).add(r.readTable(db.tags).name);
    }
    return out;
  }

  /// Dòng Sheet của một giao dịch; cột cuối là chữ ký để lần sau biết người dùng có sửa tay hay không.
  static List<Object?> txnRow(Txn t, Map<String, Category> cats, Map<String, Wallet> wallets, List<String> tags) {
    final cat = cats[t.categoryId];
    final parent = cat?.parentId == null ? null : cats[cat!.parentId];
    final walletName = t.type == 'transfer'
        ? '${wallets[t.walletId]?.name ?? ''} → ${wallets[t.toWalletId]?.name ?? ''}'
        : wallets[t.walletId]?.name ?? '';
    final row = <Object?>[
      t.id,
      _fmtDate(t.occurredAt),
      typeLabel[t.type],
      t.amount,
      walletName,
      parent?.name ?? cat?.name ?? '',
      parent == null ? '' : cat!.name,
      t.note,
      tags.join(', '),
      sourceLabel[t.source] ?? t.source,
      _fmtDate(t.updatedAt),
    ];
    row.add(rowSig(row));
    return [for (final v in row) safeCell(v)];
  }

  /// Tạo giao dịch từ một dòng Sheet. Ví/danh mục khớp theo tên (mỗi máy có id riêng); thiếu ví thì tạo.
  Future<bool> _importRow(String id, List<Object?> row, List<Category> cats, Map<String, Wallet> wallets, Set<String> created) async {
    final date = _parseDate(row.length > 1 ? row[1] : null);
    final amount = int.tryParse(_cell(row, 3).replaceAll(RegExp(r'[^\d]'), ''));
    final type = typeLabel.entries.where((e) => e.value == _cell(row, 2)).firstOrNull?.key;
    if (date == null || amount == null || amount <= 0 || type == null) return false;

    Future<String> walletId(String name) async {
      final n = name.trim().isEmpty ? 'Ví từ Sheet' : name.trim();
      final w = wallets.values.where((w) => w.name == n && w.deletedAt == null).firstOrNull;
      if (w != null) return w.id;
      final nw = await db.into(db.wallets).insertReturning(WalletsCompanion.insert(name: n, type: 'bank'));
      wallets[nw.id] = nw;
      created.add(nw.id);
      return nw.id;
    }

    final names = _cell(row, 4).split(' → ');
    final from = await walletId(names.first);
    final to = type == 'transfer' && names.length > 1 ? await walletId(names[1]) : null;
    final rootName = _cell(row, 5), subName = _cell(row, 6);
    final root = cats.where((c) => c.parentId == null && c.name == rootName).firstOrNull;
    final sub = root == null ? null : cats.where((c) => c.parentId == root.id && c.name == subName).firstOrNull;
    final source = sourceLabel.entries.where((e) => e.value == _cell(row, 9)).firstOrNull?.key ?? 'manual';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: Value(id),
      walletId: from,
      toWalletId: Value(to),
      type: type,
      amount: amount,
      amountBase: amount,
      categoryId: Value(type == 'transfer' ? null : (sub?.id ?? root?.id)),
      occurredAt: date,
      note: Value(_cell(row, 7)),
      source: Value(source),
    ));
    final tags = _cell(row, 8).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (tags.isNotEmpty) await repo.saveTxn(TransactionsCompanion(id: Value(id)), tags: tags);
    // Đánh dấu đã đồng bộ: dòng đến từ Sheet, không cần đẩy ngược lên.
    await (db.delete(db.syncLog)..where((l) => l.entityId.equals(id))).go();
    await db.into(db.syncLog).insert(SyncLogCompanion.insert(
        entity: 'transaction', entityId: id, op: 'insert', changedAt: DateTime.now(), syncedAt: Value(DateTime.now())));
    return true;
  }

  /// Ví vừa tạo từ Sheet: đặt số dư đầu sao cho số dư app tính khớp cột "Số dư" ở tab Ví.
  Future<void> _fixOpeningBalances(Set<String> walletIds) async {
    final sheetBal = {for (final r in (await io.read(tabWallet)).skip(1)) _cell(r, 0): int.tryParse(_cell(r, 2))};
    final computed = await repo.walletBalances();
    for (final id in walletIds) {
      final w = await (db.select(db.wallets)..where((x) => x.id.equals(id))).getSingle();
      final target = sheetBal[w.name];
      if (target == null) continue;
      await (db.update(db.wallets)..where((x) => x.id.equals(id)))
          .write(WalletsCompanion(openingBalance: Value(target - (computed[id] ?? 0))));
    }
  }

  Future<void> _applySheetRow(Txn t, List<Object?> row, List<Category> cats) async {
    final date = _parseDate(row.length > 1 ? row[1] : null);
    final amount = int.tryParse(_cell(row, 3).replaceAll(RegExp(r'[^\d]'), ''));
    final rootName = _cell(row, 5), subName = _cell(row, 6);
    final root = cats.where((c) => c.parentId == null && c.name == rootName).firstOrNull;
    final sub = root == null ? null : cats.where((c) => c.parentId == root.id && c.name == subName).firstOrNull;
    final catId = sub?.id ?? root?.id;
    await repo.saveTxn(
      TransactionsCompanion(
        id: Value(t.id),
        occurredAt: date == null ? const Value.absent() : Value(date),
        amount: amount == null || amount <= 0 ? const Value.absent() : Value(amount),
        categoryId: t.type == 'transfer' || catId == null ? const Value.absent() : Value(catId),
        note: Value(_cell(row, 7)),
      ),
      tags: _cell(row, 8).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    );
  }

  /// Người dùng chọn bản nào thắng cho một dòng xung đột.
  Future<void> resolveConflict(SyncConflict c, {required bool keepApp}) async {
    final t = await (db.select(db.transactions)..where((x) => x.id.equals(c.id))).getSingle();
    if (keepApp) {
      final cats = {for (final x in await repo.allCategories()) x.id: x};
      final wallets = {for (final w in await db.select(db.wallets).get()) w.id: w};
      await io.writeRows(tabTxn, {
        c.row: txnRow(t, cats, wallets, (await _tagsFor({c.id}))[c.id] ?? const []),
      });
      await (db.update(
        db.syncLog,
      )..where((l) => l.entityId.equals(c.id) & l.syncedAt.isNull())).write(SyncLogCompanion(syncedAt: Value(DateTime.now())));
    } else {
      await (db.update(
        db.syncLog,
      )..where((l) => l.entityId.equals(c.id) & l.syncedAt.isNull())).write(SyncLogCompanion(syncedAt: Value(DateTime.now())));
      await _applySheetRow(t, c.sheetRow, await repo.allCategories()); // tạo log mới → lần sau đẩy chữ ký mới
    }
  }

  Future<void> _writeDerivedTabs(List<Category> cats, Map<String, Wallet> wallets) async {
    final balances = await repo.walletBalances();
    await io.replaceAll(tabWallet, [
      ['Tên', 'Loại', 'Số dư', '4 số cuối', 'Lưu trữ'],
      for (final w in wallets.values.where((w) => w.deletedAt == null))
        [safeCell(w.name), w.type, balances[w.id] ?? 0, w.accountLast4 ?? '', w.archived ? 'Có' : ''],
    ]);
    final byId = {for (final c in cats) c.id: c};
    await io.replaceAll(tabCategory, [
      ['Tên', 'Loại', 'Danh mục cha', 'Icon', 'Chi cố định'],
      for (final c in cats)
        [safeCell(c.name), c.type == 'expense' ? 'Chi' : 'Thu', byId[c.parentId]?.name ?? '', c.icon, c.isFixedCost ? 'Có' : ''],
    ]);
    final budgets = await (db.select(db.budgets)..where((b) => b.deletedAt.isNull())).get();
    await io.replaceAll(tabBudget, [
      ['Danh mục', 'Kỳ', 'Số tiền', 'Chuyển dư'],
      for (final b in budgets) [byId[b.categoryId]?.name ?? 'Tổng', b.period, b.amount, b.rollover ? 'Có' : ''],
    ]);
    // Tổng hợp chi theo danh mục gốc × tháng của năm hiện tại, bằng SUMIFS để Sheet tự tính lại khi sửa tay.
    final y = DateTime.now().year;
    final roots = cats.where((c) => c.parentId == null && c.type == 'expense').toList();
    String sumifs(int row, int m) =>
        "=SUMIFS('$tabTxn'!D:D,'$tabTxn'!F:F,\$A$row,'$tabTxn'!C:C,\"Chi\","
        "'$tabTxn'!B:B,\">=\"&DATE($y,$m,1),'$tabTxn'!B:B,\"<\"&DATE($y,${m + 1},1))";
    await io.replaceAll(tabSummary, [
      ['Danh mục', for (var m = 1; m <= 12; m++) 'T$m/$y', 'Cả năm'],
      for (var i = 0; i < roots.length; i++)
        [safeCell(roots[i].name), for (var m = 1; m <= 12; m++) sumifs(i + 2, m), '=SUM(B${i + 2}:M${i + 2})'],
    ]);
  }

  /// Email hoá đơn do Apps Script ghi vào tab "Hộp thư" (S3 phương án A) → hàng chờ duyệt.
  Future<int> _pullInbox(Set<String> whitelist, bool autoConfirm) async {
    final rows = await io.read(tabInbox);
    final done = <int, List<Object?>>{};
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (_cell(r, 4).isNotEmpty || _cell(r, 3).isEmpty) continue;
      await pipeline!.ingest(
        RawInput(
          source: 'email',
          package: 'email',
          title: _cell(r, 1),
          text: '${_cell(r, 2)}\n${_cell(r, 3)}',
          receivedAt: _parseDate(r.isNotEmpty ? r[0] : null) ?? DateTime.now(),
        ),
        whitelist: whitelist,
        autoConfirmEnabled: autoConfirm,
      );
      done[i + 1] = [...List<Object?>.generate(4, (k) => safeCell(_cell(r, k))), 'x'];
    }
    await io.writeRows(tabInbox, done);
    return done.length;
  }
}
