import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_settings.dart';
import 'ad_removal_purchase_launcher.dart';
import 'banner_ad_widget.dart';

class ScreenBottomBannerAd extends StatefulWidget {
  const ScreenBottomBannerAd({
    super.key,
    this.reserveSpaceWhenHidden = false,
  });

  static const double contentHeight = 76;
  static const double _bannerWidth = 320;
  static const double _bannerHeight = 50;
  static const double _removeButtonWidth = 54;
  static const double _removeButtonHeight = 24;

  final bool reserveSpaceWhenHidden;

  @override
  State<ScreenBottomBannerAd> createState() => _ScreenBottomBannerAdState();
}

class _ScreenBottomBannerAdState extends State<ScreenBottomBannerAd> {
  Timer? _skipRefreshTimer;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.interstitialSkipUntil.addListener(
      _handleSkipUntilChanged,
    );
    _syncSkipRefreshTimer();
  }

  @override
  void dispose() {
    AppSettings.instance.interstitialSkipUntil.removeListener(
      _handleSkipUntilChanged,
    );
    _skipRefreshTimer?.cancel();
    super.dispose();
  }

  void _handleSkipUntilChanged() {
    _syncSkipRefreshTimer();
    if (mounted) {
      setState(() {});
    }
  }

  void _syncSkipRefreshTimer() {
    final active = AppSettings.instance.isInterstitialSkipActive;
    if (!active) {
      _skipRefreshTimer?.cancel();
      _skipRefreshTimer = null;
      return;
    }
    _skipRefreshTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (!AppSettings.instance.isInterstitialSkipActive) {
        _syncSkipRefreshTimer();
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.instance.adsRemoved,
      builder: (context, adsRemoved, child) {
        final hidden =
            adsRemoved || AppSettings.instance.isInterstitialSkipActive;
        if (hidden) {
          return widget.reserveSpaceWhenHidden
              ? const SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: ScreenBottomBannerAd.contentHeight,
                  ),
                )
              : const SizedBox.shrink();
        }
        return SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: ScreenBottomBannerAd.contentHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final adSideInset = ((constraints.maxWidth -
                            ScreenBottomBannerAd._bannerWidth) /
                        2)
                    .clamp(0, 9999);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      right: adSideInset + 8,
                      child: _RemoveAdsButton(
                        onTap: () => unawaited(
                          AdRemovalPurchaseLauncher.startFromBanner(context),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: ScreenBottomBannerAd._bannerHeight,
                      child: Center(child: BannerAdWidget()),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _RemoveAdsButton extends StatelessWidget {
  const _RemoveAdsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: '広告削除',
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: Container(
            width: ScreenBottomBannerAd._removeButtonWidth,
            height: ScreenBottomBannerAd._removeButtonHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFF334F).withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.88),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 5,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '×',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 0.9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(width: 3),
                Text(
                  'AD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
