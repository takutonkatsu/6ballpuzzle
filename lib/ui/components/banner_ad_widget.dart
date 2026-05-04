import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app_review_config.dart';
import '../../app_settings.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  static const Duration _retryDelay = Duration(seconds: 8);

  BannerAd? _bannerAd;
  bool _isLoaded = false;
  Timer? _retryTimer;

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
    _loadBannerAd();
  }

  void _handleAdsRemovedChanged() {
    if (AppSettings.instance.adsRemoved.value) {
      _retryTimer?.cancel();
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

  void _loadBannerAd() {
    if (AppSettings.instance.adsRemoved.value || _bannerAd != null) {
      return;
    }
    _retryTimer?.cancel();
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
          debugPrint(
            'Banner ad failed to load '
            '(code=${error.code}, domain=${error.domain}): ${error.message}',
          );
          ad.dispose();
          _bannerAd = null;
          _isLoaded = false;
          _scheduleRetry();
        },
      ),
    );

    try {
      ad.load();
    } on MissingPluginException {
      ad.dispose();
    }
  }

  void _scheduleRetry() {
    if (AppSettings.instance.adsRemoved.value) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (mounted) {
        _loadBannerAd();
      }
    });
  }

  @override
  void dispose() {
    AppSettings.instance.adsRemoved.removeListener(_handleAdsRemovedChanged);
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppSettings.instance.adsRemoved.value) {
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
