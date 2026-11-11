import 'dart:math';

import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/periods.dart';
import '../data/database.dart';
import '../reports/report.dart';
import '../services.dart';
import 'export.dart';
import 'lists.dart';
import 'widgets.dart';

/// SC-06: chọn Tuần | Tháng | Quý | Năm, vuốt ngang để sang kỳ trước/sau (US-05).
class ReportsTab extends StatefulWidget {
  final PeriodType initial;
  const ReportsTab({super.key, this.initial = PeriodType.month});
  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  late PeriodType type = widget.initial;
  int offset = 0;
  Future<(Report, List<Category>)>? future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final s = Services.I;
    future = () async {
      final prefs = await s.prefs();
      final p = shiftPeriod(periodOf(type, DateTime.now(), prefs), offset, prefs);
      return (await s.report(p), await s.repo.allCategories());
    }();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<PeriodType>(
            segments: [for (final t in PeriodType.values) ButtonSegment(value: t, label: Text(periodLabels[t]!))],
            selected: {type},
            onSelectionChanged: (v) {
              type = v.first;
              offset = 0;
              _reload();
            },
          ),
        ),
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 200) return;
              offset += v > 0 ? -1 : 1;
              _reload();
            },
            child: FutureBuilder<(Report, List<Category>)>(
              future: future,
              builder: (context, snap) {
                if (snap.hasError) return EmptyState('Lỗi tạo báo cáo: ${snap.error}');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final (r, cats) = snap.data!;
                return _ReportView(
                  r,
                  CatIndex(cats),
                  onShift: (n) {
                    offset += n;
                    _reload();
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportView extends StatelessWidget {
  final Report r;
  final CatIndex cats;
  final ValueChanged<int> onShift;
  const _ReportView(this.r, this.cats, {required this.onShift});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = r.totals;
    final change = pctChange(t.expense, r.previous.expense);
    final yoy = r.lastYear == null ? null : pctChange(t.expense, r.lastYear!.expense);
    final maxCat = r.byCategory.isEmpty ? 1 : r.byCategory.first.value;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(tooltip: 'Kỳ trước', onPressed: () => onShift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(r.period.label, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            ),
            IconButton(tooltip: 'Kỳ sau', onPressed: () => onShift(1), icon: const Icon(Icons.chevron_right)),
            IconButton(
              tooltip: 'Xuất CSV kỳ này',
              icon: const Icon(Icons.ios_share),
              onPressed: () => exportTxnsCsv(context, from: r.period.start, to: r.period.end, name: r.period.label),
            ),
          ],
        ),
        // 1) Tiêu bao nhiêu
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _kv(context, 'Tổng thu', Money(t.income, type: 'income')),
                _kv(context, 'Tổng chi', Money(t.expense, type: 'expense')),
                const Divider(),
                _kv(context, 'Chênh lệch', Money(t.net.abs(), type: t.net >= 0 ? 'income' : 'expense')),
                if (r.period.type != PeriodType.week && t.savingsRate != null)
                  _kv(context, 'Tỷ lệ tiết kiệm', Text('${(t.savingsRate! * 100).round()}%')),
                if (change != null) _kv(context, 'Chi so với kỳ trước', _pct(change)),
                if (yoy != null) _kv(context, 'Chi so với cùng kỳ năm trước', _pct(yoy)),
              ],
            ),
          ),
        ),
        if (r.insights.isNotEmpty)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final i in r.insights) Text('💡 $i')]),
            ),
          ),
        // 2) Tiêu vào đâu
        _section(context, 'Cơ cấu chi theo danh mục'),
        if (r.byCategory.isEmpty) const Text('Chưa có khoản chi nào trong kỳ.'),
        if (r.period.type == PeriodType.month && r.byCategory.isNotEmpty)
          Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: CustomPaint(
                painter: _Donut([for (final e in r.byCategory) (e.value, Color(cats.byId[e.key]?.color ?? 0xFF9E9E9E))]),
              ),
            ),
          ),
        for (final e in (r.period.type == PeriodType.week ? r.byCategory.take(5) : r.byCategory))
          InkWell(
            onTap: () => _showCategory(context, e.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${cats.byId[e.key]?.icon ?? '❔'} ${cats.name(e.key)}'),
                      const Spacer(),
                      Text('${t.expense == 0 ? 0 : (e.value * 100 / t.expense).round()}%  '),
                      Money(e.value),
                    ],
                  ),
                  Bar(e.value / maxCat, Color(cats.byId[e.key]?.color ?? 0xFF9E9E9E)),
                ],
              ),
            ),
          ),
        if (r.period.type != PeriodType.week) ...[
          _section(context, 'Chi cố định và biến đổi'),
          _kv(context, 'Cố định (nhà, hoá đơn…)', Money(r.fixedExpense)),
          _kv(context, 'Biến đổi', Money(r.variableExpense)),
        ],
        // 3) Xu hướng
        _section(
          context,
          r.period.type == PeriodType.week || r.period.type == PeriodType.month ? 'Chi theo ngày' : 'Chi theo tháng',
        ),
        SizedBox(height: 140, child: _TrendChart(r.trend)),
        _section(context, 'Khoản chi lớn nhất'),
        for (final x in r.largest)
          ListTile(
            dense: true,
            title: Text(x.merchant ?? (x.note.isEmpty ? cats.name(x.categoryId) : x.note)),
            subtitle: Text('${dayLabel(x.occurredAt)} · ${cats.name(x.categoryId)}'),
            trailing: Money(x.amount, type: 'expense'),
          ),
        if (r.heatmap != null) ...[_section(context, 'Bản đồ nhiệt: thứ × giờ'), _Heatmap(r.heatmap!)],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _pct(double v) => Text(
    '${v >= 0 ? '▲ +' : '▼ −'}${(v.abs() * 100).round()}%',
    style: TextStyle(color: v > 0 ? expenseColor : incomeColor, fontFeatures: tabular),
  );

  Widget _kv(BuildContext context, String k, Widget v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(k)),
        v,
      ],
    ),
  );

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  /// Chạm lát biểu đồ → xem giao dịch của danh mục đó trong kỳ (SC-06).
  void _showCategory(BuildContext context, String? rootId) {
    final s = Services.I;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (context, ctl) => WithLookups(
          builder: (context, c, w) => FutureBuilder<List<Txn>>(
            future: s.repo.confirmedBetween(r.period.start, r.period.end),
            builder: (context, snap) {
              final list =
                  (snap.data ?? const <Txn>[]).where((t) => expenseOf(t, cats) != 0 && cats.root(t.categoryId) == rootId).toList()
                    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
              return ListView(
                controller: ctl,
                children: [
                  ListTile(title: Text(cats.name(rootId), style: Theme.of(context).textTheme.titleLarge)),
                  for (final t in list) TxnTile(t, c, w),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Donut extends CustomPainter {
  final List<(int, Color)> parts;
  _Donut(this.parts);

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    if (total == 0) return;
    final rect = Rect.fromLTWH(18, 18, size.width - 36, size.height - 36);
    var start = -pi / 2;
    for (final (v, c) in parts) {
      final sweep = 2 * pi * v / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 32,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_Donut old) => old.parts != parts;
}

class _TrendChart extends StatelessWidget {
  final List<TrendPoint> points;
  const _TrendChart(this.points);

  @override
  Widget build(BuildContext context) {
    final maxV = points.fold<int>(1, (a, p) => max(a, p.expense));
    return Semantics(
      label: 'Biểu đồ chi theo thời gian, cao nhất ${formatVnd(maxV)}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in points)
            Expanded(
              child: Tooltip(
                message: '${p.label}: ${formatVnd(p.expense)}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 110 * p.expense / maxV,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: expenseColor.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (points.length <= 12 || (int.tryParse(p.label) ?? 0) % 5 == 1)
                      Text(p.label, style: const TextStyle(fontSize: 9), maxLines: 1)
                    else
                      const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  final List<List<int>> grid;
  const _Heatmap(this.grid);

  @override
  Widget build(BuildContext context) {
    final maxV = grid.expand((r) => r).fold<int>(1, max);
    const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return Column(
      children: [
        for (var d = 0; d < 7; d++)
          Row(
            children: [
              SizedBox(width: 28, child: Text(days[d], style: const TextStyle(fontSize: 11))),
              for (var h = 0; h < 24; h++)
                Expanded(
                  child: Tooltip(
                    message: '${days[d]} ${h}h: ${formatVnd(grid[d][h])}',
                    child: Container(
                      height: 14,
                      margin: const EdgeInsets.all(0.5),
                      color: expenseColor.withValues(alpha: grid[d][h] == 0 ? 0.05 : 0.15 + 0.85 * grid[d][h] / maxV),
                    ),
                  ),
                ),
            ],
          ),
        const Row(
          children: [
            SizedBox(width: 28),
            Expanded(child: Text('0h', style: TextStyle(fontSize: 10))),
            Text('23h', style: TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
