import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/pro.dart';
import '../app/session.dart';
import '../app/tracker.dart';
import '../data/sync.dart';
import '../main.dart' show pro, rose, track;
import 'home.dart';

/// URL công khai của chính sách & trang xoá tài khoản (docs/release/*.md đăng lên web). Play bắt buộc.
const privacyUrl = String.fromEnvironment('PRIVACY_URL');

/// SC-07.
class ProScreen extends StatelessWidget {
  final String? reason;
  const ProScreen({super.key, this.reason});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Gói Gia đình')),
        body: ValueListenableBuilder(
          valueListenable: pro.owned,
          builder: (_, owned, _) => ListView(padding: const EdgeInsets.all(20), children: [
            if (reason != null && !owned)
              Card(color: rose.withValues(alpha: 0.1), child: ListTile(leading: const Icon(Icons.info_outline), title: Text(reason!))),
            const Icon(Icons.family_restroom, size: 72, color: rose),
            const SizedBox(height: 12),
            Text(owned ? 'Bạn đã có Gói Gia đình ❤' : 'Giữ cả nhà trong một sợi tơ',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            for (final t in const [
              'Sợi tơ gia đình tới $familyMax người — cha mẹ, con cái, ông bà',
              'Tạo tới $proMaxCircles sợi tơ (gia đình, người yêu, nhóm bạn đi phượt…)',
              'Người được mời dùng miễn phí — cả nhà chỉ cần một người mua',
              'Mua một lần, dùng mãi. Không thuê bao, không quảng cáo',
            ])
              ListTile(leading: const Icon(Icons.check_circle, color: rose), title: Text(t)),
            const SizedBox(height: 16),
            if (!owned) ...[
              FilledButton(
                onPressed: pro.buy,
                child: Text('Mua trọn đời · ${pro.product?.price ?? '299.000 ₫'}'),
              ),
              TextButton(onPressed: pro.restore, child: const Text('Khôi phục giao dịch đã mua')),
            ],
            ValueListenableBuilder(
              valueListenable: pro.message,
              builder: (_, m, _) => m.isEmpty ? const SizedBox() : Padding(padding: const EdgeInsets.all(8), child: Text(m, textAlign: TextAlign.center)),
            ),
            const SizedBox(height: 8),
            const Text('Vị trí, kế hoạch, kỷ niệm, SOS, tạm ẩn luôn miễn phí cho sợi tơ đôi.', textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// SC-08.
class SettingsScreen extends StatelessWidget {
  final Sync sync;
  const SettingsScreen({super.key, required this.sync});

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Xoá dữ liệu & rời mọi sợi tơ?'),
        content: const Text('Bạn sẽ rời mọi sợi tơ; lịch chung do bạn tạo (gồm kế hoạch, kỷ niệm) bị xoá khỏi Google Calendar của mọi người; '
            'lộ trình trên máy bị xoá; app thu hồi quyền Google. Dây tơ hồng không có máy chủ nên không còn dữ liệu nào khác. Không hoàn tác được.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Thôi')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(d, true), child: const Text('Xoá vĩnh viễn')),
        ],
      ),
    );
    if (ok != true) return;
    if (await Tracker.running) Tracker.stop();
    if (!context.mounted) return;
    await guard(context, () async {
      final nav = Navigator.of(context), messenger = ScaffoldMessenger.of(context);
      final failed = await wipeAll(sync, track);
      if (failed > 0) {
        messenger.showSnackBar(SnackBar(content: Text('$failed sợi tơ chưa xoá được trên Google Calendar — xoá tay lịch "Dây tơ hồng" trong Google Calendar.')));
      }
      nav.popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cài đặt')),
        body: ListView(children: [
          ListTile(leading: const Icon(Icons.account_circle_outlined), title: Text(sync.name), subtitle: Text(sync.email)),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined, color: rose),
            title: const Text('Gói Gia đình'),
            subtitle: Text(pro.owned.value ? 'Đã mở vĩnh viễn' : '299.000 ₫ một lần'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProScreen())),
          ),
          const ListTile(leading: Icon(Icons.battery_alert_outlined), title: Text('Vị trí hay bị ngắt?'), subtitle: Text(batteryHint)),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Chính sách quyền riêng tư'),
            subtitle: privacyUrl.isEmpty ? const Text('Bản build chưa đặt PRIVACY_URL') : null,
            onTap: privacyUrl.isEmpty ? null : () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Đăng xuất'),
            onTap: () async {
              final nav = Navigator.of(context);
              if (await Tracker.running) Tracker.stop();
              await signOut();
              nav.popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Xoá dữ liệu & rời mọi sợi tơ', style: TextStyle(color: Colors.red)),
            onTap: () => _delete(context),
          ),
        ]),
      );
}
