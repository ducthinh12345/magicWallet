import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/periods.dart';
import '../data/database.dart';
import '../reports/report.dart';
import '../services.dart';
import 'add_txn.dart';
import 'widgets.dart';

/// Cung cấp bảng tra danh mục/ví (cập nhật trực tiếp từ DB) cho các danh sách.
class WithLookups extends StatelessWidget {
  final Widget Function(BuildContext, Map<String, Category>, Map<String, Wallet>) builder;
  const WithLookups({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Category>>(
    stream: Services.I.repo.watchCategories(),
    builder: (context, c) => StreamBuilder<List<Wallet>>(
      stream: Services.I.repo.watchWallets(),
      builder: (context, w) => builder(
        context,
        {for (final x in c.data ?? const <Category>[]) x.id: x},
        {for (final x in w.data ?? const <Wallet>[]) x.id: x},
      ),
    ),
  );
}

Future<void> openEditor(BuildContext context, [Txn? t]) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => AddTxnScreen(editing: t)));

// ---------------- SC-02 Tổng quan ----------------

class OverviewTab extends StatelessWidget {
  final VoidCallback openPending;
  const OverviewTab({super.key, required this.openPending});

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    final theme = Theme.of(context);
    return WithLookups(
      builder: (context, cats, wallets) {
        if (wallets.isEmpty) {
          return const EmptyState('Chưa có ví nào. Vào tab Thêm › Ví để tạo ví đầu tiên kèm số dư.');
        }
        return StreamBuilder<Map<String, int>>(
          stream: s.repo.watchBalances(),
          builder: (context, bal) {
            final total = wallets.values.where((w) => !w.archived).fold<int>(0, (a, w) => a + (bal.data?[w.id] ?? 0));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GestureDetector(
                  onDoubleTap: () => hideAmounts.value = !hideAmounts.value,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tổng số dư', style: theme.textTheme.labelLarge),
                          Money(total, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          Text('Chạm 2 lần để ẩn/hiện số tiền', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
                _ReconcileHints(wallets: wallets, balances: bal.data ?? const {}),
                const _MonthBudgetCard(),
                StreamBuilder<List<Txn>>(
                  stream: s.repo.watchPending(),
                  builder: (context, p) => (p.data?.isEmpty ?? true)
                      ? const SizedBox()
                      : Card(
                          color: theme.colorScheme.tertiaryContainer,
                          child: ListTile(
                            leading: const Icon(Icons.inbox),
                            title: Text('Chờ duyệt (${p.data!.length})'),
                            subtitle: const Text('Giao dịch ghi tự động cần bạn xác nhận'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: openPending,
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Text('Gần đây', style: theme.textTheme.titleMedium),
                StreamBuilder<List<Txn>>(
                  stream: s.repo.watchTxns(limit: 5),
                  builder: (context, t) => (t.data?.isEmpty ?? true)
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có giao dịch. Bấm + để ghi khoản đầu tiên.'))
                      : Column(
                          children: [for (final x in t.data!) TxnTile(x, cats, wallets, onTap: () => openEditor(context, x))],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ReconcileHints extends StatelessWidget {
  final Map<String, Wallet> wallets;
  final Map<String, int> balances;
  const _ReconcileHints({required this.wallets, required this.balances});

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return Column(
      children: [
        for (final w in wallets.values)
          StreamBuilder<String?>(
            stream: s.db.watchSetting('reconcile_hint:${w.id}'),
            builder: (context, h) {
              final reported = int.tryParse(h.data ?? '');
              if (reported == null || reported == balances[w.id]) return const SizedBox();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text('Số dư ${w.name} lệch'),
                  subtitle: Text('Ngân hàng báo ${formatVnd(reported)}, app tính ${formatVnd(balances[w.id] ?? 0)}.'),
                  trailing: TextButton(
                    child: const Text('Điều chỉnh'),
                    onPressed: () async {
                      await s.repo.reconcile(w.id, reported);
                      await s.db.setSetting('reconcile_hint:${w.id}', '');
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Thanh tiến độ chi tháng so với ngân sách tổng; không có ngân sách tổng thì chỉ hiện tổng chi.
class _MonthBudgetCard extends StatelessWidget {
  const _MonthBudgetCard();

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return StreamBuilder(
      // Tính lại khi giao dịch hoặc ngân sách đổi.
      stream: s.live(_load),
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox();
        final (spent, total, insight) = d;
        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chi tháng này', style: theme.textTheme.labelLarge),
                Row(
                  children: [
                    Money(spent, style: theme.textTheme.titleLarge),
                    if (total != null) ...[const Text(' / '), Money(total.limit, style: theme.textTheme.bodyLarge)],
                  ],
                ),
                if (total != null) ...[
                  const SizedBox(height: 8),
                  Bar(total.pct, budgetColor(total.pct)),
                  const SizedBox(height: 4),
                  Text('Còn được chi ${hideAmounts.value ? '•••' : formatVnd(total.perDayLeft(DateTime.now()))}/ngày'),
                ],
                if (insight != null) ...[const SizedBox(height: 8), Text('💡 $insight')],
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<(int, BudgetStatus?, String?)> _load() async {
    final s = Services.I;
    final p = periodOf(PeriodType.month, DateTime.now(), await s.prefs());
    final r = await s.report(p);
    final total = (await s.budgetStatus()).where((b) => b.budget.categoryId == null && b.budget.period == 'month').firstOrNull;
    return (r.totals.expense, total, r.insights.firstOrNull);
  }
}

// ---------------- SC-05 Danh sách giao dịch ----------------

class TxnListTab extends StatefulWidget {
  const TxnListTab({super.key});
  @override
  State<TxnListTab> createState() => _TxnListTabState();
}

class _TxnListTabState extends State<TxnListTab> {
  String search = '';
  String? walletId, categoryId;
  int limit = 100;

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return WithLookups(
      builder: (context, cats, wallets) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm ghi chú, cửa hàng'),
                      onChanged: (v) => setState(() => search = v.trim()),
                    ),
                  ),
                  PopupMenuButton<String?>(
                    tooltip: 'Lọc theo ví',
                    icon: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: walletId == null ? null : Theme.of(context).colorScheme.primary,
                    ),
                    onSelected: (v) => setState(() => walletId = v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: null, child: Text('Mọi ví')),
                      for (final w in wallets.values) PopupMenuItem(value: w.id, child: Text(w.name)),
                    ],
                  ),
                  PopupMenuButton<String?>(
                    tooltip: 'Lọc theo danh mục',
                    icon: Icon(Icons.category_outlined, color: categoryId == null ? null : Theme.of(context).colorScheme.primary),
                    onSelected: (v) => setState(() => categoryId = v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: null, child: Text('Mọi danh mục')),
                      for (final c in cats.values) PopupMenuItem(value: c.id, child: Text('${c.icon} ${c.name}')),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Txn>>(
                stream: s.repo.watchTxns(search: search, walletId: walletId, categoryId: categoryId, limit: limit),
                builder: (context, snap) {
                  final list = snap.data ?? const <Txn>[];
                  if (snap.hasData && list.isEmpty) {
                    return EmptyState(
                      'Chưa có giao dịch. Bật ghi tự động?',
                      action: 'Ghi khoản đầu tiên',
                      onAction: () => openEditor(context),
                    );
                  }
                  // Nhóm theo ngày, tổng mỗi ngày ở đầu nhóm.
                  final groups = <DateTime, List<Txn>>{};
                  for (final t in list) {
                    (groups[DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day)] ??= []).add(t);
                  }
                  final days = groups.keys.toList();
                  return NotificationListener<ScrollEndNotification>(
                    onNotification: (n) {
                      // Cuộn vô hạn: gần cuối thì tải thêm.
                      if (n.metrics.extentAfter < 400 && list.length >= limit) setState(() => limit += 100);
                      return false;
                    },
                    child: ListView.builder(
                      itemCount: days.length,
                      itemBuilder: (context, i) {
                        final items = groups[days[i]]!;
                        final dayTotal = items.fold<int>(
                          0,
                          (a, t) => a + (t.type == 'expense' ? -t.amount : (t.type == 'income' ? t.amount : 0)),
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              color: Theme.of(context).colorScheme.surfaceContainer,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(child: Text(dayLabel(days[i]), style: Theme.of(context).textTheme.labelLarge)),
                                  Money(dayTotal.abs(), type: dayTotal < 0 ? 'expense' : 'income'),
                                ],
                              ),
                            ),
                            for (final t in items)
                              Dismissible(
                                key: ValueKey(t.id),
                                background: Container(
                                  color: transferColor,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 16),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.copy, color: Colors.white),
                                      Text(' Nhân bản', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                secondaryBackground: Container(
                                  color: expenseColor,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Icon(Icons.delete, color: Colors.white),
                                      Text(' Xoá', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                confirmDismiss: (dir) async {
                                  if (dir == DismissDirection.startToEnd) {
                                    await _duplicate(t);
                                    if (context.mounted) toast(context, 'Đã nhân bản sang hôm nay');
                                    return false;
                                  }
                                  await s.repo.deleteTxn(t.id);
                                  if (context.mounted) {
                                    toast(
                                      context,
                                      'Đã xoá',
                                      action: SnackBarAction(label: 'Hoàn tác', onPressed: () => s.repo.undoDeleteTxn(t.id)),
                                    );
                                  }
                                  return true;
                                },
                                child: TxnTile(t, cats, wallets, onTap: () => openEditor(context, t)),
                              ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _duplicate(Txn t) async {
    final s = Services.I;
    await s.repo.saveTxn(
      TransactionsCompanion.insert(
        walletId: t.walletId,
        toWalletId: Value(t.toWalletId),
        type: t.type,
        amount: t.amount,
        amountBase: t.amountBase,
        categoryId: Value(t.categoryId),
        occurredAt: DateTime.now(),
        note: Value(t.note),
        merchant: Value(t.merchant),
      ),
      tags: await s.repo.tagsOf(t.id),
    );
  }
}

// ---------------- SC-04 Hàng chờ duyệt ----------------

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chờ duyệt'),
        actions: [
          TextButton(
            onPressed: () async {
              await s.repo.confirmAllPending();
              await s.checkBudgetAlerts();
            },
            child: const Text('Xác nhận tất cả'),
          ),
        ],
      ),
      body: WithLookups(
        builder: (context, cats, wallets) {
          return StreamBuilder<List<Txn>>(
            stream: s.repo.watchPending(),
            builder: (context, snap) {
              final list = snap.data ?? const <Txn>[];
              if (snap.hasData && list.isEmpty) return const EmptyState('Không còn gì chờ duyệt. 🎉');
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Vuốt phải = xác nhận · vuốt trái = bỏ qua · chạm = sửa'),
                  ),
                  for (final t in list)
                    Card(
                      child: Dismissible(
                        key: ValueKey('p${t.id}'),
                        background: Container(
                          color: incomeColor,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 16),
                          child: const Icon(Icons.check, color: Colors.white, semanticLabel: 'Xác nhận'),
                        ),
                        secondaryBackground: Container(
                          color: Colors.grey,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.close, color: Colors.white, semanticLabel: 'Bỏ qua'),
                        ),
                        onDismissed: (dir) async {
                          await s.repo.setStatus(t.id, dir == DismissDirection.startToEnd ? 'confirmed' : 'ignored');
                          await s.checkBudgetAlerts();
                        },
                        child: Column(
                          children: [
                            TxnTile(t, cats, wallets, onTap: () => openEditor(context, t)),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                              child: Row(
                                children: [
                                  Text(
                                    'Nguồn: ${_src[t.source] ?? t.source} · tin cậy ${((t.confidence ?? 0) * 100).round()}%',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: 'Bỏ qua',
                                    icon: const Icon(Icons.close),
                                    onPressed: () => s.repo.setStatus(t.id, 'ignored'),
                                  ),
                                  IconButton.filledTonal(
                                    tooltip: 'Xác nhận',
                                    icon: const Icon(Icons.check),
                                    onPressed: () async {
                                      await s.repo.setStatus(t.id, 'confirmed');
                                      await s.checkBudgetAlerts();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

const _src = {
  'notification': 'Thông báo',
  'email': 'Email',
  'import': 'Sao kê',
  'recurring': 'Định kỳ',
  'ocr': 'Biên lai',
  'manual': 'Nhập tay',
};
