import 'dart:async';
import 'dart:math';
import 'dart:collection';
import 'package:flame/game.dart';
import 'package:flame/events.dart'; 
import 'package:flame/effects.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'components/active_piece_component.dart';
import 'components/ball_component.dart';
import 'components/effect_components.dart';
import 'components/hint_component.dart';
import 'grid_system.dart';
import 'score_manager.dart';
import 'cpu_agent.dart';
import 'game_models.dart';

enum GameState { title, playing, gameover }

class PuzzleGame extends FlameGame with KeyboardEvents {
  final bool isCpuMode;
  final int? seed;
  late final Random _rng;
  CPUAgent? cpuAgent;
  late GridSystem grid;
  ActivePieceComponent? activePiece;
  ActivePieceComponent? ghostPiece;
  
  bool _isSpawning = false;
  final ValueNotifier<GameState> gameStateWrapper = ValueNotifier(GameState.title);

  bool isMovingLeft = false;
  bool isMovingRight = false;
  double moveSpeed = 200.0;

  // Nextは1セットのみ
  final ValueNotifier<List<BallColor>> nextPieceColors = ValueNotifier([]);

  // ワザ名表示用
  final ValueNotifier<String?> wazaNameNotifier = ValueNotifier(null);

  // おじゃまキュー
  final Queue<OjamaTask> incomingOjama = Queue();
  
  // ワザ発動コールバック
  Function(WazaType, BallColor?)? onWazaFired;
  
  static const double constantFallSpeed = 50.0; // 一定化された遅めの落下速度

  void startMovingLeft() => isMovingLeft = true;
  void stopMovingLeft() => isMovingLeft = false;
  void startMovingRight() => isMovingRight = true;
  void stopMovingRight() => isMovingRight = false;

  void startGame() {
    grid.lockedBalls.values.forEach((b) => remove(b));
    grid.lockedBalls.clear();
    _clearHints();
    incomingOjama.clear();
    
    scoreManager.reset();
    _idleGlowTime = 0.0;
    _idleGlowIndex = 0;
    nextPieceColors.value = _generatePieceColors();
    wazaNameNotifier.value = null;

    if (activePiece != null) {
      remove(activePiece!);
      activePiece = null;
    }
    if (ghostPiece != null) {
      remove(ghostPiece!);
      ghostPiece = null;
    }
    _isSpawning = false;
    isMovingLeft = false;
    isMovingRight = false;
    
    gameStateWrapper.value = GameState.playing;
    _spawnNewPiece();
  }

  void gameOver() {
    gameStateWrapper.value = GameState.gameover;
  }

  @override
  Color backgroundColor() => const Color(0xFF101010);

  PuzzleGame({this.isCpuMode = false, this.seed}) {
     _rng = seed != null ? Random(seed) : Random();
     if (isCpuMode) {
       cpuAgent = CPUAgent(this, difficulty: CPUDifficulty.hard);
     }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    grid = GridSystem(
      ballRadius: 15.0,
      offset: Vector2((size.x - 300) / 2 + 15, 100),
    );
  }

  List<BallColor> _generatePieceColors() {
    return List.generate(3, (_) => BallColor.values[_rng.nextInt(BallColor.values.length)]);
  }

  void _spawnNewPiece() {
    scoreManager.endChain();

    if (nextPieceColors.value.isEmpty) {
       nextPieceColors.value = _generatePieceColors();
    }

    final currentColors = nextPieceColors.value;

    activePiece = ActivePieceComponent(
      position: Vector2(size.x / 2, 50),
      ballRadius: 15.0,
      fallSpeed: constantFallSpeed,
      presetColors: currentColors,
    )..priority = 10;
    add(activePiece!);
    
    ghostPiece = ActivePieceComponent(
      position: Vector2(size.x / 2, 50),
      ballRadius: 15.0,
      isGhost: true,
      fallSpeed: constantFallSpeed,
      presetColors: currentColors,
    )..priority = 0;
    add(ghostPiece!);

    nextPieceColors.value = _generatePieceColors();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final wallPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8)
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(grid.leftWallX, grid.floorY), 
      Offset(grid.rightWallX, grid.floorY), 
      wallPaint
    );
    canvas.drawLine(Offset(grid.leftWallX, -1000), Offset(grid.leftWallX, grid.floorY), wallPaint);
    canvas.drawLine(Offset(grid.rightWallX, -1000), Offset(grid.rightWallX, grid.floorY), wallPaint);

    final deathLineY = grid.offset.y - 15.0; 
    final deathLinePaint = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2.0;
      
    canvas.drawLine(
      Offset(grid.leftWallX, deathLineY), 
      Offset(grid.rightWallX, deathLineY), 
      deathLinePaint
    );
  }

  // 定期発光用タイマー
  double _idleGlowTime = 0.0;
  int _idleGlowIndex = 0;
  static const double _idleGlowInterval = 5.0;

  @override
  void update(double dt) {
    super.update(dt);
    
    if (gameStateWrapper.value != GameState.playing) return;

    if (cpuAgent != null) {
       cpuAgent!.update(dt);
    }

    // 定期発光（5秒ごとに順番に色を光らせる）
    _idleGlowTime += dt;
    if (_idleGlowTime >= _idleGlowInterval) {
      _idleGlowTime = 0.0;
      final colors = BallColor.values;
      final targetColor = colors[_idleGlowIndex % colors.length];
      _idleGlowIndex++;
      for (var ball in grid.lockedBalls.values) {
        if (ball.ballColor == targetColor) {
          ball.startPulse();
        }
      }
    }
    
    if (activePiece != null && !activePiece!.isLocked) {
      if (isMovingLeft && !isMovingRight) {
        activePiece!.position.x -= moveSpeed * dt;
      } else if (isMovingRight && !isMovingLeft) {
        activePiece!.position.x += moveSpeed * dt;
      }
      _enforceBounds();
    }
    
    _updateGhostPosition();
    _checkActivePieceCollision();
  }

  void _updateGhostPosition() {
    if (activePiece == null || ghostPiece == null) return;
    
    ghostPiece!.position = activePiece!.position.clone();
    ghostPiece!.angle = activePiece!.angle;
    
    double minGy = grid.floorY + 1000;
    
    final positions = activePiece!.absoluteBallPositions;
    for (var pos in positions) {
      double relX = pos.x - activePiece!.position.x;
      double relY = pos.y - activePiece!.position.y;
      
      double hitY = grid.floorY - 15.0 - relY;
      if (hitY < minGy) minGy = hitY;
      
      double ballAx = activePiece!.position.x + relX;
      for (var locked in grid.lockedBalls.values) {
         double dx = ballAx - locked.position.x;
         if (dx.abs() <= 30.0) { 
             double dy = sqrt(900.0 - dx * dx);
             double hitLockedY = locked.position.y - dy - relY;
             if (hitLockedY < minGy) minGy = hitLockedY;
         }
      }
    }
    
    if (minGy < activePiece!.position.y) {
      minGy = activePiece!.position.y;
    }
    
    ghostPiece!.position.y = minGy;
  }

  void _checkActivePieceCollision() {
    if (activePiece == null || activePiece!.isLocked) return;

    bool hit = false;
    final positions = activePiece!.absoluteBallPositions;
    final colors = activePiece!.colors;

    for (var pos in positions) {
      if (pos.y + 15.0 >= grid.floorY) hit = true;
      for (var locked in grid.lockedBalls.values) {
        if (pos.distanceTo(locked.position) <= 30.0) hit = true;
      }
    }

    if (hit) {
      final oldActive = activePiece!;
      final oldGhost = ghostPiece;

      oldActive.isLocked = true;
      remove(oldActive);
      if (oldGhost != null) {
        remove(oldGhost);
      }
      
      activePiece = null;
      ghostPiece = null;

      _executeLogicDrop(positions, colors);
    }
  }

  final ScoreManager scoreManager = ScoreManager();
  final List<Component> _hintComponents = [];

  void _clearHints() {
     for (var h in _hintComponents) {
        if (h.parent != null) remove(h);
     }
     _hintComponents.clear();
  }

  void _updateHints() {
     _clearHints();
     var hintHexes = grid.getHintHexes();
     for (var entry in hintHexes.entries) {
        var hex = entry.key;
        var colors = entry.value.toList();
        var px = grid.hexToPixel(hex);
        var comp = HintOutlineComponent(position: px, radius: 15.0, hintColor: colors[0].color);
        add(comp);
        _hintComponents.add(comp);
     }
  }

  Future<void> _executeLogicDrop(List<Vector2> positions, List<BallColor> colors) async {
    _clearHints();
    for (int i = 0; i < 3; i++) {
       var hex = grid.pixelToHex(positions[i]);
       hex = grid.findNearestEmpty(hex); 
       
       var newBall = BallComponent(
          position: positions[i],  // 接触箇所からアニメーション開始
          radius: 15.0,
          ballColor: colors[i],
       );
       newBall.hitOffsetX = positions[i].x - grid.hexToPixel(hex).x; // ズレを保持
       add(newBall);
       grid.lockedBalls[hex] = newBall;
    }

    await _processGravityAndMatches();
  }

  Future<void> _processGravityAndMatches() async {
    bool hasMatches = true;
    while (hasMatches && gameStateWrapper.value == GameState.playing) {
      
      // 1. 重力落下ループ
      bool changed = true;
      while (changed) {
        if (gameStateWrapper.value != GameState.playing) return;
        changed = false;
        
        List<HexCoordinate> allHexes = grid.lockedBalls.keys.toList();
        allHexes.sort((a, b) {
            int rowDiff = b.row.compareTo(a.row);
            if (rowDiff != 0) return rowDiff;
            return a.col.compareTo(b.col);
        });

        for (var curr in allHexes) {
           BallComponent comp = grid.lockedBalls.remove(curr)!;
           
           HexCoordinate next = _calcNextStep(curr, comp.hitOffsetX);
           
           if (next != curr) {
              changed = true;
              grid.lockedBalls[next] = comp;
              Vector2 targetPx = grid.hexToPixel(next);
              
              comp.add(MoveEffect.to(
                 targetPx,
                 EffectController(duration: 0.15, curve: Curves.easeInQuad),
              ));
           } else {
              grid.lockedBalls[curr] = comp;
              comp.snapTo(grid.hexToPixel(curr));
           }
        }

        if (changed) {
           await Future.delayed(const Duration(milliseconds: 155)); 
        }
      }

      // 2. 消滅判定
      if (gameStateWrapper.value != GameState.playing) return;
      
      var matchResults = grid.findMatchesAndWazas();
      if (matchResults.isEmpty) {
         hasMatches = false;
      } else {
         for (var matchResult in matchResults) {
             // 既に消去済みのターゲットが含まれている場合はスキップや除外が必要
             // （Wazaによって同色全体が消去された直後の別の成分など）
             var validTargets = matchResult.targets.where((h) => grid.lockedBalls.containsKey(h)).toList();
             if (validTargets.isEmpty) continue;
             
             scoreManager.addMatch(validTargets.length, matchResult.highestWaza);
             
             // ワザ演出シーケンス
             if (matchResult.highestWaza != WazaType.none && matchResult.wazaPattern.isNotEmpty) {
                if (onWazaFired != null) {
                   onWazaFired!(matchResult.highestWaza, matchResult.wazaColor);
                }
                await _playWazaAnimation(matchResult);
             }
             
             // 消滅アニメーション（スケール縮小 + リングエフェクト）
             for (var hex in validTargets) {
                BallComponent? comp = grid.lockedBalls.remove(hex);
                if (comp == null) continue;
                
                // リング爆発エフェクト
                final ringEffect = BallPopRingEffect(
                  position: comp.position.clone(),
                  ringColor: comp.ballColor.glowColor,
                );
                add(ringEffect);
                
                // ボールは縮小して消える
                comp.add(ScaleEffect.to(
                   Vector2.zero(),
                   EffectController(duration: 0.15), 
                ));
                Future.delayed(const Duration(milliseconds: 160), () {
                   if (comp.parent != null) comp.removeFromParent();
                });
             }
             await Future.delayed(const Duration(milliseconds: 350)); 
             wazaNameNotifier.value = null;
         }
      }
    }

    // 連鎖終了後のゲームオーバー確認・新規生成
    bool isGameOver = false;
    for (var hex in grid.lockedBalls.keys) {
       if (hex.row < 0) isGameOver = true;
    }

    if (isGameOver) {
      gameOver();
    } else {
      _updateHints();

      if (gameStateWrapper.value == GameState.playing && !_isSpawning) {
         if (incomingOjama.isNotEmpty) {
            var task = incomingOjama.removeFirst();
            await _dropOjamaTask(task);
            // おじゃま落下後、連鎖の可能性があるためループ再起
            _processGravityAndMatches(); 
            return;
         }

         _isSpawning = true;
         _spawnNewPiece();
         _isSpawning = false;
      }
    }
  }

  Future<void> _dropOjamaTask(OjamaTask task) async {
     List<BallColor> loopColors = [BallColor.blue, BallColor.purple, BallColor.yellow, BallColor.red, BallColor.green];
     int maxCols = grid.getColumnsForRow(0);
     
     if (task.type == OjamaType.colorSet) {
        // ピラミッド・ヘキサゴン用の1セット(6個)
        List<BallColor> colors = List.from(BallColor.values); 
        colors.add(BallColor.values[_rng.nextInt(BallColor.values.length)]); 
        colors.shuffle(_rng);

        List<int> cols = List.generate(maxCols, (idx) => idx)..shuffle(_rng);
        cols = cols.take(6).toList();

        for (int j = 0; j < 6; j++) {
           int c = cols[j];
           // 上空から降らせる
           double px = grid.offset.x + c * 30.0 + 15.0; 
           var hex = grid.pixelToHex(Vector2(px, -50.0));
           hex = grid.findNearestEmpty(hex);
           
           var ball = BallComponent(position: Vector2(px, -50.0), radius: 15.0, ballColor: colors[j]);
           ball.hitOffsetX = 0.0;
           add(ball);
           grid.lockedBalls[hex] = ball;
        }
     } else if (task.type == OjamaType.straightSet) {
        // ストレート用: 1段分(=一番上の列個数)を降らせる
        int startIdx = task.startColor != null ? loopColors.indexOf(task.startColor!) : _rng.nextInt(loopColors.length);
        if (startIdx == -1) startIdx = 0;

        for (int c = 0; c < maxCols; c++) {
           BallColor colColor = loopColors[(startIdx + c) % loopColors.length];
           double px = grid.offset.x + c * 30.0 + 15.0;
           var hex = grid.pixelToHex(Vector2(px, -50.0));
           hex = grid.findNearestEmpty(hex);

           var ball = BallComponent(position: Vector2(px, -50.0), radius: 15.0, ballColor: colColor);
           ball.hitOffsetX = 0.0;
           add(ball);
           grid.lockedBalls[hex] = ball;
        }
     }
  }

  Future<void> _playWazaAnimation(MatchResult matchResult) async {
    final wazaName = _wazaName(matchResult.highestWaza);
    wazaNameNotifier.value = '$wazaName！';

    // ワザ構成ボール以外の同色ボールに isWazaSameColor フラグを立てる（枠リング発光）
    final sameColorBalls = <BallComponent>[];
    if (matchResult.wazaColor != null) {
      for (var ball in grid.lockedBalls.values) {
        if (ball.ballColor == matchResult.wazaColor && !matchResult.targets.contains(_hexForBall(ball))) {
          ball.isWazaSameColor = true;
          sameColorBalls.add(ball);
        }
      }
    }

    // ワザ構成ボールを段階的に白くフラッシュ
    for (var group in matchResult.wazaPattern) {
      for (var hex in group) {
        final ball = grid.lockedBalls[hex];
        if (ball != null) {
          ball.flashGlow();
        }
      }
      await Future.delayed(const Duration(milliseconds: 180));
    }

    // 全フラッシュが落ち着くまで少し待つ
    await Future.delayed(const Duration(milliseconds: 350));

    // 同色フラグをリセット
    for (var ball in sameColorBalls) {
      ball.isWazaSameColor = false;
    }
  }

  HexCoordinate? _hexForBall(BallComponent ball) {
    for (var entry in grid.lockedBalls.entries) {
      if (entry.value == ball) return entry.key;
    }
    return null;
  }

  String _wazaName(WazaType waza) {
    switch (waza) {
      case WazaType.hexagon: return 'HEXAGON';
      case WazaType.pyramid: return 'PYRAMID';
      case WazaType.straight: return 'STRAIGHT';
      case WazaType.none: return '';
    }
  }

  HexCoordinate _calcNextStep(HexCoordinate curr, double offsetX) {
      if (curr.row >= grid.numRows - 1) return curr;

      var a = grid.getNeighbor(curr, 'a');
      var b = grid.getNeighbor(curr, 'b');
      var c = grid.getNeighbor(curr, 'c');
      var d = grid.getNeighbor(curr, 'd');
      var e = grid.getNeighbor(curr, 'e');

      bool bEmpty = !grid.isOccupied(b) && !grid.isOutOfBounds(b);
      bool cEmpty = !grid.isOccupied(c) && !grid.isOutOfBounds(c);
      bool aOccupied = grid.isOccupied(a);
      bool dOccupied = grid.isOccupied(d);

      if (bEmpty && cEmpty) {
          if (aOccupied && !dOccupied) {
              return c!;
          } else if (!aOccupied && dOccupied) {
              return b!;
          } else {
              bool eEmpty = !grid.isOccupied(e) && !grid.isOutOfBounds(e);
              if (eEmpty) {
                  return e!; // 完全に空いていれば真下に落ちる
              } else {
                  if (offsetX == 0.0) {
                      return Random().nextBool() ? b! : c!;
                  }
                  return (offsetX < 0) ? b! : c!; // 塞がっていればズレで判定
              }
          }
      } else if (bEmpty && !cEmpty) {
          if (!aOccupied) return b!;
          if (grid.isOutOfBounds(c)) return b!; // 右の壁際(cが壁)ならaがあってもbへ回避
          return curr;
      } else if (!bEmpty && cEmpty) {
          if (!dOccupied) return c!;
          if (grid.isOutOfBounds(b)) return c!; // 左の壁際(bが壁)ならdがあってもcへ回避
          return curr;
      }

      return curr;
  }

  void rotateLeft() {
    if (activePiece == null || activePiece!.isLocked) return;
    activePiece!.rotateLeft();
    _enforceBounds();
  }

  void rotateRight() {
    if (activePiece == null || activePiece!.isLocked) return;
    activePiece!.rotateRight();
    _enforceBounds();
  }
  
  void _enforceBounds() {
    if (activePiece == null) return;
    for (var pos in activePiece!.absoluteBallPositions) {
      if (pos.x - 15.0 < grid.leftWallX) {
        activePiece!.position.x += (grid.leftWallX - (pos.x - 15.0));
      } else if (pos.x + 15.0 > grid.rightWallX) {
        activePiece!.position.x -= ((pos.x + 15.0) - grid.rightWallX);
      }
    }
  }

  void hardDrop() {
    if (activePiece == null || activePiece!.isLocked) return;
    if (ghostPiece != null) {
      final dropPositions = ghostPiece!.absoluteBallPositions;
      final pieceColors = activePiece!.colors;

      // 火花エフェクトを各ボールの落下地点に
      for (var i = 0; i < dropPositions.length && i < pieceColors.length; i++) {
        final effect = SparkEffect(
          position: dropPositions[i].clone(),
          sparkColor: pieceColors[i].glowColor,
        );
        add(effect);
      }

      activePiece!.position = ghostPiece!.position.clone();
      activePiece!.position.y += 5.0; 
    }
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (gameStateWrapper.value != GameState.playing) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        startMovingLeft();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        startMovingRight();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        hardDrop();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        rotateRight();
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        stopMovingLeft();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        stopMovingRight();
        return KeyEventResult.handled;
      }
    }
    return super.onKeyEvent(event, keysPressed);
  }
}
