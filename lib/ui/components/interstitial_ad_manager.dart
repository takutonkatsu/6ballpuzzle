import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class InterstitialAdManager {
  InterstitialAdManager._internal();

  static final InterstitialAdManager instance =
      InterstitialAdManager._internal();

  String? get _adUnitId {
    if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/1033173712';
    }
    return null;
  }

  Future<void> showIfNeeded() async {
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
