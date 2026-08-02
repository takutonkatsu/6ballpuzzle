import 'dart:async' as async;
import 'dart:async' show Completer, unawaited;
import 'dart:math';
import 'dart:collection';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/effects.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_settings.dart';
import '../audio/sfx_player.dart';
import 'components/active_piece_component.dart';
import 'components/ball_component.dart';
import 'components/effect_components.dart';
import 'components/hint_component.dart';
import 'components/ojama_block_component.dart';
import 'grid_system.dart';
import 'score_manager.dart';
import 'cpu_agent.dart';
import 'game_models.dart';
import 'perf_monitor.dart';

enum GameState { title, ready, playing, gameover }

class _QueuedPreviewOjamaTask {
  final OjamaTask task;
  final DateTime readyAt;

  const _QueuedPreviewOjamaTask({
    required this.task,
    required this.readyAt,
  });
}

class _RemoteBoardCell {
  final BallColor color;
  final double hitOffsetX;

  const _RemoteBoardCell({
    required this.color,
    this.hitOffsetX = 0,
  });
}

class _ResolvedDropCell {
  final HexCoordinate hex;
  final Vector2 position;
  final BallColor color;
  final double hitOffsetX;

  const _ResolvedDropCell({
    required this.hex,
    required this.position,
    required this.color,
    required this.hitOffsetX,
  });
}

class _ActiveBallContactState {
  const _ActiveBallContactState({
    required this.isTouching,
    required this.isFallInevitable,
    required this.isPastLockAngle,
    required this.upwardCorrection,
    required this.slideDirection,
    required this.horizontalOffset,
    required this.slideSpeedFactor,
  });

  const _ActiveBallContactState.none()
      : isTouching = false,
        isFallInevitable = false,
        isPastLockAngle = false,
        upwardCorrection = 0.0,
        slideDirection = 0.0,
        horizontalOffset = 0.0,
        slideSpeedFactor = 0.0;

  final bool isTouching;
  final bool isFallInevitable;
  final bool isPastLockAngle;
  final double upwardCorrection;
  final double slideDirection;
  final double horizontalOffset;
  final double slideSpeedFactor;
}

class PuzzleGame extends FlameGame with KeyboardEvents {
  static const String _spawnSfx = '決定ボタンを押す33_スポーン02.mp3';
  static const String _hardDropSfx = 'カーソル移動5_落下02.mp3';
  static const String _landingSfx = 'カーソル移動12_落下.mp3';
  static const String _rotationSfx = 'キャンセル1＿回転01.mp3';
  static const String _ojamaSpawnSfx = 'データ表示3_おじゃまボール.mp3';
  static const String _ojamaBlockSpawnSfx = '決定、ボタン押下34_おじゃまスポーン01.mp3';
  static const String _wazaChargeSfx = 'メニューを開く4_ワザ.mp3';
  static const String _clearSfx = '決定ボタンを押す42_消去03.mp3';
  static const double _sfxVolumeMultiplier = 2.6;

  final bool isCpuMode;
  final int? seed;
  final bool autoStart;
  final bool isRemotePlayerMode;
  final bool useConstantFallSpeed;
  final bool manualPieceSpawning;
  final bool renderDetectedFormationEffects;
  String ballSkinId;
  late Random _rng;
  Random? syncDropRng;
  int currentDropSeed = 0;
  CPUAgent? cpuAgent;
  late GridSystem grid;
  ActivePieceComponent? activePiece;
  ActivePieceComponent? ghostPiece;

  bool _isSpawning = false;
  bool _isRemoved = false;
  final ValueNotifier<GameState> gameStateWrapper =
      ValueNotifier(GameState.title);

  bool isMovingLeft = false;
  bool isMovingRight = false;
  double moveSpeed = 200.0;

  final ValueNotifier<List<BallColor>> nextPieceColors = ValueNotifier([]);

  final ValueNotifier<String?> wazaNameNotifier = ValueNotifier(null);

  final Queue<OjamaTask> incomingOjama = Queue();

  Function(WazaType, BallColor?)? onWazaFired;
  Function(int ballsDestroyed)? onBallsCleared;
  Function(int ballsDestroyed, WazaType highestWaza)? onMatchCleared;
  Function(Map<String, dynamic>)? onBoardUpdated;
  Function(String reason)? onRemoteBoardCorrectionApplied;
  Function()? onGameOverTriggered;
  Function()? onDeathLineCrossed;
  Function(
    String action,
    double x,
    double y,
    int rotation,
    List<BallColor> colors,
    int dropSeed,
    int pieceId,
    int eventSeq,
    List<Map<String, dynamic>>? lockedCells,
  )? onActivePieceChanged;
  Function(List<dynamic>, int)? onOjamaSpawned;

  static const double constantFallSpeed = 15.0;
  static const double _activePieceSyncInterval = 0.08;
  static const double _ballRadius = 15.0;
  static const double _gridUnit = _ballRadius * 2;
  static const double _boardWidth = _ballRadius * 20;
  static const double _contactLockAngle = pi / 6;
  static const double _contactSlideSpeed = 22.0;
  static const double _contactTopSlideSpeedFactor = 0.25;
  static const double _contactTopEpsilon = 0.5;
  static const double _activePieceWallInset = 0.3;
  static const double _wallBlockedSlideLockDelay = 0.3;
  static const double _wallBlockedSlideMoveRatio = 0.25;
  static const double _deathLineYOffset = _gridUnit * 0.05;
  static const double _pieceSpawnRaiseYOffset = _gridUnit * 0.5;
  static const double _ojamaSpawnYOffset = 120 - (_ballRadius * 1.73205);
  static const double _lockedBallFallDuration = 0.105;
  static const double _lockedBallFallMinDuration = 0.085;
  static const double _lockedBallFallAcceleration = 0.0;
  static const Curve _lockedBallFallCurve = Curves.linear;
  static const Duration _defaultHapticCooldown = Duration(milliseconds: 90);

  final List<OjamaBlockComponent> activeOjamaBlocks = [];
  int pendingOjamaSpawns = 0;
  int _pendingOjamaBatchLandings = 0;
  int _ojamaSpawnBatchVersion = 0;
  int _pendingPreviewOjamaSpawns = 0;
  final Queue<_QueuedPreviewOjamaTask> _previewOjamaQueue = Queue();
  bool _isProcessingPreviewOjamaQueue = false;
  bool _autonomousRemotePreviewEnabled = false;
  int _remotePreviewRespawnVersion = 0;
  bool isReadyGoText = false;
  double _activePieceSyncCooldown = 0.0;
  int _nextPieceSyncId = 0;
  int _currentPieceSyncId = 0;
  int _activePieceEventSeq = 0;
  bool _suppressNextLandingSfx = false;
  bool _forceLockNextActivePieceContact = false;
  bool _activePieceWasSupportedByContact = false;
  double _activePieceContactSlideDirection = 0.0;
  double? _remoteTopContactSlideDirection;
  Vector2? _remoteTransformStartPosition;
  Vector2? _remoteTransformTargetPosition;
  double _remoteTransformBlendDuration = 0.0;
  double _remoteTransformBlendElapsed = 0.0;
  double _wallBlockedSlideTime = 0.0;
  bool _ghostPositionDirty = true;
  int _boardVersion = 0;
  int _lastGhostBoardVersion = -1;
  double? _lastGhostPieceX;
  int? _lastGhostRotation;
  bool _hasRemoteOjamaInFlight = false;
  DateTime? _remoteOjamaSpawnedAt;
  bool _isApplyingRemoteHardDrop = false;
  bool _remotePieceAwaitingTerminalLock = false;
  Map<HexCoordinate, _RemoteBoardCell>? _pendingSpectatorBoardState;
  async.Timer? _deferredRemoteBoardTimer;
  Map<String, dynamic>? _deferredRemoteBoardState;
  final Map<String, DateTime> _lastHapticAtByKey = {};
  int _remoteAttackFormationGeneration = 0;
  static const Duration _minimumRemoteOjamaVisibleDuration =
      Duration(milliseconds: 180);
  static const Duration _deathLineTransitionDuration =
      Duration(milliseconds: 650);
  static const double _defaultDeathLineProgress = 0.0;

  double get currentFallSpeed => isCpuMode
      ? (useConstantFallSpeed
          ? constantFallSpeed
          : scoreManager.currentFallSpeed)
      : useConstantFallSpeed
          ? constantFallSpeed
          : scoreManager.currentFallSpeed;

  bool get _playsBoardSfx => true;

  double _deathLineDangerProgress = _defaultDeathLineProgress;
  async.Timer? _deathLineTransitionTimer;

  void _playSfx(String fileName, {double volume = 1.0}) {
    final masterVolume = AppSettings.instance.sfxVolume.value;
    final adjustedVolume =
        (volume * _sfxVolumeMultiplier * masterVolume).clamp(0.0, 1.0);
    unawaited(_playSfxSafely(fileName, volume: adjustedVolume));
  }

  Future<void> _playSfxSafely(String fileName, {double volume = 1.0}) async {
    try {
      await SfxPlayer.play(fileName, volume: volume);
    } catch (_) {
      // SE再生失敗でゲーム進行を止めない。
    }
  }

  bool get _shouldPlayHaptics => !isCpuMode && !isRemotePlayerMode;

  void _triggerHapticFeedback(Future<void> Function() action) {
    if (!_shouldPlayHaptics) {
      return;
    }
    unawaited(_triggerHapticFeedbackSafely(action));
  }

  void _triggerThrottledHapticFeedback(
    String key,
    Future<void> Function() action, {
    Duration cooldown = _defaultHapticCooldown,
  }) {
    if (!_shouldPlayHaptics) {
      return;
    }
    final now = DateTime.now();
    final last = _lastHapticAtByKey[key];
    if (last != null && now.difference(last) < cooldown) {
      return;
    }
    _lastHapticAtByKey[key] = now;
    unawaited(_triggerHapticFeedbackSafely(action));
  }

  Future<void> _triggerHapticFeedbackSafely(
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      // バイブ非対応環境でもゲーム進行を止めない。
    }
  }

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

  void _markBoardChanged() {
    _boardVersion++;
    _markGhostPositionDirty();
  }

  void _markGhostPositionDirty() {
    _ghostPositionDirty = true;
  }

  void refreshGhostPositionForCurrentPiece() {
    _markGhostPositionDirty();
    _updateGhostPosition();
  }

  void startGame({int? newSeed, bool spawnInitialPiece = true}) {
    if (newSeed != null) {
      _rng = Random(newSeed);
    }
    syncDropRng = null;
    currentDropSeed = 0;
    _clearAllBoardComponents();
    _markBoardChanged();
    _clearHints();
    incomingOjama.clear();

    for (final block in activeOjamaBlocks) {
      if (block.parent != null) {
        remove(block);
      }
    }
    activeOjamaBlocks.clear();
    pendingOjamaSpawns = 0;
    _pendingOjamaBatchLandings = 0;
    _ojamaSpawnBatchVersion++;
    _pendingPreviewOjamaSpawns = 0;
    _previewOjamaQueue.clear();
    _isProcessingPreviewOjamaQueue = false;
    _autonomousRemotePreviewEnabled = false;
    _remotePreviewRespawnVersion++;
    syncDropRng = null;
    _hasRemoteOjamaInFlight = false;
    _remoteOjamaSpawnedAt = null;
    _deferredRemoteBoardTimer?.cancel();
    _deferredRemoteBoardTimer = null;
    _deferredRemoteBoardState = null;
    _needsMatchResolutionRetry = false;
    _deathLineTransitionTimer?.cancel();
    _deathLineTransitionTimer = null;
    _deathLineDangerProgress = _defaultDeathLineProgress;

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
    _forceLockNextActivePieceContact = false;
    _activePieceWasSupportedByContact = false;
    _activePieceContactSlideDirection = 0.0;
    _remoteTopContactSlideDirection = null;
    _remotePieceAwaitingTerminalLock = false;
    _clearRemoteTransformBlend();
    _wallBlockedSlideTime = 0.0;
    _markGhostPositionDirty();

    gameStateWrapper.value = GameState.playing;
    if (!isRemotePlayerMode && spawnInitialPiece) {
      _spawnNewPiece();
    } else {
      _notifyBoardUpdated();
    }
  }

  void simulateOjamaTaskOnPreview(OjamaTask task) {
    if (!isRemotePlayerMode) {
      return;
    }
    _autonomousRemotePreviewEnabled = true;
    _remotePreviewRespawnVersion++;
    _pendingPreviewOjamaSpawns += _ojamaSetCountFor(task);
    _previewOjamaQueue.add(
      _QueuedPreviewOjamaTask(
        task: _cloneOjamaTask(task),
        readyAt: DateTime.now().add(const Duration(seconds: 2)),
      ),
    );
    unawaited(_drainPreviewOjamaQueue());
  }

  OjamaTask _cloneOjamaTask(OjamaTask task) {
    return OjamaTask(
      task.type,
      startColor: task.startColor,
      presetColors: task.presetColors == null
          ? null
          : List<BallColor>.from(task.presetColors!),
      ballSkinId: task.ballSkinId,
      effectSkinId: task.effectSkinId,
    );
  }

  Future<void> _drainPreviewOjamaQueue() async {
    if (!isRemotePlayerMode || _isProcessingPreviewOjamaQueue) {
      return;
    }

    _isProcessingPreviewOjamaQueue = true;
    try {
      while (_previewOjamaQueue.isNotEmpty &&
          gameStateWrapper.value == GameState.playing) {
        final queuedTask = _previewOjamaQueue.removeFirst();
        final waitDuration = queuedTask.readyAt.difference(DateTime.now());
        if (waitDuration > Duration.zero) {
          await Future<void>.delayed(waitDuration);
        }
        if (gameStateWrapper.value != GameState.playing) {
          return;
        }

        await _waitForRemotePieceSettlement();
        if (gameStateWrapper.value != GameState.playing) {
          return;
        }

        final numSets = _ojamaSetCountFor(queuedTask.task);
        await _runPreviewOjamaSequence(queuedTask.task, numSets);
      }
    } finally {
      _isProcessingPreviewOjamaQueue = false;
    }
  }

  int _ojamaSetCountFor(OjamaTask task) {
    if (task.type == OjamaType.pyramidSet) {
      return 4;
    }
    if (task.type == OjamaType.hexagonSet) {
      return 6;
    }
    return 1;
  }

  Future<void> _runPreviewOjamaSequence(OjamaTask task, int numSets) async {
    clearRemoteActivePiece();

    for (var i = 0; i < numSets; i++) {
      if (gameStateWrapper.value != GameState.playing) {
        return;
      }

      clearRemoteActivePiece();
      final block = _buildPreviewOjamaBlock(task, i);
      activeOjamaBlocks.add(block);
      add(block);
      if (i == 0 && _playsBoardSfx) {
        _playSfx(_ojamaSpawnSfx, volume: 0.9);
      }
      if (_playsBoardSfx) {
        _playSfx(_ojamaBlockSpawnSfx, volume: 0.41);
      }
      _triggerThrottledHapticFeedback(
        'preview_ojama_spawn',
        HapticFeedback.heavyImpact,
        cooldown: const Duration(milliseconds: 240),
      );

      _pendingPreviewOjamaSpawns = max(0, _pendingPreviewOjamaSpawns - 1);
      if (i < numSets - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  OjamaBlockComponent _buildPreviewOjamaBlock(OjamaTask task, int index) {
    double spawnX;
    if (task.type == OjamaType.pyramidSet) {
      const cols = [0, 2, 4, 6];
      spawnX = grid.offset.x + cols[index % 4] * 30.0;
    } else if (task.type == OjamaType.hexagonSet) {
      const cols = [0, 3, 6, 1, 4, 7];
      spawnX = grid.offset.x + cols[index % 6] * 30.0;
    } else {
      spawnX = grid.offset.x;
    }

    return OjamaBlockComponent(
      ojamaType: task.type,
      position: Vector2(spawnX, grid.offset.y - _ojamaSpawnYOffset),
      startColor: task.type == OjamaType.straightSet ? task.startColor : null,
      presetColors: _colorsForOjamaSet(task),
      ballSkinId: ballSkinId,
      effectSkinId: task.effectSkinId,
    );
  }

  Future<void> _waitForRemotePieceSettlement() async {
    if (!isRemotePlayerMode) {
      return;
    }
    while (gameStateWrapper.value == GameState.playing) {
      if (activePiece == null || activePiece!.isLocked) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  void gameOver() {
    gameStateWrapper.value = GameState.gameover;
    if (activePiece != null) activePiece!.isLocked = true;
    onGameOverTriggered?.call();
  }

  void freezeToBoardOnly() {
    if (_isRemoved) {
      return;
    }
    gameStateWrapper.value = GameState.gameover;
    cpuAgent?.stop();
    cpuAgent = null;
    isMovingLeft = false;
    isMovingRight = false;
    _activePieceSyncCooldown = 0.0;
    _isSpawning = false;
    _forceLockNextActivePieceContact = false;
    _activePieceWasSupportedByContact = false;
    _wallBlockedSlideTime = 0.0;
    _previewOjamaQueue.clear();
    _isProcessingPreviewOjamaQueue = false;
    _pendingPreviewOjamaSpawns = 0;
    _autonomousRemotePreviewEnabled = false;
    _hasRemoteOjamaInFlight = false;
    _remoteOjamaSpawnedAt = null;
    _deferredRemoteBoardTimer?.cancel();
    _deferredRemoteBoardTimer = null;
    _deferredRemoteBoardState = null;
    _deathLineTransitionTimer?.cancel();
    _deathLineTransitionTimer = null;
    _deathLineDangerProgress = _defaultDeathLineProgress;
    incomingOjama.clear();
    pendingOjamaSpawns = 0;
    _pendingOjamaBatchLandings = 0;

    if (activePiece?.parent != null) {
      activePiece!.removeFromParent();
    }
    if (ghostPiece?.parent != null) {
      ghostPiece!.removeFromParent();
    }
    activePiece = null;
    ghostPiece = null;
    _remotePieceAwaitingTerminalLock = false;

    for (final block in List<OjamaBlockComponent>.from(activeOjamaBlocks)) {
      if (block.parent != null) {
        block.removeFromParent();
      }
    }
    activeOjamaBlocks.clear();

    for (final component in children.whereType<BallPopRingEffect>().toList()) {
      component.removeFromParent();
    }
    for (final component in children.whereType<SparkEffect>().toList()) {
      component.removeFromParent();
    }
    for (final component
        in children.whereType<HintOutlineComponent>().toList()) {
      component.removeFromParent();
    }

    pauseEngine();
  }

  @override
  void onRemove() {
    if (_isRemoved) {
      super.onRemove();
      return;
    }
    freezeToBoardOnly();
    _clearAllBoardComponents();
    onWazaFired = null;
    onBallsCleared = null;
    onMatchCleared = null;
    onBoardUpdated = null;
    onRemoteBoardCorrectionApplied = null;
    onGameOverTriggered = null;
    onDeathLineCrossed = null;
    onActivePieceChanged = null;
    onOjamaSpawned = null;
    gameStateWrapper.dispose();
    nextPieceColors.dispose();
    wazaNameNotifier.dispose();
    scoreManager.dispose();
    _isRemoved = true;
    super.onRemove();
  }

  void setDeathLineDangerProgress(double progress) {
    _deathLineDangerProgress = progress.clamp(0.0, 1.0);
  }

  bool get hasOverflowedDeathLine =>
      grid.lockedBalls.keys.any((hex) => hex.row < 0);

  bool get hasActiveOjamaAnimation => activeOjamaBlocks.isNotEmpty;

  bool get hasPendingPreviewOjamaSpawns => _pendingPreviewOjamaSpawns > 0;

  bool get isBoardProcessing =>
      activePiece != null ||
      _isProcessingGravity ||
      _needsGravityRetry ||
      _needsMatchResolutionRetry ||
      pendingOjamaSpawns > 0 ||
      activeOjamaBlocks.isNotEmpty;

  Future<void> animateDeathLineToRed({
    Duration duration = _deathLineTransitionDuration,
  }) async {
    _deathLineTransitionTimer?.cancel();
    if (duration <= Duration.zero) {
      _deathLineDangerProgress = 1.0;
      return;
    }

    final completer = Completer<void>();
    final totalMicros = duration.inMicroseconds;
    const tick = Duration(milliseconds: 16);
    final startedAt = DateTime.now();
    _deathLineTransitionTimer = async.Timer.periodic(tick, (timer) {
      final elapsedMicros = DateTime.now()
          .difference(startedAt)
          .inMicroseconds
          .clamp(0, totalMicros)
          .toInt();
      final t = elapsedMicros / totalMicros;
      _deathLineDangerProgress = Curves.easeOutCubic.transform(t);
      if (elapsedMicros >= totalMicros) {
        timer.cancel();
        _deathLineTransitionTimer = null;
        _deathLineDangerProgress = 1.0;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    return completer.future;
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
    this.manualPieceSpawning = false,
    this.renderDetectedFormationEffects = true,
    this.wallColor,
    this.ballSkinId = 'default',
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
    _snapLockedBallsToGrid();
    _updateGhostPosition();
    _updateHints();
  }

  void _snapLockedBallsToGrid() {
    for (final entry in grid.lockedBalls.entries) {
      _settleLockedBallVisual(entry.value, grid.hexToPixel(entry.key));
      entry.value.hitOffsetX = 0;
    }
  }

  Vector2 get _pieceSpawnPosition {
    return Vector2(
      size.x / 2 + _gridUnit * 0.1,
      max(32.0, grid.offset.y - 50 - _pieceSpawnRaiseYOffset),
    );
  }

  List<BallColor> _generatePieceColors() {
    return List.generate(
        3, (_) => BallColor.values[_rng.nextInt(BallColor.values.length)]);
  }

  void _spawnNewPiece() {
    if (gameStateWrapper.value != GameState.playing) {
      return;
    }
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
      _currentPieceSyncId = ++_nextPieceSyncId;
      _activePieceEventSeq = 0;
    }

    activePiece = ActivePieceComponent(
      position: _pieceSpawnPosition,
      ballRadius: _ballRadius,
      fallSpeed: currentFallSpeed,
      presetColors: currentColors,
      ballSkinId: ballSkinId,
    )..priority = 10;
    add(activePiece!);
    _markGhostPositionDirty();
    _forceLockNextActivePieceContact = false;
    _activePieceWasSupportedByContact = false;
    _activePieceContactSlideDirection = 0.0;
    _remoteTopContactSlideDirection = null;
    _wallBlockedSlideTime = 0.0;

    ghostPiece = ActivePieceComponent(
      position: _pieceSpawnPosition,
      ballRadius: _ballRadius,
      isGhost: true,
      fallSpeed: currentFallSpeed,
      presetColors: currentColors,
      ballSkinId: ballSkinId,
    )..priority = 0;
    add(ghostPiece!);
    _markGhostPositionDirty();

    nextPieceColors.value = _generatePieceColors();
    if (_playsBoardSfx) {
      _playSfx(_spawnSfx, volume: 0.53);
    }
    _notifyActivePieceState(force: true, action: 'spawn');
  }

  void spawnInitialPieceAfterReadyGo() {
    if (isRemotePlayerMode || activePiece != null) {
      return;
    }
    _spawnNewPiece();
  }

  void loadFixedBoard(Map<HexCoordinate, BallColor> balls) {
    if (gameStateWrapper.value != GameState.playing) {
      gameStateWrapper.value = GameState.playing;
    }
    _clearLockedBalls();
    _clearHints();
    _clearActiveOjamaBlocks();
    if (activePiece?.parent != null) {
      activePiece!.removeFromParent();
    }
    if (ghostPiece?.parent != null) {
      ghostPiece!.removeFromParent();
    }
    activePiece = null;
    ghostPiece = null;

    for (final entry in balls.entries) {
      final ball = BallComponent(
        position: grid.hexToPixel(entry.key),
        radius: _ballRadius,
        ballColor: entry.value,
        ballSkinId: ballSkinId,
      );
      add(ball);
      grid.lockedBalls[entry.key] = ball;
    }
    _markBoardChanged();
    _updateHints();
    _notifyBoardUpdated();
  }

  void spawnFixedPiece({
    required List<BallColor> colors,
    required int column,
    int rotation = 0,
    double fallSpeed = 0,
  }) {
    if (gameStateWrapper.value != GameState.playing) {
      gameStateWrapper.value = GameState.playing;
    }
    if (activePiece?.parent != null) {
      activePiece!.removeFromParent();
    }
    if (ghostPiece?.parent != null) {
      ghostPiece!.removeFromParent();
    }
    final spawnPosition = _pieceSpawnPositionForColumn(column);
    activePiece = ActivePieceComponent(
      position: spawnPosition,
      ballRadius: _ballRadius,
      fallSpeed: fallSpeed,
      presetColors: colors,
      ballSkinId: ballSkinId,
    )..priority = 10;
    activePiece!.setRotationIndex(rotation);
    add(activePiece!);
    _forceLockNextActivePieceContact = false;
    _activePieceWasSupportedByContact = false;
    _activePieceContactSlideDirection = 0.0;
    _remoteTopContactSlideDirection = null;
    _wallBlockedSlideTime = 0.0;

    ghostPiece = ActivePieceComponent(
      position: spawnPosition.clone(),
      ballRadius: _ballRadius,
      isGhost: true,
      fallSpeed: fallSpeed,
      presetColors: colors,
    )..priority = 0;
    ghostPiece!.setRotationIndex(rotation);
    add(ghostPiece!);
    _updateGhostPosition();
    _notifyActivePieceState(force: true, action: 'spawn');
  }

  void moveFixedPieceByColumns(int delta) {
    if (activePiece == null || activePiece!.isLocked) {
      return;
    }
    final currentColumn = activePieceColumn;
    setFixedPieceColumn((currentColumn + delta).clamp(0, 8));
    _notifyActivePieceState(
      force: true,
      action: delta < 0 ? 'start_left' : 'start_right',
    );
  }

  double? get activePieceX => activePiece?.position.x;
  double get boardOriginX => grid.offset.x;
  double get boardOriginY => grid.offset.y;

  void setFixedPieceX(double x) {
    if (activePiece == null || activePiece!.isLocked) {
      return;
    }
    activePiece!.position.x = x;
    if (ghostPiece != null) {
      ghostPiece!.position.x = x;
    }
    _markGhostPositionDirty();
    _enforceBounds();
    _updateGhostPosition();
    _notifyActivePieceState(force: true, action: 'set_x');
  }

  void snapCpuPieceXBeforeDrop(double x) {
    if (activePiece == null || activePiece!.isLocked) {
      return;
    }
    activePiece!.position.x = x;
    _markGhostPositionDirty();
    _enforceBounds();
    _updateGhostPosition();
  }

  void snapCpuPieceTransformBeforeDrop({
    required double x,
    required int rotation,
  }) {
    if (activePiece == null || activePiece!.isLocked) {
      return;
    }
    activePiece!.position.x = x;
    activePiece!.setRotationIndex(rotation);
    if (ghostPiece != null) {
      ghostPiece!.setRotationIndex(rotation);
    }
    _markGhostPositionDirty();
    _enforceBounds();
    _updateGhostPosition();
  }

  void setFixedPieceColumn(int column) {
    if (activePiece == null || activePiece!.isLocked) {
      return;
    }
    final nextX = _pieceSpawnPositionForColumn(column).x;
    activePiece!.position.x = nextX;
    if (ghostPiece != null) {
      ghostPiece!.position.x = nextX;
    }
    _markGhostPositionDirty();
    _enforceBounds();
    _updateGhostPosition();
  }

  int get activePieceColumn {
    if (activePiece == null) {
      return 0;
    }
    final raw =
        ((activePiece!.position.x - grid.offset.x) / (_ballRadius * 2)).round();
    return raw.clamp(0, 8);
  }

  int get activePieceRotationIndex => activePiece?.logicalRotationIndex ?? 0;

  Future<void> dropFixedPieceToHexes(List<HexCoordinate> targets) async {
    if (activePiece == null || activePiece!.isLocked || targets.length < 3) {
      return;
    }
    final colors = activePiece!.colors.toList(growable: false);
    final positions = [
      for (final target in targets.take(colors.length)) grid.hexToPixel(target),
    ];

    for (var i = 0; i < positions.length && i < colors.length; i++) {
      add(
        SparkEffect(
          position: positions[i].clone(),
          sparkColor: colors[i].glowColor,
        ),
      );
    }
    if (_playsBoardSfx) {
      _playSfx(_hardDropSfx, volume: 0.85);
    }
    _triggerHapticFeedback(HapticFeedback.heavyImpact);
    _notifyActivePieceState(force: true, action: 'hard_drop');

    if (activePiece?.parent != null) {
      activePiece!.removeFromParent();
    }
    if (ghostPiece?.parent != null) {
      ghostPiece!.removeFromParent();
    }
    activePiece = null;
    ghostPiece = null;
    await _executeLogicDrop(
      positions,
      colors,
      lockedHexes: targets.take(colors.length).toList(growable: false),
    );
  }

  Vector2 _pieceSpawnPositionForColumn(int column) {
    final spawn = _pieceSpawnPosition;
    final rowOffset = grid.hexToPixel(HexCoordinate(column.clamp(0, 8), 0));
    spawn.x = rowOffset.x;
    return spawn;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();

    // The visual top is exactly 5 rows of hexes above the death line.
    // rowHeight = _ballRadius * sqrt(3)
    const rowHeight = _ballRadius * 1.73205;
    final deathLineY = grid.offset.y - _ballRadius + _deathLineYOffset;
    final topClipY = deathLineY - (rowHeight * 5);

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

      final path = Path();
      path.moveTo(grid.leftWallX, deathLineY);
      path.lineTo(grid.leftWallX, grid.floorY);
      path.lineTo(grid.rightWallX, grid.floorY);
      path.lineTo(grid.rightWallX, deathLineY);

      canvas.drawPath(path, wallPaint);
    }

    super.render(canvas);

    if (wallColor != null) {
      final lineColor = Color.lerp(
            Colors.white,
            Colors.red,
            _deathLineDangerProgress,
          ) ??
          Colors.white;
      final deathLinePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 3.4;

      canvas.drawLine(Offset(grid.leftWallX, deathLineY),
          Offset(grid.rightWallX, deathLineY), deathLinePaint);
    }

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
      final beforeX = activePiece!.position.x;
      if (isMovingLeft && !isMovingRight) {
        activePiece!.position.x -= moveSpeed * dt;
      } else if (isMovingRight && !isMovingLeft) {
        activePiece!.position.x += moveSpeed * dt;
      }
      _enforceBounds();
      if ((activePiece!.position.x - beforeX).abs() > 0.01) {
        _markGhostPositionDirty();
        if (!isRemotePlayerMode) {
          _notifyActivePieceState(action: 'move');
        }
      }
    }

    _applyRemoteTransformBlend(dt);
    _updateGhostPosition();
    _checkActivePieceCollision(dt);
  }

  void _updateGhostPosition() {
    if (activePiece == null || ghostPiece == null) return;

    final rotation = activePieceRotation;
    if (!_ghostPositionDirty &&
        _lastGhostBoardVersion == _boardVersion &&
        _lastGhostPieceX != null &&
        (_lastGhostPieceX! - activePiece!.position.x).abs() <= 0.01 &&
        _lastGhostRotation == rotation) {
      return;
    }

    final stopwatch = PerfMonitor.enabled ? (Stopwatch()..start()) : null;
    ghostPiece!.setRotationIndex(rotation);
    ghostPiece!.position = activePiece!.position.clone();

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
    _ghostPositionDirty = false;
    _lastGhostBoardVersion = _boardVersion;
    _lastGhostPieceX = activePiece!.position.x;
    _lastGhostRotation = rotation;
    if (stopwatch != null) {
      PerfMonitor.logDuration('ghost.update', stopwatch, warnMs: 3);
    }
  }

  void _checkActivePieceCollision(double dt) {
    if (activePiece == null || activePiece!.isLocked) return;

    final previousContactSlideDirection = _activePieceContactSlideDirection;
    var shouldLock = false;
    var hasContactSupport = false;
    var upwardCorrection = 0.0;
    var slideDirection = 0.0;
    var slideSpeedFactor = 0.0;
    var strongestSlideOffset = 0.0;
    var contactAdjustedPiece = false;
    var positions = activePiece!.absoluteBallPositions;
    final colors = activePiece!.colors;

    for (var i = 0; i < positions.length; i++) {
      final pos = positions[i];
      if (pos.y + _ballRadius >= grid.floorY) {
        shouldLock = true;
        break;
      }
      for (var locked in grid.lockedBalls.values) {
        final contact = _activeBallContactState(pos, colors[i], locked);
        if (!contact.isTouching) {
          continue;
        }
        if (_forceLockNextActivePieceContact ||
            contact.isFallInevitable ||
            contact.isPastLockAngle) {
          shouldLock = true;
          break;
        }
        hasContactSupport = true;
        upwardCorrection = max(upwardCorrection, contact.upwardCorrection);
        if (contact.horizontalOffset > strongestSlideOffset ||
            slideDirection == 0.0) {
          strongestSlideOffset = contact.horizontalOffset;
          slideDirection = contact.slideDirection;
          slideSpeedFactor = contact.slideSpeedFactor;
        }
      }
      if (shouldLock) {
        break;
      }
    }

    if (!shouldLock &&
        !hasContactSupport &&
        _activePieceWasSupportedByContact) {
      shouldLock = true;
    }

    if (!shouldLock && upwardCorrection > 0) {
      activePiece!.position.y -= upwardCorrection;
      positions = activePiece!.absoluteBallPositions;
      _updateGhostPosition();
      contactAdjustedPiece = true;
    }

    if (!shouldLock && hasContactSupport && slideDirection != 0) {
      final beforeX = activePiece!.position.x;
      final intendedMove =
          slideDirection * _contactSlideSpeed * slideSpeedFactor * dt;
      activePiece!.position.x += intendedMove;
      _enforceBounds();
      final actualMove = activePiece!.position.x - beforeX;
      if (actualMove.abs() > 0.01) {
        contactAdjustedPiece = true;
      }
      final slideBlockedByWall = intendedMove.abs() > 0 &&
          (actualMove.sign != intendedMove.sign ||
              actualMove.abs() <
                  intendedMove.abs() * _wallBlockedSlideMoveRatio);
      if (slideBlockedByWall) {
        _wallBlockedSlideTime += dt;
        if (_wallBlockedSlideTime >= _wallBlockedSlideLockDelay) {
          shouldLock = true;
        }
      } else {
        _wallBlockedSlideTime = 0.0;
      }
      positions = activePiece!.absoluteBallPositions;
      _updateGhostPosition();
    } else {
      _wallBlockedSlideTime = 0.0;
    }

    _activePieceWasSupportedByContact = !shouldLock && hasContactSupport;
    _activePieceContactSlideDirection =
        _activePieceWasSupportedByContact ? slideDirection : 0.0;
    if (!shouldLock && contactAdjustedPiece) {
      final slideDirectionChanged = previousContactSlideDirection.sign !=
          _activePieceContactSlideDirection.sign;
      _notifyActivePieceState(
        force: slideDirectionChanged,
        action: 'contact_slide',
      );
    }

    if (shouldLock) {
      if (isRemotePlayerMode && !_isApplyingRemoteHardDrop) {
        activePiece?.isLocked = true;
        ghostPiece?.isLocked = true;
        _remotePieceAwaitingTerminalLock = true;
        isMovingLeft = false;
        isMovingRight = false;
        _activePieceWasSupportedByContact = false;
        _activePieceContactSlideDirection = 0.0;
        _remoteTopContactSlideDirection = null;
        _wallBlockedSlideTime = 0.0;
        return;
      }
      final oldActive = activePiece!;
      final oldGhost = ghostPiece;

      _notifyActivePieceState(force: true, action: 'lock');

      oldActive.isLocked = true;
      remove(oldActive);
      if (oldGhost != null) {
        remove(oldGhost);
      }

      activePiece = null;
      ghostPiece = null;
      _clearRemoteTransformBlend();
      _forceLockNextActivePieceContact = false;
      _activePieceWasSupportedByContact = false;
      _activePieceContactSlideDirection = 0.0;
      _remoteTopContactSlideDirection = null;
      _wallBlockedSlideTime = 0.0;

      _executeLogicDrop(positions, colors);
    }
  }

  _ActiveBallContactState _activeBallContactState(
    Vector2 activePosition,
    BallColor activeColor,
    BallComponent lockedBall,
  ) {
    const diameter = _ballRadius * 2;
    final lockedPosition = lockedBall.position;
    final dx = activePosition.x - lockedPosition.x;
    if (dx.abs() >= diameter) {
      return const _ActiveBallContactState.none();
    }
    final dy = activePosition.y - lockedPosition.y;
    final distanceSquared = dx * dx + dy * dy;
    if (distanceSquared > diameter * diameter) {
      return const _ActiveBallContactState.none();
    }

    final surfaceY = lockedPosition.y - sqrt(diameter * diameter - dx * dx);
    final lockOffset = diameter * sin(_contactLockAngle);
    final isAboveCenter = activePosition.y < lockedPosition.y;
    final isTopContact = dx.abs() <= _contactTopEpsilon;
    final slideDirection = isTopContact
        ? _topContactSlideDirection(activePosition, activeColor, lockedBall)
        : dx.sign;
    final slideSpeedFactor = isTopContact
        ? _contactTopSlideSpeedFactor
        : (dx.abs() / lockOffset).clamp(0.2, 1.0);
    return _ActiveBallContactState(
      isTouching: true,
      isFallInevitable: !isAboveCenter,
      isPastLockAngle: isAboveCenter && dx.abs() > lockOffset,
      upwardCorrection: max(0.0, activePosition.y - surfaceY),
      slideDirection: slideDirection,
      horizontalOffset: isTopContact ? _contactTopEpsilon : dx.abs(),
      slideSpeedFactor: slideSpeedFactor,
    );
  }

  double _topContactSlideDirection(
    Vector2 activePosition,
    BallColor activeColor,
    BallComponent lockedBall,
  ) {
    final remoteDirection = _remoteTopContactSlideDirection;
    if (isRemotePlayerMode && remoteDirection != null && remoteDirection != 0) {
      return remoteDirection.sign.toDouble();
    }
    if (isMovingLeft && !isMovingRight) {
      return -1.0;
    }
    if (isMovingRight && !isMovingLeft) {
      return 1.0;
    }
    return _deterministicTopContactSlideRight(
      activePosition,
      activeColor,
      lockedBall,
    )
        ? 1.0
        : -1.0;
  }

  bool _deterministicTopContactSlideRight(
    Vector2 activePosition,
    BallColor activeColor,
    BallComponent lockedBall,
  ) {
    var hash = 17;
    hash = 31 * hash + activePosition.x.round();
    hash = 31 * hash + activePosition.y.round();
    hash = 31 * hash + activeColor.index;
    hash = 31 * hash + lockedBall.position.x.round();
    hash = 31 * hash + lockedBall.position.y.round();
    hash = 31 * hash + lockedBall.ballColor.index;
    return hash.abs() % 2 == 0;
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
    List<Vector2> positions,
    List<BallColor> colors, {
    List<HexCoordinate>? lockedHexes,
    List<Map<String, dynamic>>? lockedCells,
  }) async {
    _clearHints();
    final resolvedCells = lockedCells != null && lockedCells.isNotEmpty
        ? _resolveDropCellsFromLockedPayload(colors, lockedCells)
        : lockedHexes == null
            ? _resolveDropCells(positions, colors)
            : _resolveDropCellsFromLockedHexes(positions, colors, lockedHexes);

    for (final cell in resolvedCells) {
      final existingBall = grid.lockedBalls.remove(cell.hex);
      if (existingBall != null && existingBall.parent != null) {
        existingBall.removeFromParent();
      }
      var newBall = BallComponent(
        position: cell.position,
        radius: 15.0,
        ballColor: cell.color,
        ballSkinId: ballSkinId,
      );
      newBall.hitOffsetX = cell.hitOffsetX;
      add(newBall);
      grid.lockedBalls[cell.hex] = newBall;
    }
    _markBoardChanged();

    if (_playsBoardSfx && !_suppressNextLandingSfx) {
      _playSfx(_landingSfx, volume: 0.33);
    }
    _suppressNextLandingSfx = false;

    await _processGravityAndMatches();
    if (isRemotePlayerMode && _autonomousRemotePreviewEnabled) {
      _scheduleRemotePreviewRespawn();
    }
  }

  List<_ResolvedDropCell> _resolveDropCells(
    List<Vector2> positions,
    List<BallColor> colors,
  ) {
    final resolved = <_ResolvedDropCell>[];
    final reserved = <HexCoordinate>{};
    final count = min(positions.length, colors.length);
    for (var i = 0; i < count; i++) {
      final hex = _findNearestEmptyForDrop(
        grid.pixelToHex(positions[i]),
        reserved,
      );
      reserved.add(hex);
      resolved.add(
        _ResolvedDropCell(
          hex: hex,
          position: positions[i].clone(),
          color: colors[i],
          hitOffsetX: positions[i].x - grid.hexToPixel(hex).x,
        ),
      );
    }
    return resolved;
  }

  List<_ResolvedDropCell> _resolveDropCellsFromLockedHexes(
    List<Vector2> positions,
    List<BallColor> colors,
    List<HexCoordinate> lockedHexes,
  ) {
    final resolved = <_ResolvedDropCell>[];
    final count = min(min(positions.length, colors.length), lockedHexes.length);
    for (var i = 0; i < count; i++) {
      final hex = lockedHexes[i];
      resolved.add(
        _ResolvedDropCell(
          hex: hex,
          position: positions[i].clone(),
          color: colors[i],
          hitOffsetX: positions[i].x - grid.hexToPixel(hex).x,
        ),
      );
    }
    return resolved;
  }

  List<_ResolvedDropCell> _resolveDropCellsFromLockedPayload(
    List<BallColor> colors,
    List<Map<String, dynamic>> lockedCells,
  ) {
    final resolved = <_ResolvedDropCell>[];
    final count = min(colors.length, lockedCells.length);
    for (var i = 0; i < count; i++) {
      final raw = lockedCells[i];
      final row = _asInt(raw['row']);
      final col = _asInt(raw['col']);
      if (row == null || col == null) {
        continue;
      }
      final hex = HexCoordinate(col, row);
      final hitOffsetX = _asDouble(raw['hitOffsetX']) ?? 0.0;
      final basePosition = grid.hexToPixel(hex);
      resolved.add(
        _ResolvedDropCell(
          hex: hex,
          position: Vector2(basePosition.x + hitOffsetX, basePosition.y),
          color: colors[i],
          hitOffsetX: hitOffsetX,
        ),
      );
    }
    return resolved;
  }

  HexCoordinate _findNearestEmptyForDrop(
    HexCoordinate start,
    Set<HexCoordinate> reserved,
  ) {
    bool blocked(HexCoordinate? hex) {
      return grid.isOutOfBounds(hex) ||
          grid.isOccupied(hex) ||
          (hex != null && reserved.contains(hex));
    }

    if (!blocked(start)) {
      return start;
    }

    final queue = [start];
    final visited = {start};
    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      if (!blocked(curr)) {
        return curr;
      }
      for (final dir in ['a', 'd', 'b', 'c', 'f', 'g']) {
        final next = grid.getNeighbor(curr, dir);
        if (next != null && !grid.isOutOfBounds(next) && visited.add(next)) {
          queue.add(next);
        }
      }
    }
    return start;
  }

  bool _isProcessingGravity = false;
  bool _needsGravityRetry = false;
  bool _needsMatchResolutionRetry = false;

  double _lockedBallFallDurationFor(int fallStreak) {
    final acceleration =
        1 + max(0, fallStreak - 1) * _lockedBallFallAcceleration;
    return max(
      _lockedBallFallMinDuration,
      _lockedBallFallDuration / acceleration,
    );
  }

  void _moveLockedBallOneStep(
    BallComponent comp,
    Vector2 targetPx,
    double duration,
  ) {
    comp.clearSnapTarget();
    for (final effect in comp.children.whereType<MoveEffect>().toList()) {
      effect.removeFromParent();
    }
    comp.add(
      MoveEffect.to(
        targetPx,
        EffectController(duration: duration, curve: _lockedBallFallCurve),
      ),
    );
  }

  void _settleLockedBallVisual(BallComponent comp, Vector2 targetPx) {
    for (final effect in comp.children.whereType<MoveEffect>().toList()) {
      effect.removeFromParent();
    }
    comp.lockTo(targetPx);
  }

  void _settleLockedBallVisualsToGrid() {
    for (final entry in grid.lockedBalls.entries) {
      _settleLockedBallVisual(entry.value, grid.hexToPixel(entry.key));
    }
  }

  Future<bool> _settleBoardGravity() async {
    var hadGravitySequence = false;
    bool changed = true;
    final fallStreaks = <BallComponent, int>{};
    while (changed) {
      if (gameStateWrapper.value != GameState.playing) {
        return hadGravitySequence;
      }
      changed = false;
      var longestFallDuration = 0.0;

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
          hadGravitySequence = true;
          grid.lockedBalls[next] = comp;
          _markBoardChanged();
          Vector2 targetPx = grid.hexToPixel(next);
          final fallStreak = (fallStreaks[comp] ?? 0) + 1;
          fallStreaks[comp] = fallStreak;
          final fallDuration = _lockedBallFallDurationFor(fallStreak);
          longestFallDuration = max(longestFallDuration, fallDuration);

          _moveLockedBallOneStep(comp, targetPx, fallDuration);
        } else {
          fallStreaks.remove(comp);
          grid.lockedBalls[curr] = comp;
          comp.snapTo(grid.hexToPixel(curr));
        }
      }

      if (changed) {
        final delayMs = (longestFallDuration * 1000).round() + 4;
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    _settleLockedBallVisualsToGrid();

    if (_playsBoardSfx &&
        gameStateWrapper.value == GameState.playing &&
        hadGravitySequence) {
      _playSfx(_landingSfx, volume: 0.33);
    }
    return hadGravitySequence;
  }

  Future<void> _processGravityAndMatches({bool allowMatches = true}) async {
    if (_isProcessingGravity) {
      _needsGravityRetry = true;
      if (allowMatches) {
        _needsMatchResolutionRetry = true;
      }
      return;
    }
    _isProcessingGravity = true;
    final stopwatch = PerfMonitor.enabled ? (Stopwatch()..start()) : null;

    try {
      do {
        final shouldResolveMatches = allowMatches || _needsMatchResolutionRetry;
        _needsGravityRetry = false;
        _needsMatchResolutionRetry = false;
        await _settleBoardGravity();
        if (!shouldResolveMatches ||
            gameStateWrapper.value != GameState.playing) {
          if (_needsGravityRetry &&
              gameStateWrapper.value == GameState.playing) {
            continue;
          }
          return;
        }

        bool hasMatches = true;
        while (hasMatches && gameStateWrapper.value == GameState.playing) {
          var matchResults = grid.findMatchesAndWazas();
          if (matchResults.isEmpty) {
            hasMatches = false;
          } else {
            if (matchResults.any((result) =>
                result.highestWaza != WazaType.none &&
                result.wazaPattern.isNotEmpty)) {
              _clearHints();
            }
            for (var matchResult in matchResults) {
              var validTargets = matchResult.targets
                  .where((h) => grid.lockedBalls.containsKey(h))
                  .toList();
              if (validTargets.isEmpty) continue;

              scoreManager.addMatch(
                  validTargets.length, matchResult.highestWaza);
              if (onBallsCleared != null) {
                onBallsCleared!(validTargets.length);
              }
              if (onMatchCleared != null) {
                onMatchCleared!(validTargets.length, matchResult.highestWaza);
              }

              if (matchResult.highestWaza != WazaType.none &&
                  matchResult.wazaPattern.isNotEmpty) {
                if (onWazaFired != null) {
                  onWazaFired!(matchResult.highestWaza, matchResult.wazaColor);
                }
                if (renderDetectedFormationEffects) {
                  await _playWazaAnimation(matchResult);
                } else {
                  await _waitForWazaAnimation(matchResult);
                }
              }

              if (_playsBoardSfx) {
                _playSfx(_clearSfx, volume: 1.0);
              }
              if (matchResult.highestWaza == WazaType.none) {
                _triggerThrottledHapticFeedback(
                  'normal_clear',
                  HapticFeedback.heavyImpact,
                  cooldown: const Duration(milliseconds: 140),
                );
              }
              for (var hex in validTargets) {
                BallComponent? comp = grid.lockedBalls.remove(hex);
                if (comp == null) continue;
                _markBoardChanged();

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

          if (hasMatches && gameStateWrapper.value == GameState.playing) {
            await _settleBoardGravity();
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
            onDeathLineCrossed?.call();
            if (isRemotePlayerMode) {
              return;
            }
            gameOver();
            return;
          }

          _updateHints();
          _notifyBoardUpdated();

          if (incomingOjama.isNotEmpty) {
            var task = incomingOjama.removeFirst();
            _dropOjamaTask(task);
            return;
          } else if (activePiece == null &&
              !isRemotePlayerMode &&
              !manualPieceSpawning) {
            _isSpawning = true;
            await Future.delayed(const Duration(milliseconds: 500));
            if (gameStateWrapper.value != GameState.playing ||
                activePiece != null) {
              _isSpawning = false;
              return;
            }
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
      if (isRemotePlayerMode && !_isApplyingRemoteHardDrop) {
        final pendingBoard = _pendingSpectatorBoardState;
        _pendingSpectatorBoardState = null;
        if (pendingBoard != null &&
            gameStateWrapper.value == GameState.playing) {
          _mergeRemoteBoardState(pendingBoard);
        }
      }
      if (stopwatch != null) {
        PerfMonitor.logDuration('board.process', stopwatch, warnMs: 20);
      }
    }
  }

  void applyRemoteBoardState(Map<String, dynamic> boardData) {
    if (_shouldDeferRemoteBoardState(boardData)) {
      return;
    }

    _replaceRemoteBoardState(_parseRemoteBoardState(boardData));
  }

  void applyRemoteBoardStateWithSpectatorEffects(
    Map<String, dynamic> boardData,
  ) {
    applyRemoteBoardState(boardData);
  }

  Map<HexCoordinate, _RemoteBoardCell> _parseRemoteBoardState(
    Map<String, dynamic> boardData,
  ) {
    final parsed = <HexCoordinate, _RemoteBoardCell>{};
    for (final entry in boardData.entries) {
      final key = entry.key.split(',');
      if (key.length != 2) {
        continue;
      }

      final row = int.tryParse(key[0]);
      final col = int.tryParse(key[1]);
      final value = entry.value;
      final colorIndex = switch (value) {
        int raw => raw,
        num raw => raw.toInt(),
        String raw => int.tryParse(raw),
        Map raw => _asInt(raw['color']),
        _ => null,
      };
      final hitOffsetX =
          value is Map ? (_asDouble(value['hitOffsetX']) ?? 0) : 0.0;

      if (row == null ||
          col == null ||
          colorIndex == null ||
          colorIndex < 0 ||
          colorIndex >= BallColor.values.length) {
        continue;
      }

      parsed[HexCoordinate(col, row)] = _RemoteBoardCell(
        color: BallColor.values[colorIndex],
        hitOffsetX: hitOffsetX,
      );
    }
    return parsed;
  }

  void _replaceRemoteBoardState(
    Map<HexCoordinate, _RemoteBoardCell> boardData,
  ) {
    final changed = !_remoteBoardEquals(boardData);
    final preserveAutonomousPreviewPiece =
        isRemotePlayerMode && _autonomousRemotePreviewEnabled;
    final preserveRemoteActivePiece = isRemotePlayerMode &&
        activePiece != null &&
        !_remoteBoardIncludesActivePiece(boardData);
    _clearLockedBalls();
    _clearHints();
    if (!preserveAutonomousPreviewPiece && !preserveRemoteActivePiece) {
      clearRemoteActivePiece();
    }
    _clearActiveOjamaBlocks();

    for (final entry in boardData.entries) {
      final ball = BallComponent(
        position: grid.hexToPixel(entry.key),
        radius: 15.0,
        ballColor: entry.value.color,
        ballSkinId: ballSkinId,
      );
      ball.hitOffsetX = entry.value.hitOffsetX;
      add(ball);
      grid.lockedBalls[entry.key] = ball;
    }
    _markBoardChanged();

    _updateHints();
    if (changed) {
      onRemoteBoardCorrectionApplied?.call('replace');
    }
  }

  void _mergeRemoteBoardState(Map<HexCoordinate, _RemoteBoardCell> boardData) {
    final changed = !_remoteBoardEquals(boardData);
    _clearHints();
    _clearActiveOjamaBlocks();
    if (_remoteBoardIncludesActivePiece(boardData)) {
      clearRemoteActivePiece();
    }

    for (final entry in grid.lockedBalls.entries.toList()) {
      final cell = boardData[entry.key];
      if (cell != null && cell.color == entry.value.ballColor) {
        entry.value.hitOffsetX = cell.hitOffsetX;
        entry.value.lockTo(grid.hexToPixel(entry.key));
        continue;
      }
      if (entry.value.parent != null) {
        entry.value.removeFromParent();
      }
      grid.lockedBalls.remove(entry.key);
      _markBoardChanged();
    }

    for (final entry in boardData.entries) {
      if (grid.lockedBalls.containsKey(entry.key)) {
        continue;
      }
      final ball = BallComponent(
        position: grid.hexToPixel(entry.key),
        radius: 15.0,
        ballColor: entry.value.color,
        ballSkinId: ballSkinId,
      );
      ball.hitOffsetX = entry.value.hitOffsetX;
      add(ball);
      grid.lockedBalls[entry.key] = ball;
      _markBoardChanged();
    }

    _updateHints();
    if (changed) {
      onRemoteBoardCorrectionApplied?.call('merge');
    }
  }

  bool _remoteBoardEquals(Map<HexCoordinate, _RemoteBoardCell> boardData) {
    if (grid.lockedBalls.length != boardData.length) {
      return false;
    }
    for (final entry in boardData.entries) {
      final ball = grid.lockedBalls[entry.key];
      if (ball == null ||
          ball.ballColor != entry.value.color ||
          (ball.hitOffsetX - entry.value.hitOffsetX).abs() > 0.01) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> exportBoardState() {
    return {
      for (final entry in grid.lockedBalls.entries)
        '${entry.key.row},${entry.key.col}': {
          'color': entry.value.ballColor.index,
          'hitOffsetX': double.parse(entry.value.hitOffsetX.toStringAsFixed(4)),
        },
    };
  }

  bool _remoteBoardIncludesActivePiece(
    Map<HexCoordinate, _RemoteBoardCell> boardData,
  ) {
    final piece = activePiece;
    if (piece == null || piece.isLocked || piece.colors.length != 3) {
      return false;
    }
    final resolvedCells = _resolveDropCells(
      piece.absoluteBallPositions,
      piece.colors,
    );
    if (resolvedCells.length != piece.colors.length) {
      return false;
    }
    for (final cell in resolvedCells) {
      final boardCell = boardData[cell.hex];
      if (boardCell == null || boardCell.color != cell.color) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> exportRestorableSnapshot() {
    final piece = activePiece;
    return {
      'board': exportBoardState(),
      'nextColors': nextPieceColors.value.map((color) => color.index).toList(),
      'incomingOjama': incomingOjama
          .map(
            (task) => {
              'type': task.type.name,
              if (task.startColor != null) 'startColor': task.startColor!.index,
              if (task.presetColors != null)
                'presetColors':
                    task.presetColors!.map((color) => color.index).toList(),
              if (task.ballSkinId != 'default') 'ballSkinId': task.ballSkinId,
              if (task.effectSkinId != task.ballSkinId)
                'effectSkinId': task.effectSkinId,
            },
          )
          .toList(),
      'score': scoreManager.exportSnapshot(),
      'deathLineProgress': _deathLineDangerProgress,
      if (piece != null && !piece.isLocked)
        'activePiece': {
          'x': piece.position.x,
          'y': piece.position.y,
          'rotation': activePieceRotation,
          'colors': piece.colors.map((color) => color.index).toList(),
          'dropSeed': currentDropSeed,
          'pieceId': _currentPieceSyncId,
          'movingLeft': isMovingLeft,
          'movingRight': isMovingRight,
          'contactSlideDirection': _activePieceContactSlideDirection,
          if (ballSkinId != 'default') 'ballSkinId': ballSkinId,
        },
    };
  }

  void restoreFromSnapshot(Map<String, dynamic> snapshot) {
    _deathLineTransitionTimer?.cancel();
    _deathLineTransitionTimer = null;
    _clearLockedBalls();
    _clearHints();
    clearRemoteActivePiece();
    _clearActiveOjamaBlocks();
    incomingOjama.clear();
    _previewOjamaQueue.clear();
    scoreManager.restoreSnapshot(snapshot['score'] is Map<String, dynamic>
        ? snapshot['score'] as Map<String, dynamic>
        : snapshot['score'] is Map
            ? Map<String, dynamic>.from(snapshot['score'] as Map)
            : null);
    _idleGlowTime = 0.0;
    _idleGlowIndex = 0;
    _isSpawning = false;
    isMovingLeft = false;
    isMovingRight = false;
    _activePieceSyncCooldown = 0.0;
    _suppressNextLandingSfx = false;
    _hasRemoteOjamaInFlight = false;
    _remoteOjamaSpawnedAt = null;
    _deferredRemoteBoardTimer?.cancel();
    _deferredRemoteBoardTimer = null;
    _deferredRemoteBoardState = null;
    pendingOjamaSpawns = 0;
    _pendingOjamaBatchLandings = 0;
    _ojamaSpawnBatchVersion++;
    _pendingPreviewOjamaSpawns = 0;
    _isProcessingPreviewOjamaQueue = false;
    _needsMatchResolutionRetry = false;
    _autonomousRemotePreviewEnabled = snapshot['proxyControlledBy'] != null;
    _remotePreviewRespawnVersion++;
    gameStateWrapper.value = GameState.playing;

    final board = snapshot['board'];
    if (board is Map) {
      applyRemoteBoardState(Map<String, dynamic>.from(board));
    }

    final nextColors = _parseBallColors(snapshot['nextColors']);
    nextPieceColors.value =
        nextColors.isNotEmpty ? nextColors : _generatePieceColors();

    final queuedOjama = snapshot['incomingOjama'];
    if (queuedOjama is List) {
      for (final item in queuedOjama) {
        if (item is! Map) {
          continue;
        }
        final typeName = item['type']?.toString();
        OjamaType? type;
        for (final candidate in OjamaType.values) {
          if (candidate.name == typeName) {
            type = candidate;
            break;
          }
        }
        if (type == null) {
          continue;
        }
        final startColorIndex = _asInt(item['startColor']);
        incomingOjama.add(
          OjamaTask(
            type,
            startColor: startColorIndex != null &&
                    startColorIndex >= 0 &&
                    startColorIndex < BallColor.values.length
                ? BallColor.values[startColorIndex]
                : null,
            presetColors: _parseBallColors(item['presetColors']),
            ballSkinId: item['ballSkinId']?.toString() ?? 'default',
            effectSkinId: item['effectSkinId']?.toString(),
          ),
        );
      }
    }

    final activeSnapshot = snapshot['activePiece'];
    if (activeSnapshot is Map) {
      final colors = _parseBallColors(activeSnapshot['colors']);
      final x = _asDouble(activeSnapshot['x']);
      final y = _asDouble(activeSnapshot['y']);
      final rotation = _asInt(activeSnapshot['rotation']);
      final dropSeed = _asInt(activeSnapshot['dropSeed']);
      final activeBallSkinId =
          activeSnapshot['ballSkinId']?.toString() ?? ballSkinId;
      final contactSlideDirection =
          _asDouble(activeSnapshot['contactSlideDirection']);
      if (colors.length == 3 && x != null && y != null) {
        if (!isRemotePlayerMode) {
          currentDropSeed = dropSeed ?? currentDropSeed;
          syncDropRng = dropSeed == null ? null : Random(dropSeed);
        }
        activePiece = ActivePieceComponent(
          position: Vector2(x, y),
          ballRadius: _ballRadius,
          fallSpeed: currentFallSpeed,
          presetColors: colors,
          ballSkinId: activeBallSkinId,
        )..priority = 10;
        add(activePiece!);
        ghostPiece = ActivePieceComponent(
          position: Vector2(x, y),
          ballRadius: _ballRadius,
          isGhost: true,
          fallSpeed: currentFallSpeed,
          presetColors: colors,
          ballSkinId: activeBallSkinId,
        )..priority = 0;
        add(ghostPiece!);
        if (rotation != null) {
          activePiece!.setRotationIndex(rotation);
          ghostPiece!.setRotationIndex(rotation);
        }
        isMovingLeft = activeSnapshot['movingLeft'] == true;
        isMovingRight = activeSnapshot['movingRight'] == true;
        if (isRemotePlayerMode && contactSlideDirection != null) {
          syncRemoteActivePieceInputState(
            movingLeft: isMovingLeft,
            movingRight: isMovingRight,
            contactSlideDirection: contactSlideDirection,
          );
        }
        _updateGhostPosition();
      }
    }

    final deathLineProgress = snapshot['deathLineProgress'];
    setDeathLineDangerProgress(
      deathLineProgress is num ? deathLineProgress.toDouble() : 0.0,
    );
    _updateHints();
    _notifyBoardUpdated();
    if (isRemotePlayerMode) {
      _scheduleRemotePreviewRespawn();
    } else {
      unawaited(_processGravityAndMatches());
    }
  }

  void _clearLockedBalls() {
    for (final ball in grid.lockedBalls.values) {
      remove(ball);
    }
    grid.lockedBalls.clear();
    _markBoardChanged();
  }

  void _clearAllBoardComponents() {
    final snapshot = children.toList();
    for (final child in snapshot) {
      remove(child);
    }
    grid.lockedBalls.clear();
    activePiece = null;
    ghostPiece = null;
    _remotePieceAwaitingTerminalLock = false;
    _clearRemoteTransformBlend();
    activeOjamaBlocks.clear();
    _hintComponents.clear();
    _markBoardChanged();
  }

  void _clearActiveOjamaBlocks() {
    for (final block in activeOjamaBlocks) {
      if (block.parent != null) {
        remove(block);
      }
    }
    activeOjamaBlocks.clear();
    pendingOjamaSpawns = 0;
    _pendingOjamaBatchLandings = 0;
    _ojamaSpawnBatchVersion++;
    _needsMatchResolutionRetry = false;
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
    _remotePieceAwaitingTerminalLock = false;
    _clearRemoteTransformBlend();
    _markGhostPositionDirty();
  }

  void setAutonomousRemotePreviewEnabled(bool enabled) {
    if (!isRemotePlayerMode) {
      return;
    }
    if (_autonomousRemotePreviewEnabled == enabled) {
      return;
    }
    _autonomousRemotePreviewEnabled = enabled;
    _remotePreviewRespawnVersion++;
    if (enabled) {
      _scheduleRemotePreviewRespawn();
    }
  }

  void _spawnAutonomousRemotePreviewPiece() {
    if (!isRemotePlayerMode) {
      return;
    }
    if (nextPieceColors.value.isEmpty) {
      nextPieceColors.value = _generatePieceColors();
    }
    final colors = List<BallColor>.from(nextPieceColors.value);
    nextPieceColors.value = _generatePieceColors();
    spawnRemotePiece(colors);
  }

  void spawnRemotePiece(List<BallColor> colors) {
    spawnRemotePieceWithId(colors: colors);
  }

  void spawnRemotePieceWithId({
    required List<BallColor> colors,
    int? pieceId,
  }) {
    if (!isRemotePlayerMode) {
      return;
    }

    clearRemoteActivePiece();
    if (pieceId != null && pieceId > 0) {
      _currentPieceSyncId = pieceId;
      _nextPieceSyncId = max(_nextPieceSyncId, pieceId);
    } else {
      _currentPieceSyncId = ++_nextPieceSyncId;
    }
    _activePieceEventSeq = 0;
    isMovingLeft = false;
    isMovingRight = false;
    _activePieceContactSlideDirection = 0.0;
    _remoteTopContactSlideDirection = null;
    _remotePieceAwaitingTerminalLock = false;
    _clearRemoteTransformBlend();

    activePiece = ActivePieceComponent(
      position: _pieceSpawnPosition,
      ballRadius: _ballRadius,
      fallSpeed: currentFallSpeed,
      presetColors: colors,
      ballSkinId: ballSkinId,
    )..priority = 10;
    add(activePiece!);

    ghostPiece = ActivePieceComponent(
      position: _pieceSpawnPosition,
      ballRadius: _ballRadius,
      isGhost: true,
      fallSpeed: currentFallSpeed,
      presetColors: colors,
      ballSkinId: ballSkinId,
    )..priority = 0;
    add(ghostPiece!);
    _updateGhostPosition();
    if (_autonomousRemotePreviewEnabled) {
      _notifyBoardUpdated();
    }
  }

  void syncRemoteActivePieceInputState({
    required bool movingLeft,
    required bool movingRight,
    double? contactSlideDirection,
  }) {
    if (!isRemotePlayerMode) {
      return;
    }
    isMovingLeft = movingLeft;
    isMovingRight = movingRight;
    if (contactSlideDirection == null || contactSlideDirection == 0) {
      _remoteTopContactSlideDirection = null;
      _activePieceContactSlideDirection = 0.0;
      return;
    }
    _remoteTopContactSlideDirection = contactSlideDirection.sign.toDouble();
    _activePieceContactSlideDirection = _remoteTopContactSlideDirection!;
  }

  void _clearRemoteTransformBlend() {
    _remoteTransformStartPosition = null;
    _remoteTransformTargetPosition = null;
    _remoteTransformBlendDuration = 0.0;
    _remoteTransformBlendElapsed = 0.0;
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
    var playedInitialOjamaSfx = false;
    final spawnBatch = <Map<dynamic, dynamic>>[];
    final batchVersion = ++_ojamaSpawnBatchVersion;

    for (final item in ojamaData) {
      if (item is! Map) {
        continue;
      }
      spawnBatch.add(Map<dynamic, dynamic>.from(item));
    }

    if (spawnBatch.isEmpty) {
      return;
    }

    _pendingOjamaBatchLandings = spawnBatch.length;
    _hasRemoteOjamaInFlight = true;
    _remoteOjamaSpawnedAt = DateTime.now();

    for (int index = 0; index < spawnBatch.length; index++) {
      Future.delayed(
        Duration(milliseconds: index == 0 ? 0 : 500 * index),
        () {
          if (batchVersion != _ojamaSpawnBatchVersion ||
              gameStateWrapper.value != GameState.playing) {
            return;
          }
          final item = spawnBatch[index];

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
          final itemBallSkinId = item['ballSkinId']?.toString() ?? 'default';
          final itemEffectSkinId =
              item['effectSkinId']?.toString() ?? itemBallSkinId;
          if (itemDropSeed != null) {
            syncDropRng = Random(itemDropSeed);
          }

          if (type == null || x == null || y == null || colors.isEmpty) {
            if (_pendingOjamaBatchLandings > 0) {
              _pendingOjamaBatchLandings--;
            }
            if (_pendingOjamaBatchLandings == 0 && activeOjamaBlocks.isEmpty) {
              _hasRemoteOjamaInFlight = false;
              _remoteOjamaSpawnedAt = null;
            }
            return;
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
            lockedCells: _parseLockedCellPayload(item['landingCells']),
            ballSkinId: itemBallSkinId,
            effectSkinId: itemEffectSkinId,
          );
          activeOjamaBlocks.add(block);
          add(block);
          if (!playedInitialOjamaSfx && _playsBoardSfx) {
            _playSfx(_ojamaSpawnSfx, volume: 0.9);
            playedInitialOjamaSfx = true;
          }
          if (_playsBoardSfx) {
            _playSfx(_ojamaBlockSpawnSfx, volume: 0.41);
          }
        },
      );
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

    piece.setRotationIndex(rotation, animate: duration > 0.01);
    for (final effect in piece.children.whereType<MoveEffect>().toList()) {
      effect.removeFromParent();
    }
    final target = Vector2(x, y);
    if (duration <= 0.01 ||
        (piece.position.x - target.x).abs() > _gridUnit * 2) {
      _clearRemoteTransformBlend();
      piece.position = target;
    } else {
      _remoteTransformStartPosition = piece.position.clone();
      _remoteTransformTargetPosition = target;
      _remoteTransformBlendDuration = duration;
      _remoteTransformBlendElapsed = 0.0;
    }
    _markGhostPositionDirty();
    if (ghostPiece != null) {
      ghostPiece!.setRotationIndex(rotation, animate: duration > 0.01);
      ghostPiece!.angle = piece.angle;
    }
  }

  void _applyRemoteTransformBlend(double dt) {
    if (!isRemotePlayerMode ||
        activePiece == null ||
        activePiece!.isLocked ||
        _remoteTransformTargetPosition == null ||
        _remoteTransformStartPosition == null ||
        _remoteTransformBlendDuration <= 0) {
      return;
    }

    _remoteTransformBlendElapsed =
        min(_remoteTransformBlendDuration, _remoteTransformBlendElapsed + dt);
    final progress =
        (_remoteTransformBlendElapsed / _remoteTransformBlendDuration)
            .clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(progress);
    final start = _remoteTransformStartPosition!;
    final target = _remoteTransformTargetPosition!;
    activePiece!.position.x = start.x + (target.x - start.x) * eased;
    _enforceBounds();
    _markGhostPositionDirty();
    if (ghostPiece != null) {
      ghostPiece!.position.x = activePiece!.position.x;
    }
    if (progress >= 1.0) {
      _clearRemoteTransformBlend();
    }
  }

  int get activePieceRotation {
    final piece = activePiece;
    if (piece == null) {
      return 0;
    }
    return piece.logicalRotationIndex;
  }

  double get activePieceContactSlideDirection =>
      _activePieceContactSlideDirection;

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
    final eventSeq = ++_activePieceEventSeq;
    final lockedCells = action == 'hard_drop' || action == 'lock'
        ? _resolvedDropCellsToPayload(
            _resolveDropCells(
              piece.absoluteBallPositions,
              piece.colors,
            ),
          )
        : null;
    onActivePieceChanged!(
      action,
      piece.position.x,
      piece.position.y,
      activePieceRotation,
      List<BallColor>.from(piece.colors),
      currentDropSeed,
      _currentPieceSyncId,
      eventSeq,
      lockedCells,
    );
  }

  List<Map<String, dynamic>> _resolvedDropCellsToPayload(
    List<_ResolvedDropCell> cells,
  ) {
    return cells
        .map(
          (cell) => {
            'row': cell.hex.row,
            'col': cell.hex.col,
            'hitOffsetX': double.parse(cell.hitOffsetX.toStringAsFixed(4)),
          },
        )
        .toList();
  }

  void onOjamaBlockLanded(OjamaBlockComponent block) {
    activeOjamaBlocks.remove(block);
    if (_pendingOjamaBatchLandings > 0) {
      _pendingOjamaBatchLandings--;
    }
    if (isRemotePlayerMode && activeOjamaBlocks.isEmpty) {
      _hasRemoteOjamaInFlight = false;
      _remoteOjamaSpawnedAt = null;
    }
    final shouldResolveBoard = _pendingOjamaBatchLandings == 0 &&
        pendingOjamaSpawns == 0 &&
        activeOjamaBlocks.isEmpty;
    _processGravityAndMatches(allowMatches: shouldResolveBoard);
    if (isRemotePlayerMode) {
      _scheduleRemotePreviewRespawn();
    }
  }

  void _scheduleRemotePreviewRespawn() {
    if (!isRemotePlayerMode || !_autonomousRemotePreviewEnabled) {
      return;
    }
    final respawnVersion = _remotePreviewRespawnVersion;
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (respawnVersion != _remotePreviewRespawnVersion ||
          !_autonomousRemotePreviewEnabled ||
          gameStateWrapper.value != GameState.playing ||
          activePiece != null ||
          activeOjamaBlocks.isNotEmpty ||
          _pendingPreviewOjamaSpawns > 0 ||
          hasOverflowedDeathLine ||
          nextPieceColors.value.length != 3) {
        return;
      }
      _spawnAutonomousRemotePreviewPiece();
    });
  }

  bool _shouldDeferRemoteBoardState(Map<String, dynamic> boardData) {
    if (isRemotePlayerMode &&
        (_isApplyingRemoteHardDrop || _isProcessingGravity)) {
      _pendingSpectatorBoardState = _parseRemoteBoardState(boardData);
      return true;
    }

    if (isRemotePlayerMode && activeOjamaBlocks.isNotEmpty) {
      _deferRemoteBoardStateUntilOjamaComplete(boardData);
      return true;
    }

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

  void _deferRemoteBoardStateUntilOjamaComplete(
    Map<String, dynamic> boardData,
  ) {
    _deferredRemoteBoardState = Map<String, dynamic>.from(boardData);
    _deferredRemoteBoardTimer?.cancel();
    _deferredRemoteBoardTimer =
        async.Timer(const Duration(milliseconds: 80), () {
      final deferred = _deferredRemoteBoardState;
      _deferredRemoteBoardTimer = null;
      if (deferred == null || gameStateWrapper.value != GameState.playing) {
        return;
      }
      if (activeOjamaBlocks.isNotEmpty || _isProcessingGravity) {
        _deferRemoteBoardStateUntilOjamaComplete(deferred);
        return;
      }
      _deferredRemoteBoardState = null;
      applyRemoteBoardState(deferred);
    });
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
    _pendingOjamaBatchLandings = numSets;
    final batchVersion = ++_ojamaSpawnBatchVersion;
    final spawnBatch = <Map<String, dynamic>>[];
    final colorsPerSet = List<List<BallColor>>.generate(
      numSets,
      (_) => _colorsForOjamaSet(task),
    );
    final dropSeeds = List<int>.generate(numSets, (_) => _rng.nextInt(999999));
    final simulatedOccupied = <HexCoordinate, double>{
      for (final entry in grid.lockedBalls.entries)
        entry.key: entry.value.hitOffsetX,
    };
    for (int i = 0; i < numSets; i++) {
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

      final landingCells = _predictOjamaLandingCells(
        task.type,
        spawnX: spawnX,
        colors: colorsPerSet[i],
        simulatedOccupied: simulatedOccupied,
      );
      final spawnData = <String, dynamic>{
        'type': task.type.name,
        'x': spawnX,
        'y': grid.offset.y - _ojamaSpawnYOffset,
        'colors': colorsPerSet[i].map((color) => color.index).toList(),
        'dropSeed': dropSeeds[i],
        if (landingCells.isNotEmpty) 'landingCells': landingCells,
        if (ballSkinId != 'default') 'ballSkinId': ballSkinId,
        if (task.effectSkinId != ballSkinId) 'effectSkinId': task.effectSkinId,
      };
      if (task.type == OjamaType.straightSet && task.startColor != null) {
        spawnData['startColor'] = task.startColor!.index;
      }
      spawnBatch.add(spawnData);
    }
    if (spawnBatch.isNotEmpty) {
      onOjamaSpawned?.call(spawnBatch, dropSeeds.first);
    }

    for (int i = 0; i < numSets; i++) {
      Future.delayed(Duration(milliseconds: i == 0 ? 0 : 500 * i), () {
        if (batchVersion != _ojamaSpawnBatchVersion ||
            gameStateWrapper.value != GameState.playing) {
          pendingOjamaSpawns--;
          return;
        }
        final spawnData = spawnBatch[i];
        final colors = _parseBallColors(spawnData['colors']);
        final spawnX = _asDouble(spawnData['x']) ?? grid.offset.x;
        final spawnY =
            _asDouble(spawnData['y']) ?? (grid.offset.y - _ojamaSpawnYOffset);
        var block = OjamaBlockComponent(
          ojamaType: task.type,
          position: Vector2(spawnX, spawnY),
          startColor:
              task.type == OjamaType.straightSet ? task.startColor : null,
          presetColors: colors,
          lockedCells: _parseLockedCellPayload(spawnData['landingCells']),
          ballSkinId: ballSkinId,
          effectSkinId: task.effectSkinId,
        );
        activeOjamaBlocks.add(block);
        add(block);
        if (i == 0 && _playsBoardSfx) {
          _playSfx(_ojamaSpawnSfx, volume: 0.9);
        }
        if (_playsBoardSfx) {
          _playSfx(_ojamaBlockSpawnSfx, volume: 0.41);
        }
        _triggerThrottledHapticFeedback(
          'ojama_spawn',
          HapticFeedback.heavyImpact,
          cooldown: const Duration(milliseconds: 240),
        );
        final dropSeed = _asInt(spawnData['dropSeed']) ?? _rng.nextInt(999999);
        syncDropRng = Random(dropSeed);
        pendingOjamaSpawns--;
      });
    }
  }

  List<Map<String, dynamic>> _predictOjamaLandingCells(
    OjamaType type, {
    required double spawnX,
    required List<BallColor> colors,
    required Map<HexCoordinate, double> simulatedOccupied,
  }) {
    final offsets = _ojamaLocalOffsets(type);
    if (offsets.isEmpty || colors.isEmpty) {
      return const [];
    }

    final count = min(offsets.length, colors.length);
    var collisionY = double.infinity;
    const collisionDistance = 28.0;
    for (var i = 0; i < count; i++) {
      final offset = offsets[i];
      collisionY = min(collisionY, grid.floorY - _ballRadius - offset.y);
      final ballX = spawnX + offset.x;
      for (final entry in simulatedOccupied.entries) {
        final basePosition = grid.hexToPixel(entry.key);
        final lockedX = basePosition.x + entry.value;
        final dx = ballX - lockedX;
        if (dx.abs() >= collisionDistance) {
          continue;
        }
        final dy = sqrt(collisionDistance * collisionDistance - dx * dx);
        collisionY = min(collisionY, basePosition.y - dy - offset.y);
      }
    }

    if (!collisionY.isFinite) {
      return const [];
    }

    final reserved = <HexCoordinate>{};
    final cells = <Map<String, dynamic>>[];
    for (var i = 0; i < count; i++) {
      final offset = offsets[i];
      final position = Vector2(spawnX + offset.x, collisionY + offset.y);
      final hex = _findNearestEmptyForSimulatedOjama(
        grid.pixelToHex(position),
        simulatedOccupied.keys.toSet(),
        reserved,
      );
      reserved.add(hex);
      final hitOffsetX = position.x - grid.hexToPixel(hex).x;
      simulatedOccupied[hex] = hitOffsetX;
      cells.add({
        'row': hex.row,
        'col': hex.col,
        'hitOffsetX': double.parse(hitOffsetX.toStringAsFixed(4)),
      });
    }
    return cells;
  }

  List<Vector2> _ojamaLocalOffsets(OjamaType type) {
    final rowHeight = _ballRadius * sqrt(3);
    switch (type) {
      case OjamaType.straightSet:
        return [
          for (var i = 0; i < 10; i++) Vector2(i * _gridUnit, 0),
          for (var i = 0; i < 9; i++)
            Vector2(i * _gridUnit + _ballRadius, -rowHeight),
        ];
      case OjamaType.pyramidSet:
        return [
          Vector2(_gridUnit, -2 * rowHeight),
          Vector2(_ballRadius, -rowHeight),
          Vector2(_gridUnit + _ballRadius, -rowHeight),
          Vector2(0, 0),
          Vector2(_gridUnit, 0),
          Vector2(_gridUnit * 2, 0),
        ];
      case OjamaType.hexagonSet:
        return [
          Vector2(_ballRadius, -2 * rowHeight),
          Vector2(_gridUnit + _ballRadius, -2 * rowHeight),
          Vector2(0, -rowHeight),
          Vector2(_gridUnit * 2, -rowHeight),
          Vector2(_ballRadius, 0),
          Vector2(_gridUnit + _ballRadius, 0),
        ];
    }
  }

  HexCoordinate _findNearestEmptyForSimulatedOjama(
    HexCoordinate start,
    Set<HexCoordinate> occupied,
    Set<HexCoordinate> reserved,
  ) {
    bool blocked(HexCoordinate? hex) {
      return grid.isOutOfBounds(hex) ||
          (hex != null && (occupied.contains(hex) || reserved.contains(hex)));
    }

    if (!blocked(start)) {
      return start;
    }

    final queue = [start];
    final visited = {start};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!blocked(current)) {
        return current;
      }
      for (final dir in ['a', 'd', 'b', 'c', 'f', 'g']) {
        final next = grid.getNeighbor(current, dir);
        if (next != null && !grid.isOutOfBounds(next) && visited.add(next)) {
          queue.add(next);
        }
      }
    }
    return start;
  }

  List<Map<String, dynamic>>? _parseLockedCellPayload(Object? raw) {
    final items = raw is List
        ? raw
        : raw is Map
            ? raw.values.toList()
            : null;
    if (items == null) {
      return null;
    }
    final cells = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item is Map) {
        cells.add(Map<String, dynamic>.from(item));
      }
    }
    return cells.isEmpty ? null : cells;
  }

  void forceDropOjamaTask(OjamaTask task) {
    if (gameStateWrapper.value != GameState.playing) {
      return;
    }
    _dropOjamaTask(task);
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
    final colors = <BallColor>[];

    for (var i = 0; i < 10; i++) {
      colors.add(loopColors[(bottomStart + i) % loopColors.length]);
    }
    for (var i = 0; i < 9; i++) {
      colors.add(loopColors[(bottomStart + i) % loopColors.length]);
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

    if (_playsBoardSfx) {
      _playSfx(_wazaChargeSfx, volume: 0.9);
    }
    _triggerHapticFeedback(HapticFeedback.heavyImpact);
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

  Future<void> _waitForWazaAnimation(MatchResult matchResult) async {
    await Future<void>.delayed(
      Duration(milliseconds: matchResult.wazaPattern.length * 180 + 350),
    );
  }

  void showRemoteAttackFormation(OjamaType type) {
    final name = switch (type) {
      OjamaType.hexagonSet => 'HEXAGON',
      OjamaType.pyramidSet => 'PYRAMID',
      OjamaType.straightSet => 'STRAIGHT',
    };
    final generation = ++_remoteAttackFormationGeneration;
    wazaNameNotifier.value = '$name！';
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!_isRemoved && generation == _remoteAttackFormationGeneration) {
        wazaNameNotifier.value = null;
      }
    });
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
    _markGhostPositionDirty();
    _enforceBounds();
    if (_playsBoardSfx) {
      _playSfx(_rotationSfx, volume: 0.14);
    }
    _triggerThrottledHapticFeedback(
      'piece_rotate',
      HapticFeedback.mediumImpact,
      cooldown: const Duration(milliseconds: 45),
    );
    _notifyActivePieceState(force: true, action: 'rotate_left');
  }

  void rotateRight() {
    if (activePiece == null || activePiece!.isLocked) return;
    activePiece!.rotateRight();
    _markGhostPositionDirty();
    _enforceBounds();
    if (_playsBoardSfx) {
      _playSfx(_rotationSfx, volume: 0.14);
    }
    _triggerThrottledHapticFeedback(
      'piece_rotate',
      HapticFeedback.mediumImpact,
      cooldown: const Duration(milliseconds: 45),
    );
    _notifyActivePieceState(force: true, action: 'rotate_right');
  }

  bool _enforceBounds() {
    if (activePiece == null) return false;

    final minBallCenterX = grid.offset.x + _activePieceWallInset;
    final maxBallCenterX =
        grid.offset.x + _boardWidth - _ballRadius * 2 - _activePieceWallInset;
    var correction = 0.0;

    for (var pos in activePiece!.absoluteBallPositions) {
      if (pos.x + correction < minBallCenterX) {
        correction = minBallCenterX - pos.x;
      } else if (pos.x + correction > maxBallCenterX) {
        correction = maxBallCenterX - pos.x;
      }
    }

    if (correction == 0.0) {
      return false;
    }

    activePiece!.position.x += correction;
    _markGhostPositionDirty();
    return true;
  }

  void hardDrop() {
    if (activePiece == null || activePiece!.isLocked) return;
    _markGhostPositionDirty();
    _updateGhostPosition();
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
      _forceLockNextActivePieceContact = true;
      _suppressNextLandingSfx = true;
      if (_playsBoardSfx) {
        _playSfx(_hardDropSfx, volume: 0.85);
      }
      _triggerHapticFeedback(HapticFeedback.heavyImpact);
      _notifyActivePieceState(force: true, action: 'hard_drop');
      _checkActivePieceCollision(0);
    }
  }

  Future<void> applyRemoteHardDrop({
    double? x,
    double? y,
    int? rotation,
    List<HexCoordinate>? lockedHexes,
    List<Map<String, dynamic>>? lockedCells,
    bool playHardDropEffects = true,
  }) async {
    if (!isRemotePlayerMode ||
        activePiece == null ||
        (activePiece!.isLocked && !_remotePieceAwaitingTerminalLock)) {
      return;
    }

    _isApplyingRemoteHardDrop = true;
    _remotePieceAwaitingTerminalLock = false;
    _pendingSpectatorBoardState = null;
    final piece = activePiece!;
    piece.isLocked = false;
    ghostPiece?.isLocked = false;
    try {
      if (rotation != null) {
        piece.setRotationIndex(rotation, animate: false);
        ghostPiece?.setRotationIndex(rotation, animate: false);
      }
      if (x != null && y != null) {
        piece.position = Vector2(x, y);
        ghostPiece?.position = piece.position.clone();
      } else if (ghostPiece != null) {
        piece.position = ghostPiece!.position.clone()..y += 5.0;
      }

      final dropPositions = piece.absoluteBallPositions;
      final pieceColors = piece.colors.toList(growable: false);
      if (playHardDropEffects) {
        for (var i = 0;
            i < dropPositions.length && i < pieceColors.length;
            i++) {
          add(
            SparkEffect(
              position: dropPositions[i].clone(),
              sparkColor: pieceColors[i].glowColor,
            ),
          );
        }
      }

      if (playHardDropEffects && _playsBoardSfx) {
        _playSfx(_hardDropSfx, volume: 0.85);
      }

      isMovingLeft = false;
      isMovingRight = false;
      _forceLockNextActivePieceContact = false;
      _activePieceWasSupportedByContact = false;
      _activePieceContactSlideDirection = 0.0;
      _remoteTopContactSlideDirection = null;
      _wallBlockedSlideTime = 0.0;
      _suppressNextLandingSfx = true;

      if (activePiece?.parent != null) {
        activePiece!.removeFromParent();
      }
      if (ghostPiece?.parent != null) {
        ghostPiece!.removeFromParent();
      }
      activePiece = null;
      ghostPiece = null;
      _remotePieceAwaitingTerminalLock = false;
      _clearRemoteTransformBlend();

      await _executeLogicDrop(
        dropPositions,
        pieceColors,
        lockedHexes: lockedHexes,
        lockedCells: lockedCells,
      );
    } finally {
      _isApplyingRemoteHardDrop = false;
      final pendingBoard = _pendingSpectatorBoardState;
      _pendingSpectatorBoardState = null;
      if (pendingBoard != null && gameStateWrapper.value == GameState.playing) {
        _mergeRemoteBoardState(pendingBoard);
      }
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
