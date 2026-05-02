import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app_review_config.dart';
import '../../app_settings.dart';
import 'interstitial_ad_manager.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  static String? get _adUnitId {
    if (Platform.isAndroid) {
      return AppReviewConfig.androidBannerAdUnitId.isEmpty
          ? null
          : AppReviewConfig.androidBannerAdUnitId;
    }
    if (Platform.isIOS) {
      return AppReviewConfig.iosBannerAdUnitId.isEmpty
          ? null
          : AppReviewConfig.iosBannerAdUnitId;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    AppSettings.instance.adsRemoved.addListener(_handleAdsRemovedChanged);
    InterstitialAdManager.instance.isCoolingDown.addListener(
      _handleInterstitialCooldownChanged,
    );
    _loadBannerAd();
  }

  void _handleAdsRemovedChanged() {
    if (AppSettings.instance.adsRemoved.value) {
      _bannerAd?.dispose();
      _bannerAd = null;
      if (mounted) {
        setState(() {
          _isLoaded = false;
        });
      }
    } else {
      _loadBannerAd();
    }
  }

  void _handleInterstitialCooldownChanged() {
    if (InterstitialAdManager.instance.isCoolingDown.value) {
      _bannerAd?.dispose();
      _bannerAd = null;
      if (mounted) {
        setState(() {
          _isLoaded = false;
        });
      }
      return;
    }
    _loadBannerAd();
  }

  void _loadBannerAd() {
    if (AppSettings.instance.adsRemoved.value ||
        InterstitialAdManager.instance.isCoolingDown.value ||
        _bannerAd != null) {
      return;
    }
    final adUnitId = _adUnitId;
    if (adUnitId == null) {
      return;
    }

    final ad = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );

    try {
      ad.load();
    } on MissingPluginException {
      ad.dispose();
    }
  }

  @override
  void dispose() {
    AppSettings.instance.adsRemoved.removeListener(_handleAdsRemovedChanged);
    InterstitialAdManager.instance.isCoolingDown.removeListener(
      _handleInterstitialCooldownChanged,
    );
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppSettings.instance.adsRemoved.value) {
      return const SizedBox.shrink();
    }
    if (InterstitialAdManager.instance.isCoolingDown.value) {
      return const SizedBox.shrink();
    }
    final ad = _bannerAd;
    if (!_isLoaded || ad == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
