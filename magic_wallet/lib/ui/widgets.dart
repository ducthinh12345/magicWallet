import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/database.dart';

/// Chế độ riêng tư (9.3): chạm 2 lần vào số dư để ẩn mọi số tiền thành "•••".
final hideAmounts = ValueNotifier<bool>(false);

const expenseColor = Color(0xFFE64A19); // đỏ cam
const incomeColor = Color(0xFF2E7D32); // xanh lá
const transferColor = Color(0xFF546E7A); // xám xanh

const tabular = [FontFeature.tabularFigures()];

Color typeColor(String type) => switch (type) {
  'income' => incomeColor,
  'transfer' => transferColor,
  _ => expenseColor,
};
IconData typeIcon(String type) => switch (type) {
  'income' => Icons.south_west,
  'transfer' => Icons.swap_horiz,
  _ => Icons.north_east,
};

/// Số tiền luôn kèm dấu +/− và icon, không dùng màu làm tín hiệu duy nhất (9.3).
class Money extends StatelessWidget {
  final int amount;
  final String? type;
  final TextStyle? style;
  const Money(this.amount, {super.key, this.type, this.style});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: hideAmounts,
    builder: (context, hidden, _) {
      final signed = type == 'expense' ? -amount : amount;
      final text = formatVnd(signed, sign: type == 'income', hidden: hidden);
      return Text(
        text,
        semanticsLabel: hidden ? 'Số tiền đã ẩn' : text,
        style: (style ?? const TextStyle()).copyWith(
          fontFeatures: tabular,
          color: type == null ? style?.color : typeColor(type!),
        ),
      );
    },
  );
}

/// Trạng thái rỗng: một câu hướng dẫn + một nút hành động (9.3).
class EmptyState extends StatelessWidget {
  final String message;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState(this.message, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: 12), FilledButton(onPressed: onAction, child: Text(action!))],
        ],
      ),
    ),
  );
}

class TxnTile extends StatelessWidget {
  final Txn t;
  final Map<String, Category> cats;
  final Map<String, Wallet> wallets;
  final VoidCallback? onTap;
  final Widget? trailing;
  const TxnTile(this.t, this.cats, this.wallets, {super.key, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = cats[t.categoryId];
    final title = t.type == 'transfer'
        ? '${wallets[t.walletId]?.name ?? '?'} → ${wallets[t.toWalletId]?.name ?? '?'}'
        : (c?.name ?? 'Chưa phân loại');
    final sub = [t.merchant, t.note].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      onTap: onTap,
      minTileHeight: 56,
      leading: CircleAvatar(
        backgroundColor: Color(c?.color ?? transferColor.toARGB32()).withValues(alpha: 0.15),
        child: t.type == 'transfer' ? Icon(typeIcon(t.type), color: transferColor) : Text(c?.icon ?? '❔'),
      ),
      title: Text(title),
      subtitle: Text(
        [if (sub.isNotEmpty) sub, '${wallets[t.walletId]?.name ?? ''} · ${_hm(t.occurredAt)}'].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          trailing ??
          Money(
            t.amount,
            type: t.type,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
    );
  }
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  const wd = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  return '${wd[d.weekday - 1]}, ${d.day}/${d.month}${d.year == now.year ? '' : '/${d.year}'}';
}

/// Thanh ngang đơn giản cho cơ cấu danh mục / ngân sách.
class Bar extends StatelessWidget {
  final double value; // 0..1 (có thể >1)
  final Color color;
  const Bar(this.value, this.color, {super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1).toDouble(),
      minHeight: 8,
      color: color,
      backgroundColor: color.withValues(alpha: 0.15),
    ),
  );
}

/// Màu theo mức dùng ngân sách: xanh < 80% ≤ vàng < 100% ≤ đỏ (SC-02).
Color budgetColor(double pct) => pct >= 1 ? const Color(0xFFD32F2F) : (pct >= 0.8 ? const Color(0xFFF9A825) : incomeColor);

Future<bool> confirm(BuildContext context, String message, {String ok = 'Đồng ý'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

void toast(BuildContext context, String msg, {SnackBarAction? action}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), action: action));

/// iOS không có FLAG_SECURE: che nội dung khi app rời màn hình để ảnh trong trình chuyển app không lộ số tiền (10.1).
final privacyCover = ValueNotifier<bool>(true);

class PrivacyCover extends StatefulWidget {
  final Widget child;
  const PrivacyCover({super.key, required this.child});
  @override
  State<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends State<PrivacyCover> with WidgetsBindingObserver {
  bool away = false;
  final bool ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (ios) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (ios) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => setState(() => away = s != AppLifecycleState.resumed);

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (ios && away && privacyCover.value)
          const Positioned.fill(child: ColoredBox(color: Color(0xFF00796B), child: Center(child: Text('👛', style: TextStyle(fontSize: 64))))),
      ]);
}
