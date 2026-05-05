import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../ads/app_ad_service.dart';

class RewardedAdManager {
  RewardedAdManager._internal();

  static final RewardedAdManager instance = RewardedAdManager._internal();
  static const Duration _retryDelay = Duration(seconds: 10);

  RewardedAd? _cachedAd;
  bool _isLoading = false;
  Timer? _retryTimer;

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
      await _ensureLoaded().timeout(_loadTimeout);
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
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(rewarded);
        }
        unawaited(warmUp());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        unawaited(warmUp());
      },
    );
    try {
      ad.show(
        onUserEarnedReward: (_, __) {
          rewarded = true;
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Rewarded ad show threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      ad.dispose();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      unawaited(warmUp());
    }
    return completer.future;
  }

  Future<void> _ensureLoaded() async {
    if (_cachedAd != null || _isLoading) {
      while (_isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    if (!AppAdService.instance.canRequestAds) {
      return;
    }
    final adUnitId = AppAdService.instance.rewardedAdUnitId;
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
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _retryTimer?.cancel();
            _disposeCachedAd();
            _cachedAd = ad;
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              'Rewarded ad failed to load '
              '(code=${error.code}, domain=${error.domain}): ${error.message}',
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
      debugPrint('Rewarded ad load threw: $error');
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

  Duration get _loadTimeout {
    if (Platform.isIOS) {
      return const Duration(seconds: 10);
    }
    return const Duration(seconds: 2);
  }
}
