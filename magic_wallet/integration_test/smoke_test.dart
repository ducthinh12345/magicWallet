import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_wallet/main.dart' as app;

/// Smoke test trên máy thật/simulator: mở app, bấm qua các tab, bắt ngoại lệ ở từng tab.
/// Chạy: flutter test integration_test/smoke_test.dart --dart-define=DEMO_SEED=true --dart-define=DEV_PRO_LIFETIME=true -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('các tab chính hiển thị không lỗi', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Ví Ma Thuật'), findsWidgets);

    for (final tab in ['Giao dịch', 'Báo cáo', 'Thêm']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    }
    // Bản Pro (DEV_PRO_LIFETIME) phải hiện dòng này ở tab Thêm.
    expect(find.textContaining('Pro trọn đời'), findsWidgets);
  });
}
