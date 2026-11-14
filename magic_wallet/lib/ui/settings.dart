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
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Ví Ma Thuật Pro'),
          subtitle: FutureBuilder<ProState>(
            future: ProState.load(Services.I.db),
            builder: (context, st) {
              final now = DateTime.now();
              final p = st.data;
              if (p == null) return const SizedBox();
              return Text(p.purchased
                  ? 'Đang dùng Pro ${p.owned == 'lifetime' ? 'trọn đời' : 'gói năm'}'
                  : p.trialActive(now)
                  ? 'Dùng thử còn ${p.trialDaysLeft(now)} ngày'
                  : 'Bản miễn phí — xem quyền lợi Pro');
            },
          ),
          onTap: () => go(const ProScreen()),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Ví & đối soát'),
          onTap: () => go(const WalletsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Danh mục'),
          onTap: () => go(const CategoriesScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Ngân sách'),
          onTap: () => go(const BudgetsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.event_repeat),
          title: const Text('Giao dịch định kỳ'),
          onTap: () => go(const RecurringScreen()),
        ),
        ListTile(leading: const Icon(Icons.rule), title: const Text('Quy tắc phân loại'), onTap: () => go(const RulesScreen())),
        const Divider(),
        ListTile(leading: const Icon(Icons.bolt), title: const Text('Ghi tự động'), onTap: () => go(const SourcesScreen())),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Google Sheets & sao lưu'),
          onTap: () => go(const GoogleScreen()),
        ),
        ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Bảo mật'), onTap: () => go(const SecurityScreen())),
        ListTile(leading: const Icon(Icons.tune), title: const Text('Cài đặt chung'), onTap: () => go(const GeneralScreen())),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.table_view_outlined),
          title: const Text('Xuất CSV toàn bộ giao dịch'),
          onTap: () => exportTxnsCsv(context, name: 'tat-ca'),
        ),
        ListTile(
          leading: const Icon(Icons.data_object),
          title: const Text('Xuất JSON toàn bộ dữ liệu'),
          onTap: () => exportAllJson(context),
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined, color: expenseColor),
          title: const Text('Xoá toàn bộ dữ liệu trên máy'),
          onTap: () async {
            if (await confirm(
              context,
              'Xoá vĩnh viễn mọi ví, giao dịch, cài đặt trên máy này? Google Sheet và bản sao lưu trên Drive không bị xoá.',
              ok: 'Xoá hết',
            )) {
              await Services.I.wipeAll();
              if (context.mounted) toast(context, 'Đã xoá toàn bộ dữ liệu');
            }
          },
        ),
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
