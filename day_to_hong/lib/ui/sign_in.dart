import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/session.dart';
import '../main.dart' show rose;

/// SC-01: lời hứa riêng tư + đăng nhập Google.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await signIn();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không đăng nhập được: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Icon(Icons.favorite, color: rose, size: 72),
                const SizedBox(height: 16),
                Text('Dây tơ hồng', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Vị trí, kế hoạch và kỷ niệm — của riêng hai người.', textAlign: TextAlign.center),
                const SizedBox(height: 32),
                for (final (icon, text) in const [
                  (Icons.lock_outline, 'Vị trí mã hoá trên máy bạn. Không máy chủ trung gian — dữ liệu nằm trong Google Calendar của chính các bạn.'),
                  (Icons.calendar_month_outlined, 'Kế hoạch và kỷ niệm chung hiện luôn trong Google Calendar của cả hai.'),
                  (Icons.visibility_outlined, 'Chỉ Gmail bạn mời mới xem được. Luôn có thông báo khi đang chia sẻ.'),
                ])
                  ListTile(leading: Icon(icon, color: rose), title: Text(text)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy ? null : _go,
                  icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                  label: const Text('Đăng nhập bằng Google'),
                ),
              ],
            ),
          ),
        ),
      );
}

/// SC-02 (prominent disclosure, chính sách Play): giải thích *trước* hộp thoại hệ thống. Trả true nếu đủ quyền để chia sẻ.
Future<bool> askSharePermissions(BuildContext context) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy bật Vị trí (GPS) của điện thoại.')));
    }
    await Geolocator.openLocationSettings();
    return false;
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
    await requestNotificationPermission();
    return true;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.location_on, color: rose),
      title: const Text('Chia sẻ vị trí của bạn'),
      content: const Text(
        'Dây tơ hồng thu thập vị trí chính xác của bạn — kể cả khi bạn đóng app hoặc tắt màn hình — '
        'để những người trong sợi tơ của bạn thấy bạn ở đâu và lộ trình gần đây (cập nhật mỗi vài phút).\n\n'
        'Vị trí được mã hoá trên máy rồi lưu vào lịch Google chung của các bạn; chỉ người trong sợi tơ giải mã được. '
        'Khi đang chia sẻ luôn có thông báo cố định; bạn tắt hoặc tạm ẩn được bất cứ lúc nào.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Để sau')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đồng ý')),
      ],
    ),
  );
  if (ok != true) return false;
  perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.deniedForever) await Geolocator.openAppSettings();
  await requestNotificationPermission(); // Android 13+: thiếu quyền thì thông báo cố định và SOS không hiện
  return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
}
