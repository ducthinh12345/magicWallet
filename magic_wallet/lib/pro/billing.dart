import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import '../data/database.dart';
import 'pro.dart';

/// Google Play Billing / Apple StoreKit ngay trên máy (BR-08): không server, nhà phát triển không lưu thông tin người mua.
class Billing {
  final AppDb db;
  Billing(this.db);

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Completer<List<PurchaseDetails>>? _restoring;

  bool available = false;
  List<ProductDetails> products = [];

  /// Báo UI vẽ lại (đổi trạng thái Pro, lỗi mua…). Giá trị là thông điệp gần nhất cho người dùng, rỗng nếu không có.
  final message = ValueNotifier<String>('');
  final changed = ValueNotifier<int>(0);

  Future<void> init() async {
    if (kIsWeb) return; // shortcut: web chưa bán Pro (BR-11: mã kích hoạt cho PWA — chưa làm)
    available = await _iap.isAvailable();
    if (!available) return;
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => message.value = 'Lỗi thanh toán: $e');
    final r = await _iap.queryProductDetails({kProYearly, kProLifetime});
    products = r.productDetails;
    await refresh();
  }

  ProductDetails? product(String id) => products.where((p) => p.id == id).firstOrNull;

  /// Đối chiếu quyền Pro với Play (BR-09: khôi phục được trên máy mới).
  /// Lỗi mạng/Play thì giữ nguyên trạng thái đang lưu — không tước Pro của người đã trả tiền chỉ vì offline.
  Future<bool> refresh() async {
    if (!available) return false;
    _restoring = Completer();
    try {
      final Set<String> ids;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // StoreKit 2: chỉ trả quyền còn hiệu lực — gói năm hết hạn tự biến mất khỏi danh sách.
        ids = {for (final t in await SK2Transaction.currentEntitlements()) t.productId};
      } else {
        await _iap.restorePurchases();
        // Plugin Android phát đúng một lô (kể cả rỗng) sau khi restorePurchases trả về.
        final owned = await _restoring!.future.timeout(const Duration(seconds: 10));
        ids = {for (final p in owned) if (p.status == PurchaseStatus.restored || p.status == PurchaseStatus.purchased) p.productID};
      }
      await db.setSetting('pro_owned', ownedFrom(ids));
      changed.value++;
      return true;
    } catch (e) {
      return false;
    } finally {
      _restoring = null;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    if (_restoring != null && !_restoring!.isCompleted) _restoring!.complete(list);
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Quyền vừa mua: cấp ngay, không chờ lần đối chiếu sau.
          final current = await db.getSetting('pro_owned') ?? '';
          await db.setSetting('pro_owned', ownedFrom({p.productID, if (current == 'lifetime') kProLifetime, if (current == 'yearly') kProYearly}));
          if (p.status == PurchaseStatus.purchased) message.value = 'Cảm ơn bạn! Pro đã được kích hoạt.';
        case PurchaseStatus.pending:
          message.value = 'Giao dịch đang chờ xử lý. Pro sẽ bật khi Google Play xác nhận thanh toán.';
        case PurchaseStatus.error:
          message.value = 'Không mua được: ${p.error?.message ?? 'lỗi không rõ'}';
        case PurchaseStatus.canceled:
          message.value = '';
      }
      // Bắt buộc xác nhận với Play trong 3 ngày, nếu không Play tự hoàn tiền.
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    changed.value++;
  }

  Future<void> buy(ProductDetails p) => _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));

  void dispose() => _sub?.cancel();
}

/// Tên kho ứng dụng để hiển thị đúng với nền tảng người dùng đang dùng.
String get storeName => defaultTargetPlatform == TargetPlatform.iOS ? 'App Store' : 'Google Play';

/// Nơi người dùng tự huỷ gói thuê bao.
String get manageSubscriptionsUrl => defaultTargetPlatform == TargetPlatform.iOS
    ? 'https://apps.apple.com/account/subscriptions'
    : 'https://play.google.com/store/account/subscriptions';

String get cancelHint => defaultTargetPlatform == TargetPlatform.iOS
    ? 'Cài đặt › [tên bạn] › Đăng ký'
    : 'Google Play › Thanh toán và gói thuê bao';
