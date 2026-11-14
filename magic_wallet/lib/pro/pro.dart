import 'package:flutter/foundation.dart' show kDebugMode;

import '../data/database.dart';

/// Mã sản phẩm tạo trên Play Console (Kiếm tiền › Sản phẩm). Đổi ở đây thì phải đổi cả trên Play.
const kProYearly = 'pro_yearly'; // gói đăng ký năm (199.000đ đề xuất)
const kProLifetime = 'pro_lifetime'; // sản phẩm mua một lần (499.000đ đề xuất)
const trialDays = 14;

/// Cấp Pro trọn đời cho máy phát triển/thử nghiệm nội bộ: chỉ bản DEBUG build với --dart-define=DEV_PRO_LIFETIME=true.
/// Bản release luôn là false (kDebugMode là hằng false → trình biên dịch loại bỏ), nên người dùng CH Play không bao giờ có.
const bool devProLifetime = kDebugMode && bool.fromEnvironment('DEV_PRO_LIFETIME');

/// Giới hạn bản miễn phí (mục 1.4). Bảo mật, xuất dữ liệu, sao lưu thủ công không bao giờ bị khoá.
class FreeLimits {
  static const wallets = 3;
  static const autoSources = 1; // ngân hàng/ví được ghi tự động
  static const rules = 5;
  static const categoryBudgets = 3; // + 1 ngân sách tổng
}

/// Quyền Pro đọc từ cài đặt cục bộ. Nguồn sự thật là Google Play; app ghi lại kết quả mỗi lần đối chiếu.
class ProState {
  final String owned; // '' | 'yearly' | 'lifetime'
  final DateTime? trialStart;
  const ProState({this.owned = '', this.trialStart});

  DateTime? get trialEnd => trialStart?.add(const Duration(days: trialDays));
  bool trialActive(DateTime now) => trialEnd != null && now.isBefore(trialEnd!);
  bool get purchased => owned == 'yearly' || owned == 'lifetime';
  bool isPro(DateTime now) => purchased || trialActive(now);
  bool get canStartTrial => trialStart == null && !purchased;

  /// Số ngày dùng thử còn lại, làm tròn lên (còn 1 giờ vẫn tính 1 ngày).
  int trialDaysLeft(DateTime now) {
    if (!trialActive(now)) return 0;
    final h = trialEnd!.difference(now).inHours;
    return (h + 23) ~/ 24;
  }

  static Future<ProState> load(AppDb db) async => ProState(
        owned: devProLifetime ? 'lifetime' : (await db.getSetting('pro_owned') ?? ''),
        trialStart: DateTime.tryParse(await db.getSetting('pro_trial_start') ?? ''),
      );
}

Future<bool> isPro(AppDb db, [DateTime? now]) async => (await ProState.load(db)).isPro(now ?? DateTime.now());

/// Kết quả đối chiếu với Play: tập mã sản phẩm người dùng đang sở hữu → giá trị lưu 'pro_owned'.
/// Gói năm hết hạn thì Play không trả về nữa → mất Pro, dữ liệu giữ nguyên (BR-10).
String ownedFrom(Set<String> productIds) =>
    productIds.contains(kProLifetime) ? 'lifetime' : (productIds.contains(kProYearly) ? 'yearly' : '');

/// BR-10: hết Pro thì ví thứ 4 trở đi (theo thứ tự tạo) chỉ còn đọc — không chọn để ghi giao dịch mới.
List<Wallet> writableWallets(List<Wallet> wallets, bool pro) {
  if (pro) return wallets;
  final sorted = [...wallets]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return sorted.take(FreeLimits.wallets).toList();
}

/// BR-10: hết Pro thì ghi tự động quay về 1 nguồn — nguồn bật đầu tiên trong danh sách người dùng đã chọn.
List<String> allowedSources(List<String> enabledInOrder, bool pro) =>
    pro ? enabledInOrder : enabledInOrder.take(FreeLimits.autoSources).toList();
