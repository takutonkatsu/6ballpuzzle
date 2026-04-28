import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import 'ball_component.dart';
import '../game_models.dart';

class ActivePieceComponent extends PositionComponent {
  static const double _rotationStep = pi / 3;
  static const double _fullTurn = pi * 2;
  static const double _rotationDuration = 0.11;

  final double ballRadius;
  double fallSpeed;
  bool isLocked = false;
  final bool isGhost;

  double logicalAngle = 0.0;
  double _rotationStartAngle = 0.0;
  double _rotationTargetAngle = 0.0;
  double _rotationProgress = 1.0;

  // 色情報を保持しておく
  final List<BallColor> colors = [];

  // 3つの相対的なローカル座標オフセット
  final List<Vector2> baseOffsets = [];

  // アクティブピース発光用
  double _auraTime = 0.0;

  ActivePieceComponent({
    required Vector2 position,
    this.ballRadius = 15.0,
    this.isGhost = false,
    List<BallColor>? presetColors,
    this.fallSpeed = 50.0,
  }) : super(position: position) {
    final random = Random();
    final allColors = [
      BallColor.blue,
      BallColor.green,
      BallColor.red,
      BallColor.yellow,
      BallColor.purple,
    ];

    final d = ballRadius * 2;
    final rCenter = d * sqrt(3) / 3;
    final hSub = d * sqrt(3) / 6;

    baseOffsets.addAll([
      Vector2(0, -rCenter),
      Vector2(-d / 2, hSub),
      Vector2(d / 2, hSub),
    ]);

    for (int i = 0; i < 3; i++) {
      BallColor c = presetColors != null
          ? presetColors[i]
          : allColors[random.nextInt(allColors.length)];
      colors.add(c);

      add(BallComponent(
        position: baseOffsets[i],
        radius: ballRadius,
        ballColor: c,
        isGhost: isGhost,
      )..state = BallState.locked);
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!isGhost) {
      scale = Vector2.zero();
      add(
        ScaleEffect.to(
          Vector2.all(1.0),
          EffectController(
            duration: 0.25,
            curve: Curves.easeOutBack,
          ),
        ),
      );
    }
  }

  /// 現在のangleを反映した3つのワールド座標のリストを返す
  List<Vector2> get absoluteBallPositions {
    return baseOffsets.map((offset) {
      Vector2 rotated = offset.clone()..rotate(logicalAngle);
      return position + rotated;
    }).toList();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLocked && !isGhost) {
      position.y += fallSpeed * dt;
    }
    _updateVisualRotation(dt);
    _auraTime += dt;
  }

  @override
  void render(Canvas canvas) {
    // アクティブピース（非ゴースト）のみ、枠付近だけリング発光
    if (!isGhost && !isLocked) {
      final auraPulse = (sin(_auraTime * 3.0) + 1.0) / 2.0; // 0.0〜1.0
      for (var i = 0; i < baseOffsets.length; i++) {
        final offset = baseOffsets[i];
        final localPos = Offset(offset.x, offset.y);

        final auraColor =
            colors.isNotEmpty ? colors[i].glowColor : Colors.white;

        // リム（外周枠）発光のみ
        final rimPaint = Paint()
          ..color = auraColor.withValues(alpha: 0.4 + auraPulse * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 + auraPulse * 1.5
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + auraPulse * 2);
        canvas.drawCircle(localPos, ballRadius + 1.0, rimPaint);
      }
    }
    super.render(canvas);
  }

  void rotateLeft() {
    if (isLocked) return;
    _setLogicalAngle(logicalAngle - _rotationStep);
  }

  void rotateRight() {
    if (isLocked) return;
    _setLogicalAngle(logicalAngle + _rotationStep);
  }

  void setRotationIndex(int rotation, {bool animate = false}) {
    final nextAngle = rotation * _rotationStep;
    if (animate) {
      if ((logicalRotationIndex - rotation) % 6 == 0) {
        return;
      }
      _setLogicalAngle(nextAngle);
      return;
    }
    logicalAngle = nextAngle;
    angle = nextAngle;
    _rotationStartAngle = nextAngle;
    _rotationTargetAngle = nextAngle;
    _rotationProgress = 1.0;
  }

  int get logicalRotationIndex {
    final normalized = (logicalAngle / _rotationStep).round() % 6;
    return normalized < 0 ? normalized + 6 : normalized;
  }

  void _setLogicalAngle(double nextAngle) {
    logicalAngle = nextAngle;
    _rotationStartAngle = angle;
    _rotationTargetAngle = _nearestEquivalentAngle(nextAngle, angle);
    _rotationProgress = 0.0;
  }

  double _nearestEquivalentAngle(double targetAngle, double fromAngle) {
    var delta = (targetAngle - fromAngle) % _fullTurn;
    if (delta > pi) {
      delta -= _fullTurn;
    } else if (delta < -pi) {
      delta += _fullTurn;
    }
    return fromAngle + delta;
  }

  void _updateVisualRotation(double dt) {
    if (_rotationProgress >= 1.0) {
      return;
    }
    _rotationProgress = min(1.0, _rotationProgress + dt / _rotationDuration);
    final eased = Curves.easeOutCubic.transform(_rotationProgress);
    angle = _rotationStartAngle +
        (_rotationTargetAngle - _rotationStartAngle) * eased;
  }
}
