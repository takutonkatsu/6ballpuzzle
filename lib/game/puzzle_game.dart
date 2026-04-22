import 'dart:async' as async;
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
import 'components/ojama_block_component.dart';
import 'grid_system.dart';
import 'score_manager.dart';
import 'cpu_agent.dart';
import 'game_models.dart';

enum GameState { title, ready, playing, gameover }

class PuzzleGame extends FlameGame with KeyboardEvents {
  final bool isCpuMode;
  final int? seed;
  final bool autoStart;
  final bool isRemotePlayerMode;
  final bool useConstantFallSpeed;
  late Random _rng;
  Random? syncDropRng;
  int currentDropSeed = 0;
  CPUAgent? cpuAgent;
  late GridSystem grid;
  ActivePieceComponent? activePiece;
  ActivePieceComponent? ghostPiece;

  bool _isSpawning = false;
  final ValueNotifier<GameState> gameStateWrapper =
      ValueNotifier(GameState.title);

  bool isMovingLeft = false;
  bool isMovingRight = false;
  double moveSpeed = 200.0;

  final ValueNotifier<List<BallColor>> nextPieceColors = ValueNotifier([]);

  final ValueNotifier<String?> wazaNameNotifier = ValueNotifier(null);

  final Queue<OjamaTask> incomingOjama = Queue();

  Function(WazaType, BallColor?)? onWazaFired;
  Function(Map<String, dynamic>)? onBoardUpdated;
  Function()? onGameOverTriggered;
  Function(
    String action,
    double x,
    double y,
    int rotation,
    List<BallColor> colors,
    int dropSeed,
  )? onActivePieceChanged;
  Function(List<dynamic>, int)? onOjamaSpawned;

  static const double constantFallSpeed = 50.0;
  static const double _activePieceSyncInterval = 0.12;
  static const double _ballRadius = 15.0;
  static const double _boardWidth = _ballRadius * 20;

  final List<OjamaBlockComponent> activeOjamaBlocks = [];
  int pendingOjamaSpawns = 0;
  bool isReadyGoText = false;
  double _activePieceSyncCooldown = 0.0;
  bool _hasRemoteOjamaInFlight = false;
  DateTime? _remoteOjamaSpawnedAt;
  async.Timer? _deferredRemoteBoardTimer;
  Map<String, dynamic>? _deferredRemoteBoardState;
  static const Duration _minimumRemoteOjamaVisibleDuration =
      Duration(milliseconds: 180);

  double get currentFallSpeed => isCpuMode || isRemotePlayerMode
      ? constantFallSpeed
      : useConstantFallSpeed
          ? constantFallSpeed
          : scoreManager.currentFallSpeed;

  void startMovingLeft() {
    isMovingLeft = true;
    _notifyActivePieceState(force: true, action: 'start_left');
  }

  void stopMovingLeft() {
    isMovingLeft = false;
    _notifyActivePieceState(force: true, action: 'stop_left');
  }

  void startMovingRight() {
    isMovingRight = true;
    _notifyActivePieceState(force: true, action: 'start_right');
  }

  void stopMovingRight() {
    isMovingRight = false;
    _notifyActivePieceState(force: true, action: 'stop_right');
  }

  void startGame({int? newSeed}) {
    if (newSeed != null) {
      _rng = Random(newSeed);
    }
    syncDropRng = null;
    currentDropSeed = 0;
    _clearLockedBalls();
    _clearHints();
    incomingOjama.clear();

    for (final block in activeOjamaBlocks) {
      if (block.parent != null) {
        remove(block);
      }
    }
    activeOjamaBlocks.clear();
    pendingOjamaSpawns = 0;
    syncDropRng = null;
    _hasRemoteOjamaInFlight = false;
    _remoteOjamaSpawnedAt = null;
    _deferredRemoteBoardTimer?.cancel();
    _deferredRemoteBoardTimer = null;
    _deferredRemoteBoardState = null;

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
    _activePieceSyncCooldown = 0.0;

    gameStateWrapper.value = GameState.playing;
    if (!isRemotePlayerMode) {
      _spawnNewPiece();
    } else {
      _notifyBoardUpdated();
    }
  }

  void gameOver() {
    gameStateWrapper.value = GameState.gameover;
    if (activePiece != null) activePiece!.isLocked = true;
    onGameOverTriggered?.call();
  }

  @override
  Color backgroundColor() => const Color(0xFF101010);

  final Color? wallColor;

  PuzzleGame({
    this.isCpuMode = false,
    this.seed,
    this.autoStart = true,
    this.isRemotePlayerMode = false,
    this.useConstantFallSpeed = false,
    this.wallColor,
  }) {
    _rng = seed != null ? Random(seed) : Random();
    grid = GridSystem(ballRadius: _ballRadius);
    if (isCpuMode && !isRemotePlayerMode) {
      cpuAgent = CPUAgent(this, difficulty: CPUDifficulty.hard);
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _updateGridLayout();

    if (autoStart) {
      startGame();
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _updateGridLayout();
    }
  }

  void _updateGridLayout() {
    final rowHeight = _ballRadius * sqrt(3);
    final boardHeight = (grid.numRows - 1) * rowHeight + _ballRadius * 2;
    // 5virtual rows of padding space above death line but bounded by physics
    final virtualSpace = 5 * rowHeight;
    final maxTop = size.y - boardHeight - 8 - virtualSpace;
    final minTop = size.y < 420 ? 36.0 - virtualSpace : 84.0 - virtualSpace;
    final idealTop = (size.y - boardHeight) * 0.5 + 34 - virtualSpace;
    final top = maxTop >= minTop
        ? idealTop.clamp(minTop, maxTop).toDouble()
        : max(24.0 - virtualSpace, maxTop);

    grid.offset =
        Vector2((size.x - _boardWidth) / 2 + _ballRadius, top + virtualSpace);
    grid.updateBounds();
  }

  Vector2 get _pieceSpawnPosition {
    return Vector2(size.x / 2, max(32.0, grid.offset.y - 50));
  }

  List<BallColor> _generatePieceColors() {
    return List.generate(
        3, (_) => BallColor.values[_rng.nextInt(BallColor.values.length)]);
  }

  void _spawnNewPiece() {
    if (activePiece != null) {
      if (activePiece!.parent != null) remove(activePiece!);
      activePiece = null;
    }
    if (ghostPiece != null) {
      if (ghostPiece!.parent != null) remove(ghostPiece!);
      ghostPiece = null;
    }

    scoreManager.endChain();

    if (nextPieceColors.value.isEmpty) {
      nextPieceColors.value = _generatePieceColors();
    }

    final currentColors = nextPieceColors.value;

    if (!isRemotePlayerMode) {
      currentDropSeed = _rng.nextInt(999999);
      syncDropRng = Random(currentDropSeed);
    }

    activePiece = ActivePieceComponent(
      position: _pieceSpawnPosition,
      ballRadius: _ballRadius,
      fallSpeed: currentFallSpeed,
      presetColors: currentColors,
    )..priority = 10;
    add(activePiece!);

    ghostPiece = ActivePieceComponent(
      position: _pieceSpawnPosition,
      ballRadius: _ballRadius,
      isGhost: true,
      fallSpeed: currentFallSpeed,
      presetColors: currentColors,
    )..priority = 0;
    add(ghostPiece!);

    nextPieceColors.value = _generatePieceColors();
    _notifyActivePieceState(force: true, action: 'spawn');
  }

  @override
  void render(Canvas canvas) {
    canvas.save();

    // The visual top is exactly 5 rows of hexes above the death line.
    // rowHeight = _ballRadius * sqrt(3)
    const rowHeight = _ballRadius * 1.73205;
    final topClipY = grid.offset.y - (rowHeight * 5) - _ballRadius;

    final clipRect = Rect.fromLTRB(
      -1000, // Safe left boundless
      topClipY,
      10000,
      10000,
    );
    canvas.clipRect(clipRect);

    if (wallColor != null) {
      final wallPaint = Paint()
        ..color = wallColor!.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);

      final deathLineY = grid.offset.y - _ballRadius;

      final path = Path();
      path.moveTo(grid.leftWallX, deathLineY);
      path.lineTo(grid.leftWallX, grid.floorY);
      path.lineTo(grid.rightWallX, grid.floorY);
      path.lineTo(grid.rightWallX, deathLineY);

      canvas.drawPath(path, wallPaint);

      final deathLinePaint = Paint()
        ..color = Colors.orangeAccent.withValues(alpha: 0.8)
        ..strokeWidth = 2.0;

      canvas.drawLine(Offset(grid.leftWallX, deathLineY),
          Offset(grid.rightWallX, deathLineY), deathLinePaint);
    }

    super.render(canvas);
    canvas.restore();
  }

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

    if (_activePieceSyncCooldown > 0) {
      _activePieceSyncCooldown = max(0.0, _activePieceSyncCooldown - dt);
    }

    _idleGlowTime += dt;
    if (_idleGlowTime >= _idleGlowInterval) {
      _idleGlowTime = 0.0;
      const colors = BallColor.values;
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
      var comp = HintOutlineComponent(
          position: px, radius: 15.0, hintColor: colors[0].color);
      add(comp);
      _hintComponents.add(comp);
    }
  }

  Future<void> _executeLogicDrop(
      List<Vector2> positions, List<BallColor> colors) async {
    _clearHints();
    for (int i = 0; i < 3; i++) {
      var hex = grid.pixelToHex(positions[i]);
      hex = grid.findNearestEmpty(hex);

      var newBall = BallComponent(
        position: positions[i],
        radius: 15.0,
        ballColor: colors[i],
      );
      newBall.hitOffsetX = positions[i].x - grid.hexToPixel(hex).x;
      add(newBall);
      grid.lockedBalls[hex] = newBall;
    }

    await _processGravityAndMatches();
  }

  bool _isProcessingGravity = false;
  bool _needsGravityRetry = false;

  Future<void> _processGravityAndMatches() async {
    if (_isProcessingGravity) {
      _needsGravityRetry = true;
      return;
    }
    _isProcessingGravity = true;

    try {
      do {
        _needsGravityRetry = false;
        bool hasMatches = true;
        while (hasMatches && gameStateWrapper.value == GameState.playing) {
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
              if (!grid.lockedBalls.containsKey(curr)) continue;
              BallComponent comp = grid.lockedBalls.remove(curr)!;

              HexCoordinate next = _calcNextStep(curr, comp);

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

          if (gameStateWrapper.value != GameState.playing) return;

          var matchResults = grid.findMatchesAndWazas();
          if (matchResults.isEmpty) {
            hasMatches = false;
          } else {
            for (var matchResult in matchResults) {
              var validTargets = matchResult.targets
                  .where((h) => grid.lockedBalls.containsKey(h))
                  .toList();
              if (validTargets.isEmpty) continue;

              scoreManager.addMatch(
                  validTargets.length, matchResult.highestWaza);

              if (matchResult.highestWaza != WazaType.none &&
                  matchResult.wazaPattern.isNotEmpty) {
                if (onWazaFired != null) {
                  onWazaFired!(matchResult.highestWaza, matchResult.wazaColor);
                }
                await _playWazaAnimation(matchResult);
              }

              for (var hex in validTargets) {
                BallComponent? comp = grid.lockedBalls.remove(hex);
                if (comp == null) continue;

                final ringEffect = BallPopRingEffect(
                  position: comp.position.clone(),
                  ringColor: comp.ballColor.glowColor,
                );
                add(ringEffect);

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

        if (gameStateWrapper.value == GameState.playing && !_isSpawning) {
          if (pendingOjamaSpawns > 0 || activeOjamaBlocks.isNotEmpty) {
            return;
          }

          if (isRemotePlayerMode) {
            incomingOjama.clear();
          } else if (incomingOjama.isNotEmpty) {
            var task = incomingOjama.removeFirst();
            _dropOjamaTask(task);
            return;
          }

          bool isGameOver = false;
          for (var hex in grid.lockedBalls.keys) {
            if (hex.row < 0) isGameOver = true;
          }

          if (isGameOver) {
            gameOver();
            return;
          }

          _updateHints();
          _notifyBoardUpdated();

          if (incomingOjama.isNotEmpty) {
            var task = incomingOjama.removeFirst();
            _dropOjamaTask(task);
            return;
          } else if (activePiece == null) {
            _isSpawning = true;
            _spawnNewPiece();
            _isSpawning = false;
          }
        }
      } while (_needsGravityRetry);
    } finally {
      if (activeOjamaBlocks.isEmpty && pendingOjamaSpawns == 0) {
        syncDropRng = null;
      }
      _isProcessingGravity = false;
    }
  }

  void applyRemoteBoardState(Map<String, dynamic> boardData) {
    if (_shouldDeferRemoteBoardState(boardData)) {
      return;
    }

    _clearLockedBalls();
    _clearHints();
    clearRemoteActivePiece();
    _clearActiveOjamaBlocks();

    for (final entry in boardData.entries) {
      final key = entry.key.split(',');
      if (key.length != 2) {
        continue;
      }

      final row = int.tryParse(key[0]);
      final col = int.tryParse(key[1]);
      final colorIndex = switch (entry.value) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };

      if (row == null ||
          col == null ||
          colorIndex == null ||
          colorIndex < 0 ||
          colorIndex >= BallColor.values.length) {
        continue;
      }

      final hex = HexCoordinate(col, row);
      final ball = BallComponent(
        position: grid.hexToPixel(hex),
        radius: 15.0,
        ballColor: BallColor.values[colorIndex],
      );
      add(ball);
      grid.lockedBalls[hex] = ball;
    }

    _updateHints();
  }

  Map<String, dynamic> exportBoardState() {
    return {
      for (final entry in grid.lockedBalls.entries)
        '${entry.key.row},${entry.key.col}': entry.value.ballColor.index,
    };
  }

  void _clearLockedBalls() {
    for (final ball in grid.lockedBalls.values) {
      remove(ball);
    }
    grid.lockedBalls.clear();
  }

  void _clearActiveOjamaBlocks() {
    for (final block in activeOjamaBlocks) {
      if (block.parent != null) {
        remove(block);
      }
    }
    activeOjamaBlocks.clear();
    pendingOjamaSpawns = 0;
    syncDropRng = null;
    _hasRemoteOjamaInFlight = false;
    _remoteOjamaSpawnedAt = null;
    _deferredRemoteBoardTimer?.cancel();
    _deferredRemoteBoardTimer = null;
    _deferredRemoteBoardState = null;
  }

  void _notifyBoardUpdated() {
    if (onBoardUpdated == null) {
      return;
    }
    onBoardUpdated!(exportBoardState());
  }

  void clearRemoteActivePiece() {
    if (activePiece != null && activePiece!.parent != null) {
      remove(activePiece!);
    }
    activePiece = null;
    if (ghostPiece != null && ghostPiece!.parent != null) {
      remove(ghostPiece!);
    }
    ghostPiece = null;
  }

  void spawnRemotePiece(List<BallColor> colors) {
    if (!isRemotePlayerMode) {
      return;
    }

    clearRemoteActivePiece();

    activePiece = ActivePieceComponent(
      position: _pieceSpawnPosition,
      ballRadius: _ballRadius,
      fallSpeed: currentFallSpeed,
      presetColors: colors,
    )..priority = 10;
    add(activePiece!);

    ghostPiece = ActivePieceComponent(
      position: _pieceSpawnPosition,
      ballRadius: _ballRadius,
      isGhost: true,
      fallSpeed: currentFallSpeed,
      presetColors: colors,
    )..priority = 0;
    add(ghostPiece!);
    _updateGhostPosition();
  }

  void prepareSyncedOjamaDrop(int dropSeed) {
    syncDropRng = Random(dropSeed);
  }

  void spawnRemoteOjama(List<dynamic> ojamaData, int dropSeed) {
    if (!isRemotePlayerMode) {
      return;
    }

    prepareSyncedOjamaDrop(dropSeed);
    clearRemoteActivePiece();
    var spawnedAny = false;

    for (final item in ojamaData) {
      if (item is! Map) {
        continue;
      }

      final typeName = item['type'] as String?;
      OjamaType? type;
      for (final candidate in OjamaType.values) {
        if (candidate.name == typeName) {
          type = candidate;
          break;
        }
      }
      final x = _asDouble(item['x']);
      final y = _asDouble(item['y']);
      final colors = _parseBallColors(item['colors']);
      final startColorIndex = _asInt(item['startColor']);
      final itemDropSeed = _asInt(item['dropSeed']);
      if (itemDropSeed != null) {
        syncDropRng = Random(itemDropSeed);
      }

      if (type == null || x == null || y == null || colors.isEmpty) {
        continue;
      }

      final block = OjamaBlockComponent(
        ojamaType: type,
        position: Vector2(x, y),
        startColor: startColorIndex != null &&
                startColorIndex >= 0 &&
                startColorIndex < BallColor.values.length
            ? BallColor.values[startColorIndex]
            : null,
        presetColors: colors,
      );
      activeOjamaBlocks.add(block);
      add(block);
      spawnedAny = true;
    }

    if (spawnedAny) {
      _hasRemoteOjamaInFlight = true;
      _remoteOjamaSpawnedAt = DateTime.now();
    }
  }

  void syncRemoteActivePieceTransform({
    required double x,
    required double y,
    required int rotation,
    double duration = 0.12,
  }) {
    final piece = activePiece;
    if (piece == null) {
      return;
    }

    piece.angle = rotation * (pi / 3);
    piece.add(
      MoveEffect.to(
        Vector2(x, y),
        EffectController(duration: duration, curve: Curves.easeOut),
      ),
    );
    if (ghostPiece != null) {
      ghostPiece!.angle = piece.angle;
    }
  }

  int get activePieceRotation {
    final piece = activePiece;
    if (piece == null) {
      return 0;
    }
    final normalized = (piece.angle / (pi / 3)).round() % 6;
    return normalized < 0 ? normalized + 6 : normalized;
  }

  void _notifyActivePieceState({
    bool force = false,
    String action = 'move',
  }) {
    final piece = activePiece;
    if (piece == null || piece.isLocked || onActivePieceChanged == null) {
      return;
    }

    if (!force && _activePieceSyncCooldown > 0) {
      return;
    }

    _activePieceSyncCooldown = _activePieceSyncInterval;
    onActivePieceChanged!(
      action,
      piece.position.x,
      piece.position.y,
      activePieceRotation,
      List<BallColor>.from(piece.colors),
      currentDropSeed,
    );
  }

  void onOjamaBlockLanded(OjamaBlockComponent block) {
    activeOjamaBlocks.remove(block);
    if (isRemotePlayerMode && activeOjamaBlocks.isEmpty) {
      _hasRemoteOjamaInFlight = false;
      _remoteOjamaSpawnedAt = null;
    }
    _processGravityAndMatches();
  }

  bool _shouldDeferRemoteBoardState(Map<String, dynamic> boardData) {
    if (!isRemotePlayerMode ||
        !_hasRemoteOjamaInFlight ||
        activeOjamaBlocks.isEmpty) {
      return false;
    }

    final spawnedAt = _remoteOjamaSpawnedAt;
    if (spawnedAt == null) {
      return false;
    }

    final elapsed = DateTime.now().difference(spawnedAt);
    final remaining = _minimumRemoteOjamaVisibleDuration - elapsed;
    if (remaining <= Duration.zero) {
      return false;
    }

    _deferredRemoteBoardState = Map<String, dynamic>.from(boardData);
    _deferredRemoteBoardTimer?.cancel();
    _deferredRemoteBoardTimer = async.Timer(remaining, () {
      final deferred = _deferredRemoteBoardState;
      _deferredRemoteBoardState = null;
      _deferredRemoteBoardTimer = null;
      if (deferred != null) {
        applyRemoteBoardState(deferred);
      }
    });
    return true;
  }

  void _dropOjamaTask(OjamaTask task) {
    if (isRemotePlayerMode) {
      incomingOjama.clear();
      return;
    }

    int numSets = 1;
    if (task.type == OjamaType.pyramidSet) numSets = 4;
    if (task.type == OjamaType.hexagonSet) numSets = 6;

    pendingOjamaSpawns += numSets;
    for (int i = 0; i < numSets; i++) {
      Future.delayed(Duration(milliseconds: i == 0 ? 0 : 500 * i), () {
        if (gameStateWrapper.value != GameState.playing) {
          pendingOjamaSpawns--;
          return;
        }
        double spawnX;
        if (task.type == OjamaType.pyramidSet) {
          const cols = [0, 2, 4, 6];
          spawnX = grid.offset.x + cols[i % 4] * 30.0;
        } else if (task.type == OjamaType.hexagonSet) {
          const cols = [0, 3, 6, 1, 4, 7];
          spawnX = grid.offset.x + cols[i % 6] * 30.0;
        } else {
          spawnX = grid.offset.x;
        }

        final colors = _colorsForOjamaSet(task);
        final spawnY = grid.offset.y - 120;
        var block = OjamaBlockComponent(
          ojamaType: task.type,
          position: Vector2(spawnX, spawnY),
          startColor:
              task.type == OjamaType.straightSet ? task.startColor : null,
          presetColors: colors,
        );
        activeOjamaBlocks.add(block);
        add(block);
        final dropSeed = _rng.nextInt(999999);
        syncDropRng = Random(dropSeed);

        final spawnData = <String, dynamic>{
          'type': task.type.name,
          'x': spawnX,
          'y': spawnY,
          'colors': colors.map((color) => color.index).toList(),
          'dropSeed': dropSeed,
        };
        if (task.type == OjamaType.straightSet && task.startColor != null) {
          spawnData['startColor'] = task.startColor!.index;
        }
        onOjamaSpawned?.call([spawnData], dropSeed);
        pendingOjamaSpawns--;
      });
    }
  }

  List<BallColor> _colorsForOjamaSet(OjamaTask task) {
    if (task.type == OjamaType.straightSet) {
      if (task.presetColors != null && task.presetColors!.isNotEmpty) {
        return List<BallColor>.from(task.presetColors!);
      }
      return _generateStraightOjamaColors(task.startColor);
    }

    return _generateMixedOjamaColors();
  }

  List<BallColor> _generateMixedOjamaColors() {
    final colors = List<BallColor>.from(BallColor.values)
      ..add(BallColor.values[_rng.nextInt(BallColor.values.length)])
      ..shuffle(_rng);
    return colors;
  }

  List<BallColor> _generateStraightOjamaColors(BallColor? startColor) {
    const loopColors = [
      BallColor.blue,
      BallColor.purple,
      BallColor.yellow,
      BallColor.red,
      BallColor.green,
    ];
    var bottomStart = startColor == null
        ? _rng.nextInt(loopColors.length)
        : loopColors.indexOf(startColor);
    if (bottomStart == -1) {
      bottomStart = 0;
    }
    final topStart = _rng.nextInt(loopColors.length);
    final colors = <BallColor>[];

    for (var i = 0; i < 10; i++) {
      colors.add(loopColors[(bottomStart + i) % loopColors.length]);
    }
    for (var i = 0; i < 9; i++) {
      colors.add(loopColors[(topStart + i) % loopColors.length]);
    }

    return colors;
  }

  List<BallColor> _parseBallColors(Object? rawColors) {
    final values = switch (rawColors) {
      List list => list,
      Map map => (map.entries.toList()
            ..sort((a, b) => a.key.toString().compareTo(b.key.toString())))
          .map((entry) => entry.value)
          .toList(),
      _ => null,
    };

    if (values == null) {
      return const [];
    }

    return values
        .map(_asInt)
        .whereType<int>()
        .where((index) => index >= 0 && index < BallColor.values.length)
        .map((index) => BallColor.values[index])
        .toList();
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  int? _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  Future<void> _playWazaAnimation(MatchResult matchResult) async {
    final wazaName = _wazaName(matchResult.highestWaza);
    wazaNameNotifier.value = '$wazaName！';

    final sameColorBalls = <BallComponent>[];
    if (matchResult.wazaColor != null) {
      for (var ball in grid.lockedBalls.values) {
        if (ball.ballColor == matchResult.wazaColor &&
            !matchResult.targets.contains(_hexForBall(ball))) {
          ball.isWazaSameColor = true;
          sameColorBalls.add(ball);
        }
      }
    }

    for (var group in matchResult.wazaPattern) {
      for (var hex in group) {
        final ball = grid.lockedBalls[hex];
        if (ball != null) {
          ball.flashGlow();
        }
      }
      await Future.delayed(const Duration(milliseconds: 180));
    }

    await Future.delayed(const Duration(milliseconds: 350));

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
      case WazaType.hexagon:
        return 'HEXAGON';
      case WazaType.pyramid:
        return 'PYRAMID';
      case WazaType.straight:
        return 'STRAIGHT';
      case WazaType.none:
        return '';
    }
  }

  HexCoordinate _calcNextStep(HexCoordinate curr, BallComponent comp) {
    double offsetX = comp.hitOffsetX;

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
          return e!;
        } else {
          if (offsetX == 0.0) {
            final goRight = _deterministicSlideRight(curr, comp);
            return goRight ? b! : c!;
          }
          return (offsetX < 0) ? b! : c!;
        }
      }
    } else if (bEmpty && !cEmpty) {
      if (!aOccupied) return b!;
      if (grid.isOutOfBounds(c)) return b!;
      return curr;
    } else if (!bEmpty && cEmpty) {
      if (!dOccupied) return c!;
      if (grid.isOutOfBounds(b)) return c!;
      return curr;
    }

    return curr;
  }

  bool _deterministicSlideRight(HexCoordinate curr, BallComponent comp) {
    var hash = 17;
    hash = 31 * hash + curr.col;
    hash = 31 * hash + curr.row;
    hash = 31 * hash + comp.ballColor.index;
    hash = 31 * hash + (comp.hitOffsetX * 1000).round();
    return hash.abs() % 2 == 0;
  }

  void rotateLeft() {
    if (activePiece == null || activePiece!.isLocked) return;
    activePiece!.rotateLeft();
    _enforceBounds();
    _notifyActivePieceState(force: true, action: 'rotate_left');
  }

  void rotateRight() {
    if (activePiece == null || activePiece!.isLocked) return;
    activePiece!.rotateRight();
    _enforceBounds();
    _notifyActivePieceState(force: true, action: 'rotate_right');
  }

  void _enforceBounds() {
    if (activePiece == null) return;
    for (var pos in activePiece!.absoluteBallPositions) {
      if (pos.x < grid.offset.x + 0.3) {
        activePiece!.position.x += ((grid.offset.x + 0.3) - pos.x);
      } else if (pos.x > grid.offset.x + 269.7) {
        activePiece!.position.x -= (pos.x - (grid.offset.x + 269.7));
      }
    }
  }

  void hardDrop() {
    if (activePiece == null || activePiece!.isLocked) return;
    if (ghostPiece != null) {
      final dropPositions = ghostPiece!.absoluteBallPositions;
      final pieceColors = activePiece!.colors;

      for (var i = 0; i < dropPositions.length && i < pieceColors.length; i++) {
        final effect = SparkEffect(
          position: dropPositions[i].clone(),
          sparkColor: pieceColors[i].glowColor,
        );
        add(effect);
      }

      activePiece!.position = ghostPiece!.position.clone();
      activePiece!.position.y += 5.0;
      _notifyActivePieceState(force: true, action: 'hard_drop');
    }
  }

  void triggerHardDrop() {
    if (gameStateWrapper.value != GameState.playing || isRemotePlayerMode) {
      return;
    }
    hardDrop();
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (isRemotePlayerMode) {
      return KeyEventResult.ignored;
    }

    if (gameStateWrapper.value != GameState.playing) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        startMovingLeft();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        startMovingRight();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        triggerHardDrop();
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
