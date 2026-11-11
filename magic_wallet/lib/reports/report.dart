import '../core/money.dart';
import '../core/periods.dart';
import '../data/database.dart';

/// Cây danh mục gọn để tra cha và loại.
class CatIndex {
  final Map<String, Category> byId;
  CatIndex(List<Category> cats) : byId = {for (final c in cats) c.id: c};

  /// Danh mục gốc (cấp 1) — báo cáo cơ cấu gộp theo cấp này.
  String? root(String? id) {
    var c = byId[id];
    while (c?.parentId != null && byId.containsKey(c!.parentId)) {
      c = byId[c.parentId];
    }
    return c?.id;
  }

  bool isFixed(String? id) => byId[id]?.isFixedCost ?? false;
  bool isUnder(String? id, String ancestor) {
    var c = byId[id];
    while (c != null) {
      if (c.id == ancestor) return true;
      c = byId[c.parentId];
    }
    return false;
  }

  String name(String? id) => byId[id]?.name ?? 'Chưa phân loại';
}

/// Hoàn tiền: ghi là thu nhưng thuộc danh mục chi → trừ vào chi (mục 5.4).
bool isRefund(Txn t, CatIndex cats) => t.type == 'income' && cats.byId[t.categoryId]?.type == 'expense';

/// Chi ròng có dấu của một giao dịch: chi = +, hoàn tiền = −, còn lại 0. Chuyển khoản không tính (BR-01).
int expenseOf(Txn t, CatIndex cats) {
  if (t.type == 'expense') return t.amountBase;
  if (isRefund(t, cats)) return -t.amountBase;
  return 0;
}

int incomeOf(Txn t, CatIndex cats) => t.type == 'income' && !isRefund(t, cats) ? t.amountBase : 0;

class Totals {
  final int income, expense;
  const Totals(this.income, this.expense);
  int get net => income - expense;

  /// (thu − chi) / thu; null khi không có thu.
  double? get savingsRate => income == 0 ? null : net / income;

  factory Totals.of(Iterable<Txn> txns, CatIndex cats) {
    var i = 0, e = 0;
    for (final t in txns) {
      i += incomeOf(t, cats);
      e += expenseOf(t, cats);
    }
    return Totals(i, e);
  }
}

double? pctChange(int now, int before) => before == 0 ? null : (now - before) / before;

class TrendPoint {
  final String label;
  final int expense, income;
  const TrendPoint(this.label, this.expense, this.income);
}

class Report {
  final Period period;
  final Totals totals, previous;
  final Totals? lastYear;
  final List<MapEntry<String?, int>> byCategory; // id danh mục gốc → chi, giảm dần
  final List<TrendPoint> trend;
  final List<Txn> largest;
  final int fixedExpense, variableExpense;

  /// [thứ 0..6 (Thứ Hai = 0)][giờ 0..23] → chi; null nếu kỳ không cần.
  final List<List<int>>? heatmap;
  final List<String> insights;
  const Report({
    required this.period,
    required this.totals,
    required this.previous,
    required this.lastYear,
    required this.byCategory,
    required this.trend,
    required this.largest,
    required this.fixedExpense,
    required this.variableExpense,
    required this.heatmap,
    required this.insights,
  });
}

const _topN = {PeriodType.week: 3, PeriodType.month: 5, PeriodType.quarter: 10, PeriodType.year: 10};
const _maxInsights = {PeriodType.week: 2, PeriodType.month: 3, PeriodType.quarter: 3, PeriodType.year: 3};
const _thisName = {
  PeriodType.week: 'tuần này',
  PeriodType.month: 'tháng này',
  PeriodType.quarter: 'quý này',
  PeriodType.year: 'năm nay',
};
const _unitName = {PeriodType.week: 'tuần', PeriodType.month: 'tháng', PeriodType.quarter: 'quý', PeriodType.year: 'năm'};

/// Ngưỡng nhận xét (7.2): lệch ≥ 20% và ≥ 200.000đ.
const insightMinPct = 0.2;
const insightMinAbs = 200000;

/// Tạo báo cáo từ dữ liệu đã lọc sẵn theo kỳ (giao dịch đã xác nhận, chưa xoá).
Report buildReport({
  required Period period,
  required List<Txn> current,
  required List<Txn> previous,
  List<Txn>? sameLastYear,
  List<List<Txn>> prior4 = const [],
  required List<Category> categories,
  List<BudgetStatus> budgets = const [],
  required DateTime now,
  Totals? previousYearForSavings,
}) {
  final cats = CatIndex(categories);
  final totals = Totals.of(current, cats);
  final prev = Totals.of(previous, cats);

  final byCat = <String?, int>{};
  var fixed = 0, variable = 0;
  for (final t in current) {
    final e = expenseOf(t, cats);
    if (e == 0) continue;
    final root = cats.root(t.categoryId);
    byCat[root] = (byCat[root] ?? 0) + e;
    if (cats.isFixed(t.categoryId)) {
      fixed += e;
    } else {
      variable += e;
    }
  }
  final sortedCats = byCat.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));

  final byDay = period.type == PeriodType.week || period.type == PeriodType.month;
  final trend = <TrendPoint>[];
  if (byDay) {
    for (var i = 0; i < period.days; i++) {
      final d = DateTime(period.start.year, period.start.month, period.start.day + i);
      final next = DateTime(d.year, d.month, d.day + 1);
      final inDay = current.where((t) => !t.occurredAt.isBefore(d) && t.occurredAt.isBefore(next));
      final tt = Totals.of(inDay, cats);
      trend.add(TrendPoint('${d.day}', tt.expense, tt.income));
    }
  } else {
    for (var m = DateTime(period.start.year, period.start.month); m.isBefore(period.end); m = DateTime(m.year, m.month + 1)) {
      final next = DateTime(m.year, m.month + 1);
      final tt = Totals.of(current.where((t) => !t.occurredAt.isBefore(m) && t.occurredAt.isBefore(next)), cats);
      trend.add(TrendPoint('T${m.month}', tt.expense, tt.income));
    }
  }

  final largest = current.where((t) => t.type == 'expense').toList()..sort((a, b) => b.amountBase.compareTo(a.amountBase));

  List<List<int>>? heat;
  if (period.type == PeriodType.month || period.type == PeriodType.year) {
    heat = List.generate(7, (_) => List.filled(24, 0));
    for (final t in current) {
      final e = expenseOf(t, cats);
      if (e > 0) heat[t.occurredAt.weekday - 1][t.occurredAt.hour] += e;
    }
  }

  final insights = _insights(period, cats, current, prior4, budgets, totals, prev, now);

  return Report(
    period: period,
    totals: totals,
    previous: prev,
    lastYear: sameLastYear == null ? null : Totals.of(sameLastYear, cats),
    byCategory: sortedCats,
    trend: trend,
    largest: largest.take(_topN[period.type]!).toList(),
    fixedExpense: fixed,
    variableExpense: variable,
    heatmap: heat,
    insights: insights,
  );
}

class _Insight {
  final int weight; // độ lớn chênh lệch tuyệt đối, để xếp hạng
  final String text;
  _Insight(this.weight, this.text);
}

List<String> _insights(
  Period period,
  CatIndex cats,
  List<Txn> current,
  List<List<Txn>> prior4,
  List<BudgetStatus> budgets,
  Totals totals,
  Totals prev,
  DateTime now,
) {
  final out = <_Insight>[];
  String pct(double v) => '${(v * 100).round()}%';

  // 1) Danh mục lệch so với trung bình các kỳ trước.
  if (prior4.isNotEmpty) {
    Map<String?, int> sumByRoot(List<Txn> txns) {
      final m = <String?, int>{};
      for (final t in txns) {
        final e = expenseOf(t, cats);
        if (e != 0) m[cats.root(t.categoryId)] = (m[cats.root(t.categoryId)] ?? 0) + e;
      }
      return m;
    }

    final cur = sumByRoot(current);
    final hist = prior4.map(sumByRoot).toList();
    for (final id in {...cur.keys, ...hist.expand((h) => h.keys)}) {
      final now0 = cur[id] ?? 0;
      final avg = hist.fold<int>(0, (a, h) => a + (h[id] ?? 0)) ~/ hist.length;
      if (avg == 0) continue;
      final diff = now0 - avg;
      final rel = diff / avg;
      if (rel.abs() >= insightMinPct && diff.abs() >= insightMinAbs) {
        out.add(
          _Insight(
            diff.abs(),
            '${cats.name(id)} ${_thisName[period.type]} ${formatVndShort(now0)}, ${diff > 0 ? 'cao' : 'thấp'} hơn ${pct(rel.abs())} so với trung bình ${hist.length} ${_unitName[period.type]}.',
          ),
        );
      }
    }
  }

  // 2) Tốc độ dùng ngân sách nhanh hơn thời gian trôi qua.
  if (period.contains(now)) {
    final elapsed = now.difference(period.start).inMinutes / period.end.difference(period.start).inMinutes;
    for (final b in budgets) {
      if (b.limit <= 0 || b.spent < insightMinAbs) continue;
      if (b.pct - elapsed >= insightMinPct) {
        final name = b.categoryName ?? 'tổng';
        out.add(
          _Insight(
            b.spent - (b.limit * elapsed).round(),
            'Bạn đã dùng ${pct(b.pct)} ngân sách $name khi ${_unitName[b.period.type]} mới qua ${pct(elapsed)}.',
          ),
        );
      }
    }
  }

  // 3) Tỷ lệ tiết kiệm so với kỳ trước (không áp dụng cho tuần — bảng 7.1).
  final r = totals.savingsRate, rp = prev.savingsRate;
  if (period.type != PeriodType.week && r != null && rp != null && rp != 0) {
    final rel = (r - rp) / rp.abs();
    final diffAbs = (totals.net - prev.net).abs();
    if (rel.abs() >= insightMinPct && diffAbs >= insightMinAbs) {
      final pts = ((r - rp) * 100).round();
      final head = period.type == PeriodType.year ? 'Năm ${period.start.year}' : 'Kỳ này';
      out.add(
        _Insight(
          diffAbs,
          '$head bạn tiết kiệm được ${pct(r)} thu nhập, ${pts >= 0 ? 'tăng' : 'giảm'} ${pts.abs()} điểm so với kỳ trước.',
        ),
      );
    }
  }

  out.sort((a, b) => b.weight.compareTo(a.weight));
  return out.take(_maxInsights[period.type]!).map((i) => i.text).toList();
}

// ---------------- Ngân sách ----------------

class BudgetStatus {
  final Budget budget;
  final Period period;
  final String? categoryName;
  final int limit; // gồm phần dư chuyển sang (nếu bật rollover)
  final int spent;
  const BudgetStatus(this.budget, this.period, this.categoryName, this.limit, this.spent);

  double get pct => limit == 0 ? 0 : spent / limit;
  int get remaining => limit - spent;

  /// US-03 AC2: "Còn được chi X đ/ngày" cho số ngày còn lại (tính cả hôm nay).
  int perDayLeft(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final daysLeft = Period(period.type, today, period.end).days;
    if (daysLeft <= 0 || remaining <= 0) return 0;
    return remaining ~/ daysLeft;
  }

  /// Ngưỡng đã chạm: 100, 80 hoặc null.
  int? get threshold => pct >= 1 ? 100 : (pct >= 0.8 ? 80 : null);
}

int spentFor(Budget b, Iterable<Txn> txns, CatIndex cats) {
  var s = 0;
  for (final t in txns) {
    if (b.categoryId != null && !cats.isUnder(t.categoryId, b.categoryId!)) continue;
    s += expenseOf(t, cats);
  }
  return s;
}

/// Tính trạng thái ngân sách cho kỳ chứa `now`. `load` lấy giao dịch đã xác nhận trong khoảng.
Future<List<BudgetStatus>> budgetStatuses({
  required List<Budget> budgets,
  required List<Category> categories,
  required DateTime now,
  required CalendarPrefs prefs,
  required Future<List<Txn>> Function(DateTime from, DateTime to) load,
}) async {
  final cats = CatIndex(categories);
  final out = <BudgetStatus>[];
  for (final b in budgets) {
    final type = PeriodType.values.byName(b.period);
    final p = periodOf(type, now, prefs);
    final spent = spentFor(b, await load(p.start, p.end), cats);
    var limit = b.amount;
    if (b.rollover) {
      // Chuyển phần dư của đúng 1 kỳ liền trước, chỉ khi ngân sách đã tồn tại từ kỳ đó.
      final prev = shiftPeriod(p, -1, prefs);
      if (!b.startDate.isAfter(prev.start)) {
        final left = b.amount - spentFor(b, await load(prev.start, prev.end), cats);
        if (left > 0) limit += left;
      }
    }
    out.add(BudgetStatus(b, p, b.categoryId == null ? null : cats.name(b.categoryId), limit, spent));
  }
  return out;
}
