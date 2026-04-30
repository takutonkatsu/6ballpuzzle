import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_review_config.dart';
import '../app_settings.dart';

class AdRemovalPurchaseManager {
  AdRemovalPurchaseManager._();

  static final AdRemovalPurchaseManager instance = AdRemovalPurchaseManager._();

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProductDetails? _product;
  bool _isInitialized = false;

  ProductDetails? get product => _product;
  bool get isConfigured => AppReviewConfig.hasAdRemovalProduct;

  Future<bool> initialize() async {
    if (!isConfigured) {
      return false;
    }
    if (_isInitialized) {
      return _product != null;
    }

    _purchaseSubscription ??= _iap.purchaseStream.listen(_handlePurchases);
    final available = await _iap.isAvailable();
    if (!available) {
      _isInitialized = true;
      return false;
    }

    final response = await _iap.queryProductDetails({
      AppReviewConfig.adRemovalProductId,
    });
    _product =
        response.productDetails.isEmpty ? null : response.productDetails.first;
    _isInitialized = true;
    return _product != null;
  }

  Future<bool> buy() async {
    final ready = await initialize();
    final product = _product;
    if (!ready || product == null) {
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restore() async {
    if (!isConfigured) {
      return;
    }
    await initialize();
    await _iap.restorePurchases();
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _isInitialized = false;
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final isAdRemoval =
          purchase.productID == AppReviewConfig.adRemovalProductId;
      if (!isAdRemoval) {
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await AppSettings.instance.setAdsRemoved(true);
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }
}
