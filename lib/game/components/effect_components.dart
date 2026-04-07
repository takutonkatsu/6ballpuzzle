import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// ボール消滅時の外枠リングエフェクト
class BallPopRingEffect extends PositionComponent {
  final Color ringColor;
  double _radius;
  double _alpha;
  bool _done = false;

  BallPopRingEffect({
    required Vector2 position,
    required this.ringColor,
  }) : _radius = 10.0, _alpha = 0.85,
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
  }
}

/// ハードドロップ時の火花エフェクト
class SparkEffect extends PositionComponent {
  final Color sparkColor;
  final List<_Spark> _sparks = [];
  final Random _rng = Random();
  bool _initialized = false;

  SparkEffect({
    required Vector2 position,
    required this.sparkColor,
  }) : super(position: position, anchor: Anchor.center);

  @override
  void onMount() {
    super.onMount();
    if (!_initialized) {
      _initialized = true;
      final sparkCount = 8 + _rng.nextInt(5);
      for (int i = 0; i < sparkCount; i++) {
        final angle = _rng.nextDouble() * 2 * pi;
        final speed = 50.0 + _rng.nextDouble() * 90.0;
        final length = 4.0 + _rng.nextDouble() * 7.0;
        final lifetime = 0.25 + _rng.nextDouble() * 0.25;
        _sparks.add(_Spark(
          angle: angle,
          speed: speed,
          length: length,
          lifetime: lifetime,
          color: sparkColor,
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
      ..color = Color.lerp(Colors.white, color, progress)!.withValues(alpha: alpha * 0.9)
      ..strokeWidth = max(0.5, 2.0 * (1.0 - progress))
      ..strokeCap = StrokeCap.round;

    final tailX = _x - cos(angle) * tailLen;
    final tailY = _y - sin(angle) * tailLen;
    canvas.drawLine(Offset(_x, _y), Offset(tailX, tailY), paint);
  }
}
