import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../data/sync.dart';
import '../data/store.dart';

/// Mã sản phẩm trên Play Console (Kiếm tiền › Sản phẩm trong ứng dụng), 299.000 đ, không tiêu hao.
const kFamily = 'family_lifetime';
const proMaxCircles = 5; // mục 1.4

/// Chỉ bản DEBUG với --dart-define=DEV_PRO=true; bản release kDebugMode = false nên không bao giờ có.
const bool _devPro = kDebugMode && bool.fromEnvironment('DEV_PRO');

/// BR-P1: miễn phí tạo được 1 sợi tơ đôi; Pro tạo được tối đa 5 sợi tơ, có sợi tơ gia đình.
/// Trả null nếu được phép, ngược lại là lý do để hiện màn hình Pro.
String? createBlock({required bool pro, required bool family, required int ownedCircles}) {
  if (pro) return ownedCircles >= proMaxCircles ? 'Bạn đã tạo đủ $proMaxCircles sợi tơ.' : null;
  if (family) return 'Sợi tơ gia đình (tới $familyMax người) cần Gói Gia đình.';
  return ownedCircles >= 1 ? 'Bản miễn phí tạo được 1 sợi tơ đôi.' : null;
}

/// Google Play Billing ngay trên máy (BR-P2) — cùng cách làm với Ví Ma Thuật, không server xác minh.
/// shortcut: tin kết quả Play trên máy, chưa xác minh chữ ký phía server; thêm Cloud Function nếu thấy gian lận.
class Pro {
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? product;
  final owned = ValueNotifier<bool>(_devPro);
  final message = ValueNotifier<String>('');

  Future<void> init() async {
    owned.value = _devPro || await Vault.get('pro') == kFamily;
    if (!await _iap.isAvailable()) return;
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => message.value = 'Lỗi thanh toán: $e');
    product = (await _iap.queryProductDetails({kFamily})).productDetails.firstOrNull;
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != kFamily) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await Vault.set('pro', kFamily);
          owned.value = true;
          message.value = p.status == PurchaseStatus.purchased ? 'Cảm ơn bạn! Gói Gia đình đã mở vĩnh viễn.' : 'Đã khôi phục Gói Gia đình.';
        case PurchaseStatus.pending:
          message.value = 'Giao dịch đang chờ xử lý. Gói sẽ mở khi Google Play xác nhận.';
        case PurchaseStatus.error:
          message.value = 'Không mua được: ${p.error?.message ?? 'lỗi không rõ'}';
        case PurchaseStatus.canceled:
          message.value = '';
      }
      // Bắt buộc xác nhận trong 3 ngày, nếu không Play tự hoàn tiền.
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  Future<void> buy() async {
    if (product == null) {
      message.value = 'Chưa tải được thông tin gói từ Google Play.';
      return;
    }
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product!));
  }

  /// Kết quả đổ về purchaseStream với trạng thái restored.
  Future<void> restore() => _iap.restorePurchases();

  void dispose() => _sub?.cancel();
}
