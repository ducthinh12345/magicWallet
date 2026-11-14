import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/pro.dart';
import 'app/session.dart';
import 'app/tracker.dart';
import 'data/store.dart';
import 'ui/home.dart';
import 'ui/sign_in.dart';

late final Track track;
final pro = Pro();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  track = await Track.open();
  if (configured) {
    await initNotifications(onTap: openMapAt);
    await Tracker.configure();
    await loadAccount();
    await pro.init();
  }
  runApp(const App());
}

/// Mở vị trí trong app Google Maps — miễn phí, không cần khoá API hay tài khoản thanh toán (thay cho Maps SDK).
Future<void> openMapAt(String? latLng) async {
  if (latLng == null) return;
  await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$latLng'), mode: LaunchMode.externalApplication);
}

const rose = Color(0xFFE53950);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Dây tơ hồng',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: !configured
            ? const _NotConfigured()
            : ValueListenableBuilder(
                valueListenable: account,
                builder: (_, email, _) => email == null ? const SignInScreen() : HomeScreen(key: ValueKey(email)),
              ),
      );
}

ThemeData _theme(Brightness b) {
  final light = b == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: rose, brightness: b).copyWith(primary: light ? rose : const Color(0xFFFF8A9B)),
    scaffoldBackgroundColor: light ? const Color(0xFFFFF7F7) : const Color(0xFF181214),
    cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
  );
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Bản build thiếu GOOGLE_SERVER_CLIENT_ID.\nXem README › "Cấu hình Google" và build lại với --dart-define.',
                textAlign: TextAlign.center),
          ),
        ),
      );
}
