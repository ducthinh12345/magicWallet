import 'package:flutter/material.dart';

import '../services.dart';
import 'widgets.dart';

/// Một thiết lập hệ thống mà tính năng cần: vì sao cần, và các bước bấm trong màn cài đặt.
class SetupStep {
  final String key; // tên lệnh openSetting phía Android
  final IconData icon;
  final String title, why;
  final List<String> steps;
  final bool miuiOnly;
  const SetupStep(this.key, this.icon, this.title, this.why, this.steps, {this.miuiOnly = false});
}

/// Các bước viết theo đúng chữ trên MIUI/HyperOS (máy thử: Redmi Note 11 Pro 5G); máy khác tên mục gần giống.
List<SetupStep> captureSetup(bool miui) => [
      const SetupStep(
        'listener',
        Icons.notifications_active_outlined,
        'Quyền truy cập thông báo',
        'Để đọc thông báo biến động số dư của app ngân hàng bạn đã chọn. Không có quyền này thì không ghi tự động được.',
        [
          'Ở trang "Thông báo của thiết bị và ứng dụng", chạm "Ví Ma Thuật" (nằm trong nhóm "Không được phép").',
          'Bật công tắc cho phép truy cập thông báo.',
          'Bấm "Cho phép" ở hộp thoại xác nhận.',
          'Bấm nút Quay lại để về app.',
        ],
      ),
      SetupStep(
        'battery',
        Icons.battery_charging_full_outlined,
        miui ? 'Tiết kiệm pin: Không hạn chế' : 'Bỏ tối ưu hoá pin',
        'Hệ thống tiết kiệm pin hay tắt app chạy nền, làm giao dịch chỉ hiện khi bạn mở app.',
        miui
            ? ['Ở trang "Ví Ma Thuật" vừa mở, mục "Cài đặt nền", chọn "Không hạn chế".', 'Bấm nút Quay lại để về app.']
            : ['Chọn "Tất cả ứng dụng", tìm "Ví Ma Thuật".', 'Chọn "Không tối ưu hoá" (hoặc "Không hạn chế").', 'Bấm nút Quay lại để về app.'],
      ),
      if (miui)
        const SetupStep(
          'autostart',
          Icons.restart_alt,
          'Tự khởi chạy nền',
          'MIUI chặn app tự chạy lại sau khi bị đóng hoặc khởi động lại máy. Cần bật để luôn bắt được thông báo.',
          [
            'Ở trang "Tự khởi chạy nền", tìm "Ví Ma Thuật".',
            'Bật công tắc bên cạnh (đã bật thì nằm trong nhóm "có thể bắt đầu trong nền").',
            'Bấm nút Quay lại để về app.',
          ],
          miuiOnly: true,
        ),
      const SetupStep(
        'notifications',
        Icons.notifications_outlined,
        'Cho phép Ví Ma Thuật gửi thông báo',
        'Để báo "Đã ghi 45.000đ – Ăn uống. Đúng không?", cảnh báo ngân sách và báo cáo tuần.',
        ['Ở trang "Ví Ma Thuật", bật "Hiển thị thông báo".', 'Bấm nút Quay lại để về app.'],
      ),
    ];

/// Hỏi trước, chỉ cách làm; người dùng bấm "Mở cài đặt" mới chuyển sang màn cài đặt. Trả về true nếu đã mở.
Future<bool> guideTo(BuildContext context, SetupStep step) async {
  final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(step.icon),
          title: Text(step.title),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(step.why),
              const SizedBox(height: 12),
              Text('Bạn sẽ được chuyển sang Cài đặt của điện thoại. Hãy làm:', style: Theme.of(c).textTheme.titleSmall),
              const SizedBox(height: 4),
              for (var i = 0; i < step.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 22, child: Text('${i + 1}.')),
                    Expanded(child: Text(step.steps[i])),
                  ]),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Để sau')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Mở cài đặt')),
          ],
        ),
      ) ??
      false;
  if (ok) await NativeCapture.openSetting(step.key);
  return ok;
}

/// Danh sách kiểm tra: mỗi thiết lập một dòng, trạng thái thật đọc từ hệ thống, nút "Thiết lập" mở hướng dẫn.
/// Tự đọc lại khi người dùng quay về từ màn cài đặt.
class SetupChecklist extends StatefulWidget {
  final List<String> only; // rỗng = tất cả
  const SetupChecklist({super.key, this.only = const []});
  @override
  State<SetupChecklist> createState() => _SetupChecklistState();
}

class _SetupChecklistState extends State<SetupChecklist> with WidgetsBindingObserver {
  Map<String, dynamic> status = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final st = await NativeCapture.setupStatus();
    if (mounted) setState(() => status = st);
  }

  @override
  Widget build(BuildContext context) {
    if (!NativeCapture.supported || status.isEmpty) return const SizedBox();
    final steps = captureSetup(status['miui'] == true).where((s) => widget.only.isEmpty || widget.only.contains(s.key));
    return Column(children: [
      for (final st in steps)
        ListTile(
          leading: Icon(st.icon),
          title: Text(st.title),
          // Tự khởi chạy của MIUI không đọc được trạng thái → ghi rõ, không giả vờ đã bật.
          subtitle: Text(switch (status[st.key]) {
            true => 'Đã bật',
            false => 'Chưa bật',
            _ => 'Không kiểm tra tự động được — hãy tự xác nhận đã bật',
          }),
          trailing: status[st.key] == true
              ? const Icon(Icons.check_circle, color: incomeColor, semanticLabel: 'Đã bật')
              : FilledButton.tonal(onPressed: () => guideTo(context, st), child: const Text('Thiết lập')),
        ),
    ]);
  }
}
