import 'package:geolocator/geolocator.dart' show Geolocator;

/// Một điểm vị trí. `t` là mili-giây epoch theo đồng hồ máy gửi.
class Fix {
  final double lat, lng, acc;
  final int t;
  const Fix(this.lat, this.lng, this.acc, this.t);

  /// Dạng gọn [lat, lng, acc, giây] — 5 chữ số thập phân ≈ 1 m, đủ cho lộ trình mà mô tả sự kiện ngắn lại.
  List<num> pack() => [_r5(lat), _r5(lng), acc.round(), t ~/ 1000];
  factory Fix.unpack(List<dynamic> v) =>
      Fix((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble(), (v[3] as num).toInt() * 1000);

  static double _r5(double v) => (v * 1e5).round() / 1e5;

  double metersTo(Fix o) => Geolocator.distanceBetween(lat, lng, o.lat, o.lng);
  String get latLng => '$lat,$lng';
}

/// US-04: chỉ giữ điểm có ý nghĩa cho lộ trình — đi ≥ 25 m và cách điểm trước ≥ 20 s, sai số ≤ 100 m.
class Throttle {
  static const minMeters = 25.0;
  static const minGap = Duration(seconds: 20);
  static const maxAccuracy = 100.0;

  Fix? last;

  bool take(Fix f) {
    if (f.acc > maxAccuracy) return false;
    final prev = last;
    if (prev != null && (f.t - prev.t < minGap.inMilliseconds || f.metersTo(prev) < minMeters)) return false;
    last = f;
    return true;
  }
}
