import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import '../puzzle_game.dart';
import '../game_models.dart';
import '../effect_skin.dart';
import 'ball_component.dart';

class OjamaBlockComponent extends PositionComponent
    with HasGameReference<PuzzleGame> {
  final OjamaType ojamaType;
  final BallColor? startColor;
  final List<BallColor>? presetColors;
  final List<Map<String, dynamic>>? lockedCells;
  final String ballSkinId;
  final String effectSkinId;
  final List<BallComponent> innerBalls = [];

  late final double fallSpeed;
  bool _collided = false;
  double? _syncedLandingY;
  double _effectTime = 0;

  OjamaBlockComponent({
    required this.ojamaType,
    required Vector2 position,
    this.startColor,
    this.presetColors,
    this.lockedCells,
    this.ballSkinId = 'default',
    String? effectSkinId,
  })  : effectSkinId = effectSkinId ?? ballSkinId,
        super(position: position) {
    fallSpeed = ojamaType == OjamaType.straightSet ? 230.0 : 300.0;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

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
    if (ojamaType == OjamaType.straightSet) {
      _buildStraight();
    } else if (ojamaType == OjamaType.pyramidSet) {
      _buildPyramid();
    } else if (ojamaType == OjamaType.hexagonSet) {
      _buildHexagon();
    }
    _syncedLandingY = _computeSyncedLandingY();
  }

  void _buildStraight() {
    List<BallColor> loopColors = [
      BallColor.blue,
      BallColor.purple,
      BallColor.yellow,
      BallColor.red,
      BallColor.green
    ];
    final providedColors = presetColors;
    int startIdx = startColor != null
        ? loopColors.indexOf(startColor!)
        : Random().nextInt(loopColors.length);
    if (startIdx == -1) startIdx = 0;

    double rh = 15.0 * sqrt(3);

    // Bottom row (10 balls, Y = 0)
    for (int i = 0; i < 10; i++) {
      BallColor color = providedColors != null && providedColors.length > i
          ? providedColors[i]
          : loopColors[(startIdx + i) % loopColors.length];
      var ball = BallComponent(
        position: Vector2(i * 30.0, 0),
        radius: 15.0,
        ballColor: color,
        ballSkinId: ballSkinId,
      );
      innerBalls.add(ball);
      add(ball);
    }

    // Top row (9 balls, Y = -rh). Keep index 0 synchronized with bottom row.
    for (int i = 0; i < 9; i++) {
      final colorIndex = 10 + i;
      BallColor color =
          providedColors != null && providedColors.length > colorIndex
              ? providedColors[colorIndex]
              : loopColors[(startIdx + i) % loopColors.length];
      var ball = BallComponent(
        position: Vector2(i * 30.0 + 15.0, -rh),
        radius: 15.0,
        ballColor: color,
        ballSkinId: ballSkinId,
      );
      innerBalls.add(ball);
      add(ball);
    }
  }

  List<BallColor> _generateMixedColors() {
    if (presetColors != null && presetColors!.isNotEmpty) {
      return List<BallColor>.from(presetColors!);
    }
    List<BallColor> colors = List.from(BallColor.values);
    colors.add(BallColor.values[Random().nextInt(BallColor.values.length)]);
    colors.shuffle();
    return colors;
  }

  void _buildPyramid() {
    List<BallColor> colors = _generateMixedColors();
    double rh = 15.0 * sqrt(3);
    List<Vector2> offsets = [
      Vector2(30, -2 * rh), // Top
      Vector2(15, -rh), Vector2(45, -rh), // Middle
      Vector2(0, 0), Vector2(30, 0), Vector2(60, 0), // Base
    ];
    for (int i = 0; i < 6; i++) {
      var ball = BallComponent(
        position: offsets[i],
        radius: 15.0,
        ballColor: colors[i],
        ballSkinId: ballSkinId,
      );
      innerBalls.add(ball);
      add(ball);
    }
  }

  void _buildHexagon() {
    List<BallColor> colors = _generateMixedColors();
    double rh = 15.0 * sqrt(3);
    List<Vector2> offsets = [
      Vector2(15, -2 * rh), Vector2(45, -2 * rh), // Top
      Vector2(0, -rh), Vector2(60, -rh), // Middle
      Vector2(15, 0), Vector2(45, 0), // Base
    ];
    for (int i = 0; i < 6; i++) {
      var ball = BallComponent(
        position: offsets[i],
        radius: 15.0,
        ballColor: colors[i],
        ballSkinId: ballSkinId,
      );
      innerBalls.add(ball);
      add(ball);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_usesCustomEffect) {
      _effectTime = (_effectTime + dt) % 1000;
    }
    if (game.gameStateWrapper.value != GameState.playing) return;
    if (_collided) return;

    position.y += fallSpeed * dt;

    final syncedLandingY = _syncedLandingY;
    if (syncedLandingY != null) {
      if (position.y >= syncedLandingY) {
        position.y = syncedLandingY;
        _collided = true;
        _breakApart();
      }
      return;
    }

    if (_checkCollision()) {
      _collided = true;
      _breakApart();
    }
  }

  @override
  void render(Canvas canvas) {
    if (_usesCustomEffect && innerBalls.isNotEmpty) {
      _drawOjamaAura(canvas);
    }
    super.render(canvas);
    if (_usesCustomEffect && innerBalls.isNotEmpty) {
      _drawOjamaForegroundEffect(canvas);
    }
  }

  bool get _usesCustomEffect =>
      effectSkinId == 'skin_luxury_prism' ||
      effectSkinId != EffectSkinCatalog.defaultOjamaId &&
          effectSkinId.startsWith('effect_ojama_');

  void _drawOjamaAura(Canvas canvas) {
    if (effectSkinId == 'skin_luxury_prism') {
      _drawPrismOjamaAura(canvas);
      return;
    }
    final bounds = _innerBallBounds();
    final skin = EffectSkinCatalog.byId(effectSkinId);
    final pulse = (sin(_effectTime * 5.0) + 1) * 0.5;
    final glowPaint = Paint()
      ..color = skin.color.withValues(alpha: 0.16 + pulse * 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          bounds.inflate(14 + pulse * 4), const Radius.circular(22)),
      glowPaint,
    );

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = skin.color.withValues(alpha: 0.72);
    if (effectSkinId == 'effect_ojama_meteor') {
      final heatPaint = Paint()
        ..color = const Color(0xFFFF8A2A).withValues(alpha: 0.18 + pulse * 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawOval(bounds.inflate(24 + pulse * 8), heatPaint);
      return;
    }
    if (effectSkinId == 'effect_ojama_thunder') {
      for (var i = 0; i < 3; i++) {
        final y = bounds.top + (i + 1) * bounds.height / 4;
        final shift = sin(_effectTime * 9 + i) * 8;
        final path = Path()
          ..moveTo(bounds.left - 10, y)
          ..lineTo(bounds.center.dx - 12 + shift, y + 8)
          ..lineTo(bounds.center.dx + 10 - shift, y - 6)
          ..lineTo(bounds.right + 10, y + 4);
        canvas.drawPath(path, strokePaint);
      }
      return;
    }

    if (effectSkinId == 'effect_ojama_crystal') {
      final crystalPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFA7F7FF).withValues(alpha: 0.64)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      for (var i = 0; i < innerBalls.length; i++) {
        final center =
            Offset(innerBalls[i].position.x, innerBalls[i].position.y);
        final r = innerBalls[i].radius + 5 + pulse * 3;
        final path = Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r * 0.75, center.dy)
          ..lineTo(center.dx, center.dy + r)
          ..lineTo(center.dx - r * 0.75, center.dy)
          ..close();
        canvas.drawPath(path, crystalPaint);
      }
    }
  }

  void _drawOjamaForegroundEffect(Canvas canvas) {
    if (effectSkinId == 'skin_luxury_prism') {
      return;
    }
    final bounds = _innerBallBounds();
    final skin = EffectSkinCatalog.byId(effectSkinId);
    final pulse = (sin(_effectTime * 7.0) + 1) * 0.5;
    if (effectSkinId == 'effect_ojama_meteor') {
      final emberPaint = Paint()
        ..color = const Color(0xFFFFE082).withValues(alpha: 0.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      for (var i = 0; i < innerBalls.length; i++) {
        final center =
            Offset(innerBalls[i].position.x, innerBalls[i].position.y);
        final angle = _effectTime * 4.2 + i * 1.7;
        canvas.drawCircle(
          center + Offset(cos(angle), sin(angle)) * (innerBalls[i].radius + 5),
          2.2 + pulse * 1.4,
          emberPaint,
        );
      }
      return;
    }
    if (effectSkinId == 'effect_ojama_thunder') {
      final boltPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFF59D).withValues(alpha: 0.90)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      for (var i = 0; i < 2; i++) {
        final x = bounds.left + bounds.width * (i + 1) / 3;
        final phase = sin(_effectTime * 11 + i) * 6;
        final path = Path()
          ..moveTo(x - 14, bounds.top - 4)
          ..lineTo(x + phase, bounds.center.dy - 8)
          ..lineTo(x - phase * 0.5, bounds.center.dy + 4)
          ..lineTo(x + 15, bounds.bottom + 4);
        canvas.drawPath(path, boltPaint);
      }
      return;
    }
    if (effectSkinId == 'effect_ojama_crystal') {
      final shardPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE0FBFF).withValues(alpha: 0.82);
      final glintPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..color = skin.color.withValues(alpha: 0.66)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      for (var i = 0; i < innerBalls.length; i++) {
        final center =
            Offset(innerBalls[i].position.x, innerBalls[i].position.y);
        final r = innerBalls[i].radius + 4 + pulse * 2;
        final path = Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r * 0.68, center.dy)
          ..lineTo(center.dx, center.dy + r)
          ..lineTo(center.dx - r * 0.68, center.dy)
          ..close();
        canvas.drawPath(path, shardPaint);
        if (i.isEven) {
          canvas.drawLine(
            center + Offset(-r * 0.45, -r * 0.45),
            center + Offset(r * 0.45, r * 0.45),
            glintPaint,
          );
        }
      }
    }
  }

  void _drawPrismOjamaAura(Canvas canvas) {
    final bounds = _innerBallBounds();
    final center = bounds.center;
    final pulse = (sin(_effectTime * 4.0) + 1) * 0.5;
    final sweepRect = Rect.fromCircle(
      center: center,
      radius: max(bounds.width, bounds.height) * 0.72 + 28,
    );
    canvas.drawOval(
      bounds.inflate(18 + pulse * 5),
      Paint()
        ..shader = SweepGradient(
          startAngle: _effectTime * 2.5,
          endAngle: _effectTime * 2.5 + pi * 2,
          colors: [
            const Color(0xFF35F0FF).withValues(alpha: 0.00),
            const Color(0xFF35F0FF).withValues(alpha: 0.26),
            const Color(0xFFFF4DFF).withValues(alpha: 0.22),
            const Color(0xFFFFF35A).withValues(alpha: 0.28),
            const Color(0xFF35F0FF).withValues(alpha: 0.00),
          ],
        ).createShader(sweepRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    final trailPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF35F0FF).withValues(alpha: 0.00),
          const Color(0xFF35F0FF).withValues(alpha: 0.20),
          const Color(0xFFFF4DFF).withValues(alpha: 0.16),
        ],
      ).createShader(bounds.inflate(22))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (var i = 0; i < 5; i++) {
      final x = bounds.left + bounds.width * (i + 1) / 6;
      canvas.drawLine(
        Offset(x, bounds.top - 24 - pulse * 6),
        Offset(x + sin(_effectTime * 3 + i) * 10, bounds.bottom + 16),
        trailPaint,
      );
    }

    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < innerBalls.length; i++) {
      final ballCenter =
          Offset(innerBalls[i].position.x, innerBalls[i].position.y);
      final angle = _effectTime * 4 + i * pi * 0.67;
      final sparkleCenter = Offset(
        ballCenter.dx + cos(angle) * 19,
        ballCenter.dy + sin(angle) * 19,
      );
      particlePaint.color = [
        const Color(0xFF35F0FF),
        const Color(0xFFFF4DFF),
        const Color(0xFFFFF35A),
        const Color(0xFF52FF86),
      ][i % 4]
          .withValues(alpha: 0.72);
      _drawOjamaDiamond(canvas, sparkleCenter, 4.5, particlePaint);
    }
  }

  Rect _innerBallBounds() {
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final ball in innerBalls) {
      left = min(left, ball.position.x - ball.radius);
      top = min(top, ball.position.y - ball.radius);
      right = max(right, ball.position.x + ball.radius);
      bottom = max(bottom, ball.position.y + ball.radius);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  void _drawOjamaDiamond(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    final path = Path()
      ..moveTo(center.dx, center.dy - size)
      ..lineTo(center.dx + size * 0.45, center.dy)
      ..lineTo(center.dx, center.dy + size)
      ..lineTo(center.dx - size * 0.45, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  bool _checkCollision() {
    // Check if bottom-most points hit the floor
    for (var ball in innerBalls) {
      Vector2 wPos = position + ball.position;
      if (wPos.y + 15.0 >= game.grid.floorY) return true;
    }

    // Check against locked balls in the grid
    for (var ball in innerBalls) {
      Vector2 wPos = position + ball.position;
      for (var lockedBall in game.grid.lockedBalls.values) {
        if (wPos.distanceTo(lockedBall.position) < 28.0) {
          return true;
        }
      }
    }
    return false;
  }

  double? _computeSyncedLandingY() {
    final cells = lockedCells;
    if (cells == null || cells.isEmpty || innerBalls.isEmpty) {
      return null;
    }
    final impactYs = <double>[];
    for (final cell in cells) {
      final impactY = _asDouble(cell['impactY']);
      if (impactY != null && impactY.isFinite) {
        impactYs.add(impactY);
      }
    }
    if (impactYs.isNotEmpty) {
      impactYs.sort();
      return impactYs[impactYs.length ~/ 2];
    }

    // 古い同期ペイロードには impactY が無い。landingCells は接地後の
    // グリッド確定にだけ使い、空中での分解位置推測には使わない。
    return null;
  }

  void _breakApart() {
    removeFromParent();
    final cells = lockedCells;
    for (var index = 0; index < innerBalls.length; index++) {
      final ball = innerBalls[index];
      ball.removeFromParent();

      Vector2 wPos = position + ball.position;
      final lockedCell = cells != null && index < cells.length
          ? _lockedCellFromPayload(cells[index])
          : null;
      var hex = lockedCell?.$1 ?? game.grid.pixelToHex(wPos);
      if (lockedCell == null) {
        hex = game.grid.findNearestEmpty(hex);
      }
      final hitOffsetX =
          lockedCell?.$2 ?? (wPos.x - game.grid.hexToPixel(hex).x);
      if (lockedCell != null) {
        final basePosition = game.grid.hexToPixel(hex);
        wPos = Vector2(basePosition.x + hitOffsetX, basePosition.y);
      }

      var newBall = BallComponent(
        position: wPos,
        radius: 15.0,
        ballColor: ball.ballColor,
        ballSkinId: ballSkinId,
      );
      newBall.hitOffsetX = hitOffsetX;
      final existingBall = game.grid.lockedBalls.remove(hex);
      if (existingBall != null && existingBall.parent != null) {
        existingBall.removeFromParent();
      }
      game.add(newBall);
      game.grid.lockedBalls[hex] = newBall;
    }
    game.onOjamaBlockLanded(this);
  }

  (HexCoordinate, double)? _lockedCellFromPayload(Map<String, dynamic> raw) {
    final row = _asInt(raw['row']);
    final col = _asInt(raw['col']);
    if (row == null || col == null) {
      return null;
    }
    final hitOffsetX = _asDouble(raw['hitOffsetX']) ?? 0.0;
    return (HexCoordinate(col, row), hitOffsetX);
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value');
  }
}
