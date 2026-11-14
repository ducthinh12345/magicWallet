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

    return MaterialApp(
      title: 'Ví Ma Thuật',
      navigatorKey: navigatorKey,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
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

/// Phong cách quen thuộc của app quản lý chi tiêu: nền xám nhạt, thẻ trắng bo tròn, nhấn màu teal.
ThemeData appTheme(Brightness b) {
  final light = b == Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00897B), brightness: b)
      .copyWith(primary: light ? const Color(0xFF00897B) : const Color(0xFF4DB6AC));
  final surface = light ? Colors.white : const Color(0xFF1A2228);
  final round = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: light ? const Color(0xFFF2F5F7) : const Color(0xFF0E1316),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.15),
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => TextStyle(fontSize: 12, fontWeight: st.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? const Color(0xFFF2F5F7) : const Color(0xFF232C33),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: round, minimumSize: const Size(48, 48))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: round, minimumSize: const Size(48, 48))),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
  );
}
