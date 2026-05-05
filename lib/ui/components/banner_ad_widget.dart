import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../ads/app_ad_service.dart';
import '../../app_settings.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  static const Duration _retryDelay = Duration(seconds: 8);

  BannerAd? _bannerAd;
  bool _isLoading = false;
  bool _isLoaded = false;
  Timer? _retryTimer;

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
    if (!AppAdService.instance.canRequestAds ||
        _bannerAd != null ||
        _isLoading) {
      return;
    }
    _retryTimer?.cancel();
    final adUnitId = AppAdService.instance.bannerAdUnitId;
    if (adUnitId == null) {
      return;
    }
    _isLoading = true;

    unawaited(() async {
      final initialized = await AppAdService.instance.ensureInitialized();
      if (!mounted || !initialized || !AppAdService.instance.canRequestAds) {
        _isLoading = false;
        if (mounted) {
          _scheduleRetry();
        }
        return;
      }

      late final BannerAd ad;
      ad = BannerAd(
        adUnitId: adUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (loadedAd) {
            _isLoading = false;
            if (!mounted || !AppAdService.instance.canRequestAds) {
              loadedAd.dispose();
              return;
            }
            setState(() {
              _bannerAd = loadedAd as BannerAd;
              _isLoaded = true;
            });
          },
          onAdFailedToLoad: (failedAd, error) {
            _isLoading = false;
            debugPrint(
              'Banner ad failed to load '
              '(code=${error.code}, domain=${error.domain}): ${error.message}',
            );
            failedAd.dispose();
            _bannerAd = null;
            _isLoaded = false;
            _scheduleRetry();
          },
        ),
      );

      try {
        await ad.load();
      } catch (error, stackTrace) {
        _isLoading = false;
        debugPrint('Banner ad load threw: $error');
        debugPrintStack(stackTrace: stackTrace);
        ad.dispose();
        _scheduleRetry();
      }
    }());
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
