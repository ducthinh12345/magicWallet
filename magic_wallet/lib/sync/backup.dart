import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../data/database.dart';

/// Bản sao lưu .vrbackup: JSON gồm phong bì khoá + dữ liệu mã hoá AES-256-GCM.
///
/// Khoá dữ liệu (DK) ngẫu nhiên, được "bọc" hai lần: bằng khoá dẫn xuất từ mật khẩu sao lưu và từ mã khôi phục
/// 24 ký tự (Argon2id). Nhờ vậy app sao lưu tự động hằng ngày mà không cần hỏi lại mật khẩu, còn mất cả hai thì
/// không ai mở được — kể cả nhà phát triển (mục 6.4).
class BackupCrypto {
  static final _aes = AesGcm.with256bits();
  // Tham số Argon2id theo khuyến nghị OWASP (19 MiB, 2 vòng, 1 luồng).
  static final _kdf = Argon2id(parallelism: 1, memory: 19456, iterations: 2, hashLength: 32);

  static List<int> _random(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  /// 24 ký tự, bỏ ký tự dễ nhầm (0/O, 1/I/L), chia nhóm 4 khi hiển thị.
  static String newRecoveryCode() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(24, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  static String normalizeCode(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static Future<SecretKey> _derive(String secret, List<int> salt) => _kdf.deriveKeyFromPassword(password: secret, nonce: salt);

  static Future<String> _seal(SecretKey key, List<int> clear) async =>
      base64.encode((await _aes.encrypt(clear, secretKey: key)).concatenation());

  static Future<List<int>> _open(SecretKey key, String sealed) => _aes.decrypt(
    SecretBox.fromConcatenation(base64.decode(sealed), nonceLength: _aes.nonceLength, macLength: _aes.macAlgorithm.macLength),
    secretKey: key,
  );

  /// Bật sao lưu: tạo DK mới, bọc bằng mật khẩu và mã khôi phục. Trả về (DK, phong bì JSON, mã khôi phục).
  static Future<(List<int>, String, String)> setup(String password) async {
    final dk = _random(32);
    final code = newRecoveryCode();
    final saltPw = _random(16), saltRc = _random(16);
    final envelope = jsonEncode({
      'kdf': 'argon2id-m19456-t2-p1',
      'saltPw': base64.encode(saltPw),
      'saltRc': base64.encode(saltRc),
      'wrapPw': await _seal(await _derive(password, saltPw), dk),
      'wrapRc': await _seal(await _derive(code, saltRc), dk),
    });
    return (dk, envelope, code);
  }

  /// Mở DK bằng mật khẩu hoặc mã khôi phục. Sai cả hai → null.
  static Future<List<int>?> unwrap(String envelope, String secret) async {
    final e = jsonDecode(envelope) as Map<String, dynamic>;
    try {
      return await _open(await _derive(secret, base64.decode(e['saltPw'])), e['wrapPw']);
    } on SecretBoxAuthenticationError {
      try {
        return await _open(await _derive(normalizeCode(secret), base64.decode(e['saltRc'])), e['wrapRc']);
      } on SecretBoxAuthenticationError {
        return null;
      }
    }
  }

  static Future<Uint8List> encryptFile(List<int> dk, String envelope, Map<String, dynamic> payload) async {
    final file = {
      'format': 'vrbackup',
      'v': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'envelope': jsonDecode(envelope),
      'data': await _seal(SecretKey(dk), utf8.encode(jsonEncode(payload))),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(file)));
  }

  /// Trả về (payload, DK, phong bì) hoặc null nếu sai mật khẩu/mã.
  static Future<(Map<String, dynamic>, List<int>, String)?> decryptFile(List<int> bytes, String secret) async {
    final file = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (file['format'] != 'vrbackup') throw const FormatException('Không phải file sao lưu Ví Riêng');
    final envelope = jsonEncode(file['envelope']);
    final dk = await unwrap(envelope, secret);
    if (dk == null) return null;
    final clear = await _open(SecretKey(dk), file['data']);
    return (jsonDecode(utf8.decode(clear)) as Map<String, dynamic>, dk, envelope);
  }
}

/// Đổ toàn bộ dữ liệu ra JSON / nạp lại. Bỏ sync_log vì nó gắn với trạng thái đồng bộ của từng máy.
class DbSnapshot {
  final AppDb db;
  DbSnapshot(this.db);

  List<TableInfo<Table, dynamic>> get _tables => [
    db.wallets,
    db.categories,
    db.transactions,
    db.tags,
    db.transactionTags,
    db.budgets,
    db.recurringRules,
    db.rawEvents,
    db.classificationRules,
    db.settings,
  ];

  Future<Map<String, dynamic>> export() async => {
    'schemaVersion': db.schemaVersion,
    for (final t in _tables) t.actualTableName: [for (final row in await db.select(t).get()) (row as DataClass).toJson()],
  };

  /// Thay toàn bộ dữ liệu bằng bản sao lưu, trong một transaction (lỗi giữa chừng thì không mất gì).
  Future<void> restore(Map<String, dynamic> data) => db.transaction(() async {
    for (final t in _tables) {
      await db.delete(t).go();
    }
    await db.delete(db.syncLog).go();
    Future<void> load<D extends DataClass>(TableInfo<Table, D> t, D Function(Map<String, dynamic>) fromJson) async {
      for (final m in (data[t.actualTableName] as List? ?? const [])) {
        await db.into(t).insert(fromJson(Map<String, dynamic>.from(m)) as Insertable<D>);
      }
    }

    await load(db.wallets, (m) => Wallet.fromJson(m));
    await load(db.categories, (m) => Category.fromJson(m));
    await load(db.transactions, (m) => Txn.fromJson(m));
    await load(db.tags, (m) => Tag.fromJson(m));
    await load(db.transactionTags, (m) => TxnTag.fromJson(m));
    await load(db.budgets, (m) => Budget.fromJson(m));
    await load(db.recurringRules, (m) => RecurringRule.fromJson(m));
    await load(db.rawEvents, (m) => RawEvent.fromJson(m));
    await load(db.classificationRules, (m) => ClassificationRule.fromJson(m));
    await load(db.settings, (m) => Setting.fromJson(m));
  });
}
