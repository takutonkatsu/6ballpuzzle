import 'dart:math';

import 'package:flutter/material.dart';

import '../../audio/sfx.dart';
import '../../data/models/game_item.dart';
import '../../data/player_data_manager.dart';
import '../../game/gacha_manager.dart';

class GachaAnimationScreen extends StatefulWidget {
  final GachaRollResult result;

  const GachaAnimationScreen({
    super.key,
    required this.result,
  });

  @override
  State<GachaAnimationScreen> createState() => _GachaAnimationScreenState();
}

class _GachaAnimationScreenState extends State<GachaAnimationScreen>
    with TickerProviderStateMixin {
  static const String _waitingSfx = 'Scene_Change11-1(Up)_ガチャ待機.mp3';
  static const String _revealSfx = '決定ボタンを押す25_ガチャ排出.mp3';

  late AnimationController _mainController;
  late Animation<double> _chargeAnimation;
  late Animation<double> _revealScaleAnimation;
  bool _canDismiss = false;
  bool _playedRevealSfx = false;

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    _chargeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInExpo),
      ),
    );

    _revealScaleAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.7, 1.0, curve: Curves.elasticOut),
      ),
    );

    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) {
        return;
      }
      AppSfx.play(_waitingSfx, volume: 0.9);
    });
    _mainController.addListener(_playRevealSfxWhenReady);
    _mainController.forward().then((_) {
      if (mounted) {
        setState(() {
          _canDismiss = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _mainController.removeListener(_playRevealSfxWhenReady);
    _mainController.dispose();
    super.dispose();
  }

  void _playRevealSfxWhenReady() {
    if (_playedRevealSfx || _mainController.value < 0.7) {
      return;
    }
    _playedRevealSfx = true;
    AppSfx.play(_revealSfx, volume: 1.0);
  }

  Color _colorFor(GameItem item) {
    switch (item.rarity) {
      case ItemRarity.common:
        return Colors.cyanAccent;
      case ItemRarity.rare:
        return Colors.greenAccent;
      case ItemRarity.epic:
        return Colors.orangeAccent;
      case ItemRarity.legendary:
        return Colors.pinkAccent;
    }
  }

  String _grantResultMessage(ItemGrantResult grantResult) {
    final item = grantResult.item;
    if (!grantResult.isDuplicate) {
      return '${item.name}を獲得';
    }
    if (grantResult.leveledUp) {
      return 'Lv.${item.level}に強化';
    }
    return 'すでに所持済み';
  }

  String _rarityLabel(ItemRarity rarity) {
    switch (rarity) {
      case ItemRarity.common:
        return 'ノーマル';
      case ItemRarity.rare:
        return 'レア';
      case ItemRarity.epic:
        return 'エピック';
      case ItemRarity.legendary:
        return 'レジェンド';
    }
  }

  String _itemTypeLabel(GameItem item) {
    return switch (item.type) {
      ItemType.stamp => 'スタンプ',
      ItemType.skin => 'ボールスキン',
      ItemType.icon => 'プレイヤーアイコン',
      ItemType.vfx => 'エフェクト',
    };
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.result.grantResult.item;
    final accent = _colorFor(item);

    return GestureDetector(
      onTap: () {
        if (_canDismiss) {
          AppSfx.playUiTap();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: _mainController,
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // Grid background
                CustomPaint(
                  painter: _GridPainter(
                    progress: _chargeAnimation.value,
                    color: accent,
                  ),
                ),

                // Core charging
                if (_mainController.value < 0.65)
                  Center(
                    child: Transform.scale(
                      scale: 1.0 + _chargeAnimation.value * 2.0,
                      child: Transform.rotate(
                        angle: _chargeAnimation.value * pi * 4,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            border: Border.all(
                              color: accent.withValues(
                                  alpha: _chargeAnimation.value),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(
                                    alpha: _chargeAnimation.value),
                                blurRadius: 20 * _chargeAnimation.value,
                                spreadRadius: 5 * _chargeAnimation.value,
                              )
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 20,
                              height: 20,
                              color: accent.withValues(
                                  alpha: _chargeAnimation.value),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Decrypting Text
                if (_mainController.value < 0.6)
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        'カプセルを展開中...',
                        style: TextStyle(
                          color: accent.withValues(
                              alpha: 0.5 +
                                  0.5 * sin(_chargeAnimation.value * pi * 10)),
                          fontFamily: 'Courier',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),

                // Flash
                if (_mainController.value >= 0.6 && _mainController.value < 0.8)
                  Container(
                    color: Colors.white.withValues(
                        alpha: 1.0 - (_mainController.value - 0.6) * 5),
                  ),

                // Revealed Item
                if (_mainController.value >= 0.7)
                  Center(
                    child: Transform.scale(
                      scale: _revealScaleAnimation.value,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.72),
                                width: 1.3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.24),
                                  blurRadius: 14,
                                ),
                              ],
                            ),
                            child: Text(
                              _itemTypeLabel(item),
                              style: TextStyle(
                                color: accent,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Icon(
                            _iconForItem(item),
                            size: 100,
                            color: accent,
                            shadows: [
                              Shadow(
                                color: accent,
                                blurRadius: 30,
                              )
                            ],
                          ),
                          const SizedBox(height: 30),
                          Text(
                            item.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              shadows: [
                                Shadow(color: accent, blurRadius: 10),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _rarityLabel(item.rarity),
                            style: TextStyle(
                              color: accent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _grantResultMessage(widget.result.grantResult),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          if (_canDismiss) ...[
                            const SizedBox(height: 40),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 600),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: 0.4 + 0.6 * sin(value * pi),
                                  child: const Text(
                                    'TAP TO CONTINUE',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                );
                              },
                              onEnd: () {
                                // Just a simple loop effect by forcing rebuild if we wanted to
                                // but a repeating AnimationController would be better.
                                // For simplicity we let it be static or just fade in.
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  IconData _iconForItem(GameItem item) {
    switch (item.type) {
      case ItemType.skin:
        return Icons.palette;
      case ItemType.icon:
        return switch (item.iconName) {
          'bolt' => Icons.bolt,
          'star' => Icons.star,
          'gamepad' => Icons.sports_esports,
          _ => Icons.person,
        };
      case ItemType.vfx:
        return Icons.auto_awesome;
      case ItemType.stamp:
        return switch (item.iconName) {
          'handshake' => Icons.handshake,
          'water_drop' => Icons.water_drop,
          'local_fire_department' => Icons.local_fire_department,
          'thumb_up' => Icons.thumb_up,
          'coffee' => Icons.coffee,
          'visibility' => Icons.visibility,
          'memory' => Icons.memory,
          _ => Icons.chat_bubble,
        };
    }
  }
}

class _GridPainter extends CustomPainter {
  final double progress;
  final Color color;

  _GridPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.1 + 0.3 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const double radius = 24.0;
    final width = sqrt(3) * radius;
    const verticalStep = radius * 1.5;
    final drift = (progress * verticalStep * 2) % verticalStep;

    for (double y = -verticalStep * 2 + drift;
        y < size.height + verticalStep;
        y += verticalStep) {
      final row = ((y + verticalStep * 2 - drift) / verticalStep).round();
      final xOffset = row.isEven ? 0.0 : width / 2;
      for (double x = -width + xOffset; x < size.width + width; x += width) {
        canvas.drawPath(_hexPath(Offset(x, y), radius), paint);
      }
    }
  }

  Path _hexPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -pi / 2 + pi / 3 * i;
      final point = Offset(
        center.dx + cos(angle) * radius,
        center.dy + sin(angle) * radius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
