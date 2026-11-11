import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/database.dart';
import '../reports/report.dart';
import '../services.dart';
import 'widgets.dart';

const walletTypes = {'cash': 'Tiền mặt', 'bank': 'Ngân hàng', 'credit': 'Thẻ tín dụng', 'ewallet': 'Ví điện tử'};
const walletIcons = {'cash': '💵', 'bank': '🏦', 'credit': '💳', 'ewallet': '📱'};

/// Ô nhập số tiền chấp nhận cách gõ rút gọn (45k, 1tr2).
class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const AmountField(this.controller, this.label, {super.key});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label, hintText: 'vd 2tr5 hoặc 2.500.000'),
  );
}

// ---------------- SC-08 Ví & đối soát ----------------

class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Ví & tài khoản')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Thêm ví',
        onPressed: () => editWallet(context),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: s.repo.watchWallets(),
        builder: (context, w) => StreamBuilder<Map<String, int>>(
          stream: s.repo.watchBalances(),
          builder: (context, b) {
            final list = w.data ?? const <Wallet>[];
            if (w.hasData && list.isEmpty) {
              return EmptyState('Chưa có ví nào.', action: 'Tạo ví đầu tiên', onAction: () => editWallet(context));
            }
            return ListView(
              children: [
                for (final x in list)
                  ListTile(
                    leading: Text(x.icon, style: const TextStyle(fontSize: 24)),
                    title: Text(x.name + (x.archived ? ' (chỉ đọc)' : '')),
                    subtitle: Text([walletTypes[x.type], if (x.accountLast4 != null) '•••• ${x.accountLast4}'].join(' · ')),
                    trailing: Money(b.data?[x.id] ?? 0),
                    onTap: () => editWallet(context, x),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> editWallet(BuildContext context, [Wallet? w]) async {
  final s = Services.I;
  final name = TextEditingController(text: w?.name ?? '');
  final opening = TextEditingController(text: w == null ? '' : '${w.openingBalance}');
  final last4 = TextEditingController(text: w?.accountLast4 ?? '');
  final actual = TextEditingController();
  var type = w?.type ?? 'bank';
  String? instId = w?.sourceAppPackage == null ? null : s.catalog.identify(w!.sourceAppPackage!, '')?.id;
  var archived = w?.archived ?? false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(w == null ? 'Ví mới' : 'Sửa ví', style: Theme.of(ctx).textTheme.titleLarge),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Tên ví'),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Loại'),
                items: [for (final e in walletTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() => type = v!),
              ),
              if (type == 'bank' || type == 'ewallet' || type == 'credit')
                DropdownButtonFormField<String?>(
                  initialValue: instId,
                  decoration: const InputDecoration(labelText: 'Ngân hàng / ví (để ghi tự động)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Không')),
                    for (final i in s.catalog.all) DropdownMenuItem(value: i.id, child: Text(i.name)),
                  ],
                  onChanged: (v) => set(() => instId = v),
                ),
              if (type != 'cash')
                TextField(
                  controller: last4,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '4 số cuối tài khoản/thẻ (tuỳ chọn)'),
                ),
              if (w == null) AmountField(opening, 'Số dư hiện tại'),
              if (w != null) ...[
                SwitchListTile(
                  title: const Text('Lưu trữ (ẩn khỏi màn hình nhập)'),
                  value: archived,
                  onChanged: (v) => set(() => archived = v),
                ),
                const Divider(),
                Text('Đối soát số dư', style: Theme.of(ctx).textTheme.titleMedium),
                AmountField(actual, 'Số dư thực tế hiện tại'),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty) return;
                  final inst = s.catalog.byId(instId);
                  final id = await s.repo.saveWallet(
                    WalletsCompanion(
                      id: w == null ? const Value.absent() : Value(w.id),
                      name: Value(name.text.trim()),
                      type: Value(type),
                      icon: Value(walletIcons[type]!),
                      accountLast4: Value(last4.text.trim().isEmpty ? null : last4.text.trim()),
                      sourceAppPackage: Value(inst?.packages.first),
                      archived: Value(archived),
                      openingBalance: w == null ? Value(parseAmountInput(opening.text) ?? 0) : const Value.absent(),
                    ),
                  );
                  // Chọn ngân hàng cho ví thì bật luôn nguồn tự động của ngân hàng đó.
                  if (inst != null) await s.enableInstitution(inst.id);
                  final a = parseAmountInput(actual.text);
                  if (a != null) {
                    final adj = await s.repo.reconcile(id, a);
                    if (ctx.mounted && adj != null) toast(ctx, 'Đã tạo giao dịch điều chỉnh số dư');
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Lưu'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------- Danh mục (M03) ----------------

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Danh mục'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chi'),
              Tab(text: 'Thu'),
            ],
          ),
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton(
            tooltip: 'Thêm danh mục',
            onPressed: () => _edit(context, null, DefaultTabController.of(context).index == 0 ? 'expense' : 'income'),
            child: const Icon(Icons.add),
          ),
        ),
        body: StreamBuilder<List<Category>>(
          stream: s.repo.watchCategories(),
          builder: (context, snap) {
            final all = snap.data ?? const <Category>[];
            Widget list(String type) {
              final roots = all.where((c) => c.type == type && c.parentId == null);
              return ListView(
                children: [
                  for (final r in roots) ...[
                    _tile(context, r, all),
                    for (final c in all.where((c) => c.parentId == r.id))
                      Padding(padding: const EdgeInsets.only(left: 32), child: _tile(context, c, all)),
                  ],
                ],
              );
            }

            return TabBarView(children: [list('expense'), list('income')]);
          },
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Category c, List<Category> all) => ListTile(
    leading: Text(c.icon, style: const TextStyle(fontSize: 22)),
    title: Text(c.name, style: TextStyle(decoration: c.hidden ? TextDecoration.lineThrough : null)),
    subtitle: c.isFixedCost ? const Text('Chi cố định') : null,
    onTap: () => _edit(context, c, c.type),
    trailing: PopupMenuButton<String>(
      onSelected: (v) async {
        final s = Services.I;
        if (v == 'hide') {
          await s.repo.saveCategory(CategoriesCompanion(id: Value(c.id), hidden: Value(!c.hidden)));
        } else if (v == 'merge') {
          final into = await showDialog<Category>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: Text('Gộp "${c.name}" vào…'),
              children: [
                for (final o in all.where((o) => o.type == c.type && o.id != c.id))
                  SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o), child: Text('${o.icon} ${o.name}')),
              ],
            ),
          );
          if (into != null) await s.repo.mergeCategory(c.id, into.id);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'hide', child: Text(c.hidden ? 'Hiện lại' : 'Ẩn')),
        const PopupMenuItem(value: 'merge', child: Text('Gộp vào danh mục khác')),
      ],
    ),
  );

  Future<void> _edit(BuildContext context, Category? c, String type) async {
    final s = Services.I;
    final name = TextEditingController(text: c?.name ?? '');
    final icon = TextEditingController(text: c?.icon ?? '🏷️');
    var fixed = c?.isFixedCost ?? false;
    String? parent = c?.parentId;
    final roots = (await s.repo.allCategories()).where((x) => x.type == type && x.parentId == null && x.id != c?.id).toList();
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? 'Danh mục mới' : 'Sửa danh mục'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Tên'),
              ),
              TextField(
                controller: icon,
                decoration: const InputDecoration(labelText: 'Icon (emoji)'),
              ),
              DropdownButtonFormField<String?>(
                initialValue: parent,
                decoration: const InputDecoration(labelText: 'Thuộc danh mục cha'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Cấp 1 —')),
                  for (final r in roots) DropdownMenuItem(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => set(() => parent = v),
              ),
              if (type == 'expense')
                CheckboxListTile(title: const Text('Chi cố định'), value: fixed, onChanged: (v) => set(() => fixed = v!)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                final parentCat = roots.where((r) => r.id == parent).firstOrNull;
                await s.repo.saveCategory(
                  CategoriesCompanion(
                    id: c == null ? const Value.absent() : Value(c.id),
                    name: Value(name.text.trim()),
                    type: Value(type),
                    parentId: Value(parent),
                    icon: Value(icon.text.trim().isEmpty ? '🏷️' : icon.text.trim()),
                    color: c == null && parentCat != null ? Value(parentCat.color) : const Value.absent(),
                    isFixedCost: Value(fixed),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- SC-07 Ngân sách ----------------

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  final s = Services.I;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ngân sách')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Thêm ngân sách',
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<BudgetStatus>>(
        stream: s.live(s.budgetStatus),
        builder: (context, snap) {
          final list = snap.data ?? const [];
          if (snap.hasData && list.isEmpty) {
            return EmptyState(
              'Chưa có ngân sách. Đặt một ngân sách tổng cho tháng để biết mỗi ngày còn được chi bao nhiêu.',
              action: 'Đặt ngân sách',
              onAction: _edit,
            );
          }
          final now = DateTime.now();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final b in list)
                Card(
                  child: InkWell(
                    onTap: () => _edit(b.budget),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${b.categoryName ?? 'Tổng chi'} · ${b.period.label}',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                '${(b.pct * 100).round()}%',
                                style: TextStyle(color: budgetColor(b.pct), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Bar(b.pct, budgetColor(b.pct)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Money(b.spent),
                              const Text(' / '),
                              Money(b.limit),
                              if (b.limit > b.budget.amount) const Text(' (gồm dư kỳ trước)'),
                            ],
                          ),
                          Text(
                            b.remaining >= 0
                                ? 'Còn được chi ${hideAmounts.value ? '•••' : formatVnd(b.perDayLeft(now))}/ngày'
                                : 'Đã vượt ${hideAmounts.value ? '•••' : formatVnd(-b.remaining)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit([Budget? b]) async {
    final cats = (await s.repo.allCategories()).where((c) => c.type == 'expense' && c.parentId == null).toList();
    final amount = TextEditingController(text: b == null ? '' : '${b.amount}');
    String? cat = b?.categoryId;
    var period = b?.period ?? 'month';
    var rollover = b?.rollover ?? false;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(b == null ? 'Ngân sách mới' : 'Sửa ngân sách'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: cat,
                decoration: const InputDecoration(labelText: 'Danh mục'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tổng chi')),
                  for (final c in cats) DropdownMenuItem(value: c.id, child: Text('${c.icon} ${c.name}')),
                ],
                onChanged: (v) => set(() => cat = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: period,
                decoration: const InputDecoration(labelText: 'Kỳ'),
                items: const [
                  DropdownMenuItem(value: 'week', child: Text('Tuần')),
                  DropdownMenuItem(value: 'month', child: Text('Tháng')),
                  DropdownMenuItem(value: 'quarter', child: Text('Quý')),
                  DropdownMenuItem(value: 'year', child: Text('Năm')),
                ],
                onChanged: (v) => set(() => period = v!),
              ),
              AmountField(amount, 'Số tiền'),
              SwitchListTile(
                title: const Text('Chuyển phần dư sang kỳ sau'),
                value: rollover,
                onChanged: (v) => set(() => rollover = v),
              ),
            ],
          ),
          actions: [
            if (b != null)
              TextButton(
                onPressed: () async {
                  await s.repo.saveBudget(BudgetsCompanion(id: Value(b.id), deletedAt: Value(DateTime.now())));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Xoá'),
              ),
            FilledButton(
              onPressed: () async {
                final a = parseAmountInput(amount.text);
                if (a == null || a <= 0) return;
                await s.repo.saveBudget(
                  BudgetsCompanion(
                    id: b == null ? const Value.absent() : Value(b.id),
                    categoryId: Value(cat),
                    period: Value(period),
                    amount: Value(a),
                    rollover: Value(rollover),
                  ),
                );
                await s.checkBudgetAlerts();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Giao dịch định kỳ (S7) ----------------

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});
  static const freqs = {'FREQ=WEEKLY': 'Hằng tuần', 'FREQ=MONTHLY': 'Hằng tháng', 'FREQ=YEARLY': 'Hằng năm'};

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Giao dịch định kỳ')),
      floatingActionButton: FloatingActionButton(tooltip: 'Thêm', onPressed: () => _edit(context), child: const Icon(Icons.add)),
      body: StreamBuilder<List<RecurringRule>>(
        stream: (s.db.select(s.db.recurringRules)..where((r) => r.deletedAt.isNull())).watch(),
        builder: (context, snap) {
          final list = snap.data ?? const <RecurringRule>[];
          if (snap.hasData && list.isEmpty) {
            return EmptyState(
              'Tiền nhà, điện, Netflix… tự tạo giao dịch chờ duyệt vào ngày đến hạn.',
              action: 'Thêm khoản định kỳ',
              onAction: () => _edit(context),
            );
          }
          return ListView(
            children: [
              for (final r in list)
                ListTile(
                  title: Text(r.note.isEmpty ? 'Khoản định kỳ' : r.note),
                  subtitle: Text('${freqs[r.rrule] ?? r.rrule} · lần tới ${dayLabel(r.nextRunAt)}'),
                  trailing: Money(r.amount, type: r.type),
                  onLongPress: () async {
                    if (await confirm(context, 'Xoá khoản định kỳ này?', ok: 'Xoá')) {
                      await (s.db.update(
                        s.db.recurringRules,
                      )..where((x) => x.id.equals(r.id))).write(RecurringRulesCompanion(deletedAt: Value(DateTime.now())));
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final s = Services.I;
    final wallets = (await s.repo.watchWallets().first).where((w) => !w.archived).toList();
    final cats = (await s.repo.allCategories()).where((c) => c.type == 'expense').toList();
    if (wallets.isEmpty) {
      if (context.mounted) toast(context, 'Tạo ví trước');
      return;
    }
    final note = TextEditingController();
    final amount = TextEditingController();
    var wallet = wallets.first.id;
    String? cat;
    var freq = 'FREQ=MONTHLY';
    var next = DateTime.now().add(const Duration(days: 1));
    var auto = false;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Khoản chi định kỳ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Tên (vd Tiền nhà)'),
                ),
                AmountField(amount, 'Số tiền'),
                DropdownButtonFormField<String>(
                  initialValue: wallet,
                  decoration: const InputDecoration(labelText: 'Ví'),
                  items: [for (final w in wallets) DropdownMenuItem(value: w.id, child: Text(w.name))],
                  onChanged: (v) => set(() => wallet = v!),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: cat,
                  decoration: const InputDecoration(labelText: 'Danh mục'),
                  items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text('${c.icon} ${c.name}'))],
                  onChanged: (v) => set(() => cat = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: freq,
                  decoration: const InputDecoration(labelText: 'Lặp lại'),
                  items: [for (final e in freqs.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => set(() => freq = v!),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Lần đầu: ${next.day}/${next.month}/${next.year}'),
                  trailing: const Icon(Icons.event),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: next,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) set(() => next = DateTime(d.year, d.month, d.day, 8));
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tự xác nhận'),
                  value: auto,
                  onChanged: (v) => set(() => auto = v),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                final a = parseAmountInput(amount.text);
                if (a == null || a <= 0) return;
                await s.db
                    .into(s.db.recurringRules)
                    .insert(
                      RecurringRulesCompanion.insert(
                        walletId: wallet,
                        type: 'expense',
                        amount: a,
                        categoryId: Value(cat),
                        note: Value(note.text.trim()),
                        rrule: freq,
                        nextRunAt: DateTime(next.year, next.month, next.day, 8),
                        autoConfirm: Value(auto),
                      ),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Quy tắc phân loại ----------------

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Quy tắc phân loại')),
      body: StreamBuilder<List<ClassificationRule>>(
        stream: (s.db.select(s.db.classificationRules)..where((r) => r.deletedAt.isNull())).watch(),
        builder: (context, snap) => FutureBuilder<List<Category>>(
          future: s.repo.allCategories(),
          builder: (context, cats) {
            final byId = {for (final c in cats.data ?? const <Category>[]) c.id: c};
            final list = snap.data ?? const <ClassificationRule>[];
            if (snap.hasData && list.isEmpty) {
              return const EmptyState(
                'Chưa có quy tắc. Khi bạn sửa danh mục của một giao dịch tự động, app sẽ hỏi có lưu thành quy tắc không.',
              );
            }
            return ListView(
              children: [
                for (final r in list)
                  ListTile(
                    title: Text('"${r.pattern}" → ${byId[r.categoryId]?.name ?? '?'}'),
                    subtitle: Text(
                      '${r.matchField == 'merchant' ? 'Tên cửa hàng' : 'Nội dung'} ${r.matchType == 'contains' ? 'chứa' : r.matchType}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Xoá quy tắc',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => (s.db.delete(s.db.classificationRules)..where((x) => x.id.equals(r.id))).go(),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
