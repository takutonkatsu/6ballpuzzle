import 'dart:math';
import 'package:flame/components.dart';

import 'puzzle_game.dart';
import 'grid_system.dart';
import 'components/ball_component.dart';
import 'score_manager.dart';
import 'game_models.dart';
import 'game_logic.dart';

class CPUAgent {
  final PuzzleGame game;
  CPUDifficulty difficulty;
  final CPUWeights weights;

  double _thinkDelay = 0.0;
  double _moveDelay = 0.0;
  
  double _timer = 0.0;
  
  bool _isThinking = false;
  
  // 目標状態
  double? _targetPixelX;
  int _targetRotationCount = 0; // 残り何回「右回転」するか

  final Random _random = Random();

  CPUAgent(this.game, {
    this.difficulty = CPUDifficulty.hard,
    this.weights = const CPUWeights(),
  }) {
    _applyDifficultySettings();
  }

  void _applyDifficultySettings() {
    switch (difficulty) {
      case CPUDifficulty.easy:
        _thinkDelay = 1.0;
        _moveDelay = 0.25;
        break;
      case CPUDifficulty.normal:
        _thinkDelay = 0.6;
        _moveDelay = 0.12;
        break;
      case CPUDifficulty.hard:
        _thinkDelay = 0.1;
        _moveDelay = 0.03;
        break;
      case CPUDifficulty.oni:
        _thinkDelay = 0.0;
        _moveDelay = 0.05;
        break;
    }
  }

  void update(double dt) {
    if (game.gameStateWrapper.value != GameState.playing) return;
    if (game.activePiece == null || game.activePiece!.isLocked) {
      _resetState();
      return;
    }

    // まだ目標が決まっていないなら思考開始
    if (_targetPixelX == null && !_isThinking) {
      _isThinking = true;
      _timer = _thinkDelay;
    }

    if (_isThinking) {
      _timer -= dt;
      if (_timer <= 0) {
        _computeBestMove();
        _isThinking = false;
        _timer = _moveDelay;
      }
      return;
    }

    // 目標がある場合、位置を合わせるため徐々に移動させる（プレイヤーに近い動きを偽装）
    if (_targetPixelX != null && game.activePiece != null) {
      double currentX = game.activePiece!.position.x;
      double speed = difficulty == CPUDifficulty.oni ? 1400.0 : (difficulty == CPUDifficulty.hard ? 800.0 : 400.0);
      double step = speed * dt;
      
      if ((currentX - _targetPixelX!).abs() > step) {
         if (currentX > _targetPixelX!) {
            game.activePiece!.position.x -= step;
         } else {
            game.activePiece!.position.x += step;
         }
         return; // まだ目標位置に到達していないのでここで終了
      } else {
         game.activePiece!.position.x = _targetPixelX!;
      }
    }

    _timer -= dt;
    if (_timer <= 0) {
      _timer = _moveDelay + (difficulty == CPUDifficulty.oni ? 0.0 : _random.nextDouble() * 0.03);
      _executeNextAction();
    }
  }

  void _resetState() {
    _targetPixelX = null;
    _targetRotationCount = 0;
    _isThinking = false;
    game.stopMovingLeft();
    game.stopMovingRight();
  }

  void _executeNextAction() {
    if (game.activePiece == null) return;

    // 1. 回転を合わせる
    if (_targetRotationCount > 0) {
      game.rotateRight();
      _targetRotationCount--;
      return;
    }

    // X座標は update() 側で合わせ終わっているのでハードドロップ
    game.hardDrop();
    _resetState();
  }

  void _computeBestMove() {
     if (game.activePiece == null) return;
     
     List<BallColor> currColors = game.activePiece!.colors;
     List<BallColor>? nextColors = game.nextPieceColors.value.isNotEmpty ? game.nextPieceColors.value : null;

     Map<HexCoordinate, BallColor> baseBoard = {};
     for (var entry in game.grid.lockedBalls.entries) {
        baseBoard[entry.key] = entry.value.ballColor;
     }

     int maxCols = game.grid.getColumnsForRow(0);
     List<MoveOption> options = [];

     for (int col1 = 0; col1 < maxCols; col1++) {
       double x1 = game.grid.hexToPixel(HexCoordinate(col1, 0)).x;
       
       for (int rot1 = 0; rot1 < 6; rot1++) {
         SimDropResult sim1 = _simulateDrop(baseBoard, x1, currColors, rot1);
         double score1 = evaluateBoardLogic(sim1.simGrid, sim1.newBalls, weights, isEasy: difficulty == CPUDifficulty.easy);

         // 1手目で致死評価（-50万以下）ならこれ以上先読みしない
         if (score1 <= -500000.0) {
            options.add(MoveOption(x1, rot1, score1));
            continue;
         }

         double bestNextScore = 0.0;

         // 2手目（Look-ahead）の深さ探索
         if (nextColors != null && difficulty != CPUDifficulty.easy) {
            // Normal の場合は一部の確率で先読みをサボり近視眼的に動く
            bool skipLookahead = (difficulty == CPUDifficulty.normal && _random.nextDouble() < 0.2);
            
            if (!skipLookahead) {
                bestNextScore = -double.infinity;
                
                // 1手目で消えたボールを盤面から除去した状態で2手目をシミュレーション
                Map<HexCoordinate, BallColor> boardFor2 = Map.from(sim1.simGrid.board);
                for (var hex in sim1.allMatched) {
                   boardFor2.remove(hex);
                }
                
                for (int col2 = 0; col2 < maxCols; col2++) {
                  double x2 = game.grid.hexToPixel(HexCoordinate(col2, 0)).x;
                  for (int rot2 = 0; rot2 < 6; rot2++) {
                     SimDropResult sim2 = _simulateDrop(boardFor2, x2, nextColors, rot2);
                     double score2 = evaluateBoardLogic(sim2.simGrid, sim2.newBalls, weights, isEasy: difficulty == CPUDifficulty.easy);
                     if (score2 > bestNextScore) {
                        bestNextScore = score2;
                     }
                  }
                }
            }
         }
         
         options.add(MoveOption(x1, rot1, score1 + bestNextScore));
       }
     }

     // スコアが高い順にソート
     options.sort((a,b) => b.score.compareTo(a.score));
     
     if (options.isEmpty) return;

     MoveOption chosen = options.first;
     
     // 難易度による行動のブレ
     if (difficulty == CPUDifficulty.hard) {
        chosen = options.first;
     } else if (difficulty == CPUDifficulty.normal) {
        if (options.length > 2 && _random.nextDouble() < 0.1) {
           chosen = options[1]; // 10%で次善手を打つ
        }
     } else if (difficulty == CPUDifficulty.easy) {
        if (_random.nextDouble() < 0.3) {
           chosen = options[_random.nextInt(options.length)]; // 30%で完全にランダム
        } else if (options.length > 2 && _random.nextDouble() < 0.5) {
           chosen = options[2];
        }
     }

     _targetPixelX = chosen.x;
     _targetRotationCount = chosen.rot;
  }

  SimDropResult _simulateDrop(Map<HexCoordinate, BallColor> board, double xPos, List<BallColor> colors, int rot) {
     double d = 30.0;
     double rCenter = d * sqrt(3) / 3;
     double hSub = d * sqrt(3) / 6;

     List<Vector2> baseOffsets = [
       Vector2(0, -rCenter),
       Vector2(-d / 2, hSub),
       Vector2(d / 2, hSub),
     ];

     double angle = rot * (pi / 3);
     double cosA = cos(angle);
     double sinA = sin(angle);
     List<Vector2> absolutePositions = [];
     for (var offset in baseOffsets) {
       double nx = offset.x * cosA - offset.y * sinA;
       double ny = offset.x * sinA + offset.y * cosA;
       absolutePositions.add(Vector2(xPos + nx, -50 + ny));
     }

     SimGrid simGrid = SimGrid(game.grid.numRows, board);
     Map<HexCoordinate, BallColor> placingBalls = {};
     
     for (int i=0; i<3; i++) {
        var startHex = game.grid.pixelToHex(absolutePositions[i]);
        startHex = simGrid.findNearestEmpty(startHex);
        double offsetX = absolutePositions[i].x - game.grid.hexToPixel(startHex).x;
        
        HexCoordinate finalHex = simGrid.dropBall(startHex, offsetX);
        placingBalls[finalHex] = colors[i];
        simGrid.board[finalHex] = colors[i];
     }

     Set<HexCoordinate> allMatched = {};
     for (var entry in placingBalls.entries) {
        if (allMatched.contains(entry.key)) continue;
        var r = simGrid.checkMatchesFrom(entry.key, entry.value);
        if (r != null && r.matched.length >= 6) {
           allMatched.addAll(r.matched);
        }
     }
     
     return SimDropResult(simGrid, placingBalls, allMatched);
  }
}
