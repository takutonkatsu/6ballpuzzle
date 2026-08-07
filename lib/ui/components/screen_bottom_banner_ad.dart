import 'package:flutter/material.dart';

class ScreenBottomBannerAd extends StatelessWidget {
  const ScreenBottomBannerAd({
    super.key,
    this.reserveSpaceWhenHidden = false,
  });

  final bool reserveSpaceWhenHidden;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
