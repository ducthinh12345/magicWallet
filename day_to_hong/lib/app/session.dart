import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/geo.dart';
import '../data/google.dart';
import '../data/store.dart';
import '../data/sync.dart';

/// Chỉ cần OAuth client ID (Google Cloud, miễn phí, không gắn thẻ thanh toán): --dart-define=GOOGLE_SERVER_CLIENT_ID=…
bool get configured => serverClientId.isNotEmpty;

/// Email đang đăng nhập (lưu trên máy). Null = chưa đăng nhập. Không có tài khoản nào phía nhà phát triển.
final account = ValueNotifier<String?>(null);

Future<void> loadAccount() async => account.value = await Vault.get('email');

/// Phiên làm việc của người đã đăng nhập; null nếu chưa đăng nhập. Dùng được trong service nền.
Future<Sync?> openSync(Track track) async {
  final e = await Vault.get('email');
  if (e == null) return null;
  return Sync(e, await Vault.get('name') ?? e.split('@').first, track);
}

bool _gsiReady = false;
Future<void> _gsi() async {
  if (_gsiReady) return;
  await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
  _gsiReady = true;
}

/// Chọn tài khoản Google rồi xin quyền Lịch + Drive (hộp thoại của Google).
Future<void> signIn() async {
  await _gsi();
  final acc = await GoogleSignIn.instance.authenticate();
  final email = acc.email.toLowerCase();
  if (await GoogleApis(email).token(prompt: true) == null) throw StateError('Bạn chưa cấp quyền Lịch Google.');
  await Vault.set('email', email);
  await Vault.set('name', acc.displayName ?? email.split('@').first);
  account.value = email;
}

/// Cấp lại quyền khi Google thu hồi (service nền báo NeedsConsent).
Future<bool> regrant(String email) async => await GoogleApis(email).token(prompt: true) != null;

Future<void> signOut() async {
  await _gsi();
  await GoogleSignIn.instance.signOut();
  await Vault.set('email', null);
  account.value = null;
}

/// Rời/xoá mọi sợi tơ, xoá dữ liệu trên máy, thu hồi quyền Google. Trả số sợi tơ không xoá được.
Future<int> wipeAll(Sync sync, Track track) async {
  final failed = await sync.leaveAll();
  track.wipe();
  await Vault.wipe();
  await _gsi();
  await GoogleSignIn.instance.disconnect();
  account.value = null;
  return failed;
}

/// Trạng thái tạm ẩn (US-07), dùng chung giữa isolate giao diện và service qua Vault.
class Pause {
  final DateTime? until; // null + forever=false: không tạm ẩn
  final bool forever;
  const Pause({this.until, this.forever = false});

  bool get active => forever || (until != null && DateTime.now().isBefore(until!));

  static Future<Pause> load() async {
    final v = await Vault.get('pause');
    if (v == 'forever') return const Pause(forever: true);
    final ms = int.tryParse(v ?? '');
    return Pause(until: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms));
  }

  static Future<void> save(Pause p) =>
      Vault.set('pause', p.forever ? 'forever' : p.until?.millisecondsSinceEpoch.toString());
}

// ---------------- Thông báo cục bộ ----------------

const shareChannel = 'dth_share';
const _sosChannel = 'dth_sos';
final _ln = FlutterLocalNotificationsPlugin();

/// `onTap` nhận payload "lat,lng" của thông báo SOS (chỉ isolate giao diện truyền vào).
Future<void> initNotifications({void Function(String? payload)? onTap}) async {
  await _ln.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: onTap == null ? null : (r) => onTap(r.payload),
  );
  final android = _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  // Kênh của thông báo cố định "đang chia sẻ" phải có trước khi service khởi động.
  await android?.createNotificationChannel(const AndroidNotificationChannel(shareChannel, 'Đang chia sẻ vị trí',
      description: 'Thông báo cố định khi bạn đang chia sẻ vị trí', importance: Importance.low));
  await android?.createNotificationChannel(const AndroidNotificationChannel(_sosChannel, 'SOS khẩn cấp',
      description: 'Người thân bấm SOS', importance: Importance.max));
}

Future<bool> requestNotificationPermission() async =>
    await _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? true;

Future<void> showSos(String who, Fix? at) => _ln.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
      title: '🆘 $who cần giúp đỡ!',
      body: at == null ? 'Không có vị trí kèm theo — hãy gọi ngay.' : 'Chạm để xem vị trí trên bản đồ.',
      payload: at == null ? null : '${at.lat},${at.lng}',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_sosChannel, 'SOS khẩn cấp',
            importance: Importance.max, priority: Priority.max, category: AndroidNotificationCategory.alarm),
      ),
    );

Future<void> showInfo(String title, String body) => _ln.show(
      id: 9,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(shareChannel, 'Đang chia sẻ vị trí')),
    );
