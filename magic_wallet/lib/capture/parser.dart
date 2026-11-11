import 'dart:convert';

import '../core/money.dart';

class Institution {
  final String id, name, kind;
  final List<String> packages, senders;

  /// Mẫu riêng (regex có nhóm tên: amount, sign, balance, account, content, merchant). Thử trước parser chung.
  final List<RegExp> patterns;
  Institution(this.id, this.name, this.kind, this.packages, this.senders, this.patterns);
}

class InstitutionCatalog {
  final List<Institution> all;
  final List<String> smsApps;
  InstitutionCatalog(this.all, this.smsApps);

  factory InstitutionCatalog.fromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return InstitutionCatalog([
      for (final i in m['institutions'] as List)
        Institution(i['id'], i['name'], i['kind'], List<String>.from(i['packages']), List<String>.from(i['senders']), [
          for (final p in i['patterns'] as List) RegExp(p, caseSensitive: false, multiLine: true),
        ]),
    ], List<String>.from(m['smsApps']));
  }

  Institution? byId(String? id) => all.where((i) => i.id == id).firstOrNull;

  /// Thông báo app ngân hàng: khớp theo package. SMS: khớp tên người gửi trong tiêu đề.
  Institution? identify(String package, String title) {
    for (final i in all) {
      if (i.packages.contains(package)) return i;
    }
    if (smsApps.contains(package)) {
      final t = title.toUpperCase();
      for (final i in all) {
        if (i.senders.any((s) => t.contains(s.toUpperCase()))) return i;
      }
    }
    return null;
  }
}

class ParsedTxn {
  final int amount;

  /// +1 tiền vào, −1 tiền ra.
  final int direction;
  final int? balance;
  final String? last4;
  final String content;
  final String? merchant;
  final bool isRefund;

  /// Độ tin cậy của bước trích số tiền (mẫu riêng cao hơn parser chung).
  final double confidence;
  const ParsedTxn({
    required this.amount,
    required this.direction,
    this.balance,
    this.last4,
    this.content = '',
    this.merchant,
    this.isRefund = false,
    this.confidence = 0.8,
  });
}

sealed class ParseResult {}

class Parsed extends ParseResult {
  final ParsedTxn txn;
  Parsed(this.txn);
}

/// Có OTP/mã xác thực/mật khẩu: bỏ ngay, không lưu (mục 10.2.3).
class DroppedSensitive extends ParseResult {}

class Unrecognized extends ParseResult {}

final _sensitive = RegExp(
  r'\bOTP\b|m[ãa] x[áa]c (th[ựu]c|nh[ậa]n)|m[ậa]t kh[ẩa]u|passcode|verification code',
  caseSensitive: false,
);

// Số tiền có dấu: "-45,000VND", "+1.000.000 đ", "GD: -45,000 VND".
final _signedAmount = RegExp(r'([+\-−])\s?(\d{1,3}(?:[.,]\d{3})+|\d+)\s?(?:VND|VNĐ|đ|d)(?![A-Za-z0-9])', caseSensitive: false);
final _plainAmount = RegExp(r'(\d{1,3}(?:[.,]\d{3})+|\d{4,})\s?(?:VND|VNĐ|đ|d)(?![A-Za-z0-9])', caseSensitive: false);
final _balance = RegExp(r'(?:\bSD|S[ốo] d[ưu])[^\d\n]{0,20}?(\d{1,3}(?:[.,]\d{3})+|\d+)', caseSensitive: false);
final _account = RegExp(r'(?:TK|T[àa]i kho[ảa]n|Account)\s*[:#]?\s*([\dxX*]{2,}\d{3,})', caseSensitive: false);
final _content = RegExp(r'(?:ND|N[ộo]i dung|Noi dung|Description)\s*[:\-]?\s*(.+)$', caseSensitive: false, multiLine: true);
final _merchant = RegExp(
  r'(?:t[ạa]i|cho|to|at)\s+([A-Z0-9][\w&.\- ]{2,40}?)(?:\s*[.,;|]|\s+l[úu]c|\s+v[àa]o|$)',
  caseSensitive: true,
);
final _refund = RegExp(r'ho[àa]n ti[ềe]n|refund', caseSensitive: false);
final _inWords = RegExp(r'nh[ậa]n|c[ộo]ng|n[ạa]p v[àa]o|received|credited|ho[àa]n ti[ềe]n|refund', caseSensitive: false);
// Từ ngắn (chi, trừ, rút) phải đứng riêng để không khớp nhầm trong tên như "TRUONG".
final _outWords = RegExp(
  r'(?<!\p{L})(?:chi|tr[ừu]|r[úu]t)(?!\p{L})|thanh to[áa]n|chuy[ểe]n (ti[ềe]n )?(đi|di|t[ớo]i)|paid|debited|sent',
  caseSensitive: false,
  unicode: true,
);

/// Phân tích nội dung thông báo/SMS ngân hàng thành giao dịch.
ParseResult parseNotification(String text, {Institution? inst}) {
  if (_sensitive.hasMatch(text)) return DroppedSensitive();

  // Mẫu riêng của tổ chức (nếu có) — tin cậy cao hơn.
  for (final re in inst?.patterns ?? const <RegExp>[]) {
    final m = re.firstMatch(text);
    if (m == null) continue;
    String? g(String n) => m.groupNames.contains(n) ? m.namedGroup(n) : null;
    final amount = parseBankAmount(g('amount') ?? '');
    if (amount == null || amount == 0) continue;
    final sign = g('sign');
    final dir = sign == null ? _guessDirection(text) : (sign == '+' ? 1 : -1);
    if (dir == 0) continue;
    return Parsed(
      ParsedTxn(
        amount: amount,
        direction: dir,
        balance: g('balance') == null ? null : parseBankAmount(g('balance')!),
        last4: _last4(g('account')),
        content: g('content')?.trim() ?? '',
        merchant: g('merchant')?.trim(),
        isRefund: _refund.hasMatch(text),
        confidence: 0.97,
      ),
    );
  }

  // Parser chung.
  int? amount;
  var dir = 0;
  final signed = _signedAmount.firstMatch(text);
  if (signed != null) {
    amount = parseBankAmount(signed.group(2)!);
    dir = signed.group(1) == '+' ? 1 : -1;
  } else {
    // Bỏ phần số dư để không lấy nhầm số dư làm số tiền.
    final withoutBalance = text.replaceAll(_balance, '');
    final plain = _plainAmount.firstMatch(withoutBalance);
    if (plain != null) amount = parseBankAmount(plain.group(1)!);
    dir = _guessDirection(text);
  }
  if (amount == null || amount == 0 || dir == 0) return Unrecognized();

  final content = _content.firstMatch(text)?.group(1)?.trim() ?? '';
  return Parsed(
    ParsedTxn(
      amount: amount,
      direction: dir,
      balance: _balance.firstMatch(text) == null ? null : parseBankAmount(_balance.firstMatch(text)!.group(1)!),
      last4: _last4(_account.firstMatch(text)?.group(1)),
      content: content,
      merchant: _merchant.firstMatch(content.isNotEmpty ? content : text)?.group(1)?.trim(),
      isRefund: _refund.hasMatch(text),
      confidence: signed != null ? 0.9 : 0.75,
    ),
  );
}

int _guessDirection(String text) {
  final out = _outWords.hasMatch(text), inn = _inWords.hasMatch(text);
  if (inn && !out) return 1;
  if (out && !inn) return -1;
  if (_refund.hasMatch(text)) return 1;
  return 0;
}

String? _last4(String? acc) {
  if (acc == null) return null;
  final digits = acc.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 4 ? digits.substring(digits.length - 4) : null;
}
