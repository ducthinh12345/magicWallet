import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';
import '../data/google.dart';
import '../data/store.dart';
import 'session.dart';

/// Nhịp đồng bộ đã chốt với người dùng: 2–5 phút (Calendar không đẩy về máy nếu không có server).
const syncEvery = Duration(minutes: 3);

/// Đứng yên quá lâu vẫn gửi lại để người thân thấy "cập nhật x phút trước" còn mới.
const heartbeat = Duration(minutes: 15);

/// Chia sẻ nền bằng foreground service loại `location` — luôn có thông báo cố định.
class Tracker {
  static final _svc = FlutterBackgroundService();

  static Future<void> configure() => _svc.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: trackerMain,
          autoStart: false,
          // Khởi động lại sau khi bật máy cần quyền vị trí nền (không xin) → người dùng mở app để bật lại.
          autoStartOnBoot: false,
          isForegroundMode: true,
          notificationChannelId: shareChannel,
          initialNotificationTitle: 'Dây tơ hồng',
          initialNotificationContent: 'Đang chia sẻ vị trí',
          foregroundServiceNotificationId: 7,
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
        iosConfiguration: IosConfiguration(autoStart: false), // shortcut: chưa làm iOS
      );

  static Future<bool> get running => _svc.isRunning();
  static Future<void> start() => _svc.startService();
  static void stop() => _svc.invoke('stop');
  /// Báo service đọc lại trạng thái tạm ẩn và gửi ngay.
  static void refresh() => _svc.invoke('refresh');
}

Fix fixOf(Position p) => Fix(p.latitude, p.longitude, p.accuracy, p.timestamp.millisecondsSinceEpoch);

@pragma('vm:entry-point')
Future<void> trackerMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await initNotifications();
  final track = await Track.open()..prune();
  final sync = await openSync(track);
  final perm = await Geolocator.checkPermission();
  if (sync == null || perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    await service.stopSelf();
    return;
  }
  sync.onSos = showSos;

  final throttle = Throttle();
  var pause = await Pause.load();
  Fix? last;
  var dirty = true; // có điểm mới hoặc đổi trạng thái chưa gửi
  var sentAt = DateTime(2000);
  var consentWarned = false;

  void banner([String? note]) {
    if (service is! AndroidServiceInstance) return;
    final names = {
      for (final c in sync.circles.value)
        for (final m in c.members)
          if (m.email != sync.email) m.label,
    };
    service.setForegroundNotificationInfo(
      title: pause.active ? 'Đang tạm ẩn vị trí' : 'Đang chia sẻ vị trí',
      content: note ?? (names.isEmpty ? 'Chưa có ai trong sợi tơ' : 'Với ${names.join(', ')}'),
    );
  }

  Future<void> tick({bool force = false}) async {
    try {
      final beat = DateTime.now().difference(sentAt) >= heartbeat;
      if (beat && !pause.active) {
        try {
          last = fixOf(await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 20)));
        } catch (_) {
          // không có GPS: gửi điểm cũ, người xem thấy giờ của điểm cũ — trung thực
        }
      }
      if (force || dirty || beat) {
        final failed = pause.active ? await sync.publish(paused: true, until: pause.until) : await sync.publish(fix: last);
        if (failed == 0) {
          dirty = false;
          sentAt = DateTime.now();
        }
      }
      await sync.refresh();
      consentWarned = false;
      banner();
    } on NeedsConsent {
      if (!consentWarned) await showInfo('Dây tơ hồng cần cấp lại quyền Google', 'Mở app để tiếp tục chia sẻ vị trí.');
      consentWarned = true;
      banner('Tạm dừng: mở app để cấp lại quyền Google');
    } catch (e) {
      banner('Chưa gửi được — sẽ thử lại sau ${syncEvery.inMinutes} phút');
    }
  }

  final pos = Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: Throttle.minMeters.toInt(),
      intervalDuration: Throttle.minGap,
    ),
  ).listen((p) {
    final f = fixOf(p);
    last = f;
    if (!pause.active && throttle.take(f)) {
      track.add(Track.mine, sync.email, f);
      dirty = true;
    }
  }, onError: (Object e) => banner('Không lấy được vị trí: $e'));

  // Tạm ẩn hết giờ thì tự bật lại và báo người dùng.
  Timer? resume;
  void scheduleResume() {
    resume?.cancel();
    final u = pause.until;
    if (pause.forever || u == null || !pause.active) return;
    resume = Timer(u.difference(DateTime.now()), () async {
      pause = const Pause();
      await Pause.save(pause);
      await showInfo('Đã bật lại chia sẻ vị trí', 'Hết thời gian tạm ẩn.');
      await tick(force: true);
    });
  }

  scheduleResume();
  final timer = Timer.periodic(syncEvery, (_) => tick());

  service.on('refresh').listen((_) async {
    pause = await Pause.load();
    scheduleResume();
    await tick(force: true);
  });
  service.on('stop').listen((_) async {
    await pos.cancel();
    timer.cancel();
    resume?.cancel();
    await sync.publish(paused: true); // tắt chia sẻ → người thân thấy "đang ẩn", không phải vị trí cũ
    await service.stopSelf();
  });

  try {
    last = fixOf(await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 20)));
    track.add(Track.mine, sync.email, last!);
  } catch (_) {
    // chưa có GPS: lần tick sau sẽ có
  }
  await tick(force: true);
}
