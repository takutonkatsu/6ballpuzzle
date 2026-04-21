import 'dart:math';
import 'package:flame/components.dart';
import '../puzzle_game.dart';
import '../game_models.dart';
import 'ball_component.dart';

class OjamaBlockComponent extends PositionComponent
    with HasGameReference<PuzzleGame> {
  final OjamaType ojamaType;
  final BallColor? startColor;
  final List<BallColor>? presetColors;
  final List<BallComponent> innerBalls = [];

  double fallSpeed = 200.0; // Slow block fall
  bool _collided = false;

  OjamaBlockComponent({
    required this.ojamaType,
    required Vector2 position,
    this.startColor,
    this.presetColors,
  }) : super(position: position);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (ojamaType == OjamaType.straightSet) {
      _buildStraight();
    } else if (ojamaType == OjamaType.pyramidSet) {
      _buildPyramid();
    } else if (ojamaType == OjamaType.hexagonSet) {
      _buildHexagon();
    }
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
          position: Vector2(i * 30.0, 0), radius: 15.0, ballColor: color);
      innerBalls.add(ball);
      add(ball);
    }

    // Top row (9 balls, Y = -rh)
    int topStartIdx = Random().nextInt(loopColors.length);
    for (int i = 0; i < 9; i++) {
      final colorIndex = 10 + i;
      BallColor color =
          providedColors != null && providedColors.length > colorIndex
              ? providedColors[colorIndex]
              : loopColors[(topStartIdx + i) % loopColors.length];
      var ball = BallComponent(
          position: Vector2(i * 30.0 + 15.0, -rh),
          radius: 15.0,
          ballColor: color);
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
          position: offsets[i], radius: 15.0, ballColor: colors[i]);
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
          position: offsets[i], radius: 15.0, ballColor: colors[i]);
      innerBalls.add(ball);
      add(ball);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.gameStateWrapper.value != GameState.playing) return;
    if (_collided) return;

    position.y += fallSpeed * dt;

    if (_checkCollision()) {
      _collided = true;
      _breakApart();
    }
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

  void _breakApart() {
    removeFromParent();
    for (var ball in innerBalls) {
      ball.removeFromParent();

      Vector2 wPos = position + ball.position;
      var hex = game.grid.pixelToHex(wPos);
      hex = game.grid.findNearestEmpty(hex);

      var newBall = BallComponent(
          position: wPos, radius: 15.0, ballColor: ball.ballColor);
      newBall.hitOffsetX = wPos.x - game.grid.hexToPixel(hex).x;
      game.add(newBall);
      game.grid.lockedBalls[hex] = newBall;
    }
    game.onOjamaBlockLanded(this);
  }
}
