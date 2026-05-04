import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app_review_config.dart';

class RewardedAdManager {
  RewardedAdManager._internal();

  static final RewardedAdManager instance = RewardedAdManager._internal();
  static const Duration _loadTimeout = Duration(seconds: 2);
  static const Duration _retryDelay = Duration(seconds: 10);

  RewardedAd? _cachedAd;
  bool _isLoading = false;
  Timer? _retryTimer;

  String? get _adUnitId {
    if (Platform.isAndroid) {
      return AppReviewConfig.androidRewardedAdUnitId.isEmpty
          ? null
          : AppReviewConfig.androidRewardedAdUnitId;
    }
    if (Platform.isIOS) {
      return AppReviewConfig.iosRewardedAdUnitId.isEmpty
          ? null
          : AppReviewConfig.iosRewardedAdUnitId;
    }
    return null;
  }

  Future<void> warmUp() async {
    await _ensureLoaded();
  }

  Future<bool> showDoubleRewardAd() async {
    try {
      await _ensureLoaded().timeout(_loadTimeout);
    } on MissingPluginException {
      return false;
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
    ad.show(
      onUserEarnedReward: (_, __) {
        rewarded = true;
      },
    );
    return completer.future;
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
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      unawaited(warmUp());
    });
  }
}
