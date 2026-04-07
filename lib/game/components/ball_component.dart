import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../game_models.dart';

extension BallColorExtension on BallColor {
  Color get color {
    switch (this) {
      case BallColor.blue:   return const Color(0xFF4FC3F7);
      case BallColor.green:  return const Color(0xFF81C784);
      case BallColor.red:    return const Color(0xFFEF5350);
      case BallColor.yellow: return const Color(0xFFFFD54F);
      case BallColor.purple: return const Color(0xFFCE93D8);
    }
  }

  Color get darkColor {
    switch (this) {
      case BallColor.blue:   return const Color(0xFF0277BD);
      case BallColor.green:  return const Color(0xFF2E7D32);
      case BallColor.red:    return const Color(0xFFB71C1C);
      case BallColor.yellow: return const Color(0xFFF57F17);
      case BallColor.purple: return const Color(0xFF6A1B9A);
    }
  }

  Color get glowColor {
    switch (this) {
      case BallColor.blue:   return const Color(0xFF81D4FA);
      case BallColor.green:  return const Color(0xFFA5D6A7);
      case BallColor.red:    return const Color(0xFFEF9A9A);
      case BallColor.yellow: return const Color(0xFFFFE082);
      case BallColor.purple: return const Color(0xFFE1BEE7);
    }
  }
}

enum BallState { freeFall, rolling, locked }

class BallComponent extends PositionComponent {
  final double radius;
  final BallColor ballColor;
  final bool isGhost;

  BallState state = BallState.locked;
  Vector2 velocity = Vector2.zero();
  double hitOffsetX = 0.0;

  // 通常発光（定期パルス）
  double glowIntensity = 0.0;
  // ワザ演出フラッシュ（完全ホワイトアウト）
  double _flashIntensity = 0.0;
  // ワザ演出中の同色発光（枠リング）
  bool isWazaSameColor = false;

  bool _isPulsing = false;
  double _pulseTime = 0.0;

  Vector2? _snapTarget;
  double _snapProgress = 0.0;
  static const double snapSpeed = 5.0;

  BallComponent({
    required Vector2 position,
    required this.radius,
    required this.ballColor,
    this.isGhost = false,
  }) : super(position: position, anchor: Anchor.center, size: Vector2.all(radius * 2));

  /// ワザ演出のコアフラッシュ（白く塗りつぶされる）
  void flashGlow() {
    _flashIntensity = 1.0;
    glowIntensity = 0.0;
    _isPulsing = false;
  }

  /// 定期発光（パルス）
  void startPulse() {
    _isPulsing = true;
    _pulseTime = 0.0;
    glowIntensity = 0.0;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_isPulsing) {
      _pulseTime += dt;
      const pulseDuration = 1.2;
      if (_pulseTime >= pulseDuration) {
        _isPulsing = false;
        glowIntensity = 0.0;
      } else {
        glowIntensity = sin(pi * _pulseTime / pulseDuration);
      }
    } else if (glowIntensity > 0) {
      glowIntensity = max(0.0, glowIntensity - dt * 2.5);
    }

    if (_flashIntensity > 0) {
      _flashIntensity = max(0.0, _flashIntensity - dt * 3.0);
    }

    if (_snapTarget != null) {
      _snapProgress += dt * snapSpeed;
      if (_snapProgress >= 1.0) {
        position = _snapTarget!.clone();
        _snapTarget = null;
        state = BallState.locked;
      } else {
        position.lerp(_snapTarget!, _snapProgress);
      }
      return;
    }

    if (state != BallState.locked) {
      position += velocity * dt;
    }
  }

  void snapTo(Vector2 targetPos) {
    _snapTarget = targetPos;
    _snapProgress = 0.0;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final center = Offset(radius, radius);
    final alpha = isGhost ? 0.35 : 1.0;

    // ===== 通常グロー（外周リング） =====
    if ((glowIntensity > 0.01 || isGhost) && _flashIntensity < 0.9) {
      final glowAlpha = isGhost ? 0.12 : glowIntensity * 0.5;
      final glowPaint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = ballColor.glowColor.withValues(alpha: glowAlpha);
      canvas.drawCircle(center, radius * 1.3, glowPaint);
    }

    // ===== ワザ演出: 同色ボールの枠リング発光 =====
    if (isWazaSameColor && _flashIntensity < 0.5) {
      final rimPaint = Paint()
        ..color = ballColor.glowColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(center, radius + 2, rimPaint);

      final rimPaint2 = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(center, radius + 5, rimPaint2);
    }

    // ===== ボール本体（グラデーション、光沢・艶感） =====
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = RadialGradient(
      center: const Alignment(-0.25, -0.3),
      radius: 0.9,
      colors: [
        ballColor.color.withValues(alpha: alpha),
        ballColor.darkColor.withValues(alpha: alpha * 0.95),
        Colors.black.withValues(alpha: alpha * 0.3),
      ],
      stops: const [0.0, 0.7, 1.0],
    );
    final bodyPaint = Paint()..shader = gradient.createShader(rect);
    canvas.drawCircle(center, radius, bodyPaint);

    // ===== 高級感のある反射ハイライト =====
    if (!isGhost && _flashIntensity < 0.7) {
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      final highlightCenter = Offset(center.dx - radius * 0.35, center.dy - radius * 0.35);
      canvas.drawCircle(highlightCenter, radius * 0.3, highlightPaint);
    }

    // ===== 輪郭 =====
    final strokePaint = Paint()
      ..color = ballColor.darkColor.withValues(alpha: isGhost ? 0.3 : 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, strokePaint);

    // ===== 通常グロー発光リング =====
    if (glowIntensity > 0.3 && _flashIntensity < 0.5) {
      final ringPaint = Paint()
        ..color = ballColor.glowColor.withValues(alpha: (glowIntensity - 0.3) * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius + 1.5, ringPaint);
    }

    // ===== ワザフラッシュ: 完全ホワイトアウト =====
    if (_flashIntensity > 0.01) {
      // 外部ブルーム（大きなボーム光）
      final bloomPaint = Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 + _flashIntensity * 14)
        ..color = ballColor.glowColor.withValues(alpha: _flashIntensity * 0.9);
      canvas.drawCircle(center, radius * 2.8, bloomPaint);

      // 白ブルーム
      final whiteBoomPaint = Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + _flashIntensity * 8)
        ..color = Colors.white.withValues(alpha: _flashIntensity * 0.85);
      canvas.drawCircle(center, radius * 2.0, whiteBoomPaint);

      // ボール本体を白で完全に塗りつぶし
      final whiteoutPaint = Paint()
        ..color = Colors.white.withValues(alpha: _flashIntensity);
      canvas.drawCircle(center, radius, whiteoutPaint);

      // 外枠リング（発光リング2重）
      final ring1 = Paint()
        ..color = ballColor.color.withValues(alpha: _flashIntensity * 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _flashIntensity * 5.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(center, radius + 2, ring1);

      final ring2 = Paint()
        ..color = Colors.white.withValues(alpha: _flashIntensity * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _flashIntensity * 2.5;
      canvas.drawCircle(center, radius + 7 + _flashIntensity * 4, ring2);
    }
  }
}

/// Flutter UI用ボール描画ウィジェット（Nextボールなどに使用）
class MiniBallWidget extends StatelessWidget {
  final BallColor ballColor;
  final double size;

  const MiniBallWidget({super.key, required this.ballColor, required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MiniBallPainter(ballColor: ballColor),
    );
  }
}

class _MiniBallPainter extends CustomPainter {
  final BallColor ballColor;
  _MiniBallPainter({required this.ballColor});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final r = canvasSize.width / 2;
    final center = Offset(r, r);

    // グラデーション本体
    final rect = Rect.fromCircle(center: center, radius: r);
    final gradient = RadialGradient(
      center: const Alignment(-0.25, -0.3),
      radius: 0.9,
      colors: [ballColor.color, ballColor.darkColor, Colors.black.withValues(alpha: 0.3)],
      stops: const [0.0, 0.7, 1.0],
    );
    canvas.drawCircle(center, r, Paint()..shader = gradient.createShader(rect));

    // 反射ハイライト
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final highlightCenter = Offset(center.dx - r * 0.35, center.dy - r * 0.35);
    canvas.drawCircle(highlightCenter, r * 0.3, highlightPaint);

    // 輪郭
    canvas.drawCircle(center, r, Paint()
      ..color = ballColor.darkColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_MiniBallPainter old) => old.ballColor != ballColor;
}
