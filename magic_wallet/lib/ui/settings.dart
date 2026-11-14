import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../services.dart';
import '../pro/pro.dart';
import 'pro_screen.dart';
import 'export.dart';
import 'google_ui.dart';
import 'manage.dart';
import 'setup_guide.dart';
import 'sources.dart';
import 'widgets.dart';

/// Tab "Thêm": mọi thiết lập (9.1).
class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    // Một mục cài đặt: icon màu trong ô bo góc, tên, mũi tên.
    Widget item(IconData icon, Color color, String title, VoidCallback onTap, {String? subtitle}) => ListTile(
      leading: IconBadge(size: 40, color: color, child: Icon(icon, color: color, size: 21)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
    Widget group(String title, List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 0, 4),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Card(clipBehavior: Clip.antiAlias, child: Column(children: items)),
      ],
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _ProBanner(onTap: () => go(const ProScreen())),
        group('Quản lý tiền', [
          item(Icons.account_balance_wallet_outlined, const Color(0xFF00897B), 'Ví & đối soát', () => go(const WalletsScreen())),
          item(Icons.category_outlined, const Color(0xFF8E24AA), 'Danh mục', () => go(const CategoriesScreen())),
          item(Icons.savings_outlined, const Color(0xFFF9A825), 'Ngân sách', () => go(const BudgetsScreen())),
          item(Icons.event_repeat, const Color(0xFF1E88E5), 'Giao dịch định kỳ', () => go(const RecurringScreen())),
          item(Icons.rule, const Color(0xFF6D4C41), 'Quy tắc phân loại', () => go(const RulesScreen())),
        ]),
        group('Tự động & đồng bộ', [
          item(Icons.bolt, const Color(0xFFEF6C00), 'Ghi tự động', () => go(const SourcesScreen()),
              subtitle: 'Thông báo ngân hàng, email, sao kê'),
          item(Icons.cloud_outlined, const Color(0xFF1E88E5), 'Google Sheets & sao lưu', () => go(const GoogleScreen())),
        ]),
        group('Cài đặt', [
          item(Icons.lock_outline, const Color(0xFF43A047), 'Bảo mật', () => go(const SecurityScreen())),
          item(Icons.tune, const Color(0xFF546E7A), 'Cài đặt chung', () => go(const GeneralScreen())),
        ]),
        group('Dữ liệu của bạn', [
          item(Icons.table_view_outlined, const Color(0xFF2E7D32), 'Xuất CSV toàn bộ giao dịch', () => exportTxnsCsv(context, name: 'tat-ca')),
          item(Icons.data_object, const Color(0xFF546E7A), 'Xuất JSON toàn bộ dữ liệu', () => exportAllJson(context)),
          item(Icons.delete_forever_outlined, expenseColor, 'Xoá toàn bộ dữ liệu trên máy', () async {
            if (await confirm(
              context,
              'Xoá vĩnh viễn mọi ví, giao dịch, cài đặt trên máy này? Google Sheet và bản sao lưu trên Drive không bị xoá.',
              ok: 'Xoá hết',
            )) {
              await Services.I.wipeAll();
              if (context.mounted) toast(context, 'Đã xoá toàn bộ dữ liệu');
            }
          }),
        ]),
        const SizedBox(height: 8),
        const AboutListTile(
          applicationName: 'Ví Ma Thuật',
          applicationVersion: '1.0.0',
          aboutBoxChildren: [
            Text(
              'Dữ liệu chỉ nằm trên máy bạn và trong Google Drive của bạn. Không có máy chủ của nhà phát triển.\n\n'
              'Không liên kết hay được bảo trợ bởi bất kỳ ngân hàng hoặc ví điện tử nào.',
            ),
          ],
        ),
      ],
    );
  }
}

/// Banner Pro nổi bật ở đầu tab Thêm, nội dung theo trạng thái (miễn phí / dùng thử / đã mua).
class _ProBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _ProBanner({required this.onTap});

  @override
  Widget build(BuildContext context) => FutureBuilder<ProState>(
    future: ProState.load(Services.I.db),
    builder: (context, st) {
      final now = DateTime.now();
      final p = st.data;
      final text = p == null
          ? ''
          : p.purchased
          ? 'Bạn đang dùng Pro ${p.owned == 'lifetime' ? 'trọn đời' : 'gói năm'}. Cảm ơn bạn!'
          : p.trialActive(now)
          ? 'Đang dùng thử — còn ${p.trialDaysLeft(now)} ngày'
          : 'Ghi tự động mọi ngân hàng, báo cáo năm, sao lưu tự động…';
      return Material(
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFF7043)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              const CircleAvatar(radius: 24, backgroundColor: Colors.white24, child: Icon(Icons.workspace_premium, color: Colors.white, size: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Ví Ma Thuật Pro', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(color: Colors.white)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
      );
    },
  );
}

class GeneralScreen extends StatefulWidget {
  const GeneralScreen({super.key});
  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
  final s = Services.I;
  int weekStart = DateTime.monday, monthStart = 1;

  @override
  void initState() {
    super.initState();
    s.prefs().then(
      (p) => setState(() {
        weekStart = p.weekStart;
        monthStart = p.monthStartDay;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    const days = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt chung')),
      body: ListView(
        children: [
          const ListTile(title: Text('Tiền tệ'), trailing: Text('VND')),
          ListTile(
            title: const Text('Tuần bắt đầu'),
            trailing: DropdownButton<int>(
              value: weekStart,
              items: [for (var i = 1; i <= 7; i++) DropdownMenuItem(value: i, child: Text(days[i - 1]))],
              onChanged: (v) async {
                await s.db.setSetting('week_start', '$v');
                setState(() => weekStart = v!);
              },
            ),
          ),
          ListTile(
            title: const Text('Tháng tài chính bắt đầu ngày'),
            subtitle: const Text('Ví dụ ngày nhận lương'),
            trailing: DropdownButton<int>(
              value: monthStart,
              items: [for (var i = 1; i <= 28; i++) DropdownMenuItem(value: i, child: Text('$i'))],
              onChanged: (v) async {
                await s.db.setSetting('month_start_day', '$v');
                setState(() => monthStart = v!);
              },
            ),
          ),
          // Xin quyền bằng hộp thoại hệ thống; đã từ chối thì chỉ còn cách vào Cài đặt (có hướng dẫn ở dòng dưới).
          ListTile(
            title: const Text('Xin quyền gửi thông báo'),
            subtitle: const Text('Cảnh báo ngân sách, báo cáo tuần/tháng, giao dịch mới'),
            trailing: const Icon(Icons.notifications_active_outlined),
            onTap: s.notifier.requestPermission,
          ),
          const SetupChecklist(only: ['notifications']),
        ],
      ),
    );
  }
}

/// SC-11: khoá app, chặn chụp màn hình, ẩn số tiền.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final s = Services.I;
  bool lock = false, secure = true, canAuth = false;

  @override
  void initState() {
    super.initState();
    () async {
      final l = await s.flag('lock_enabled');
      final sec = await s.flag('secure_flag', def: true);
      final can = !kIsWeb && await LocalAuthentication().isDeviceSupported();
      setState(() {
        lock = l;
        secure = sec;
        canAuth = can;
      });
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bảo mật')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Khoá app'),
            subtitle: Text(
              canAuth ? 'Mở bằng vân tay / Face ID / mã PIN máy; tự khoá sau 1 phút ở nền' : 'Thiết bị này không hỗ trợ',
            ),
            value: lock,
            onChanged: !canAuth
                ? null
                : (v) async {
                    // Xác thực trước khi bật để chắc người dùng mở lại được.
                    if (v && !await LocalAuthentication().authenticate(localizedReason: 'Xác nhận để bật khoá app')) return;
                    await s.setFlag('lock_enabled', v);
                    setState(() => lock = v);
                  },
          ),
          if (!kIsWeb)
            SwitchListTile(
              // Android: FLAG_SECURE chặn cả chụp màn hình; iOS: chỉ che được trong trình chuyển ứng dụng.
              title: Text(NativeCapture.supported ? 'Chặn chụp màn hình' : 'Che nội dung khi chuyển ứng dụng'),
              subtitle: const Text('Ẩn nội dung trong trình chuyển ứng dụng'),
              value: secure,
              onChanged: (v) async {
                await s.setFlag('secure_flag', v);
                await NativeCapture.setSecure(v);
                privacyCover.value = v;
                setState(() => secure = v);
              },
            ),
          ValueListenableBuilder(
            valueListenable: hideAmounts,
            builder: (context, h, _) => SwitchListTile(
              title: const Text('Ẩn số tiền'),
              subtitle: const Text('Hoặc chạm 2 lần vào tổng số dư'),
              value: h,
              onChanged: (v) => hideAmounts.value = v,
            ),
          ),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Dữ liệu được mã hoá trên máy'),
            subtitle: Text('Khoá giữ trong Keystore/Keychain. Bản web chưa mã hoá — xem README.'),
          ),
        ],
      ),
    );
  }
}
