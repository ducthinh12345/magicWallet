import 'package:flutter_test/flutter_test.dart';
import 'package:magic_wallet/capture/statement_import.dart';
import 'package:magic_wallet/core/money.dart';
import 'package:magic_wallet/core/periods.dart';
import 'package:magic_wallet/data/repo.dart';

void main() {
  group('parseAmountInput (US-01 AC4)', () {
    final cases = {
      '45k': 45000,
      '1tr2': 1200000,
      '1tr25': 1250000,
      '1tr': 1000000,
      '1,5tr': 1500000,
      '2.5m': 2500000,
      '1.250.000': 1250000,
      '1,250,000': 1250000,
      '500': 500,
      '45K': 45000,
      '2ty': 2000000000,
      ' 30 k ': 30000,
    };
    cases.forEach((input, want) => test(input, () => expect(parseAmountInput(input), want)));
    test('rác → null', () {
      expect(parseAmountInput(''), isNull);
      expect(parseAmountInput('abc'), isNull);
      expect(parseAmountInput('1tr2tr'), isNull);
    });
  });

  test('formatVnd', () {
    expect(formatVnd(1250000), '1.250.000 đ');
    expect(formatVnd(-45000), '−45.000 đ');
    expect(formatVnd(45000, sign: true), '+45.000 đ');
    expect(formatVnd(0), '0 đ');
    expect(formatVnd(999), '999 đ');
    expect(formatVnd(1000), '1.000 đ');
    expect(formatVndShort(1200000), '1,2 triệu');
  });

  group('periods', () {
    const prefs = CalendarPrefs();
    test('tuần bắt đầu Thứ Hai (BR-03)', () {
      final p = periodOf(PeriodType.week, DateTime(2026, 11, 11, 15), prefs); // Thứ Tư
      expect(p.start, DateTime(2026, 11, 9));
      expect(p.end, DateTime(2026, 11, 16));
      expect(p.days, 7);
    });
    test('tuần bắt đầu Chủ nhật', () {
      final p = periodOf(PeriodType.week, DateTime(2026, 11, 11), const CalendarPrefs(weekStart: DateTime.sunday));
      expect(p.start, DateTime(2026, 11, 8));
    });
    test('quý theo năm dương lịch', () {
      final p = periodOf(PeriodType.quarter, DateTime(2026, 11, 11), prefs);
      expect(p.start, DateTime(2026, 10));
      expect(p.end, DateTime(2027, 1));
      expect(p.label, 'Quý 4/2026');
    });
    test('tháng tài chính bắt đầu ngày 5 (BR-04)', () {
      const p5 = CalendarPrefs(monthStartDay: 5);
      expect(periodOf(PeriodType.month, DateTime(2026, 11, 4), p5).start, DateTime(2026, 10, 5));
      final p = periodOf(PeriodType.month, DateTime(2026, 11, 5), p5);
      expect(p.start, DateTime(2026, 11, 5));
      expect(p.end, DateTime(2026, 12, 5));
      expect(shiftPeriod(p, 2, p5).start, DateTime(2027, 1, 5));
      expect(shiftPeriod(p, -11, p5).start, DateTime(2025, 12, 5));
    });
    test('tháng bắt đầu ngày 31 kẹp về cuối tháng', () {
      const p31 = CalendarPrefs(monthStartDay: 31);
      final p = periodOf(PeriodType.month, DateTime(2027, 2, 28), p31);
      expect(p.start, DateTime(2027, 2, 28));
      expect(p.end, DateTime(2027, 3, 31));
      expect(shiftPeriod(p, -1, p31).start, DateTime(2027, 1, 31));
      expect(shiftPeriod(p, 1, p31).start, DateTime(2027, 3, 31));
    });
    test('chuyển năm khi lùi/tiến', () {
      final dec = periodOf(PeriodType.month, DateTime(2026, 12, 20), prefs);
      expect(shiftPeriod(dec, 1, prefs).start, DateTime(2027, 1));
      expect(shiftPeriod(dec, -12, prefs).start, DateTime(2025, 12));
      final w = periodOf(PeriodType.week, DateTime(2026, 12, 30), prefs);
      expect(shiftPeriod(w, 1, prefs).start, DateTime(2027, 1, 4));
    });
  });

  test('nextOccurrence (định kỳ)', () {
    expect(nextOccurrence('FREQ=MONTHLY', DateTime(2026, 1, 15, 8)), DateTime(2026, 2, 15, 8));
    expect(nextOccurrence('FREQ=MONTHLY', DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
    expect(nextOccurrence('FREQ=WEEKLY;INTERVAL=2', DateTime(2026, 1, 1)), DateTime(2026, 1, 15));
    expect(nextOccurrence('FREQ=YEARLY', DateTime(2026, 3, 1)), DateTime(2027, 3, 1));
    expect(nextOccurrence('FREQ=DAILY', DateTime(2026, 12, 31)), DateTime(2027, 1, 1));
  });

  group('sao kê CSV (S5)', () {
    test('ghi nợ/ghi có, ngoặc kép, chấm phẩy', () {
      const csv =
          'Ngày GD;Nội dung;Ghi nợ;Ghi có\n'
          '01/11/2026;"Thanh toan; GRAB";45.000;\n'
          '02/11/2026 09:30;Luong T10;;15.000.000\n'
          'Tổng;;45.000;15.000.000\n';
      final rows = parseCsv(csv);
      expect(rows.length, 4);
      expect(rows[1][1], 'Thanh toan; GRAB');
      final m = guessMapping(rows.first)!;
      expect((m.date, m.description, m.debit, m.credit), (0, 1, 2, 3));
      final out = mapRows(rows.skip(1).toList(), m);
      expect(out.length, 2); // dòng "Tổng" không có ngày → bỏ
      expect((out[0].amount, out[0].direction), (45000, -1));
      expect((out[1].amount, out[1].direction, out[1].date), (15000000, 1, DateTime(2026, 11, 2, 9, 30)));
    });
    test('cột số tiền có dấu', () {
      final rows = parseCsv('Date,Description,Amount\n2026-11-03,Shopee,"-120,000"\n2026-11-04,Refund,50000');
      final m = guessMapping(rows.first)!;
      final out = mapRows(rows.skip(1).toList(), m);
      expect([for (final r in out) r.amount * r.direction], [-120000, 50000]);
    });
  });
}
