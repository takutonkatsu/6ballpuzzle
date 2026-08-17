import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../effect_skin.dart';

/// ボール消滅時の外枠リングエフェクト
class BallPopRingEffect extends PositionComponent {
  final Color ringColor;
  final String effectSkinId;
  double _radius;
  double _alpha;
  bool _done = false;

  BallPopRingEffect({
    required Vector2 position,
    required this.ringColor,
    this.effectSkinId = EffectSkinCatalog.defaultFormationId,
  })  : _radius = 10.0,
        _alpha = 0.85,
        super(position: position, anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    if (_done) return;
    _radius += 40.0 * dt;
    _alpha -= dt * 3.5;
    if (_alpha <= 0) {
      _done = true;
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (_done) return;
    final paint = Paint()
      ..color = ringColor.withValues(alpha: _alpha.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(Offset.zero, _radius, paint);
    if (effectSkinId != EffectSkinCatalog.defaultFormationId) {
      final accent = EffectSkinCatalog.byId(effectSkinId).color;
      final accentPaint = Paint()
        ..color = accent.withValues(alpha: (_alpha * 0.45).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(Offset.zero, _radius * 0.62, accentPaint);
    }
  }
}

/// ハードドロップ時の火花エフェクト
class SparkEffect extends PositionComponent {
  final Color sparkColor;
  final String effectSkinId;
  final List<_Spark> _sparks = [];
  final Random _rng = Random();
  bool _initialized = false;

  SparkEffect({
    required Vector2 position,
    required this.sparkColor,
    this.effectSkinId = EffectSkinCatalog.defaultFormationId,
  }) : super(position: position, anchor: Anchor.center);

  @override
  void onMount() {
    super.onMount();
    if (!_initialized) {
      _initialized = true;
      final boosted = effectSkinId != EffectSkinCatalog.defaultFormationId;
      final sparkCount = (boosted ? 12 : 8) + _rng.nextInt(boosted ? 7 : 5);
      for (int i = 0; i < sparkCount; i++) {
        final angle = _rng.nextDouble() * 2 * pi;
        final speed = (boosted ? 70.0 : 50.0) + _rng.nextDouble() * 90.0;
        final length = (boosted ? 6.0 : 4.0) + _rng.nextDouble() * 8.0;
        final lifetime = 0.25 + _rng.nextDouble() * (boosted ? 0.32 : 0.25);
        final baseColor = boosted
            ? Color.lerp(
                sparkColor,
                EffectSkinCatalog.byId(effectSkinId).color,
                0.55,
              )!
            : sparkColor;
        _sparks.add(_Spark(
          angle: angle,
          speed: speed,
          length: length,
          lifetime: lifetime,
          color: baseColor,
        ));
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (var spark in _sparks) {
      spark.update(dt);
    }
    if (_sparks.every((s) => s.isDone)) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    for (var spark in _sparks) {
      spark.render(canvas);
    }
  }
}

class FormationBurstEffect extends PositionComponent {
  FormationBurstEffect({
    required Vector2 position,
    required this.effectSkinId,
    required this.baseColor,
  }) : super(position: position, anchor: Anchor.center);

  final String effectSkinId;
  final Color baseColor;
  double _time = 0.0;
  static const double _duration = 0.52;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_time >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final progress = (_time / _duration).clamp(0.0, 1.0);
    final skin = EffectSkinCatalog.byId(effectSkinId);
    final color = Color.lerp(baseColor, skin.color, 0.65)!;
    final alpha = (1.0 - progress).clamp(0.0, 1.0);
    final radius = 18.0 + 62.0 * progress;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * (1.0 - progress) + 0.8
      ..color = color.withValues(alpha: alpha * 0.72);
    canvas.drawCircle(Offset.zero, radius, ringPaint);

    final rayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * (1.0 - progress) + 0.6
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: alpha * 0.86);
    final rayCount = effectSkinId == 'effect_formation_emerald' ? 7 : 6;
    final spin = effectSkinId == 'effect_formation_arc' ? progress * pi : 0.0;
    for (var i = 0; i < rayCount; i++) {
      final angle = spin + (2 * pi / rayCount) * i;
      final inner = radius * 0.42;
      final outer =
          radius * (effectSkinId == 'effect_formation_burst' ? 1.12 : 0.92);
      canvas.drawLine(
        Offset(cos(angle) * inner, sin(angle) * inner),
        Offset(cos(angle) * outer, sin(angle) * outer),
        rayPaint,
      );
    }

    if (effectSkinId == 'effect_formation_arc') {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: alpha * 0.55);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius * 0.72),
        progress * pi * 2,
        pi * 0.72,
        false,
        arcPaint,
      );
    }
  }
}

class _Spark {
  final double angle;
  final double speed;
  final double length;
  final double lifetime;
  final Color color;

  double _time = 0.0;
  bool isDone = false;

  double _x = 0.0;
  double _y = 0.0;

  _Spark({
    required this.angle,
    required this.speed,
    required this.length,
    required this.lifetime,
    required this.color,
  });

  void update(double dt) {
    _time += dt;
    if (_time >= lifetime) {
      isDone = true;
      return;
    }
    _x += cos(angle) * speed * dt;
    _y += sin(angle) * speed * dt;
    _y += 60.0 * dt * dt; // 重力による下方向への曲がり
  }

  void render(Canvas canvas) {
    if (isDone) return;
    final progress = _time / lifetime;
    final alpha = (1.0 - progress).clamp(0.0, 1.0);
    final tailLen = length * (1.0 - progress * 0.5);

    final paint = Paint()
      ..color = Color.lerp(Colors.white, color, progress)!
          .withValues(alpha: alpha * 0.9)
      ..strokeWidth = max(0.5, 2.0 * (1.0 - progress))
      ..strokeCap = StrokeCap.round;

    final tailX = _x - cos(angle) * tailLen;
    final tailY = _y - sin(angle) * tailLen;
    canvas.drawLine(Offset(_x, _y), Offset(tailX, tailY), paint);
  }
}
