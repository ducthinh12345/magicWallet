import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/geo.dart';

/// Lộ trình trên máy. Mở được từ cả isolate giao diện lẫn isolate service nền:
/// WAL + busy_timeout cho hai bên cùng ghi; INSERT OR IGNORE để nhận trùng điểm không sao.
/// Điểm của chính mình lưu với circle = [mine].
class Track {
  static const mine = '_me';
  final Database db;
  Track(this.db) {
    db.execute('''
      PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS points(circle TEXT, uid TEXT, t INTEGER, lat REAL, lng REAL, acc REAL, PRIMARY KEY(circle, uid, t));
      CREATE TABLE IF NOT EXISTS seen(id TEXT PRIMARY KEY);
    ''');
  }

  static Future<Track> open() async =>
      Track(sqlite3.open(p.join((await getApplicationSupportDirectory()).path, 'track.db')));

  void add(String circle, String uid, Fix f) =>
      db.execute('INSERT OR IGNORE INTO points VALUES(?,?,?,?,?,?)', [circle, uid, f.t, f.lat, f.lng, f.acc]);

  List<Fix> since(String circle, String uid, DateTime from) => [
        for (final r in db.select('SELECT lat,lng,acc,t FROM points WHERE circle=? AND uid=? AND t>=? ORDER BY t',
            [circle, uid, from.millisecondsSinceEpoch]))
          Fix(r['lat'] as double, r['lng'] as double, r['acc'] as double, r['t'] as int),
      ];

  /// true đúng một lần cho mỗi id, kể cả khi hai isolate cùng thấy — để không báo SOS hai lần.
  bool firstSeen(String id) {
    db.execute('INSERT OR IGNORE INTO seen VALUES(?)', [id]);
    return db.updatedRows == 1;
  }

  /// Giữ 30 ngày.
  void prune() => db.execute('DELETE FROM points WHERE t < ?',
      [DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch]);

  void forget(String circle) => db.execute('DELETE FROM points WHERE circle=?', [circle]);

  void wipe() => db.execute('DELETE FROM points; DELETE FROM seen;');
}

/// Một sợi tơ = một lịch phụ Google. Chỉ lưu trên máy: không có máy chủ nào biết ai ở sợi tơ nào.
class CircleRef {
  final String id; // calendarId
  final List<int> key;
  final bool owner, family;
  const CircleRef(this.id, this.key, {this.owner = false, this.family = false});

  Map<String, dynamic> toJson() => {'id': id, 'key': base64.encode(key), 'owner': owner, 'family': family};
  factory CircleRef.fromJson(Map<String, dynamic> j) =>
      CircleRef(j['id'] as String, base64.decode(j['key'] as String), owner: j['owner'] == true, family: j['family'] == true);
}

/// Bí mật trên máy (Keystore): khoá từng sợi tơ, email đăng nhập, trạng thái tạm ẩn, Pro.
class Vault {
  static const _s = FlutterSecureStorage();

  static Future<String?> get(String k) => _s.read(key: k);
  static Future<void> set(String k, String? v) => v == null ? _s.delete(key: k) : _s.write(key: k, value: v);
  static Future<void> wipe() => _s.deleteAll();

  static Future<List<CircleRef>> circles() async => [
        for (final j in jsonDecode(await get('circles') ?? '[]') as List) CircleRef.fromJson(Map<String, dynamic>.from(j as Map)),
      ];

  static Future<void> saveCircles(List<CircleRef> cs) => set('circles', jsonEncode([for (final c in cs) c.toJson()]));
}
