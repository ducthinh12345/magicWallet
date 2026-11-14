import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_wallet/core/periods.dart';
import 'package:magic_wallet/data/database.dart';
import 'package:magic_wallet/data/repo.dart';
import 'package:magic_wallet/pro/pro.dart';
import 'package:magic_wallet/reports/report.dart';

void main() {
  final now = DateTime(2026, 11, 14, 12);

  test('quyền Pro: mua, dùng thử 14 ngày, hết hạn', () {
    expect(const ProState().isPro(now), isFalse);
    expect(const ProState().canStartTrial, isTrue);
    expect(const ProState(owned: 'lifetime').isPro(now), isTrue);
    expect(const ProState(owned: 'yearly').isPro(now), isTrue);
    final t = ProState(trialStart: now.subtract(const Duration(days: 13, hours: 1)));
    expect((t.isPro(now), t.trialDaysLeft(now), t.canStartTrial), (true, 1, false));
    final expired = ProState(trialStart: now.subtract(const Duration(days: 14)));
    expect((expired.isPro(now), expired.trialDaysLeft(now)), (false, 0));
    // Đã mua thì không mời dùng thử nữa.
    expect(const ProState(owned: 'yearly').canStartTrial, isFalse);
  });

  test('đối chiếu với Play: trọn đời thắng gói năm; gói năm không còn trả về = hết hạn', () {
    expect(ownedFrom({kProYearly, kProLifetime}), 'lifetime');
    expect(ownedFrom({kProYearly}), 'yearly');
    expect(ownedFrom({}), '');
    expect(ownedFrom({'thu_khac'}), '');
  });

  test('BR-10: hết Pro thì chỉ 3 ví đầu được ghi, ghi tự động về 1 nguồn đầu tiên', () {
    Wallet w(String id, int day) => Wallet(
        id: id, createdAt: DateTime(2026, 1, day), updatedAt: DateTime(2026, 1, day), name: id, type: 'bank', currency: 'VND',
        openingBalance: 0, icon: '', color: 0, archived: false);
    final ws = [w('d', 4), w('a', 1), w('c', 3), w('b', 2)];
    expect(writableWallets(ws, false).map((x) => x.id), ['a', 'b', 'c']);
    expect(writableWallets(ws, true).length, 4);
    expect(allowedSources(['tpbank', 'momo', 'vcb'], false), ['tpbank']);
    expect(allowedSources(['tpbank', 'momo'], true), ['tpbank', 'momo']);
  });

  test('báo cáo miễn phí: không bản đồ nhiệt, nhận xét chỉ ở báo cáo tuần', () async {
    final db = AppDb(NativeDatabase.memory());
    final cats = await Repo(db).allCategories();
    const prefs = CalendarPrefs();
    final month = periodOf(PeriodType.month, now, prefs);
    final free = buildReport(period: month, current: const [], previous: const [], categories: cats, now: now, pro: false);
    final paid = buildReport(period: month, current: const [], previous: const [], categories: cats, now: now);
    expect((free.heatmap, paid.heatmap != null), (null, true));
    await db.close();
  });

  test('quyền Pro đọc từ cài đặt cục bộ', () async {
    final db = AppDb(NativeDatabase.memory());
    expect(await isPro(db, now), isFalse);
    await db.setSetting('pro_trial_start', now.subtract(const Duration(days: 2)).toIso8601String());
    expect(await isPro(db, now), isTrue);
    await db.setSetting('pro_trial_start', now.subtract(const Duration(days: 20)).toIso8601String());
    await db.setSetting('pro_owned', 'yearly');
    expect(await isPro(db, now), isTrue);
    await db.setSetting('pro_owned', ''); // gói năm hết hạn
    expect(await isPro(db, now), isFalse);
    await db.close();
  });
}
