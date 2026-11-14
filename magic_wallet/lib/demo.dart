import 'dart:math';

import 'package:drift/drift.dart' show Value;

import 'data/database.dart';
import 'data/repo.dart';

/// Dữ liệu mẫu để xem giao diện và chụp ảnh cho trang cửa hàng. Chỉ bật khi build với --dart-define=DEMO_SEED=true;
/// bản phát hành không truyền cờ này nên không bao giờ chạy.
const demoSeed = bool.fromEnvironment('DEMO_SEED');

Future<void> seedDemo(AppDb db, Repo repo) async {
  if (!demoSeed || (await db.select(db.wallets).get()).isNotEmpty) return;
  // Một transaction cho cả lô: nhanh hơn nhiều trên web (IndexedDB).
  await db.transaction(() => _seed(db, repo));
}

Future<void> _seed(AppDb db, Repo repo) async {
  final cats = {for (final c in await repo.allCategories()) c.name: c.id};
  final cash = await repo.saveWallet(WalletsCompanion.insert(name: 'Tiền mặt', type: 'cash', icon: const Value('💵'), openingBalance: const Value(2500000)));
  final bank = await repo.saveWallet(WalletsCompanion.insert(
      name: 'TPBank', type: 'bank', icon: const Value('🏦'), openingBalance: const Value(18000000), accountLast4: const Value('6789')));
  final momo = await repo.saveWallet(WalletsCompanion.insert(name: 'MoMo', type: 'ewallet', icon: const Value('📱'), openingBalance: const Value(1500000)));
  await repo.saveBudget(BudgetsCompanion.insert(period: 'month', amount: 12000000));

  final now = DateTime.now();
  final r = Random(7); // cố định để ảnh chụp lần nào cũng giống nhau
  Future<void> add(String cat, int amount, DateTime at, String wallet, {String type = 'expense', String note = ''}) =>
      repo.saveTxn(TransactionsCompanion.insert(
          walletId: wallet, type: type, amount: amount, amountBase: amount, occurredAt: at, categoryId: Value(cats[cat]), note: Value(note)));

  for (var d = 45; d >= 0; d--) {
    final day = DateTime(now.year, now.month, now.day - d);
    await add('Ăn sáng', 30000 + r.nextInt(4) * 5000, day.add(const Duration(hours: 7, minutes: 30)), cash, note: 'Bánh mì, phở');
    await add('Ăn trưa', 45000 + r.nextInt(6) * 5000, day.add(const Duration(hours: 12)), bank, note: 'Cơm văn phòng');
    if (r.nextBool()) await add('Cà phê', 39000 + r.nextInt(3) * 10000, day.add(const Duration(hours: 15)), momo, note: 'Highlands');
    if (d % 3 == 0) await add('Taxi/Grab', 35000 + r.nextInt(8) * 5000, day.add(const Duration(hours: 18)), bank, note: 'Grab');
    if (d % 7 == 2) await add('Mua sắm', 150000 + r.nextInt(10) * 50000, day.add(const Duration(hours: 20)), bank, note: 'Shopee');
    if (d % 10 == 4) await add('Giải trí', 120000 + r.nextInt(4) * 30000, day.add(const Duration(hours: 21)), bank, note: 'CGV');
  }
  for (final m in [1, 0]) {
    final first = DateTime(now.year, now.month - m, 5, 9);
    if (first.isAfter(now)) continue;
    await add('Lương', 22000000, first, bank, type: 'income', note: 'Lương tháng');
    await add('Tiền nhà', 5500000, first.add(const Duration(hours: 1)), bank, note: 'Tiền nhà');
    await add('Điện', 650000 + r.nextInt(5) * 50000, first.add(const Duration(days: 3)), bank, note: 'EVN');
    await add('Internet', 250000, first.add(const Duration(days: 4)), bank, note: 'FPT Telecom');
  }
  // Vài giao dịch "chờ duyệt" như ghi tự động từ thông báo ngân hàng.
  await repo.saveTxn(TransactionsCompanion.insert(
      walletId: bank, type: 'expense', amount: 89000, amountBase: 89000, occurredAt: now.subtract(const Duration(minutes: 20)),
      categoryId: Value(cats['Cà phê']), note: const Value('THANH TOAN QR PHUC LONG'), status: const Value('pending'),
      source: const Value('notification'), confidence: const Value(0.9)));
  await repo.saveTxn(TransactionsCompanion.insert(
      walletId: bank, type: 'expense', amount: 245000, amountBase: 245000, occurredAt: now.subtract(const Duration(hours: 2)),
      categoryId: Value(cats['Mua sắm']), note: const Value('SHOPEE PAY'), status: const Value('pending'),
      source: const Value('notification'), confidence: const Value(0.9)));
  await db.setSetting('onboarded', '1');
}
