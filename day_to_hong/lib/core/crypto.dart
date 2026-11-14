import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Mã hoá vị trí đầu-cuối: Google chỉ thấy bản mã trong mô tả sự kiện 📍.
/// box = base64(nonce 12B ‖ ciphertext ‖ tag 16B), AES-256-GCM bằng khoá sợi tơ (nằm trong mã mời).
class Box {
  static final _aes = AesGcm.with256bits();

  static List<int> randomKey() {
    final r = Random.secure();
    return List<int>.generate(32, (_) => r.nextInt(256));
  }

  static Future<String> seal(List<int> key, Map<String, dynamic> data) async {
    final sb = await _aes.encrypt(utf8.encode(jsonEncode(data)), secretKey: SecretKey(key));
    return base64.encode(sb.concatenation());
  }

  /// Ném lỗi nếu sai khoá hoặc bản mã bị sửa (GCM kiểm tra tag).
  static Future<Map<String, dynamic>> open(List<int> key, String box) async {
    final sb = SecretBox.fromConcatenation(base64.decode(box.trim()), nonceLength: 12, macLength: 16);
    return jsonDecode(utf8.decode(await _aes.decrypt(sb, secretKey: SecretKey(key)))) as Map<String, dynamic>;
  }
}

/// Mã mời `DTH1.<id lịch>.<khoá>` — người nhận cần ĐÚNG Gmail được chia sẻ lịch (Google kiểm) VÀ mã này (để giải mã vị trí).
class Invite {
  final String calendarId;
  final List<int> key;
  const Invite(this.calendarId, this.key);

  static String _b(List<int> v) => base64Url.encode(v).replaceAll('=', '');
  static List<int> _d(String s) => base64Url.decode(base64Url.normalize(s));

  String encode() => 'DTH1.${_b(utf8.encode(calendarId))}.${_b(key)}';

  /// Chấp nhận mã bị dán kèm chữ thừa (lời nhắn Zalo): tìm đoạn DTH1.… trong văn bản. Null nếu không hợp lệ.
  static Invite? parse(String text) {
    final m = RegExp(r'DTH1\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]{43})').firstMatch(text);
    if (m == null) return null;
    try {
      final id = utf8.decode(_d(m[1]!));
      final key = _d(m[2]!);
      return id.contains('@') && key.length == 32 ? Invite(id, key) : null;
    } catch (_) {
      return null;
    }
  }
}
