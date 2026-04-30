import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app_review_config.dart';
import '../../app_settings.dart';

class InterstitialAdManager {
  InterstitialAdManager._internal();

  static final InterstitialAdManager instance =
      InterstitialAdManager._internal();

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

  Future<void> showIfNeeded() async {
    if (AppSettings.instance.adsRemoved.value) {
      return;
    }
    final adUnitId = _adUnitId;
    if (adUnitId == null) {
      return;
    }

    final completer = Completer<void>();
    try {
      await InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                if (!completer.isCompleted) {
                  completer.complete();
                }
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                if (!completer.isCompleted) {
                  completer.complete();
                }
              },
            );
            ad.show();
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        ),
      );
    } on MissingPluginException {
      return;
    }

    await completer.future;
  }
}
