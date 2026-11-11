/// Số tiền luôn là số nguyên theo đơn vị nhỏ nhất (VND: đồng) — BR-05.
library;

const _units = {'k': 1000, 'n': 1000, 'tr': 1000000, 'm': 1000000, 'ty': 1000000000, 'tỷ': 1000000000};

/// Đọc chuỗi người dùng gõ nhanh (US-01 AC4): "45k" → 45000, "1tr2" → 1200000,
/// "1.250.000" → 1250000, "1,5tr" → 1500000. Trả null nếu không hiểu.
int? parseAmountInput(String input) {
  var s = input.trim().toLowerCase().replaceAll(' ', '').replaceAll('đ', '').replaceAll('vnd', '');
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d+(?:[.,]\d+)*)(k|n|tr|m|ty|tỷ)?(\d*)$').firstMatch(s);
  if (m == null) return null;
  final head = m.group(1)!;
  final unitKey = m.group(2);
  final tail = m.group(3)!;
  if (unitKey == null) {
    if (tail.isNotEmpty) return null;
    // Không có đơn vị: dấu . và , đều là phân cách hàng nghìn (thói quen VN).
    return int.tryParse(head.replaceAll(RegExp(r'[.,]'), ''));
  }
  final unit = _units[unitKey]!;
  // Có đơn vị: "1,5tr" — dấu thập phân; "1tr2" — phần đuôi là thập phân của đơn vị.
  final parts = head.split(RegExp(r'[.,]'));
  if (parts.length > 2 || (parts.length == 2 && tail.isNotEmpty)) return null;
  final whole = int.parse(parts[0]);
  final frac = parts.length == 2 ? parts[1] : tail;
  var value = whole * unit;
  if (frac.isNotEmpty) {
    value += int.parse(frac) * unit ~/ _pow10(frac.length);
  }
  return value;
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// 1250000 → "1.250.000 đ" (mục 9.3: dấu chấm phân cách hàng nghìn).
String formatVnd(int amount, {bool sign = false, bool hidden = false}) {
  if (hidden) return '••• đ';
  final neg = amount < 0;
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  final prefix = neg ? '−' : (sign && amount > 0 ? '+' : '');
  return '$prefix$buf đ';
}

/// Dạng rút gọn cho câu nhận xét: 1200000 → "1,2 triệu", 45000 → "45 nghìn".
String formatVndShort(int amount) {
  final a = amount.abs();
  String fmt(double v) {
    final s = v.toStringAsFixed(1);
    return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).replaceAll('.', ',');
  }

  if (a >= 1000000000) return '${fmt(a / 1e9)} tỷ';
  if (a >= 1000000) return '${fmt(a / 1e6)} triệu';
  if (a >= 1000) return '${fmt(a / 1e3)} nghìn';
  return '$a đ';
}

/// Đọc số tiền trong thông báo ngân hàng: "1,234,567" hoặc "1.234.567" hoặc "45000".
/// shortcut: bỏ qua phần lẻ thập phân (VND không có xu); khi thêm ngoại tệ cần xử lý "12.50 USD".
int? parseBankAmount(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[.,\s]'), '');
  return int.tryParse(cleaned);
}
