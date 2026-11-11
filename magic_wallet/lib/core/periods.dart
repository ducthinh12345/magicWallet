/// Kỳ báo cáo/ngân sách. Khoảng [start, end) — end không bao gồm.
enum PeriodType { week, month, quarter, year }

const periodLabels = {PeriodType.week: 'Tuần', PeriodType.month: 'Tháng', PeriodType.quarter: 'Quý', PeriodType.year: 'Năm'};

class Period {
  final PeriodType type;
  final DateTime start;
  final DateTime end;
  const Period(this.type, this.start, this.end);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
  int get days => _utc(end).difference(_utc(start)).inDays;

  String get label {
    String d(DateTime t) => '${t.day}/${t.month}';
    switch (type) {
      case PeriodType.week:
        return '${d(start)} – ${d(end.subtract(const Duration(days: 1)))}';
      case PeriodType.month:
        // Tháng tài chính lệch ngày 1 (BR-04) thì ghi rõ khoảng ngày.
        return start.day == 1
            ? 'Tháng ${start.month}/${start.year}'
            : '${d(start)} – ${d(end.subtract(const Duration(days: 1)))}/${end.year}';
      case PeriodType.quarter:
        return 'Quý ${(start.month - 1) ~/ 3 + 1}/${start.year}';
      case PeriodType.year:
        return 'Năm ${start.year}';
    }
  }

  @override
  bool operator ==(Object other) => other is Period && other.type == type && other.start == start;
  @override
  int get hashCode => Object.hash(type, start);
}

/// Cài đặt lịch: tuần bắt đầu thứ mấy (1 = Thứ Hai, BR-03), tháng tài chính bắt đầu ngày mấy (BR-04).
class CalendarPrefs {
  final int weekStart;
  final int monthStartDay;
  const CalendarPrefs({this.weekStart = DateTime.monday, this.monthStartDay = 1});
}

// Đếm ngày theo lịch UTC để không lệch giờ khi có DST.
DateTime _utc(DateTime t) => DateTime.utc(t.year, t.month, t.day);

DateTime _dayInMonth(int year, int month, int day) {
  // Ngày 31 với tháng ngắn thì lùi về ngày cuối tháng.
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}

Period periodOf(PeriodType type, DateTime at, CalendarPrefs prefs) {
  final day = DateTime(at.year, at.month, at.day);
  switch (type) {
    case PeriodType.week:
      final back = (day.weekday - prefs.weekStart + 7) % 7;
      final s = DateTime(day.year, day.month, day.day - back);
      return Period(type, s, DateTime(s.year, s.month, s.day + 7));
    case PeriodType.month:
      var s = _dayInMonth(day.year, day.month, prefs.monthStartDay);
      if (day.isBefore(s)) s = _dayInMonth(day.year, day.month - 1, prefs.monthStartDay);
      // DateTime tự chuẩn hoá tháng 13 → tháng 1 năm sau.
      final norm = DateTime(s.year, s.month);
      return Period(type, s, _dayInMonth(norm.year, norm.month + 1, prefs.monthStartDay));
    case PeriodType.quarter:
      final qm = (day.month - 1) ~/ 3 * 3 + 1;
      return Period(type, DateTime(day.year, qm), DateTime(day.year, qm + 3));
    case PeriodType.year:
      return Period(type, DateTime(day.year), DateTime(day.year + 1));
  }
}

/// Kỳ trước/sau `n` bước (n âm = lùi).
Period shiftPeriod(Period p, int n, CalendarPrefs prefs) {
  switch (p.type) {
    case PeriodType.week:
      return periodOf(p.type, DateTime(p.start.year, p.start.month, p.start.day + 7 * n), prefs);
    case PeriodType.month:
      // Lấy ngày giữa kỳ rồi dời tháng để tránh lệch khi ngày bắt đầu là 29–31.
      final mid = DateTime(p.start.year, p.start.month + n, 15);
      final anchor = prefs.monthStartDay > 15 ? DateTime(mid.year, mid.month + 1, 1) : mid;
      return periodOf(p.type, anchor, prefs);
    case PeriodType.quarter:
      return periodOf(p.type, DateTime(p.start.year, p.start.month + 3 * n), prefs);
    case PeriodType.year:
      return periodOf(p.type, DateTime(p.start.year + n), prefs);
  }
}

/// Cùng kỳ năm trước (dùng cho báo cáo tháng).
Period sameLastYear(Period p, CalendarPrefs prefs) =>
    periodOf(p.type, DateTime(p.start.year - 1, p.start.month, p.start.day), prefs);
