import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../core/money.dart';
import '../core/periods.dart';
import '../data/database.dart';
import '../services.dart';
import 'lists.dart';
import 'manage.dart';
import 'pro_screen.dart';
import 'reports_ui.dart';
import 'settings.dart';
import 'sources.dart';
import 'widgets.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final s = Services.I;
  int tab = 0;
  PeriodType reportType = PeriodType.month;
  bool locked = false, onboarded = true;
  DateTime? pausedAt;
  Timer? ticker;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.notifier.init(onTap: _route);
    () async {
      onboarded = await s.flag('onboarded');
      locked = await s.flag('lock_enabled');
      final secure = await s.flag('secure_flag', def: true);
      await NativeCapture.setSecure(secure);
      privacyCover.value = secure;
      await s.pushWhitelist();
      setState(() {});
      if (locked) _unlock();
      _tick();
    }();
    // Khi app mở: gom thông báo mới và đẩy thay đổi lên Sheet trong ≤ 60 giây (US-04 AC2).
    ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _tick() async {
    if (syncing) return;
    syncing = true;
    try {
      await s.drainCapture();
      final dirty =
          await (s.db.select(s.db.syncLog)
                ..where((l) => l.syncedAt.isNull())
                ..limit(1))
              .getSingleOrNull();
      final last = DateTime.tryParse(await s.db.getSetting('sheets_last_sync') ?? '');
      // Có thay đổi thì đẩy ngay; không thì vẫn kéo về 15 phút/lần để nhận sửa tay trên Sheet và email mới.
      if (dirty != null || last == null || DateTime.now().difference(last).inMinutes >= 15) await s.backgroundSync();
    } finally {
      syncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      // Tự khoá sau 1 phút ở nền (10.1).
      if (pausedAt != null && DateTime.now().difference(pausedAt!) > const Duration(minutes: 1)) {
        s.flag('lock_enabled').then((on) {
          if (on) {
            setState(() => locked = true);
            _unlock();
          }
        });
      }
      _tick();
    }
  }

  Future<void> _unlock() async {
    if (kIsWeb) return setState(() => locked = false);
    try {
      final ok = await LocalAuthentication().authenticate(localizedReason: 'Mở khoá Ví Ma Thuật');
      if (ok && mounted) setState(() => locked = false);
    } catch (_) {
      // Người dùng huỷ hoặc thiết bị lỗi: giữ màn khoá, có nút thử lại.
    }
  }

  void _route(String? payload) {
    final nav = navigatorKey.currentState;
    if (payload == null || nav == null) return;
    if (payload == 'pending') nav.push(MaterialPageRoute(builder: (_) => const PendingScreen()));
    if (payload == 'budgets') nav.push(MaterialPageRoute(builder: (_) => const BudgetsScreen()));
    if (payload == 'pro') nav.push(MaterialPageRoute(builder: (_) => const ProScreen()));
    if (payload.startsWith('report:')) {
      setState(() {
        reportType = PeriodType.values.byName(payload.substring(7));
        tab = 2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!onboarded) return Onboarding(onDone: () => setState(() => onboarded = true));
    if (locked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 64),
              const SizedBox(height: 16),
              FilledButton(onPressed: _unlock, child: const Text('Mở khoá')),
            ],
          ),
        ),
      );
    }
    final pages = [
      OverviewTab(
        openPending: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingScreen())),
        openTransactions: () => setState(() => tab = 1),
      ),
      const TxnListTab(),
      ReportsTab(key: ValueKey(reportType), initial: reportType),
      const MoreTab(),
    ];
    const titles = ['Ví Ma Thuật', 'Giao dịch', 'Báo cáo', 'Thêm'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[tab])),
      // Nút "+" nổi đè nửa lên nội dung: chừa khoảng dưới để mục cuối danh sách không bị che.
      body: Padding(padding: const EdgeInsets.only(bottom: 36), child: pages[tab]),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ghi giao dịch',
        onPressed: () => openEditor(context),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Tổng quan'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Giao dịch',
          ),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Báo cáo'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Thêm'),
        ],
      ),
    );
  }
}

/// SC-01: 3 bước, có "Bỏ qua", làm lại được trong Cài đặt.
class Onboarding extends StatefulWidget {
  final VoidCallback onDone;
  const Onboarding({super.key, required this.onDone});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final s = Services.I;
  int step = 0;
  final name = TextEditingController(text: 'Tiền mặt');
  final balance = TextEditingController();
  String type = 'cash';

  Future<void> _finish() async {
    await s.setFlag('onboarded', true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = switch (step) {
      0 => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👛', style: TextStyle(fontSize: 64)),
          Text('Ví Ma Thuật', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
            'Biết tiền đi đâu mà không mất công ghi chép.\nDữ liệu chỉ ở trên máy bạn và Google Drive của bạn.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const ListTile(title: Text('Tiền tệ'), trailing: Text('VND – Việt Nam đồng')),
        ],
      ),
      1 => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Ví đầu tiên', style: theme.textTheme.headlineSmall),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Tên ví'),
          ),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Loại'),
            items: [for (final e in walletTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => type = v!),
          ),
          AmountField(balance, 'Số dư hiện tại'),
        ],
      ),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Ghi chi tiêu tự động?', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            NativeCapture.supported
                ? 'App có thể tự đọc thông báo biến động số dư từ app ngân hàng bạn chọn. Mọi giao dịch vào hàng chờ để bạn xác nhận 1 chạm.'
                : 'Trên thiết bị này, bạn có thể nhập sao kê hoặc đọc email hoá đơn qua Google.',
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesScreen())),
            child: const Text('Thiết lập ghi tự động'),
          ),
        ],
      ),
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(onPressed: _finish, child: const Text('Bỏ qua')),
              ),
              Expanded(
                child: Center(child: SingleChildScrollView(child: body)),
              ),
              Row(
                children: [
                  Text('${step + 1}/3'),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      if (step == 1 && name.text.trim().isNotEmpty) {
                        await s.repo.saveWallet(
                          WalletsCompanion.insert(
                            name: name.text.trim(),
                            type: type,
                            icon: Value(walletIcons[type]!),
                            openingBalance: Value(parseAmountInput(balance.text) ?? 0),
                          ),
                        );
                      }
                      if (step == 2) return _finish();
                      setState(() => step++);
                    },
                    child: Text(step == 2 ? 'Bắt đầu' : 'Tiếp'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
