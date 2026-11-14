import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/periods.dart';
import '../data/database.dart';
import '../reports/report.dart';
import '../services.dart';
import 'add_txn.dart';
import 'manage.dart';
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
  final VoidCallback openPending, openTransactions;
  const OverviewTab({super.key, required this.openPending, required this.openTransactions});

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return WithLookups(
      builder: (context, cats, wallets) {
        if (wallets.isEmpty) {
          return EmptyState(
            'Chưa có ví nào. Tạo ví đầu tiên kèm số dư hiện tại để bắt đầu.',
            action: 'Tạo ví',
            onAction: () => editWallet(context),
          );
        }
        return StreamBuilder<_Overview>(
          stream: s.live(_Overview.load),
          builder: (context, snap) {
            final d = snap.data;
            if (d == null) return const Center(child: CircularProgressIndicator());
            final active = wallets.values.where((w) => !w.archived).toList();
            final total = active.fold<int>(0, (a, w) => a + (d.balances[w.id] ?? 0));
            final top = d.month.byCategory.take(3).toList();
            final topMax = top.isEmpty ? 1 : top.first.value;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _HeroCard(total: total, income: d.month.totals.income, expense: d.month.totals.expense),
                _ReconcileHints(wallets: wallets, balances: d.balances),
                StreamBuilder<List<Txn>>(
                  stream: s.repo.watchPending(),
                  builder: (context, p) => (p.data?.isEmpty ?? true)
                      ? const SizedBox()
                      : Card(
                          color: const Color(0xFFFFF3E0),
                          child: ListTile(
                            leading: const IconBadge(
                              color: Color(0xFFEF6C00),
                              child: Icon(Icons.inbox, color: Color(0xFFEF6C00)),
                            ),
                            title: Text(
                              '${p.data!.length} giao dịch chờ duyệt',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF5D4037)),
                            ),
                            subtitle: const Text('Ghi tự động — chạm để xác nhận', style: TextStyle(color: Color(0xFF795548))),
                            trailing: const Icon(Icons.chevron_right, color: Color(0xFF795548)),
                            onTap: openPending,
                          ),
                        ),
                ),
                if (d.budget != null) _BudgetRing(d.budget!),
                SectionHeader(
                  'Ví của tôi',
                  action: 'Quản lý',
                  onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletsScreen())),
                ),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: active.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => _WalletChip(active[i], d.balances[active[i].id] ?? 0),
                  ),
                ),
                if (d.month.insights.isNotEmpty)
                  Card(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(d.month.insights.first)),
                        ],
                      ),
                    ),
                  ),
                if (top.isNotEmpty) ...[
                  const SectionHeader('Chi nhiều nhất tháng này'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Column(
                        children: [
                          for (final e in top)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  IconBadge(
                                    size: 38,
                                    color: Color(cats[e.key]?.color ?? 0xFF9E9E9E),
                                    child: Text(cats[e.key]?.icon ?? '❔', style: const TextStyle(fontSize: 18)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                cats[e.key]?.name ?? 'Chưa phân loại',
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                            Money(e.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Bar(e.value / topMax, Color(cats[e.key]?.color ?? 0xFF9E9E9E)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                SectionHeader('Giao dịch gần đây', action: 'Xem tất cả', onAction: openTransactions),
                StreamBuilder<List<Txn>>(
                  stream: s.repo.watchTxns(limit: 5),
                  builder: (context, t) => (t.data?.isEmpty ?? true)
                      ? const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Chưa có giao dịch. Bấm + để ghi khoản đầu tiên.'),
                          ),
                        )
                      : Card(
                          child: Column(
                            children: [for (final x in t.data!) TxnTile(x, cats, wallets, onTap: () => openEditor(context, x))],
                          ),
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

/// Dữ liệu màn Tổng quan, tính lại mỗi khi DB đổi.
class _Overview {
  final Map<String, int> balances;
  final Report month;
  final BudgetStatus? budget; // ngân sách tổng của tháng, nếu có
  const _Overview(this.balances, this.month, this.budget);

  static Future<_Overview> load() async {
    final s = Services.I;
    final p = periodOf(PeriodType.month, DateTime.now(), await s.prefs());
    final budget = (await s.budgetStatus()).where((b) => b.budget.categoryId == null && b.budget.period == 'month').firstOrNull;
    return _Overview(await s.repo.walletBalances(), await s.report(p), budget);
  }
}

class _HeroCard extends StatelessWidget {
  final int total, income, expense;
  const _HeroCard({required this.total, required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white);
    return GestureDetector(
      onDoubleTap: () => hideAmounts.value = !hideAmounts.value,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF00897B), Color(0xFF26A69A), Color(0xFF66BB6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFF00897B).withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Tổng số dư', style: white.copyWith(fontSize: 14, color: Colors.white70)),
                const Spacer(),
                ValueListenableBuilder(
                  valueListenable: hideAmounts,
                  builder: (context, h, _) => IconButton(
                    tooltip: h ? 'Hiện số tiền' : 'Ẩn số tiền',
                    icon: Icon(h ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white),
                    onPressed: () => hideAmounts.value = !h,
                  ),
                ),
              ],
            ),
            Money(total, style: white.copyWith(fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(label: 'Thu tháng này', amount: income, icon: Icons.south_west),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroStat(label: 'Chi tháng này', amount: expense, icon: Icons.north_east),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final int amount;
  final IconData icon;
  const _HeroStat({required this.label, required this.amount, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
    child: Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Colors.white,
          child: Icon(icon, size: 16, color: const Color(0xFF00897B)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Money(
                  amount,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BudgetRing extends StatelessWidget {
  final BudgetStatus b;
  const _BudgetRing(this.b);

  @override
  Widget build(BuildContext context) {
    final c = budgetColor(b.pct);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: b.pct.clamp(0, 1).toDouble(),
                      strokeWidth: 8,
                      color: c,
                      backgroundColor: c.withValues(alpha: 0.15),
                      strokeCap: StrokeCap.round,
                    ),
                    Center(
                      child: Text(
                        '${(b.pct * 100).round()}%',
                        style: TextStyle(fontWeight: FontWeight.w800, color: c),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ngân sách tháng', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(children: [Money(b.spent), const Text(' / '), Money(b.limit)]),
                    const SizedBox(height: 2),
                    ValueListenableBuilder(
                      valueListenable: hideAmounts,
                      builder: (context, h, _) => Text(
                        b.remaining >= 0
                            ? 'Còn được chi ${h ? '•••' : formatVnd(b.perDayLeft(DateTime.now()))}/ngày'
                            : 'Đã vượt ngân sách',
                        style: TextStyle(color: b.remaining >= 0 ? null : c, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletChip extends StatelessWidget {
  final Wallet w;
  final int balance;
  const _WalletChip(this.w, this.balance);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 156,
    child: Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => editWallet(context, w),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconBadge(
                size: 34,
                color: Theme.of(context).colorScheme.primary,
                child: Text(w.icon, style: const TextStyle(fontSize: 17)),
              ),
              Text(
                w.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Money(balance, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
                        // Mỗi ngày một thẻ trắng: tiêu đề ngày + tổng ngày, các giao dịch bên trong.
                        return Card(
                          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        dayLabel(days[i]),
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                      ),
                                    ),
                                    Money(
                                      dayTotal.abs(),
                                      type: dayTotal < 0 ? 'expense' : 'income',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 8, indent: 16, endIndent: 16),
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
                          ),
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
