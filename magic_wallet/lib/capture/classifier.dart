import 'dart:math';

import '../data/database.dart';

/// Từ điển nhà bán phổ biến (mục 5.2 bước 4b): từ khoá → tên danh mục mặc định.
const merchantDictionary = <String, String>{
  'grab': 'Taxi/Grab',
  'xanh sm': 'Taxi/Grab',
  'gojek': 'Taxi/Grab',
  'petrolimex': 'Xăng xe',
  'xang dau': 'Xăng xe',
  'pvoil': 'Xăng xe',
  'highlands': 'Cà phê',
  'phuc long': 'Cà phê',
  'phúc long': 'Cà phê',
  'starbucks': 'Cà phê',
  'the coffee house': 'Cà phê',
  'katinat': 'Cà phê',
  'cong caphe': 'Cà phê',
  'cộng cà phê': 'Cà phê',
  'kfc': 'Ăn uống',
  'lotteria': 'Ăn uống',
  'jollibee': 'Ăn uống',
  'mcdonald': 'Ăn uống',
  'pizza': 'Ăn uống',
  'shopeefood': 'Ăn uống',
  'grabfood': 'Ăn uống',
  'baemin': 'Ăn uống',
  'bun ': 'Ăn uống',
  'pho ': 'Ăn uống',
  'shopee': 'Mua sắm',
  'lazada': 'Mua sắm',
  'tiki': 'Mua sắm',
  'tiktok shop': 'Mua sắm',
  'uniqlo': 'Quần áo',
  'winmart': 'Mua sắm',
  'bach hoa xanh': 'Mua sắm',
  'bách hóa xanh': 'Mua sắm',
  'coopmart': 'Mua sắm',
  'circle k': 'Mua sắm',
  'gs25': 'Mua sắm',
  'aeon': 'Mua sắm',
  'go!': 'Mua sắm',
  'evn': 'Điện',
  'dien luc': 'Điện',
  'điện lực': 'Điện',
  'tien dien': 'Điện',
  'tiền điện': 'Điện',
  'nuoc sach': 'Nước',
  'cap nuoc': 'Nước',
  'tien nuoc': 'Nước',
  'tiền nước': 'Nước',
  'fpt telecom': 'Internet',
  'vnpt': 'Internet',
  'viettel': 'Điện thoại',
  'mobifone': 'Điện thoại',
  'vinaphone': 'Điện thoại',
  'nap tien dt': 'Điện thoại',
  'netflix': 'Giải trí',
  'spotify': 'Giải trí',
  'youtube': 'Giải trí',
  'cgv': 'Giải trí',
  'steam': 'Giải trí',
  'pharmacity': 'Sức khỏe',
  'long chau': 'Sức khỏe',
  'long châu': 'Sức khỏe',
  'benh vien': 'Sức khỏe',
  'tien nha': 'Tiền nhà',
  'tiền nhà': 'Tiền nhà',
  'hoc phi': 'Giáo dục',
  'học phí': 'Giáo dục',
  'luong': 'Lương',
  'lương': 'Lương',
  'salary': 'Lương',
  'thuong': 'Thưởng',
  'thưởng': 'Thưởng',
};

class Classification {
  final String? categoryId;
  final double confidence;
  final String via; // rule / dictionary / learned / none
  const Classification(this.categoryId, this.confidence, this.via);
}

/// Mẫu học từ một giao dịch đã xác nhận.
class LearnedSample {
  final String text, categoryId;
  const LearnedSample(this.text, this.categoryId);
}

List<String> _tokens(String s) =>
    s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((t) => t.length >= 2).toList();

/// Phân loại theo thứ tự (a) quy tắc người dùng, (b) từ điển, (c) Naive Bayes học cục bộ.
Classification classify({
  required String text,
  required String type, // expense / income
  required List<ClassificationRule> rules,
  required List<Category> categories,
  List<LearnedSample> history = const [],
  String? walletId,
}) {
  final lower = text.toLowerCase();
  final sorted = [...rules]..sort((a, b) => b.priority.compareTo(a.priority));
  for (final r in sorted) {
    if (r.walletId != null && r.walletId != walletId) continue;
    final p = r.pattern.toLowerCase();
    final hit = switch (r.matchType) {
      'exact' => lower.trim() == p.trim(),
      'regex' => RegExp(r.pattern, caseSensitive: false).hasMatch(text),
      _ => lower.contains(p),
    };
    if (hit) return Classification(r.categoryId, 0.97, 'rule');
  }

  final ofType = categories.where((c) => c.type == type && !c.hidden).toList();
  // Khoá dài trước để "grabfood" thắng "grab".
  final keys = merchantDictionary.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (lower.contains(k)) {
      final cat = ofType.where((c) => c.name == merchantDictionary[k]).firstOrNull;
      if (cat != null) return Classification(cat.id, 0.9, 'dictionary');
    }
  }

  final allowed = {for (final c in ofType) c.id};
  final learned = _naiveBayes(_tokens(text), history.where((h) => allowed.contains(h.categoryId)));
  if (learned != null) return learned;

  final fallback = ofType.where((c) => c.name == (type == 'income' ? 'Thu khác' : 'Khác')).firstOrNull;
  return Classification(fallback?.id, 0.3, 'none');
}

Classification? _naiveBayes(List<String> tokens, Iterable<LearnedSample> samples) {
  if (tokens.isEmpty) return null;
  final docCount = <String, int>{};
  final tokenCount = <String, Map<String, int>>{};
  final totalTokens = <String, int>{};
  final vocab = <String>{};
  for (final s in samples) {
    docCount[s.categoryId] = (docCount[s.categoryId] ?? 0) + 1;
    for (final t in _tokens(s.text)) {
      (tokenCount[s.categoryId] ??= {})[t] = (tokenCount[s.categoryId]![t] ?? 0) + 1;
      totalTokens[s.categoryId] = (totalTokens[s.categoryId] ?? 0) + 1;
      vocab.add(t);
    }
  }
  // Không có token nào từng gặp → không đoán bừa.
  if (!tokens.any(vocab.contains)) return null;
  final n = docCount.values.fold(0, (a, b) => a + b);
  final logp = <String, double>{};
  for (final c in docCount.keys) {
    var lp = log(docCount[c]! / n);
    for (final t in tokens) {
      lp += log(((tokenCount[c]?[t] ?? 0) + 1) / ((totalTokens[c] ?? 0) + vocab.length));
    }
    logp[c] = lp;
  }
  final best = logp.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final maxLp = best.value;
  final z = logp.values.fold(0.0, (a, v) => a + exp(v - maxLp));
  // Trần 0,9: mô hình học không bao giờ đủ để tự xác nhận (ngưỡng 95%).
  return Classification(best.key, min(0.9, 1 / z), 'learned');
}
