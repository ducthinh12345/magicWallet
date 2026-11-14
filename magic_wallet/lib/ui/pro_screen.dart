import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pro/billing.dart';
import '../pro/pro.dart';
import '../services.dart';
import 'widgets.dart';

/// Chặn một thao tác Pro: đã có Pro thì cho qua (true); chưa có thì giải thích và mời xem gói, trả false.
Future<bool> requirePro(BuildContext context, String what) async {
  if (await Services.I.pro()) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined),
      title: const Text('Tính năng Pro'),
      content: Text('$what cần gói Ví Ma Thuật Pro. Dữ liệu hiện có của bạn vẫn giữ nguyên.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Để sau')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xem gói Pro')),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProScreen()));
  }
  return Services.I.pro();
}

const _benefits = [
  ('Ví / tài khoản', 'Tối đa 3', 'Không giới hạn'),
  ('Ghi tự động ngân hàng, ví', '1 tổ chức', 'Cả 25 tổ chức'),
  ('Đọc email hoá đơn', '—', 'Có'),
  ('Tự xác nhận khi tin cậy ≥ 95%', '—', 'Có'),
  ('Quy tắc phân loại', '5', 'Không giới hạn'),
  ('Ngân sách', '1 tổng + 3 danh mục', 'Không giới hạn, chuyển dư'),
  ('Báo cáo', 'Tuần, Tháng', '+ Quý, Năm, bản đồ nhiệt'),
  ('Nhận xét tự động', 'Báo cáo tuần', 'Mọi báo cáo'),
  ('Sao lưu Drive', 'Thủ công', 'Tự động hằng ngày, giữ 30 bản'),
  ('Bảo mật, xuất CSV/JSON, đồng bộ Sheets', 'Có', 'Có'),
];

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});
  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  final s = Services.I;
  ProState? state;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    s.billing.changed.addListener(_load);
    s.billing.message.addListener(_toast);
    _load();
  }

  @override
  void dispose() {
    s.billing.changed.removeListener(_load);
    s.billing.message.removeListener(_toast);
    super.dispose();
  }

  Future<void> _load() async {
    final st = await ProState.load(s.db);
    if (mounted) setState(() => state = st);
  }

  void _toast() {
    final m = s.billing.message.value;
    if (m.isNotEmpty && mounted) toast(context, m);
  }

  @override
  Widget build(BuildContext context) {
    final st = state;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final b = s.billing;
    final yearly = b.product(kProYearly), lifetime = b.product(kProLifetime);
    return Scaffold(
      appBar: AppBar(title: const Text('Ví Ma Thuật Pro')),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                color: st.isPro(now) ? theme.colorScheme.primaryContainer : null,
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium),
                  title: Text(switch (st.owned) {
                    'lifetime' => 'Bạn đang dùng Pro trọn đời',
                    'yearly' => 'Bạn đang dùng Pro gói năm',
                    _ => st.trialActive(now) ? 'Đang dùng thử Pro — còn ${st.trialDaysLeft(now)} ngày' : 'Bạn đang dùng bản miễn phí',
                  }),
                  subtitle: st.owned == 'yearly'
                      ? Text('Quản lý hoặc huỷ gia hạn trong $cancelHint.')
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Table(
                columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.6)},
                children: [
                  TableRow(children: [
                    const SizedBox(),
                    Text('Miễn phí', style: theme.textTheme.labelLarge),
                    Text('Pro', style: theme.textTheme.labelLarge),
                  ]),
                  for (final (f, free, pro) in _benefits)
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(f)),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(free)),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(pro, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                ],
              ),
              const SizedBox(height: 16),
              if (!st.purchased) ...[
                if (!b.available)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text('Chưa kết nối được $storeName'),
                      subtitle: Text('Mua Pro cần bản cài từ $storeName (kể cả bản thử nghiệm) và đã đăng nhập $storeName trên máy.'),
                    ),
                  ),
                // Giá lấy nguyên văn từ kho ứng dụng: đã gồm thuế, đúng tiền tệ của người mua.
                if (yearly != null)
                  _buyButton(yearly.price, 'mỗi năm · tự gia hạn, huỷ bất cứ lúc nào', () => b.buy(yearly), primary: true),
                if (lifetime != null) _buyButton(lifetime.price, 'trả một lần · dùng trọn đời', () => b.buy(lifetime)),
                if (b.available && yearly == null && lifetime == null)
                  Text('Không tải được giá từ $storeName. Kiểm tra mạng rồi mở lại màn này.'),
                if (st.canStartTrial) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await s.startTrial();
                      await _load();
                      if (context.mounted) toast(context, 'Đã bật dùng thử Pro $trialDays ngày');
                    },
                    child: const Text('Dùng thử $trialDays ngày miễn phí — không cần thẻ'),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy || !b.available
                    ? null
                    : () async {
                        setState(() => busy = true);
                        final ok = await b.refresh();
                        await _load();
                        setState(() => busy = false);
                        if (context.mounted) {
                          toast(context, !ok ? 'Không kết nối được $storeName' : (state!.purchased ? 'Đã khôi phục Pro' : 'Không tìm thấy giao dịch mua nào'));
                        }
                      },
                child: const Text('Khôi phục giao dịch mua'),
              ),
              const SizedBox(height: 8),
              // Luật BVQLNTD 2023: thông tin gia hạn, cách huỷ hiển thị ngay trên màn mua; không dùng thiết kế đánh lừa.
              Text(
                'Giá hiển thị là giá $storeName tính cho bạn, đã gồm thuế. Gói năm tự gia hạn mỗi năm cho tới khi bạn huỷ; '
                'huỷ trước ngày gia hạn ít nhất 24 giờ trong $cancelHint để không bị trừ tiền kỳ sau. '
                'Hết hạn Pro, dữ liệu vẫn giữ nguyên và xem được: ví thứ 4 trở đi chuyển sang chỉ đọc, ghi tự động quay về 1 nguồn. '
                'Quyền Pro gắn với tài khoản $storeName và khôi phục được trên máy mới.',
                style: theme.textTheme.bodySmall,
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(manageSubscriptionsUrl),
                    mode: LaunchMode.externalApplication),
                child: Text('Mở trang quản lý gói thuê bao của $storeName'),
              ),
            ]),
    );
  }

  Widget _buyButton(String price, String note, VoidCallback onTap, {bool primary = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 64,
          child: (primary ? FilledButton.new : OutlinedButton.new)(
            onPressed: onTap,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(note, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );
}
