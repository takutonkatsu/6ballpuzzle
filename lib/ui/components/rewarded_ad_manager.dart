import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app_review_config.dart';

class RewardedAdManager {
  RewardedAdManager._internal();

  static final RewardedAdManager instance = RewardedAdManager._internal();

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

  Future<bool> showDoubleRewardAd() async {
    final adUnitId = _adUnitId;
    if (adUnitId == null) {
      return false;
    }

    final completer = Completer<bool>();
    try {
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            var rewarded = false;
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                if (!completer.isCompleted) {
                  completer.complete(rewarded);
                }
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                if (!completer.isCompleted) {
                  completer.complete(false);
                }
              },
            );
            ad.show(
              onUserEarnedReward: (_, __) {
                rewarded = true;
              },
            );
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          },
        ),
      );
    } on MissingPluginException {
      return false;
    }

    return completer.future;
  }
}
