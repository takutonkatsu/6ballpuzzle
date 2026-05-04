import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter/foundation.dart';

import '../app_review_config.dart';
import '../app_settings.dart';

class AdRemovalPurchaseManager {
  AdRemovalPurchaseManager._();

  static final AdRemovalPurchaseManager instance = AdRemovalPurchaseManager._();

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProductDetails? _product;
  bool _isInitialized = false;
  String? _lastInitializationError;

  ProductDetails? get product => _product;
  bool get isConfigured => AppReviewConfig.hasAdRemovalProduct;
  String? get lastInitializationError => _lastInitializationError;
  bool get isAvailableForPurchase => _product != null;

  Future<bool> initialize() async {
    if (!isConfigured) {
      return false;
    }
    if (_isInitialized) {
      return _product != null;
    }

    try {
      _lastInitializationError = null;
      _purchaseSubscription ??= _iap.purchaseStream.listen(_handlePurchases);
      final available = await _iap.isAvailable();
      if (!available) {
        _isInitialized = true;
        _lastInitializationError = 'StoreKit is unavailable on this device.';
        return false;
      }

      final response = await _iap.queryProductDetails({
        AppReviewConfig.adRemovalProductId,
      });
      if (response.error != null) {
        _lastInitializationError =
            'Product query failed: ${response.error!.message}';
      }
      _product =
          response.productDetails.isEmpty ? null : response.productDetails.first;
      _isInitialized = true;
      if (_product == null && _lastInitializationError == null) {
        _lastInitializationError =
            'Product ${AppReviewConfig.adRemovalProductId} was not returned by the store.';
      }
      return _product != null;
    } catch (error) {
      _isInitialized = true;
      _product = null;
      _lastInitializationError = '$error';
      return false;
    }
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
    final ready = await initialize();
    if (!ready) {
      return;
    }
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

      if (purchase.status == PurchaseStatus.error) {
        debugPrint('Ad removal purchase error: ${purchase.error}');
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }
}
