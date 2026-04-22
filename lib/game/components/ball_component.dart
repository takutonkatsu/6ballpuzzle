import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../game_models.dart';

extension BallColorExtension on BallColor {
  Color get color {
    switch (this) {
      case BallColor.blue:
        return const Color(0xFF4FC3F7);
      case BallColor.green:
        return const Color(0xFF81C784);
      case BallColor.red:
        return const Color(0xFFEF5350);
      case BallColor.yellow:
        return const Color(0xFFFF9800);
      case BallColor.purple:
        return const Color(0xFFCE93D8);
    }
  }

  Color get darkColor {
    switch (this) {
      case BallColor.blue:
        return const Color(0xFF0277BD);
      case BallColor.green:
        return const Color(0xFF2E7D32);
      case BallColor.red:
        return const Color(0xFFB71C1C);
      case BallColor.yellow:
        return const Color(0xFFE65100);
      case BallColor.purple:
        return const Color(0xFF6A1B9A);
    }
  }

  Color get glowColor {
    switch (this) {
      case BallColor.blue:
        return const Color(0xFF81D4FA);
      case BallColor.green:
        return const Color(0xFFA5D6A7);
      case BallColor.red:
        return const Color(0xFFEF9A9A);
      case BallColor.yellow:
        return const Color(0xFFFFCC80);
      case BallColor.purple:
        return const Color(0xFFE1BEE7);
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
  }) : super(
            position: position,
            anchor: Anchor.center,
            size: Vector2.all(radius * 2));

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

    if ((glowIntensity > 0.01 || isGhost) && _flashIntensity < 0.9) {
      final glowAlpha = isGhost ? 0.12 : glowIntensity * 0.5;
      final glowPaint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = ballColor.glowColor.withValues(alpha: glowAlpha);
      canvas.drawCircle(center, radius * 1.3, glowPaint);
    }

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

    drawCyberSphere(
      canvas,
      center,
      radius,
      ballColor,
      alpha: alpha,
    );

    if (glowIntensity > 0.3 && _flashIntensity < 0.5) {
      final ringPaint = Paint()
        ..color =
            ballColor.glowColor.withValues(alpha: (glowIntensity - 0.3) * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius + 1.5, ringPaint);
    }

    if (_flashIntensity > 0.01) {
      final bloomPaint = Paint()
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, 18 + _flashIntensity * 14)
        ..color = ballColor.glowColor.withValues(alpha: _flashIntensity * 0.9);
      canvas.drawCircle(center, radius * 2.8, bloomPaint);

      final whiteBoomPaint = Paint()
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, 10 + _flashIntensity * 8)
        ..color = Colors.white.withValues(alpha: _flashIntensity * 0.85);
      canvas.drawCircle(center, radius * 2.0, whiteBoomPaint);

      final whiteoutPaint = Paint()
        ..color = Colors.white.withValues(alpha: _flashIntensity);
      canvas.drawCircle(center, radius, whiteoutPaint);

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

class _SpherePalette {
  const _SpherePalette({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.rim,
  });

  final Color top;
  final Color mid;
  final Color bottom;
  final Color rim;
}

_SpherePalette _paletteFor(BallColor color) {
  switch (color) {
    case BallColor.purple:
      return const _SpherePalette(
        top: Color(0xFFFF4CFF),
        mid: Color(0xFFB91DFF),
        bottom: Color(0xFF2A075E),
        rim: Color(0xFFEAA7FF),
      );
    case BallColor.green:
      return const _SpherePalette(
        top: Color(0xFFB7FF3B),
        mid: Color(0xFF22E85A),
        bottom: Color(0xFF046B28),
        rim: Color(0xFFD8FF9A),
      );
    case BallColor.blue:
      return const _SpherePalette(
        top: Color(0xFF35F0FF),
        mid: Color(0xFF0877FF),
        bottom: Color(0xFF06105B),
        rim: Color(0xFFB9F8FF),
      );
    case BallColor.yellow:
      return const _SpherePalette(
        top: Color(0xFFFFF35A),
        mid: Color(0xFFFFA726),
        bottom: Color(0xFFE65100),
        rim: Color(0xFFFFF7A6),
      );
    case BallColor.red:
      return const _SpherePalette(
        top: Color(0xFFFF6B64),
        mid: Color(0xFFE02020),
        bottom: Color(0xFF65060C),
        rim: Color(0xFFFFA0A8),
      );
  }
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

void drawCyberSphere(
  Canvas canvas,
  Offset center,
  double radius,
  BallColor color, {
  double alpha = 1,
  bool compact = false,
}) {
  final palette = _paletteFor(color);
  final bodyRect = Rect.fromCircle(center: center, radius: radius);
  final blur = compact ? 4.0 : 8.0;

  canvas.drawCircle(
    center,
    radius * 1.22,
    Paint()
      ..color = palette.rim.withValues(alpha: 0.2 * alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
  );

  final basePaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _mix(palette.top, Colors.white, 0.3).withValues(alpha: alpha),
        palette.top.withValues(alpha: alpha),
        palette.mid.withValues(alpha: alpha),
        palette.bottom.withValues(alpha: alpha),
      ],
      stops: const [0.0, 0.28, 0.64, 1.0],
    ).createShader(bodyRect);
  canvas.drawCircle(center, radius, basePaint);

  canvas.save();
  canvas.clipPath(Path()..addOval(bodyRect));

  final edgeShade = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.25, -0.32),
      radius: 0.95,
      colors: [
        Colors.transparent,
        Colors.transparent,
        Colors.black.withValues(alpha: 0.42 * alpha),
      ],
      stops: const [0.0, 0.62, 1.0],
    ).createShader(bodyRect);
  canvas.drawCircle(center, radius, edgeShade);

  final emissionPaint = Paint()
    ..shader = RadialGradient(
      center: const Alignment(0.18, 0.18),
      radius: 0.95,
      colors: [
        palette.rim.withValues(alpha: 0.2 * alpha),
        Colors.transparent,
      ],
      stops: const [0.0, 0.78],
    ).createShader(bodyRect);
  canvas.drawCircle(center, radius * 0.94, emissionPaint);

  canvas.restore();

  _drawFresnelRim(canvas, center, radius, palette, alpha, compact);
  _drawSpecularHighlights(canvas, center, radius, alpha, compact);
}

void _drawFresnelRim(
  Canvas canvas,
  Offset center,
  double radius,
  _SpherePalette palette,
  double alpha,
  bool compact,
) {
  final rimRect = Rect.fromCircle(center: center, radius: radius);
  canvas.drawCircle(
    center,
    radius * 0.97,
    Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.72 * alpha),
          palette.rim.withValues(alpha: 0.16 * alpha),
          Colors.black.withValues(alpha: 0.18 * alpha),
          palette.rim.withValues(alpha: 0.54 * alpha),
          Colors.white.withValues(alpha: 0.72 * alpha),
        ],
        stops: const [0.0, 0.25, 0.56, 0.82, 1.0],
      ).createShader(rimRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, radius * (compact ? 0.08 : 0.1)),
  );
}

void _drawSpecularHighlights(
  Canvas canvas,
  Offset center,
  double radius,
  double alpha,
  bool compact,
) {
  canvas.save();
  canvas.translate(center.dx - radius * 0.34, center.dy - radius * 0.42);
  canvas.rotate(-0.5);
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset.zero,
      width: radius * 0.72,
      height: radius * 0.28,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.62 * alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, compact ? 0.7 : 1.4),
  );
  canvas.restore();

  canvas.drawCircle(
    Offset(center.dx + radius * 0.32, center.dy - radius * 0.33),
    radius * 0.13,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.78 * alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, compact ? 0.7 : 1.4),
  );
}

/// Flutter UI用ボール描画ウィジェット（Nextボールなどに使用）
class MiniBallWidget extends StatelessWidget {
  final BallColor ballColor;
  final double size;

  const MiniBallWidget(
      {super.key, required this.ballColor, required this.size});

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

    drawCyberSphere(
      canvas,
      center,
      r,
      ballColor,
      compact: true,
    );
  }

  @override
  bool shouldRepaint(_MiniBallPainter old) => old.ballColor != ballColor;
}
