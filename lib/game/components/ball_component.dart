import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final bool isGuideGhost;
  final String ballSkinId;

  BallState state = BallState.locked;
  Vector2 velocity = Vector2.zero();
  double hitOffsetX = 0.0;

  // 通常発光（定期パルス）
  double glowIntensity = 0.0;
  // フォーメーション演出フラッシュ（完全ホワイトアウト）
  double _flashIntensity = 0.0;
  // フォーメーション演出中の同色発光（枠リング）
  bool isWazaSameColor = false;

  bool _isPulsing = false;
  double _pulseTime = 0.0;
  double _skinEffectTime = 0.0;

  Vector2? _snapTarget;
  double _snapProgress = 0.0;
  static const double snapSpeed = 5.0;

  BallComponent({
    required Vector2 position,
    required this.radius,
    required this.ballColor,
    this.isGhost = false,
    this.isGuideGhost = false,
    this.ballSkinId = 'default',
  }) : super(
          position: position,
          anchor: Anchor.center,
          size: Vector2.all(radius * 2),
        ) {
    _warmUpBallSkinImage(ballSkinId, ballColor);
  }

  /// フォーメーション演出のコアフラッシュ（白く塗りつぶされる）
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
    if (_isAnimatedBallSkin(ballSkinId)) {
      _skinEffectTime = (_skinEffectTime + dt) % 1000;
    }

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

  void clearSnapTarget() {
    _snapTarget = null;
    _snapProgress = 0.0;
  }

  void lockTo(Vector2 targetPos) {
    clearSnapTarget();
    velocity = Vector2.zero();
    state = BallState.locked;
    position = targetPos.clone();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final center = Offset(radius, radius);
    final alpha = isGuideGhost
        ? 0.26
        : isGhost
            ? 0.35
            : 1.0;

    if ((glowIntensity > 0.01 || isGhost) && _flashIntensity < 0.9) {
      final glowAlpha = isGuideGhost
          ? 0.12
          : isGhost
              ? 0.12
              : glowIntensity * 0.5;
      final glowPaint = Paint()
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          isGuideGhost ? 10 : 5,
        )
        ..color = (isGuideGhost ? const Color(0xFF66F7FF) : ballColor.glowColor)
            .withValues(alpha: glowAlpha);
      canvas.drawCircle(
          center, radius * (isGuideGhost ? 1.45 : 1.3), glowPaint);
    }

    if (ballSkinId == 'skin_luxury_prism' && _flashIntensity < 0.9) {
      _drawPrismBoardAura(
        canvas,
        center,
        radius,
        ballColor,
        alpha,
        _skinEffectTime,
      );
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

    final imageDrawn = _drawBallSkinImage(
      canvas,
      center,
      radius,
      ballColor,
      ballSkinId,
      alpha: alpha,
      showOuterGlow: true,
    );
    if (!imageDrawn) {
      drawCyberSphere(
        canvas,
        center,
        radius,
        ballColor,
        alpha: alpha,
        skinId: ballSkinId,
        effectTime: _skinEffectTime,
      );
    }

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

      if (ballSkinId == 'skin_luxury_prism') {
        _drawPrismFormationBurst(
          canvas,
          center,
          radius,
          ballColor,
          alpha,
          _flashIntensity,
          _skinEffectTime,
        );
      }
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
  bool showOuterGlow = true,
  String skinId = 'default',
  double effectTime = 0,
}) {
  final palette = _paletteFor(color);
  final bodyRect = Rect.fromCircle(center: center, radius: radius);
  final blur = compact ? 4.0 : 8.0;

  if (showOuterGlow) {
    canvas.drawCircle(
      center,
      radius * 1.22,
      Paint()
        ..color = palette.rim.withValues(alpha: 0.2 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

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
  if (skinId == 'skin_luxury_prism') {
    _drawPrismSkinDetails(
      canvas,
      center,
      radius,
      palette,
      alpha,
      compact,
      effectTime,
    );
  } else if (skinId.startsWith('skin_hexa_orbit_')) {
    _drawHexaOrbitSkinDetails(
      canvas,
      center,
      radius,
      _hexaOrbitAccentFor(skinId, palette),
      alpha,
      compact,
      effectTime,
    );
  }
}

bool _isAnimatedBallSkin(String skinId) =>
    skinId == 'skin_luxury_prism' || skinId.startsWith('skin_hexa_orbit_');

const Set<String> _imageBallSkinIds = {
  'skin_orbit',
  'skin_arcade',
  'skin_hexacore',
  'skin_element',
  'skin_cosmic',
};

final Map<String, ui.Image> _ballSkinImageCache = {};
final Set<String> _ballSkinImageLoading = {};

String _normalizedBallSkinId(String skinId) {
  if (skinId.startsWith('skin_hexa_orbit_')) {
    return 'skin_orbit';
  }
  return skinId;
}

String _ballColorAssetSuffix(BallColor color) => switch (color) {
      BallColor.blue => 'blue',
      BallColor.green => 'green',
      BallColor.red => 'red',
      BallColor.yellow => 'yellow',
      BallColor.purple => 'purple',
    };

String? _ballSkinAssetPath(String skinId, BallColor color) {
  final normalized = _normalizedBallSkinId(skinId);
  final suffix = _ballColorAssetSuffix(color);
  final prefix = switch (normalized) {
    'skin_orbit' => 'ball_skin_hexa_orbit',
    'skin_arcade' => 'ball_skin_arcade',
    'skin_hexacore' => 'ball_hexacore',
    'skin_element' => 'ball_element',
    'skin_cosmic' => 'ball_cosmic',
    _ => null,
  };
  if (prefix == null) {
    return null;
  }
  return 'assets/images/BallSkins/${prefix}_$suffix.png';
}

void _warmUpBallSkinImage(String skinId, BallColor color) {
  final assetPath = _ballSkinAssetPath(skinId, color);
  if (assetPath == null ||
      _ballSkinImageCache.containsKey(assetPath) ||
      _ballSkinImageLoading.contains(assetPath)) {
    return;
  }
  _ballSkinImageLoading.add(assetPath);
  unawaited(() async {
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _ballSkinImageCache[assetPath] = frame.image;
    } catch (_) {
      // 画像読み込みに失敗した場合は標準描画へフォールバックする。
    } finally {
      _ballSkinImageLoading.remove(assetPath);
    }
  }());
}

bool _drawBallSkinImage(
  Canvas canvas,
  Offset center,
  double radius,
  BallColor color,
  String skinId, {
  double alpha = 1,
  bool showOuterGlow = true,
}) {
  final normalized = _normalizedBallSkinId(skinId);
  if (!_imageBallSkinIds.contains(normalized)) {
    return false;
  }
  final assetPath = _ballSkinAssetPath(normalized, color);
  if (assetPath == null) {
    return false;
  }
  final image = _ballSkinImageCache[assetPath];
  if (image == null) {
    _warmUpBallSkinImage(normalized, color);
    return false;
  }
  if (showOuterGlow) {
    canvas.drawCircle(
      center,
      radius * 1.22,
      Paint()
        ..color = color.glowColor.withValues(alpha: 0.22 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      center.translate(-radius * 0.24, -radius * 0.28),
      radius * 0.54,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }
  final src = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  final dst = Rect.fromCircle(center: center, radius: radius * 1.18);
  canvas.drawImageRect(
    image,
    src,
    dst,
    Paint()
      ..filterQuality = FilterQuality.high
      ..color = Colors.white.withValues(alpha: alpha),
  );
  return true;
}

Color _hexaOrbitAccentFor(String skinId, _SpherePalette palette) {
  if (skinId.endsWith('_red')) {
    return const Color(0xFFFF4C55);
  }
  if (skinId.endsWith('_blue')) {
    return const Color(0xFF38D8FF);
  }
  if (skinId.endsWith('_green')) {
    return const Color(0xFF42FF9A);
  }
  if (skinId.endsWith('_purple')) {
    return const Color(0xFFD85BFF);
  }
  if (skinId.endsWith('_yellow')) {
    return const Color(0xFFFFE24A);
  }
  return palette.rim;
}

void _drawHexaOrbitSkinDetails(
  Canvas canvas,
  Offset center,
  double radius,
  Color accent,
  double alpha,
  bool compact,
  double effectTime,
) {
  final orbitPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = max(1.0, radius * (compact ? 0.065 : 0.08))
    ..color = accent.withValues(alpha: 0.90 * alpha);
  final glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.4, radius * 0.12)
    ..color = accent.withValues(alpha: 0.24 * alpha)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

  final orbitRect = Rect.fromCircle(center: center, radius: radius * 0.88);
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(compact ? -0.28 : effectTime * 1.1 - 0.35);
  canvas.translate(-center.dx, -center.dy);
  canvas.drawOval(
    Rect.fromCenter(
      center: center,
      width: orbitRect.width * 1.10,
      height: orbitRect.height * 0.48,
    ),
    glowPaint,
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: center,
      width: orbitRect.width * 1.10,
      height: orbitRect.height * 0.48,
    ),
    orbitPaint,
  );
  canvas.restore();

  final hexPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, radius * (compact ? 0.045 : 0.055))
    ..color = Colors.white.withValues(alpha: 0.48 * alpha);
  final hexPath = Path();
  for (var i = 0; i < 6; i++) {
    final angle = -pi / 2 + i * pi / 3;
    final point = Offset(
      center.dx + cos(angle) * radius * 0.54,
      center.dy + sin(angle) * radius * 0.54,
    );
    if (i == 0) {
      hexPath.moveTo(point.dx, point.dy);
    } else {
      hexPath.lineTo(point.dx, point.dy);
    }
  }
  hexPath.close();
  canvas.drawPath(hexPath, hexPaint);

  final corePaint = Paint()
    ..color = accent.withValues(alpha: 0.80 * alpha)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
  canvas.drawCircle(center, radius * 0.12, corePaint);
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

void _drawPrismBoardAura(
  Canvas canvas,
  Offset center,
  double radius,
  BallColor color,
  double alpha,
  double effectTime,
) {
  final pulse = (sin(effectTime * 3.2) + 1) * 0.5;
  final sweepAngle = effectTime * 1.8;
  final auraRect = Rect.fromCircle(center: center, radius: radius * 1.55);
  canvas.drawCircle(
    center,
    radius * (1.34 + pulse * 0.08),
    Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle,
        endAngle: sweepAngle + pi * 2,
        colors: [
          color.glowColor.withValues(alpha: 0.00),
          const Color(0xFF35F0FF).withValues(alpha: 0.22 * alpha),
          const Color(0xFFFF4DFF).withValues(alpha: 0.16 * alpha),
          const Color(0xFFFFF35A).withValues(alpha: 0.20 * alpha),
          color.glowColor.withValues(alpha: 0.00),
        ],
      ).createShader(auraRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2.4, radius * 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
  );
}

void _drawPrismSkinDetails(
  Canvas canvas,
  Offset center,
  double radius,
  _SpherePalette palette,
  double alpha,
  bool compact,
  double effectTime,
) {
  final ringRect = Rect.fromCircle(center: center, radius: radius * 1.04);
  final sweepOffset = effectTime * (compact ? 0.0 : 1.7);
  canvas.drawCircle(
    center,
    radius * 1.01,
    Paint()
      ..shader = SweepGradient(
        startAngle: sweepOffset,
        endAngle: sweepOffset + pi * 2,
        colors: [
          palette.rim.withValues(alpha: 0.86 * alpha),
          const Color(0xFF35F0FF).withValues(alpha: 0.90 * alpha),
          const Color(0xFFFF4DFF).withValues(alpha: 0.86 * alpha),
          const Color(0xFFFFF35A).withValues(alpha: 0.92 * alpha),
          palette.rim.withValues(alpha: 0.86 * alpha),
        ],
      ).createShader(ringRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, radius * (compact ? 0.08 : 0.105)),
  );

  final innerRect = Rect.fromCircle(center: center, radius: radius * 0.74);
  canvas.drawCircle(
    center,
    radius * 0.72,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.30, -0.40),
        radius: 0.95,
        colors: [
          Colors.white.withValues(alpha: 0.20 * alpha),
          const Color(0xFF35F0FF).withValues(alpha: 0.12 * alpha),
          Colors.transparent,
        ],
        stops: const [0.0, 0.36, 1.0],
      ).createShader(innerRect),
  );

  final streakPaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.54 * alpha),
        const Color(0xFF35F0FF).withValues(alpha: 0.10 * alpha),
        Colors.transparent,
      ],
    ).createShader(Rect.fromCircle(center: center, radius: radius))
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(0.8, radius * (compact ? 0.035 : 0.045))
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
    Offset(center.dx - radius * 0.48, center.dy - radius * 0.12),
    Offset(center.dx + radius * 0.38, center.dy - radius * 0.52),
    streakPaint,
  );
  canvas.drawLine(
    Offset(center.dx - radius * 0.16, center.dy + radius * 0.40),
    Offset(center.dx + radius * 0.56, center.dy + radius * 0.04),
    streakPaint,
  );

  _drawPrismSparkle(
    canvas,
    Offset(center.dx + radius * 0.42, center.dy - radius * 0.36),
    radius * (compact ? 0.13 : 0.17),
    alpha,
  );
  _drawPrismSparkle(
    canvas,
    Offset(center.dx - radius * 0.42, center.dy + radius * 0.28),
    radius * (compact ? 0.09 : 0.12),
    alpha * 0.72,
  );
}

void _drawPrismFormationBurst(
  Canvas canvas,
  Offset center,
  double radius,
  BallColor color,
  double alpha,
  double flashIntensity,
  double effectTime,
) {
  final burstAlpha = (flashIntensity * alpha).clamp(0.0, 1.0).toDouble();
  final sweepRect = Rect.fromCircle(center: center, radius: radius * 2.35);
  final sweep = effectTime * 5.5;
  final prismColors = [
    const Color(0xFF35F0FF).withValues(alpha: 0.92 * burstAlpha),
    const Color(0xFFFF4DFF).withValues(alpha: 0.86 * burstAlpha),
    const Color(0xFFFFF35A).withValues(alpha: 0.90 * burstAlpha),
    const Color(0xFF52FF86).withValues(alpha: 0.82 * burstAlpha),
    const Color(0xFF35F0FF).withValues(alpha: 0.92 * burstAlpha),
  ];

  for (var i = 0; i < 3; i++) {
    canvas.drawCircle(
      center,
      radius * (1.42 + i * 0.34 + flashIntensity * 0.62),
      Paint()
        ..shader = SweepGradient(
          startAngle: sweep + i * pi * 0.35,
          endAngle: sweep + i * pi * 0.35 + pi * 2,
          colors: prismColors,
        ).createShader(sweepRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.2, radius * (0.18 - i * 0.035))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
  }

  final particlePaint = Paint()..style = PaintingStyle.fill;
  for (var i = 0; i < 14; i++) {
    final angle = sweep * 0.48 + i * pi / 7;
    final distance =
        radius * (1.45 + (i.isEven ? 0.36 : 0.78) * flashIntensity);
    final particleCenter = Offset(
      center.dx + cos(angle) * distance,
      center.dy + sin(angle) * distance,
    );
    final size = radius * (0.08 + (i.isEven ? 0.07 : 0.02));
    particlePaint.color = prismColors[i % (prismColors.length - 1)];
    _drawPrismDiamond(canvas, particleCenter, size, particlePaint);
  }

  canvas.drawCircle(
    center,
    radius * (1.15 + flashIntensity * 0.20),
    Paint()
      ..color = color.glowColor.withValues(alpha: 0.38 * burstAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.4, radius * 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
  canvas.drawCircle(
    center,
    radius * (0.76 + flashIntensity * 0.18),
    Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.52 * burstAlpha),
          const Color(0xFFFFF35A).withValues(alpha: 0.20 * burstAlpha),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.2)),
  );
}

void _drawPrismSparkle(
    Canvas canvas, Offset center, double size, double alpha) {
  _drawPrismDiamond(
    canvas,
    center,
    size,
    Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.92 * alpha),
          const Color(0xFF35F0FF).withValues(alpha: 0.55 * alpha),
          const Color(0xFFFF4DFF).withValues(alpha: 0.10 * alpha),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size * 1.2))
      ..style = PaintingStyle.fill,
  );
  canvas.drawCircle(
    center,
    size * 0.28,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.60 * alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
  );
}

void _drawPrismDiamond(
  Canvas canvas,
  Offset center,
  double size,
  Paint paint,
) {
  final path = Path()
    ..moveTo(center.dx, center.dy - size)
    ..lineTo(center.dx + size * 0.42, center.dy)
    ..lineTo(center.dx, center.dy + size)
    ..lineTo(center.dx - size * 0.42, center.dy)
    ..close();
  canvas.drawPath(path, paint);
}

/// Flutter UI用ボール描画ウィジェット（Nextボールなどに使用）
class MiniBallWidget extends StatelessWidget {
  final BallColor ballColor;
  final double size;
  final bool showOuterGlow;
  final String ballSkinId;

  const MiniBallWidget(
      {super.key,
      required this.ballColor,
      required this.size,
      this.showOuterGlow = true,
      this.ballSkinId = 'default'});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MiniBallPainter(
        ballColor: ballColor,
        showOuterGlow: showOuterGlow,
        ballSkinId: ballSkinId,
      ),
    );
  }
}

class _MiniBallPainter extends CustomPainter {
  final BallColor ballColor;
  final bool showOuterGlow;
  final String ballSkinId;
  _MiniBallPainter({
    required this.ballColor,
    required this.showOuterGlow,
    required this.ballSkinId,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final r = canvasSize.width / 2;
    final center = Offset(r, r);

    final imageDrawn = _drawBallSkinImage(
      canvas,
      center,
      r,
      ballColor,
      ballSkinId,
      showOuterGlow: showOuterGlow,
    );
    if (!imageDrawn) {
      drawCyberSphere(
        canvas,
        center,
        r,
        ballColor,
        compact: true,
        showOuterGlow: showOuterGlow,
        skinId: ballSkinId,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniBallPainter old) =>
      old.ballColor != ballColor ||
      old.showOuterGlow != showOuterGlow ||
      old.ballSkinId != ballSkinId;
}
