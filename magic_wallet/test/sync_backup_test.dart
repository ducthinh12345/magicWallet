import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_wallet/data/database.dart';
import 'package:magic_wallet/data/repo.dart';
import 'package:magic_wallet/sync/backup.dart';
import 'package:magic_wallet/sync/sheet_io.dart';
import 'package:magic_wallet/sync/sheets_sync.dart';

/// Sheet giả trong bộ nhớ, mô phỏng hành vi đọc/ghi theo số dòng.
class FakeSheet implements SheetIO {
  final tabs = <String, List<List<Object?>>>{};
  int writeCalls = 0;
  List<List<Object?>> tab(String t) => tabs.putIfAbsent(t, () => []);

  @override
  Future<List<List<Object?>>> read(String t) async => [
    for (final r in tab(t)) [...r],
  ];
  @override
  Future<void> writeRows(String t, Map<int, List<Object?>> rows) async {
    if (rows.isNotEmpty) writeCalls++;
    rows.forEach((n, v) {
      while (tab(t).length < n) {
        tab(t).add([]);
      }
      // USER_ENTERED: dấu ' đầu chuỗi chỉ để ép thành chữ, đọc lại không còn.
      tab(t)[n - 1] = [for (final c in v) c is String && c.startsWith("'") ? c.substring(1) : c];
    });
  }

  @override
  Future<void> append(String t, List<List<Object?>> rows) async {
    if (rows.isNotEmpty) writeCalls++;
    tab(t).addAll([
      for (final v in rows) [for (final c in v) c is String && c.startsWith("'") ? c.substring(1) : c],
    ]);
  }

  @override
  Future<void> deleteRows(String t, List<int> rowNumbers) async {
    for (final n in [...rowNumbers]..sort((a, b) => b.compareTo(a))) {
      tab(t).removeAt(n - 1);
    }
  }

  @override
  Future<void> replaceAll(String t, List<List<Object?>> rows) async => tabs[t] = [
    for (final r in rows) [...r],
  ];
}

void main() {
  late AppDb db;
  late Repo repo;
  late FakeSheet sheet;
  late SheetsSync sync;
  late String w;

  setUp(() async {
    db = AppDb(NativeDatabase.memory());
    repo = Repo(db);
    sheet = FakeSheet();
    sync = SheetsSync(db, repo, sheet);
    w = await repo.saveWallet(WalletsCompanion.insert(name: 'Tiền mặt', type: 'cash', openingBalance: const Value(1000000)));
  });
  tearDown(() => db.close());

  Future<String> add(int amount, {String note = ''}) => repo.saveTxn(
    TransactionsCompanion.insert(
      walletId: w,
      type: 'expense',
      amount: amount,
      amountBase: amount,
      occurredAt: DateTime(2026, 11, 11, 12, 30),
      note: Value(note),
    ),
  );

  int rowOf(String id) => sheet.tab(tabTxn).indexWhere((r) => r.isNotEmpty && r[0] == id) + 1;

  test('đẩy giao dịch mới, tab phụ, _meta; lần 2 không ghi lại gì', () async {
    final id = await add(45000, note: '=IMPORTXML("http://x")');
    final r = await sync.run();
    expect(r.pushed, 1);
    final row = sheet.tab(tabTxn)[rowOf(id) - 1];
    expect(row.sublist(0, 4), [id, '2026-11-11 12:30', 'Chi', 45000]);
    expect(row[7], '=IMPORTXML("http://x")'); // trên Sheet là chữ, không phải công thức (FakeSheet đã bỏ dấu ')
    expect(SheetsSync.txnRow((await db.select(db.transactions).get()).single, {}, {}, [])[7], startsWith("'="));
    expect(sheet.tab(tabWallet)[1].sublist(0, 3), ['Tiền mặt', 'cash', 1000000 - 45000]);
    expect(sheet.tab(tabMeta).first, ['schema_version', 1]);
    expect(sheet.tab(tabSummary).first.length, 14);

    final before = sheet.writeCalls;
    final r2 = await sync.run();
    expect((r2.pushed, r2.pulled, sheet.writeCalls), (0, 0, before));
  });

  test('sửa tay trên Sheet được kéo về (US-04 AC3)', () async {
    final id = await add(45000);
    await sync.run();
    final row = sheet.tab(tabTxn)[rowOf(id) - 1];
    row[3] = 50000;
    row[5] = 'Ăn uống';
    row[6] = 'Cà phê';
    row[8] = 'công việc, khách';
    final r = await sync.run();
    expect(r.pulled, 1);
    final t = await (db.select(db.transactions)..where((x) => x.id.equals(id))).getSingle();
    final cats = await repo.allCategories();
    expect((t.amount, cats.firstWhere((c) => c.id == t.categoryId).name), (50000, 'Cà phê'));
    expect(await repo.tagsOf(id), unorderedEquals(['công việc', 'khách']));
    // Chữ ký đã được cập nhật → lần sau không kéo lại.
    expect((await sync.run()).pulled, 0);
  });

  test('cả hai bên cùng sửa → xung đột, người dùng chọn', () async {
    final id = await add(45000);
    await sync.run();
    sheet.tab(tabTxn)[rowOf(id) - 1][3] = 60000;
    await repo.saveTxn(TransactionsCompanion(id: Value(id), amount: const Value(70000)));
    final r = await sync.run();
    expect(r.conflicts.map((c) => c.id), [id]);
    expect(sheet.tab(tabTxn)[rowOf(id) - 1][3], 60000); // chưa ghi đè khi chưa chọn
    await sync.resolveConflict(r.conflicts.single, keepApp: true);
    expect(sheet.tab(tabTxn)[rowOf(id) - 1][3], 70000);
    expect((await sync.run()).conflicts, isEmpty);
  });

  test('dòng bị xoá trên Sheet không xoá trong app, chỉ báo (6.3 bước 5)', () async {
    final id = await add(45000);
    await sync.run();
    sheet.tab(tabTxn).removeAt(rowOf(id) - 1);
    final r = await sync.run();
    expect(r.missingOnSheet, [id]);
    expect((await repo.watchTxns().first).length, 1);
  });

  test('xoá trong app → xoá dòng trên Sheet', () async {
    final a = await add(1000), b = await add(2000);
    await sync.run();
    await repo.deleteTxn(a);
    await sync.run();
    expect(rowOf(a), 0);
    expect(rowOf(b), greaterThan(1));
  });

  test('tiêu đề Sheet bị đổi → dừng, không ghi', () async {
    await add(1000);
    await sync.run();
    sheet.tab(tabTxn)[0][3] = 'Tiền';
    expect(() => sync.run(), throwsA(isA<SchemaMismatch>()));
  });

  test('2 máy cùng một Sheet: máy mới nhận giao dịch của máy cũ và ngược lại; chờ duyệt không lên Sheet', () async {
    final cats = await repo.allCategories();
    final cafe = cats.firstWhere((c) => c.name == 'Cà phê').id;
    final a = await repo.saveTxn(TransactionsCompanion.insert(
        walletId: w, type: 'expense', amount: 45000, amountBase: 45000, occurredAt: DateTime(2026, 11, 11, 9), categoryId: Value(cafe)));
    await repo.saveTxn(TransactionsCompanion.insert(
        walletId: w, type: 'expense', amount: 99000, amountBase: 99000, occurredAt: DateTime(2026, 11, 11, 10), status: const Value('pending')));
    await sync.run();
    expect(sheet.tab(tabTxn).length, 2); // tiêu đề + 1 dòng đã xác nhận

    // Máy B: DB trống, cùng Sheet.
    final dbB = AppDb(NativeDatabase.memory());
    final repoB = Repo(dbB);
    final syncB = SheetsSync(dbB, repoB, sheet);
    final r = await syncB.run();
    expect(r.pulled, 1);
    final tB = await (dbB.select(dbB.transactions)..where((x) => x.id.equals(a))).getSingle();
    final catsB = await repoB.allCategories();
    expect((tB.amount, tB.status, catsB.firstWhere((c) => c.id == tB.categoryId).name), (45000, 'confirmed', 'Cà phê'));
    final wB = (await dbB.select(dbB.wallets).get()).single;
    expect(wB.name, 'Tiền mặt');
    expect((await repoB.walletBalances())[wB.id], 955000); // khớp số dư máy A
    expect((await syncB.run()).pulled, 0); // không nhập trùng

    // B ghi thêm → A nhận về.
    final b = await repoB.saveTxn(TransactionsCompanion.insert(
        walletId: wB.id, type: 'income', amount: 500000, amountBase: 500000, occurredAt: DateTime(2026, 11, 12)));
    await syncB.run();
    expect((await sync.run()).pulled, 1);
    expect((await (db.select(db.transactions)..where((x) => x.id.equals(b))).getSingle()).walletId, w);
    expect((await repo.walletBalances())[w], 1000000 - 45000 + 500000);
    expect(sheet.tab(tabTxn).length, 3);
    await dbB.close();
  });

  test('sao lưu: mã hoá, mở bằng mật khẩu hoặc mã khôi phục, khôi phục đủ dữ liệu', () async {
    final id = await add(45000, note: 'cà phê');
    await repo.saveTxn(TransactionsCompanion(id: Value(id)), tags: ['sáng']);
    final (dk, envelope, code) = await BackupCrypto.setup('mat-khau-dai');
    expect(code.length, 24);
    final bytes = await BackupCrypto.encryptFile(dk, envelope, await DbSnapshot(db).export());
    expect(String.fromCharCodes(bytes).contains('cà phê'), isFalse);
    expect(await BackupCrypto.decryptFile(bytes, 'sai'), isNull);

    final db2 = AppDb(NativeDatabase.memory());
    final byCode = await BackupCrypto.decryptFile(bytes, '${code.substring(0, 4).toLowerCase()}-${code.substring(4)}');
    expect(byCode, isNotNull);
    final (payload, dk2, _) = (await BackupCrypto.decryptFile(bytes, 'mat-khau-dai'))!;
    expect(dk2, dk);
    await DbSnapshot(db2).restore(payload);
    final t = await (db2.select(db2.transactions)..where((x) => x.id.equals(id))).getSingle();
    expect((t.amount, t.note), (45000, 'cà phê'));
    expect(await Repo(db2).tagsOf(id), ['sáng']);
    expect((await Repo(db2).walletBalances())[w], 955000);
    await db2.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
