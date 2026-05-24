import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../ads/app_ad_service.dart';
import '../../audio/seamless_bgm.dart';

class RewardedAdManager {
  RewardedAdManager._internal();

  static final RewardedAdManager instance = RewardedAdManager._internal();
  static const Duration _retryDelay = Duration(seconds: 10);

  RewardedAd? _cachedAd;
  bool _isLoading = false;
  Completer<void>? _loadingCompleter;
  Timer? _retryTimer;

  bool get isReady => _cachedAd != null;
  bool get isLoading => _isLoading;

  Future<void> warmUp() async {
    try {
      await _ensureLoaded();
    } catch (error, stackTrace) {
      debugPrint('Rewarded ad warm up failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleRetry();
    }
  }

  Future<bool> showDoubleRewardAd() async {
    try {
      if (_cachedAd == null) {
        await _ensureLoaded().timeout(_loadTimeout);
      }
    } on TimeoutException {
      return false;
    }

    final ad = _cachedAd;
    if (ad == null) {
      return false;
    }
    _cachedAd = null;

    final completer = Completer<bool>();
    var rewarded = false;
    Future<void> finishAd(RewardedAd ad, bool result) async {
      ad.dispose();
      try {
        await SeamlessBgm.instance.resumeFromExternalAudio();
      } finally {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
        unawaited(warmUp());
      }
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(finishAd(ad, rewarded));
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        unawaited(finishAd(ad, false));
      },
    );
    try {
      await SeamlessBgm.instance.suspendForExternalAudio();
      ad.show(
        onUserEarnedReward: (_, __) {
          rewarded = true;
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Rewarded ad show threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      ad.dispose();
      try {
        await SeamlessBgm.instance.resumeFromExternalAudio();
      } finally {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        unawaited(warmUp());
      }
    }
    return completer.future;
  }

  Future<void> _ensureLoaded() async {
    if (_cachedAd != null) {
      return;
    }
    final loadingCompleter = _loadingCompleter;
    if (_isLoading && loadingCompleter != null) {
      await loadingCompleter.future;
      return;
    }
    if (!AppAdService.instance.canRequestAds) {
      return;
    }
    final adUnitId = AppAdService.instance.rewardedAdUnitId;
    if (adUnitId == null) {
      return;
    }

    _isLoading = true;
    _loadingCompleter = Completer<void>();
    final loadCompleter = Completer<void>();
    try {
      final initialized = await AppAdService.instance.ensureInitialized();
      if (!initialized || !AppAdService.instance.canRequestAds) {
        _scheduleRetry();
        return;
      }
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _retryTimer?.cancel();
            _disposeCachedAd();
            _cachedAd = ad;
            if (!loadCompleter.isCompleted) {
              loadCompleter.complete();
            }
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              'Rewarded ad failed to load '
              '(code=${error.code}, domain=${error.domain}): ${error.message}',
            );
            _scheduleRetry();
            if (!loadCompleter.isCompleted) {
              loadCompleter.complete();
            }
          },
        ),
      );
      await loadCompleter.future;
    } catch (error, stackTrace) {
      debugPrint('Rewarded ad load threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleRetry();
    } finally {
      _isLoading = false;
      if (_loadingCompleter case final loadingCompleter?
          when !loadingCompleter.isCompleted) {
        loadingCompleter.complete();
      }
      _loadingCompleter = null;
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

  Duration get _loadTimeout {
    if (Platform.isIOS) {
      return const Duration(seconds: 10);
    }
    return const Duration(seconds: 2);
  }
}
