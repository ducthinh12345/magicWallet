import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services.dart';
import 'ui/home.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Services.init();
  runApp(const MagicWalletApp());
}

/// Điểm vào cho engine chạy nền do NotificationListenerService khởi động (Android):
/// xử lý hàng đợi thông báo ngay khi có, không chờ người dùng mở app (NFR-04 ≤ 3 giây).
@pragma('vm:entry-point')
Future<void> captureMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = await Services.init(headless: true);
  const ch = MethodChannel('magic_wallet/capture');
  ch.setMethodCallHandler((call) async {
    if (call.method == 'drain') await s.drainCapture();
  });
  await s.drainCapture();
}

class MagicWalletApp extends StatelessWidget {
  const MagicWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B), brightness: b),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Ví Ma Thuật',
      navigatorKey: navigatorKey,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => PrivacyCover(child: child!),
      home: const HomeScreen(),
    );
  }
}
