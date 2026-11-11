import 'dart:convert';

import '../core/money.dart';

/// Đọc CSV chuẩn RFC 4180 (dấu phẩy hoặc chấm phẩy, có ngoặc kép).
List<List<String>> parseCsv(String text) {
  final sep = _guessSeparator(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
  return rows;
}

String _guessSeparator(String text) {
  final firstLine = text.split('\n').first;
  return ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';
}

/// Chỉ số cột của sao kê. `amount` là cột có dấu; hoặc dùng cặp `debit`/`credit`.
class ColumnMapping {
  final int date;
  final int? amount, debit, credit;
  final int description;
  const ColumnMapping({required this.date, this.amount, this.debit, this.credit, required this.description});

  bool get valid => amount != null || debit != null || credit != null;

  Map<String, int?> toJson() => {'date': date, 'amount': amount, 'debit': debit, 'credit': credit, 'description': description};
  factory ColumnMapping.fromJson(Map<String, dynamic> m) =>
      ColumnMapping(date: m['date'], amount: m['amount'], debit: m['debit'], credit: m['credit'], description: m['description']);

  /// Khoá lưu mẫu ánh xạ theo dòng tiêu đề, để lần sau nhập cùng ngân hàng không phải chọn lại.
  static String keyFor(List<String> header) => 'import_mapping:${base64Url.encode(utf8.encode(header.join('|').toLowerCase()))}';
}

int? _find(List<String> header, List<String> keys) {
  for (var i = 0; i < header.length; i++) {
    final h = header[i].toLowerCase();
    if (keys.any(h.contains)) return i;
  }
  return null;
}

/// Đoán cột theo tên tiêu đề phổ biến của sao kê ngân hàng Việt Nam.
ColumnMapping? guessMapping(List<String> header) {
  final date = _find(header, ['ngày', 'ngay', 'date']);
  final desc = _find(header, ['nội dung', 'noi dung', 'mô tả', 'mo ta', 'diễn giải', 'dien giai', 'description', 'chi tiết']);
  final debit = _find(header, ['ghi nợ', 'ghi no', 'debit', 'số tiền rút', 'tiền ra']);
  final credit = _find(header, ['ghi có', 'ghi co', 'credit', 'số tiền gửi', 'tiền vào']);
  final amount = (debit == null && credit == null) ? _find(header, ['số tiền', 'so tien', 'amount']) : null;
  if (date == null || desc == null) return null;
  final m = ColumnMapping(date: date, amount: amount, debit: debit, credit: credit, description: desc);
  return m.valid ? m : null;
}

class StatementRow {
  final DateTime date;
  final int amount; // dương
  final int direction; // +1 vào, −1 ra
  final String description;
  const StatementRow(this.date, this.amount, this.direction, this.description);
}

/// dd/MM/yyyy, dd-MM-yyyy, yyyy-MM-dd, có thể kèm giờ HH:mm(:ss).
DateTime? parseStatementDate(String s) {
  final t = s.trim();
  var m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?').firstMatch(t);
  if (m != null) {
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    return DateTime(
      y,
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
      int.parse(m.group(4) ?? '12'),
      int.parse(m.group(5) ?? '0'),
    );
  }
  m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?').firstMatch(t);
  if (m != null) {
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4) ?? '12'),
      int.parse(m.group(5) ?? '0'),
    );
  }
  return null;
}

int? _amountCell(String s) {
  final t = s.replaceAll(RegExp(r'[^\d\-−+]'), '');
  if (t.isEmpty || t == '-' || t == '+') return null;
  final neg = t.startsWith('-') || t.startsWith('−');
  final v = parseBankAmount(t.replaceAll(RegExp(r'[\-−+]'), ''));
  return v == null ? null : (neg ? -v : v);
}

/// Đổi dữ liệu CSV (bỏ dòng tiêu đề) thành các dòng giao dịch; bỏ qua dòng không đọc được.
List<StatementRow> mapRows(List<List<String>> rows, ColumnMapping m) {
  final out = <StatementRow>[];
  String at(List<String> r, int? i) => (i != null && i < r.length) ? r[i] : '';
  for (final r in rows) {
    final date = parseStatementDate(at(r, m.date));
    if (date == null) continue;
    int? signed;
    if (m.amount != null) {
      signed = _amountCell(at(r, m.amount));
    } else {
      final d = _amountCell(at(r, m.debit))?.abs() ?? 0;
      final c = _amountCell(at(r, m.credit))?.abs() ?? 0;
      signed = c - d;
    }
    if (signed == null || signed == 0) continue;
    out.add(StatementRow(date, signed.abs(), signed > 0 ? 1 : -1, at(r, m.description)));
  }
  return out;
}
