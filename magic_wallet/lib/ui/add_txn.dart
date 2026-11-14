import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/database.dart';
import '../services.dart';
import '../pro/pro.dart';
import 'pro_screen.dart';
import 'widgets.dart';

/// SC-03: thêm/sửa giao dịch. Mở sẵn bàn phím số; tối thiểu số tiền + danh mục là lưu được (US-01).
class AddTxnScreen extends StatefulWidget {
  final Txn? editing;
  const AddTxnScreen({super.key, this.editing});
  @override
  State<AddTxnScreen> createState() => _AddTxnScreenState();
}

class _AddTxnScreenState extends State<AddTxnScreen> {
  final s = Services.I;
  String type = 'expense';
  String input = '';
  String? categoryId, walletId, toWalletId;
  DateTime when = DateTime.now();
  final note = TextEditingController();
  final tags = TextEditingController();
  List<Category> cats = [];
  List<Wallet> wallets = [];
  List<String> suggested = [];
  bool showKeypad = true;

  int? get amount => parseAmountInput(input);

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      type = e.type;
      input = e.amount.toString();
      categoryId = e.categoryId;
      walletId = e.walletId;
      toWalletId = e.toWalletId;
      when = e.occurredAt;
      note.text = e.note;
      s.repo.tagsOf(e.id).then((t) => tags.text = t.join(', '));
    }
    _load();
  }

  Future<void> _load() async {
    final c = await s.repo.allCategories();
    final w = writableWallets((await s.repo.watchWallets().first).where((w) => !w.archived).toList(), await s.pro());
    walletId ??= await s.repo.lastUsedWalletId();
    final sug = await s.repo.suggestedCategoryIds(type, DateTime.now());
    if (!mounted) return;
    setState(() {
      cats = c;
      wallets = w;
      suggested = sug;
    });
  }

  void _key(String k) => setState(() {
    if (k == '⌫') {
      input = input.isEmpty ? '' : input.substring(0, input.length - 1);
    } else if (input.length < 14) {
      input += k;
    }
  });

  Future<void> _save() async {
    final a = amount;
    if (a == null || a <= 0) return toast(context, 'Nhập số tiền, ví dụ 45k hoặc 1tr2');
    if (walletId == null) return toast(context, 'Tạo một ví trước trong tab Thêm › Ví');
    if (type == 'transfer' && (toWalletId == null || toWalletId == walletId)) {
      return toast(context, 'Chọn ví nhận khác ví chuyển');
    }
    if (type != 'transfer' && categoryId == null) return toast(context, 'Chọn danh mục');

    final e = widget.editing;
    final categoryChanged = e != null && e.source != 'manual' && e.categoryId != categoryId;
    await s.repo.saveTxn(
      TransactionsCompanion(
        id: e == null ? const Value.absent() : Value(e.id),
        walletId: Value(walletId!),
        toWalletId: Value(type == 'transfer' ? toWalletId : null),
        type: Value(type),
        amount: Value(a),
        categoryId: Value(type == 'transfer' ? null : categoryId),
        occurredAt: Value(when),
        note: Value(note.text.trim()),
        // Sửa một giao dịch tự động nghĩa là người dùng đã duyệt nó.
        status: const Value('confirmed'),
      ),
      tags: tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
    );
    // 5.2 bước 7: học lại từ lần sửa danh mục.
    if (categoryChanged && mounted) {
      final key = (e.merchant?.isNotEmpty ?? false) ? e.merchant! : e.note;
      final ruleCount = (await s.db.select(s.db.classificationRules).get()).length;
      if (key.trim().length >= 3 &&
          mounted &&
          await confirm(context, 'Áp dụng danh mục này cho các giao dịch tương tự "$key"?', ok: 'Áp dụng') &&
          (ruleCount < FreeLimits.rules ||
              (mounted && await requirePro(context, 'Tạo quá ${FreeLimits.rules} quy tắc phân loại')))) {
        await s.db
            .into(s.db.classificationRules)
            .insert(
              ClassificationRulesCompanion.insert(
                matchField: (e.merchant?.isNotEmpty ?? false) ? 'merchant' : 'note',
                matchType: 'contains',
                pattern: key.trim().toLowerCase(),
                categoryId: categoryId!,
              ),
            );
      }
    }
    await s.checkBudgetAlerts();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final ofType = cats.where((c) => c.type == (type == 'income' ? 'income' : 'expense') && !c.hidden).toList();
    final sugCats = [for (final id in suggested) ...ofType.where((c) => c.id == id)];
    final rest = ofType.where((c) => !suggested.contains(c.id)).toList();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'Ghi nhanh' : 'Sửa giao dịch'),
        actions: [
          if (widget.editing != null)
            IconButton(
              tooltip: 'Xoá',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await s.repo.deleteTxn(widget.editing!.id);
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Chi'), icon: Icon(Icons.north_east)),
                  ButtonSegment(value: 'income', label: Text('Thu'), icon: Icon(Icons.south_west)),
                  ButtonSegment(value: 'transfer', label: Text('Chuyển'), icon: Icon(Icons.swap_horiz)),
                ],
                selected: {type},
                onSelectionChanged: (v) {
                  setState(() {
                    type = v.first;
                    categoryId = null;
                  });
                  _load();
                },
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => showKeypad = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Semantics(
                      liveRegion: true,
                      label: 'Số tiền',
                      child: Text(
                        amount == null ? (input.isEmpty ? '0 đ' : input) : formatVnd(amount!),
                        style: theme.textTheme.displaySmall?.copyWith(fontFeatures: tabular, color: typeColor(type)),
                      ),
                    ),
                    if (input.isNotEmpty && amount != null && input != amount.toString())
                      Text(input, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (type == 'transfer') ...[
                    _walletPicker('Từ ví', walletId, (v) => setState(() => walletId = v)),
                    _walletPicker('Đến ví', toWalletId, (v) => setState(() => toWalletId = v)),
                  ] else ...[
                    if (sugCats.isNotEmpty) ...[
                      Text('Gợi ý lúc này', style: theme.textTheme.labelLarge),
                      _catGrid(sugCats),
                      const Divider(),
                    ],
                    _catGrid(rest),
                    _walletPicker('Ví', walletId, (v) => setState(() => walletId = v)),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event),
                          label: Text(dayLabel(when)),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: when,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setState(() => when = DateTime(d.year, d.month, d.day, when.hour, when.minute));
                          },
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: note,
                    onTap: () => setState(() => showKeypad = false),
                    decoration: const InputDecoration(labelText: 'Ghi chú'),
                  ),
                  TextField(
                    controller: tags,
                    onTap: () => setState(() => showKeypad = false),
                    decoration: const InputDecoration(labelText: 'Thẻ (cách nhau dấu phẩy)', hintText: 'công việc, du lịch'),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            if (showKeypad) _keypad(),
          ],
        ),
      ),
      // Khi bàn phím số đang mở, nút Lưu nằm ở góc dưới phải của bàn phím.
      floatingActionButton: showKeypad
          ? null
          : FloatingActionButton.extended(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Lưu')),
    );
  }

  Widget _catGrid(List<Category> list) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final c in list)
        ChoiceChip(
          avatar: Text(c.icon),
          label: Text(c.name),
          selected: categoryId == c.id,
          onSelected: (_) => setState(() => categoryId = c.id),
        ),
    ],
  );

  Widget _walletPicker(String label, String? value, ValueChanged<String?> onChanged) => DropdownButtonFormField<String>(
    initialValue: wallets.any((w) => w.id == value) ? value : null,
    decoration: InputDecoration(labelText: label),
    items: [for (final w in wallets) DropdownMenuItem(value: w.id, child: Text('${w.icon} ${w.name}'))],
    onChanged: onChanged,
  );

  Widget _keypad() {
    const keys = ['1', '2', '3', 'k', '4', '5', '6', 'tr', '7', '8', '9', '⌫', ',', '0', '000', 'Lưu'];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        childAspectRatio: 2.2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final k in keys)
            k == 'Lưu'
                ? Padding(
                    padding: const EdgeInsets.all(4),
                    child: FilledButton(onPressed: _save, child: const Text('Lưu')),
                  )
                : InkWell(
                    onTap: () => _key(k),
                    child: Center(
                      child: k == '⌫'
                          ? const Icon(Icons.backspace_outlined, semanticLabel: 'Xoá')
                          : Text(k, style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ),
        ],
      ),
    );
  }
}
