import 'package:flutter/material.dart';

const String defaultPlayerIconAsset =
    'assets/images/PlayerIcons/icon_default.png';

String? playerIconAssetPath(String? iconId) {
  final normalized = (iconId ?? '').trim();
  return switch (normalized) {
    '' || 'default' => defaultPlayerIconAsset,
    'icon_bolt' => 'assets/images/PlayerIcons/icon_bolt.png',
    'icon_star' => 'assets/images/PlayerIcons/icon_star.png',
    'icon_gamepad' => 'assets/images/PlayerIcons/icon_gamepad.png',
    'icon_sword' => 'assets/images/PlayerIcons/icon_sword.png',
    'icon_shield' => 'assets/images/PlayerIcons/icon_shield.png',
    'icon_crown' => 'assets/images/PlayerIcons/icon_crown.png',
    'icon_trophy' => 'assets/images/PlayerIcons/icon_trophy.png',
    'icon_medal' => 'assets/images/PlayerIcons/icon_medal.png',
    'icon_hexagon' => 'assets/images/PlayerIcons/icon_hexagon.png',
    'icon_hexagon2' => 'assets/images/PlayerIcons/icon_hexagon2.png',
    'icon_diamond' => 'assets/images/PlayerIcons/icon_diamond.png',
    'icon_fire' => 'assets/images/PlayerIcons/icon_fire.png',
    'icon_water' => 'assets/images/PlayerIcons/icon_water.png',
    'icon_moon' => 'assets/images/PlayerIcons/icon_moon.png',
    'icon_rocket' => 'assets/images/PlayerIcons/icon_rocket.png',
    'icon_terminal' => 'assets/images/PlayerIcons/icon_terminal.png',
    'icon_smile' => 'assets/images/PlayerIcons/icon_smile.png',
    'icon_ribbon' => 'assets/images/PlayerIcons/icon_ribbon.png',
    'icon_heart' => 'assets/images/PlayerIcons/icon_heart.png',
    'icon_music' => 'assets/images/PlayerIcons/icon_music.png',
    'icon_cafe' => 'assets/images/PlayerIcons/icon_cafe.png',
    'icon_flower' => 'assets/images/PlayerIcons/icon_flower.png',
    'icon_bell' => 'assets/images/PlayerIcons/icon_bell.png',
    'icon_visibility' => 'assets/images/PlayerIcons/icon_visibility.png',
    _ => null,
  };
}

double playerIconImageScale(String? iconId) {
  final normalized = (iconId ?? '').trim();
  return switch (normalized) {
    'icon_hexagon2' => 1.08,
    'icon_bolt' ||
    'icon_star' ||
    'icon_gamepad' ||
    'icon_sword' ||
    'icon_shield' ||
    'icon_crown' ||
    'icon_trophy' ||
    'icon_medal' ||
    'icon_hexagon' ||
    'icon_diamond' ||
    'icon_fire' ||
    'icon_water' ||
    'icon_moon' ||
    'icon_rocket' ||
    'icon_terminal' ||
    'icon_smile' ||
    'icon_ribbon' ||
    'icon_heart' ||
    'icon_music' ||
    'icon_cafe' ||
    'icon_flower' ||
    'icon_bell' ||
    'icon_visibility' =>
      0.96,
    _ => 0.84,
  };
}

Color playerIconInnerBackgroundColor(
  String? iconId,
  Color fallback, {
  String? frameId,
}) {
  return fallback;
}

class PlayerIconImage extends StatelessWidget {
  const PlayerIconImage({
    super.key,
    required this.iconId,
    required this.fallbackIcon,
    required this.size,
    this.color = Colors.white,
  });

  final String? iconId;
  final IconData fallbackIcon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final assetPath = playerIconAssetPath(iconId);
    if (assetPath == null) {
      return Icon(fallbackIcon, color: color, size: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Image.asset(
          assetPath,
          width: size * playerIconImageScale(iconId),
          height: size * playerIconImageScale(iconId),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(fallbackIcon, color: color, size: size);
          },
        ),
      ),
    );
  }
}
