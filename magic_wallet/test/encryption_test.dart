import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_wallet/data/database.dart';
import 'package:magic_wallet/data/repo.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

void main() {
  test('DB trên đĩa được mã hoá: không có header SQLite, không lộ chữ, sai khoá thì không mở được', () async {
    final dir = await Directory.systemTemp.createTemp('mw');
    final file = File('${dir.path}/t.db');
    final key = 'ab' * 32;
    final db = AppDb(NativeDatabase(file, setup: (d) => AppDb.applyKey(d, key)));
    final repo = Repo(db);
    final w = await repo.saveWallet(WalletsCompanion.insert(name: 'BiMatXYZ', type: 'cash'));
    await repo.saveTxn(TransactionsCompanion.insert(
        walletId: w, type: 'expense', amount: 45000, amountBase: 45000, occurredAt: DateTime.now(), note: const Value('GhiChuBiMat')));
    await db.close();

    // WAL có thể còn dữ liệu chưa checkpoint: kiểm cả file chính lẫn -wal.
    for (final f in dir.listSync().whereType<File>()) {
      final bytes = f.readAsBytesSync();
      final text = String.fromCharCodes(bytes);
      expect(text.contains('SQLite format 3'), isFalse, reason: f.path);
      expect(text.contains('BiMatXYZ') || text.contains('GhiChuBiMat'), isFalse, reason: f.path);
    }

    final wrong = AppDb(NativeDatabase(file, setup: (d) => AppDb.applyKey(d, 'cd' * 32)));
    await expectLater(wrong.select(wrong.wallets).get(), throwsA(anything));
    await wrong.close();

    final right = AppDb(NativeDatabase(file, setup: (d) => AppDb.applyKey(d, key)));
    expect((await right.select(right.wallets).get()).single.name, 'BiMatXYZ');
    await right.close();
    await dir.delete(recursive: true);
  });

  test('khoá sai định dạng bị từ chối (chặn chèn SQL vào PRAGMA)', () {
    final mem = sqlite3.openInMemory();
    expect(() => AppDb.applyKey(mem, "x'; DROP TABLE wallets; --"), throwsArgumentError);
    mem.close();
  });
}
