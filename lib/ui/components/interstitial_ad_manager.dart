import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app_review_config.dart';
import '../../app_settings.dart';

class InterstitialAdManager {
  InterstitialAdManager._internal();

  static final InterstitialAdManager instance =
      InterstitialAdManager._internal();
  static const Duration _showTimeout = Duration(seconds: 8);
  static const Duration _androidCooldownDuration = Duration(seconds: 30);
  static const Duration _androidWarmUpDelay = Duration(seconds: 5);
  static const Duration _retryDelay = Duration(seconds: 10);

  InterstitialAd? _cachedAd;
  bool _isLoading = false;
  Timer? _cooldownTimer;
  Timer? _warmUpTimer;
  Timer? _retryTimer;
  final ValueNotifier<bool> isCoolingDown = ValueNotifier(false);

  String? get _adUnitId {
    if (Platform.isIOS) {
      return AppReviewConfig.iosInterstitialAdUnitId.isEmpty
          ? null
          : AppReviewConfig.iosInterstitialAdUnitId;
    }
    if (Platform.isAndroid) {
      return AppReviewConfig.androidInterstitialAdUnitId.isEmpty
          ? null
          : AppReviewConfig.androidInterstitialAdUnitId;
    }
    return null;
  }

  Future<void> warmUp() async {
    if (AppSettings.instance.adsRemoved.value) {
      _retryTimer?.cancel();
      _disposeCachedAd();
      return;
    }
    if (Platform.isAndroid && isCoolingDown.value) {
      return;
    }
    await _ensureLoaded();
  }

  Future<void> showIfNeeded() async {
    if (AppSettings.instance.adsRemoved.value) {
      return;
    }
    final ad = _cachedAd;
    if (ad == null) {
      unawaited(warmUp());
      return;
    }
    _cachedAd = null;

    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete();
        }
        _beginCooldown();
        _scheduleWarmUp();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete();
        }
        _beginCooldown();
        _scheduleWarmUp();
      },
    );
    try {
      ad.show();
      await completer.future.timeout(_showTimeout, onTimeout: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
    } on MissingPluginException {
      ad.dispose();
    } finally {
      _scheduleWarmUp();
    }
  }

  Future<void> settleAfterGame() async {
    if (!Platform.isAndroid) {
      return;
    }
    _warmUpTimer?.cancel();
    _warmUpTimer = null;
    _disposeCachedAd();
    _beginCooldown();
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _ensureLoaded() async {
    if (_cachedAd != null || _isLoading) {
      while (_isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    final adUnitId = _adUnitId;
    if (adUnitId == null) {
      return;
    }

    _isLoading = true;
    final completer = Completer<void>();
    try {
      await InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _disposeCachedAd();
            _cachedAd = ad;
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onAdFailedToLoad: (_) {
            debugPrint(
              'Interstitial ad failed to load '
              '(code=${_.code}, domain=${_.domain}): ${_.message}',
            );
            _scheduleRetry();
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        ),
      );
      await completer.future;
    } on MissingPluginException {
      rethrow;
    } finally {
      _isLoading = false;
    }
  }

  void _disposeCachedAd() {
    _cachedAd?.dispose();
    _cachedAd = null;
  }

  void _scheduleRetry() {
    if (AppSettings.instance.adsRemoved.value) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (!isCoolingDown.value) {
        unawaited(warmUp());
      }
    });
  }

  void _beginCooldown() {
    if (!Platform.isAndroid) {
      return;
    }
    isCoolingDown.value = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(_androidCooldownDuration, () {
      isCoolingDown.value = false;
    });
  }

  void _scheduleWarmUp() {
    if (Platform.isAndroid && isCoolingDown.value) {
      return;
    }
    _retryTimer?.cancel();
    _warmUpTimer?.cancel();
    final delay = Platform.isAndroid ? _androidWarmUpDelay : Duration.zero;
    _warmUpTimer = Timer(delay, () {
      unawaited(warmUp());
    });
  }
}
