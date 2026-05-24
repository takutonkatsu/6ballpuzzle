import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../ads/app_ad_service.dart';
import '../../audio/seamless_bgm.dart';

class InterstitialAdManager {
  InterstitialAdManager._internal();

  static final InterstitialAdManager instance =
      InterstitialAdManager._internal();
  static const Duration _retryDelay = Duration(seconds: 10);
  static const Duration _afterGameLoadGrace = Duration(milliseconds: 900);

  InterstitialAd? _cachedAd;
  bool _isLoading = false;
  bool _isShowing = false;
  Timer? _retryTimer;

  Future<void> warmUp() async {
    if (!AppAdService.instance.canRequestAds) {
      _retryTimer?.cancel();
      _disposeCachedAd();
      return;
    }
    try {
      await _ensureLoaded();
    } catch (error, stackTrace) {
      debugPrint('Interstitial warm up failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleRetry();
    }
  }

  Future<void> showAfterGame() async {
    if (!AppAdService.instance.canRequestAds) {
      return;
    }
    if (_cachedAd == null) {
      try {
        await _ensureLoaded().timeout(
          _afterGameLoadGrace,
          onTimeout: () {},
        );
      } catch (_) {
        // リザルト離脱時に間に合わない広告は、次の操作へ持ち越して表示しない。
      }
    }
    await showIfNeeded(warmUpOnMiss: false);
  }

  Future<void> showIfNeeded({bool warmUpOnMiss = true}) async {
    if (!AppAdService.instance.canRequestAds) {
      return;
    }
    if (_isShowing) {
      return;
    }
    final ad = _cachedAd;
    if (ad == null) {
      if (warmUpOnMiss) {
        unawaited(warmUp());
      }
      return;
    }
    _cachedAd = null;
    _isShowing = true;

    final completer = Completer<void>();
    Future<void> finishAd(InterstitialAd ad) async {
      ad.dispose();
      try {
        await SeamlessBgm.instance.resumeFromExternalAudio();
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(finishAd(ad));
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        unawaited(finishAd(ad));
      },
    );
    try {
      await SeamlessBgm.instance.suspendForExternalAudio();
      ad.show();
      await completer.future;
    } catch (error, stackTrace) {
      debugPrint('Interstitial ad show threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      ad.dispose();
      try {
        await SeamlessBgm.instance.resumeFromExternalAudio();
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    } finally {
      _isShowing = false;
      unawaited(warmUp());
    }
  }

  Future<void> settleAfterGame() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _ensureLoaded() async {
    if (_cachedAd != null || _isLoading) {
      while (_isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    final adUnitId = AppAdService.instance.interstitialAdUnitId;
    if (adUnitId == null) {
      return;
    }

    final initialized = await AppAdService.instance.ensureInitialized();
    if (!initialized || !AppAdService.instance.canRequestAds) {
      _scheduleRetry();
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
    } catch (error, stackTrace) {
      debugPrint('Interstitial ad load threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleRetry();
    } finally {
      _isLoading = false;
    }
  }

  void _disposeCachedAd() {
    _cachedAd?.dispose();
    _cachedAd = null;
  }

  void _scheduleRetry() {
    if (!AppAdService.instance.canRequestAds) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      unawaited(warmUp());
    });
  }
}
