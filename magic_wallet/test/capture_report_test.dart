import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_wallet/capture/classifier.dart';
import 'package:magic_wallet/capture/parser.dart';
import 'package:magic_wallet/capture/pipeline.dart';
import 'package:magic_wallet/capture/statement_import.dart';
import 'package:magic_wallet/core/periods.dart';
import 'package:magic_wallet/data/database.dart';
import 'package:magic_wallet/data/repo.dart';
import 'package:magic_wallet/reports/report.dart';

// Thông báo mẫu TỰ SOẠN theo dạng phổ biến — chưa phải thông báo thật thu từ người thử nghiệm (mục 5.5).
const vcbStyle = 'TK 0071000123456 | GD: -45,000VND 11/11/26 12:31 | SD: 1,955,000VND | ND: THANH TOAN QR HIGHLANDS COFFEE';
const momoStyle = 'Bạn đã nhận 200.000đ từ NGUYEN VAN A. Số dư ví: 350.000đ';
const otpSms = 'Ma OTP cua quy khach la 123456. KHONG chia se ma nay. Vietcombank';

final catalog = InstitutionCatalog.fromJson(File('assets/institutions.json').readAsStringSync());

void main() {
  group('parser', () {
    test('dạng có dấu, số dư, 4 số cuối, nội dung', () {
      final r = parseNotification(vcbStyle) as Parsed;
      expect(r.txn.amount, 45000);
      expect(r.txn.direction, -1);
      expect(r.txn.balance, 1955000);
      expect(r.txn.last4, '3456');
      expect(r.txn.content, contains('HIGHLANDS'));
    });
    test('dạng chữ không dấu số tiền: đoán chiều theo từ khoá, không lấy nhầm số dư', () {
      final r = parseNotification(momoStyle) as Parsed;
      expect(r.txn.amount, 200000);
      expect(r.txn.direction, 1);
      expect(r.txn.balance, 350000);
    });
    test('OTP bị bỏ ngay (10.2.3)', () {
      expect(parseNotification(otpSms), isA<DroppedSensitive>());
      expect(parseNotification('Mã xác thực của bạn là 8899'), isA<DroppedSensitive>());
    });
    test('hoàn tiền', () {
      final r = parseNotification('TK 1234 +120,000VND. ND: SHOPEE HOAN TIEN DON 123') as Parsed;
      expect(r.txn.isRefund, isTrue);
      expect(r.txn.direction, 1);
    });
    test('tên người có "TRUONG" không làm đảo chiều', () {
      final r = parseNotification('Bạn đã nhận 500.000đ từ LE VAN TRUONG') as Parsed;
      expect(r.txn.direction, 1);
    });
    test('không nhận dạng được', () {
      expect(parseNotification('Chúc mừng sinh nhật quý khách!'), isA<Unrecognized>());
    });
    test('mẫu riêng của tổ chức thắng parser chung', () {
      final inst = Institution('x', 'X', 'bank', ['x.app'], ['X'], [
        RegExp(r'Chi (?<amount>[\d.]+)d tai (?<merchant>\w+)', caseSensitive: false),
      ]);
      final r = parseNotification('Chi 99.000d tai CIRCLEK luc 10:00', inst: inst) as Parsed;
      expect((r.txn.amount, r.txn.direction, r.txn.merchant, r.txn.confidence), (99000, -1, 'CIRCLEK', 0.97));
    });
    test('catalog có đủ 25 tổ chức, nhận SMS theo tên người gửi', () {
      expect(catalog.all.length, 25);
      expect(catalog.identify('com.google.android.apps.messaging', 'Vietcombank')?.id, 'vcb');
      expect(catalog.identify('com.mservice.momotransfer', '')?.id, 'momo');
      expect(catalog.identify('com.unknown', 'Vietcombank'), isNull);
    });
  });

  group('DB', () {
    late AppDb db;
    late Repo repo;
    late CapturePipeline pipe;
    late String vcb, momo, cash;
    final whitelist = {'com.VCB', 'com.mservice.momotransfer', 'com.google.android.apps.messaging'};
    final t0 = DateTime(2026, 11, 11, 12, 31);

    setUp(() async {
      db = AppDb(NativeDatabase.memory());
      repo = Repo(db);
      pipe = CapturePipeline(db, repo, catalog);
      vcb = await repo.saveWallet(
        WalletsCompanion.insert(
          name: 'VCB',
          type: 'bank',
          openingBalance: const Value(2000000),
          accountLast4: const Value('3456'),
          sourceAppPackage: const Value('com.VCB'),
        ),
      );
      momo = await repo.saveWallet(
        WalletsCompanion.insert(
          name: 'MoMo',
          type: 'ewallet',
          openingBalance: const Value(150000),
          sourceAppPackage: const Value('com.mservice.momotransfer'),
        ),
      );
      cash = await repo.saveWallet(WalletsCompanion.insert(name: 'Tiền mặt', type: 'cash'));
    });
    tearDown(() => db.close());

    Future<IngestOutcome> notif(String pkg, String text, DateTime at, {String title = '', bool auto = false}) => pipe.ingest(
      RawInput(source: 'notification', package: pkg, title: title, text: text, receivedAt: at),
      whitelist: whitelist,
      autoConfirmEnabled: auto,
    );

    test('seed danh mục tiếng Việt 2 cấp', () async {
      final cats = await repo.allCategories();
      expect(cats.where((c) => c.parentId == null).map((c) => c.name), containsAll(['Ăn uống', 'Lương', 'Khác']));
      expect(cats.firstWhere((c) => c.name == 'Cà phê').parentId, cats.firstWhere((c) => c.name == 'Ăn uống').id);
    });

    test('thông báo → chờ duyệt, gán ví theo 4 số cuối, phân loại từ điển, không tính vào số dư', () async {
      final out = await notif('com.VCB', vcbStyle, t0) as Created;
      expect(out.autoConfirmed, isFalse);
      final t = await (db.select(db.transactions)..where((x) => x.id.equals(out.txnId))).getSingle();
      expect((t.walletId, t.type, t.amount, t.status, t.source), (vcb, 'expense', 45000, 'pending', 'notification'));
      final cats = await repo.allCategories();
      expect(cats.firstWhere((c) => c.id == t.categoryId).name, 'Cà phê');
      expect((await repo.walletBalances())[vcb], 2000000); // US-02 AC2
      // Số dư báo 1.955.000 = 2.000.000 − 45.000 → khớp, không có gợi ý đối soát.
      expect(await db.getSetting('reconcile_hint:$vcb'), isNull);
      await repo.setStatus(t.id, 'confirmed');
      expect((await repo.walletBalances())[vcb], 1955000);
    });

    test('ngoài whitelist / OTP: không lưu gì', () async {
      expect((await notif('com.facebook', vcbStyle, t0) as Skipped).reason, 'not_whitelisted');
      expect((await notif('com.google.android.apps.messaging', otpSms, t0, title: 'Vietcombank') as Skipped).reason, 'sensitive');
      expect(await db.select(db.rawEvents).get(), isEmpty);
      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('chống trùng SMS + thông báo trong 5 phút (US-02 AC3)', () async {
      await notif('com.VCB', vcbStyle, t0);
      final dup = await notif(
        'com.google.android.apps.messaging',
        vcbStyle,
        t0.add(const Duration(minutes: 2)),
        title: 'Vietcombank',
      );
      expect(dup, isA<MergedDuplicate>());
      expect((await db.select(db.transactions).get()).length, 1);
      // Ngoài 5 phút thì là giao dịch mới.
      expect(await notif('com.VCB', vcbStyle, t0.add(const Duration(minutes: 6))), isA<Created>());
    });

    test('nạp ví: ngân hàng trừ + ví cộng → 1 chuyển khoản (5.5)', () async {
      await notif('com.VCB', 'TK 0071000123456 GD: -200,000VND SD: 1,800,000VND ND: NAP TIEN MOMO', t0);
      final out = await notif(
        'com.mservice.momotransfer',
        'Nạp tiền thành công: nhận 200.000đ vào ví',
        t0.add(const Duration(minutes: 1)),
      );
      expect(out, isA<PairedTransfer>());
      final all = await db.select(db.transactions).get();
      expect(all.length, 1);
      expect((all.single.type, all.single.walletId, all.single.toWalletId, all.single.categoryId), ('transfer', vcb, momo, null));
    });

    test('lệch số dư → gợi ý đối soát; đối soát tạo giao dịch điều chỉnh', () async {
      await notif('com.VCB', 'TK 0071000123456 GD: -45,000VND SD: 1,900,000VND', t0);
      expect(await db.getSetting('reconcile_hint:$vcb'), '1900000');
      final adj = await repo.reconcile(vcb, 1900000);
      expect(adj, isNotNull);
      expect((await repo.walletBalances())[vcb], 1900000);
    });

    test('quy tắc người dùng: tin cậy 0,97 → tự xác nhận khi bật', () async {
      final cats = await repo.allCategories();
      final cafe = cats.firstWhere((c) => c.name == 'Cà phê').id;
      await db
          .into(db.classificationRules)
          .insert(
            ClassificationRulesCompanion.insert(
              matchField: 'note',
              matchType: 'contains',
              pattern: 'highlands',
              categoryId: cafe,
            ),
          );
      // Parser chung chỉ đạt 0,9 → vẫn chờ duyệt dù quy tắc 0,97 (lấy mức thấp hơn).
      expect((await notif('com.VCB', vcbStyle, t0, auto: true) as Created).autoConfirmed, isFalse);
    });

    test('học cục bộ: giao dịch đã sửa danh mục dạy mô hình', () async {
      final cats = await repo.allCategories();
      final gift = cats.firstWhere((c) => c.name == 'Quà tặng').id;
      final r = classify(
        text: 'CK MUNG CUOI ANH TUAN',
        type: 'expense',
        rules: const [],
        categories: cats,
        history: const [
          LearnedSample('MUNG CUOI CHI LAN', 'x'),
          LearnedSample('mung cuoi ban', 'x'),
        ].map((s) => LearnedSample(s.text, gift)).toList(),
      );
      expect((r.categoryId, r.via), (gift, 'learned'));
      expect(r.confidence, lessThanOrEqualTo(0.9));
    });

    test('nhập sao kê chỉ thêm dòng còn thiếu', () async {
      await repo.saveTxn(
        TransactionsCompanion.insert(
          walletId: vcb,
          type: 'expense',
          amount: 45000,
          amountBase: 45000,
          occurredAt: DateTime(2026, 11, 1, 8),
        ),
      );
      final n = await pipe.importStatement([
        StatementRow(DateTime(2026, 11, 1, 12), 45000, -1, 'GRAB'), // đã có cùng ngày → bỏ
        StatementRow(DateTime(2026, 11, 2, 12), 99000, -1, 'SHOPEE'),
      ], vcb);
      expect(n, 1);
    });

    test('xoá mềm, hoàn tác, dọn sau 30 ngày (BR-07)', () async {
      final id = await repo.saveTxn(
        TransactionsCompanion.insert(walletId: cash, type: 'expense', amount: 10000, amountBase: 10000, occurredAt: t0),
      );
      await repo.deleteTxn(id);
      expect(await repo.watchTxns().first, isEmpty);
      await repo.undoDeleteTxn(id);
      expect((await repo.watchTxns().first).length, 1);
      await repo.deleteTxn(id);
      await repo.purgeExpired(DateTime.now().add(const Duration(days: 31)));
      expect(await db.select(db.transactions).get(), isEmpty);
      // Mọi thay đổi đều có trong nhật ký đồng bộ.
      final log = await db.select(db.syncLog).get();
      expect(log.where((l) => l.entityId == id).map((l) => l.op), ['insert', 'delete', 'update', 'delete']);
    });

    test('định kỳ: bù các kỳ lỡ, tạo ở trạng thái chờ duyệt', () async {
      await db
          .into(db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              walletId: cash,
              type: 'expense',
              amount: 260000,
              rrule: 'FREQ=MONTHLY',
              nextRunAt: DateTime(2026, 9, 5),
            ),
          );
      expect(await repo.runRecurring(DateTime(2026, 11, 11)), 3);
      expect((await repo.watchPending().first).length, 3);
      expect(await repo.runRecurring(DateTime(2026, 11, 11)), 0);
    });

    test('báo cáo: chuyển khoản không tính, hoàn tiền trừ vào chi, so kỳ trước, top, cố định', () async {
      final cats = await repo.allCategories();
      String c(String n) => cats.firstWhere((x) => x.name == n).id;
      Future<void> add(String type, int amount, String? cat, DateTime at, {String? to}) => repo.saveTxn(
        TransactionsCompanion.insert(
          walletId: vcb,
          type: type,
          amount: amount,
          amountBase: amount,
          occurredAt: at,
          categoryId: Value(cat),
          toWalletId: Value(to),
        ),
      );
      await add('income', 20000000, c('Lương'), DateTime(2026, 11, 5));
      await add('expense', 5000000, c('Tiền nhà'), DateTime(2026, 11, 5));
      await add('expense', 1000000, c('Ăn trưa'), DateTime(2026, 11, 6, 12));
      await add('income', 200000, c('Ăn trưa'), DateTime(2026, 11, 7)); // hoàn tiền
      await add('transfer', 3000000, null, DateTime(2026, 11, 8), to: momo);
      await add('expense', 2000000, c('Ăn tối'), DateTime(2026, 10, 10));
      await add('income', 20000000, c('Lương'), DateTime(2026, 10, 5));

      const prefs = CalendarPrefs();
      final p = periodOf(PeriodType.month, DateTime(2026, 11, 11), prefs);
      final prev = shiftPeriod(p, -1, prefs);
      final r = buildReport(
        period: p,
        current: await repo.confirmedBetween(p.start, p.end),
        previous: await repo.confirmedBetween(prev.start, prev.end),
        categories: cats,
        now: DateTime(2026, 11, 11),
      );
      expect(r.totals.income, 20000000);
      expect(r.totals.expense, 5800000); // 5tr + 1tr − 200k, không tính 3tr chuyển khoản
      expect(r.previous.expense, 2000000);
      expect(pctChange(r.totals.expense, r.previous.expense), closeTo(1.9, 1e-9));
      expect(r.totals.savingsRate, closeTo(0.71, 1e-9));
      expect(r.byCategory.map((e) => (cats.firstWhere((x) => x.id == e.key).name, e.value)), [
        ('Nhà ở', 5000000),
        ('Ăn uống', 800000),
      ]);
      expect((r.fixedExpense, r.variableExpense), (5000000, 800000));
      expect(r.largest.first.amount, 5000000);
      expect(r.trend.length, 30);
      expect(r.heatmap![DateTime(2026, 11, 6).weekday - 1][12], 1000000);
    });

    test('nhận xét: chỉ khi lệch ≥ 20% và ≥ 200k, tối đa 3 câu', () async {
      final cats = await repo.allCategories();
      final food = cats.firstWhere((x) => x.name == 'Ăn uống').id;
      final shop = cats.firstWhere((x) => x.name == 'Mua sắm').id;
      Txn tx(String cat, int amount, DateTime at) => Txn(
        id: newId(),
        createdAt: at,
        updatedAt: at,
        walletId: vcb,
        type: 'expense',
        amount: amount,
        currency: 'VND',
        fxRate: 1,
        amountBase: amount,
        categoryId: cat,
        occurredAt: at,
        note: '',
        status: 'confirmed',
        source: 'manual',
      );
      const prefs = CalendarPrefs();
      final p = periodOf(PeriodType.week, DateTime(2026, 11, 11), prefs);
      final r = buildReport(
        period: p,
        current: [tx(food, 1200000, DateTime(2026, 11, 10)), tx(shop, 110000, DateTime(2026, 11, 10))],
        previous: const [],
        prior4: [
          for (var i = 0; i < 4; i++) [tx(food, 888889, DateTime(2026, 10, 1)), tx(shop, 100000, DateTime(2026, 10, 1))],
        ],
        categories: cats,
        now: DateTime(2026, 11, 11),
      );
      // Ăn uống +35% và +311k → có; Mua sắm +10% → không.
      expect(r.insights, ['Ăn uống tuần này 1,2 triệu, cao hơn 35% so với trung bình 4 tuần.']);
    });

    test('ngân sách: 80%, còn/ngày, chuyển dư', () async {
      final cats = await repo.allCategories();
      final shop = cats.firstWhere((x) => x.name == 'Mua sắm').id;
      final clothes = cats.firstWhere((x) => x.name == 'Quần áo').id;
      await repo.saveBudget(
        BudgetsCompanion.insert(
          categoryId: Value(shop),
          period: 'month',
          amount: 1000000,
          rollover: const Value(true),
          startDate: Value(DateTime(2026, 1, 1)),
        ),
      );
      await repo.saveTxn(
        TransactionsCompanion.insert(
          walletId: cash,
          type: 'expense',
          amount: 600000,
          amountBase: 600000,
          occurredAt: DateTime(2026, 10, 3),
          categoryId: Value(clothes),
        ),
      );
      await repo.saveTxn(
        TransactionsCompanion.insert(
          walletId: cash,
          type: 'expense',
          amount: 1100000,
          amountBase: 1100000,
          occurredAt: DateTime(2026, 11, 3),
          categoryId: Value(clothes),
        ),
      );
      final st = (await budgetStatuses(
        budgets: await repo.watchBudgets().first,
        categories: cats,
        now: DateTime(2026, 11, 11),
        prefs: const CalendarPrefs(),
        load: repo.confirmedBetween,
      )).single;
      expect(st.limit, 1400000); // 1tr + 400k dư tháng 10
      expect(st.spent, 1100000); // danh mục con tính vào cha
      expect(st.threshold, isNull); // 78,6%
      expect(st.perDayLeft(DateTime(2026, 11, 11)), 15000); // 300k / 20 ngày (11→30)
    });
  });
}
