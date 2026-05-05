import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../app_review_config.dart';
import '../app_settings.dart';

class AppAdService {
  AppAdService._();

  static final AppAdService instance = AppAdService._();

  Completer<bool>? _initializationCompleter;
  bool _initialized = false;

  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  String? get bannerAdUnitId {
    if (Platform.isAndroid) {
      return _nonEmpty(AppReviewConfig.androidBannerAdUnitId);
    }
    if (Platform.isIOS) {
      return _nonEmpty(AppReviewConfig.iosBannerAdUnitId);
    }
    return null;
  }

  String? get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return _nonEmpty(AppReviewConfig.androidInterstitialAdUnitId);
    }
    if (Platform.isIOS) {
      return _nonEmpty(AppReviewConfig.iosInterstitialAdUnitId);
    }
    return null;
  }

  String? get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return _nonEmpty(AppReviewConfig.androidRewardedAdUnitId);
    }
    if (Platform.isIOS) {
      return _nonEmpty(AppReviewConfig.iosRewardedAdUnitId);
    }
    return null;
  }

  Future<bool> ensureInitialized() {
    if (_initialized) {
      return Future<bool>.value(true);
    }
    final existing = _initializationCompleter;
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<bool>();
    _initializationCompleter = completer;
    unawaited(_initialize(completer));
    return completer.future;
  }

  Future<void> _initialize(Completer<bool> completer) async {
    if (!isSupportedPlatform) {
      completer.complete(false);
      _initializationCompleter = null;
      return;
    }

    try {
      await MobileAds.instance.initialize().timeout(_initializationTimeout);
      _initialized = true;
      completer.complete(true);
    } on MissingPluginException catch (error) {
      debugPrint('Mobile Ads plugin is not available: $error');
      completer.complete(false);
    } on TimeoutException {
      debugPrint('Mobile Ads initialization timed out.');
      completer.complete(false);
    } catch (error, stackTrace) {
      debugPrint('Mobile Ads initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      completer.complete(false);
    } finally {
      _initializationCompleter = null;
    }
  }

  bool get canRequestAds =>
      isSupportedPlatform && !AppSettings.instance.adsRemoved.value;

  String? _nonEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Duration get _initializationTimeout {
    if (Platform.isIOS) {
      return const Duration(seconds: 20);
    }
    return const Duration(seconds: 8);
  }
}
