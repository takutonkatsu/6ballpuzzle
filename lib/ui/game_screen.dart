import 'dart:async';
import 'dart:math';

import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../audio/seamless_bgm.dart';
import '../audio/sfx.dart';
import '../audio/sfx_player.dart';
import '../data/models/badge_item.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../game/arena_manager.dart';
import '../game/components/ball_component.dart';
import '../game/components/effect_components.dart';
import '../game/game_models.dart';
import '../game/mission_manager.dart';
import '../game/puzzle_game.dart';
import '../network/multiplayer_manager.dart';
import '../network/game_activity_presence.dart';
import '../network/ranking_manager.dart';
import '../network/realtime_connection_guard.dart';
import 'components/banner_ad_widget.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/interstitial_ad_manager.dart';
import 'components/rewarded_ad_manager.dart';
import 'components/stamp_widget.dart';
import 'home_screen.dart';
import 'theme/game_theme_colors.dart';

const Color _gameCyan = GameThemeColors.cyan;
const Color _battlePlayerColor = GameThemeColors.blueSide;
const Color _battleOpponentColor = GameThemeColors.redSide;
const Color _rankedPurple = GameThemeColors.ranked;
const Color _endlessGreen = GameThemeColors.endless;
const Color _computerYellow = GameThemeColors.computer;
const Color _friendPink = GameThemeColors.friend;
const Color _mutedButtonGrey = GameThemeColors.mutedButton;
const Duration _playerProfileSyncTimeout = Duration(seconds: 5);

class GameScreen extends StatefulWidget {
  final bool isCpuMode;
  final bool isOnlineMultiplayer;
  final String? roomId;
  final bool isHost;
  final bool isRankedMode;
  final bool isArenaMode;
  final CPUDifficulty cpuDifficulty;
  final int? rankedBotRating;
  final String rankedBotName;
  final bool isTutorialMode;
  final bool returnToCallerOnExit;

  const GameScreen({
    super.key,
    this.isCpuMode = false,
    this.isOnlineMultiplayer = false,
    this.roomId,
    this.isHost = false,
    this.isRankedMode = false,
    this.isArenaMode = false,
    this.cpuDifficulty = CPUDifficulty.hard,
    this.rankedBotRating,
    this.rankedBotName = 'Player',
    this.isTutorialMode = false,
    this.returnToCallerOnExit = false,
  });

  const GameScreen.online({
    super.key,
    this.roomId,
    this.isHost = false,
    this.isRankedMode = false,
    this.isArenaMode = false,
  })  : cpuDifficulty = CPUDifficulty.hard,
        rankedBotRating = null,
        rankedBotName = 'Player',
        isTutorialMode = false,
        returnToCallerOnExit = false,
        isCpuMode = false,
        isOnlineMultiplayer = true;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _TutorialPhase {
  step1Move,
  step1Drop,
  step1Clear,
  step2HintIntro,
  step2Move,
  step2Rotate,
  step2Drop,
  step2Clear,
  step3Incoming,
  step3OpponentAttack,
  step3Move,
  step3Rotate,
  step3Drop,
  step3Skill,
}

enum _TutorialAction {
  moveLeft,
  moveRight,
  rotateLeft,
  rotateRight,
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const Object _bgmOwner = 'game_screen';

  static const double _gameViewportWidth = 308;
  static const double _gameViewportHeight = 480;
  static const double _gridBallDiameter = 30;
  static const double _compactStampWidth = 118;
  static const Duration _postReadyGoBoardPause = Duration(milliseconds: 350);
  static const Duration _preReadyDelay = Duration(milliseconds: 500);
  static const Duration _resultFreezeDelay = Duration(milliseconds: 700);
  static const Duration _resultBoardSettleDelay = Duration(milliseconds: 650);
  static const Duration _resultOpponentDisplayGrace =
      Duration(milliseconds: 450);
  static const Duration _battleBgmDuration = Duration(microseconds: 60007438);
  static const Duration _homeBgmDuration = Duration(microseconds: 96003651);
  static const String _readySfx = 'メニューを開く3_ READY02.mp3';

  final MultiplayerManager _multiplayerManager = MultiplayerManager();
  final RankingManager _rankingManager = RankingManager.instance;
  final PlayerDataManager _playerDataManager = PlayerDataManager.instance;
  final ArenaManager _arenaManager = ArenaManager.instance;
  final MissionManager _missionManager = MissionManager.instance;
  late final PuzzleGame _playerGame;
  PuzzleGame? _cpuGame;
  final FocusNode _playerFocusNode = FocusNode();
  MultiplayerRoom? _room;
  bool _onlineGameStarted = false;
  bool _readySubmitting = false;
  String? _onlineResultMessage;
  bool _onlineResultWasForfeit = false;
  bool _onlineResultWasOfflineForfeit = false;
  bool _isWaitingForRematch = false;
  bool _opponentUnavailableForRematch = false;
  bool _isDisconnectDialogVisible = false;
  bool _isReturningToHome = false;
  bool _isCheckingHomeReturnConnection = false;
  bool? _cpuBattlePlayerWon;
  bool _rankedRatingApplied = false;
  RankedRatingChange? _rankedRatingChange;
  bool _rankedBotMatchOverlayVisible = false;
  bool _battleIntroLocked = false;
  Timer? _rankedAutoStartTimer;
  bool _rankedAutoStartScheduled = false;
  bool _opponentGameOverVerificationPending = false;
  Timer? _pendingEmptyOpponentBoardTimer;
  bool _matchingSfxPlayed = false;
  bool _autoReadyRequested = false;
  bool _pendingPreBattleForfeitWin = false;
  String? _readyGoOverlayText;
  bool _isBattleBgmPlaying = false;
  bool _resultRevealPending = false;
  bool _arenaResultApplied = false;
  ArenaMatchResult? _arenaMatchResult;
  bool _matchExpApplied = false;
  int? _matchExpEarned;
  bool _soloExpApplied = false;
  int? _soloExpEarned;
  bool _resultCoinApplied = false;
  int? _resultCoinBaseEarned;
  bool _resultCoinTripleClaimed = false;
  bool _resultCoinTripleInProgress = false;
  bool _didLevelUpFromResultExp = false;
  int? _resultLevelAfterExp;
  Set<String>? _resultUnlockedBadgeIdsBefore;
  List<BadgeItem> _newlyUnlockedBadges = const [];
  bool _battleBgmSuspendedByLifecycle = false;
  final Map<WazaType, int> _playerWazaCounts = {
    WazaType.straight: 0,
    WazaType.pyramid: 0,
    WazaType.hexagon: 0,
  };
  int _playerNormalClearedBalls = 0;

  // Stamp States
  bool _isStampCoolingDown = false;
  GameItem? _currentFloatingStamp;
  GameItem? _opponentFloatingStamp;
  bool _tutorialRightMoveActive = false;
  bool _tutorialLeftMoveActive = false;
  Timer? _myStampTimer;
  Timer? _opponentStampTimer;
  Timer? _stampCooldownTimer;
  Timer? _tutorialTimer;
  StreamSubscription<bool>? _realtimeConnectionSubscription;
  bool _realtimeConnected = true;
  bool _rankedOfflineForfeitStarted = false;
  DateTime? _lastRealtimeOfflineMessageAt;
  _TutorialPhase? _tutorialPhase;
  double? _tutorialStep1StartX;
  double? _tutorialStep2StartX;
  double? _tutorialStep3StartX;
  int _tutorialStep2RotationTicks = 0;
  int _tutorialStep3RotationTicks = 0;
  bool _tutorialOpponentAttackQueued = false;
  bool _tutorialOpponentDefeatQueued = false;
  DateTime? _ignoreEmptyOpponentBoardUntil;
  bool _resultAudioStarted = false;
  DateTime? _resultAudioStartedAt;
  final List<Timer> _pendingAttackTimers = [];

  bool get _isOnlineMode => widget.isOnlineMultiplayer;
  bool get _isTutorialStep3 {
    final phase = _tutorialPhase;
    return widget.isTutorialMode &&
        phase != null &&
        phase.index >= _TutorialPhase.step3Incoming.index;
  }

  bool get _showsOpponentBoard =>
      widget.isCpuMode || _isOnlineMode || _isTutorialStep3;
  bool get _usesEndlessBattleLayout =>
      !widget.isTutorialMode &&
      !_showsOpponentBoard &&
      !_isOnlineMode &&
      !widget.isCpuMode;
  bool get _blocksOnlineExit =>
      _isOnlineMode && _onlineGameStarted && _onlineResultMessage == null;

  String get _myDisplayName {
    if (widget.isTutorialMode) {
      return 'プレイヤー';
    }
    if (_isOnlineMode) {
      final roleId = _multiplayerManager.myRoleId;
      return _displayNameForRole(roleId) ??
          _multiplayerManager.displayPlayerName;
    }
    return _multiplayerManager.displayPlayerName;
  }

  String get _opponentDisplayName {
    if (widget.isTutorialMode) {
      return 'トレーナー';
    }
    if (widget.isCpuMode) {
      if (widget.isRankedMode) {
        return widget.rankedBotName;
      }
      return 'コンピュータ${_cpuDifficultyLabel(widget.cpuDifficulty)}';
    }
    if (_isOnlineMode) {
      return _displayNameForRole(_multiplayerManager.opponentRoleId) ??
          'Opponent';
    }
    return '';
  }

  int get _arenaRewardExp => _arenaMatchResult?.reward.exp ?? 0;

  int? get _rankedBotRating =>
      widget.isCpuMode && widget.isRankedMode ? widget.rankedBotRating : null;

  String _cpuDifficultyLabel(CPUDifficulty difficulty) {
    final rankedLevel = MultiplayerManager.rankedBotLevelForDifficulty(
      difficulty,
    );
    if (difficulty.name.startsWith('rankedLv')) {
      return 'ランクBot Lv.$rankedLevel';
    }
    return switch (difficulty) {
      CPUDifficulty.easy => '弱い',
      CPUDifficulty.normal => '普通',
      CPUDifficulty.hard => '強い',
      CPUDifficulty.oni => '鬼',
      _ => 'ランクBot Lv.$rankedLevel',
    };
  }

  int? get _totalResultExpEarned {
    final baseExp = _matchExpEarned ?? _soloExpEarned;
    if (baseExp == null) {
      return null;
    }
    return baseExp + _arenaRewardExp;
  }

  int get _straightCount => _playerWazaCounts[WazaType.straight] ?? 0;
  int get _pyramidCount => _playerWazaCounts[WazaType.pyramid] ?? 0;
  int get _hexagonCount => _playerWazaCounts[WazaType.hexagon] ?? 0;
  bool get _isTutorialBoardDropEnabled =>
      widget.isTutorialMode &&
      (_tutorialPhase == _TutorialPhase.step1Drop ||
          _tutorialPhase == _TutorialPhase.step2Drop ||
          _tutorialPhase == _TutorialPhase.step3Drop);

  int? get _totalResultCoinsEarned {
    final baseCoins = _resultCoinBaseEarned;
    if (baseCoins == null) {
      return null;
    }
    return _resultCoinTripleClaimed ? baseCoins * 3 : baseCoins;
  }

  bool get _isFriendMode =>
      _isOnlineMode && !widget.isRankedMode && !widget.isArenaMode;

  int get _currentPlayerScore => _playerGame.scoreManager.state.value.score;

  bool get _isRankedBotMode =>
      widget.isCpuMode && widget.isRankedMode && !_isOnlineMode;

  bool get _usesConstantFallSpeed =>
      widget.isCpuMode || widget.isOnlineMultiplayer || widget.isTutorialMode;

  bool get _showsStampButton => _isOnlineMode || _isRankedBotMode;

  bool get _isBattleInProgress =>
      _playerGame.gameStateWrapper.value == GameState.playing &&
      _readyGoOverlayText == null &&
      !_resultRevealPending &&
      _onlineResultMessage == null &&
      _cpuBattlePlayerWon == null;

  bool get _canOpenBattleSettings {
    final playerState = _playerGame.gameStateWrapper.value;
    final opponentState = _cpuGame?.gameStateWrapper.value;
    final resultSettled = _onlineResultMessage != null ||
        _cpuBattlePlayerWon != null ||
        playerState == GameState.gameover ||
        opponentState == GameState.gameover;
    return !_rankedBotMatchOverlayVisible &&
        !_isRankedBotMode &&
        !_battleIntroLocked &&
        _readyGoOverlayText == null &&
        !_resultRevealPending &&
        !resultSettled;
  }

  void _playUiTap() {
    final playerState = _playerGame.gameStateWrapper.value;
    final opponentState = _cpuGame?.gameStateWrapper.value;
    final isResultOrTransition = _readyGoOverlayText != null ||
        _resultRevealPending ||
        _onlineResultMessage != null ||
        _cpuBattlePlayerWon != null ||
        playerState == GameState.gameover ||
        opponentState == GameState.gameover;
    if (_isBattleInProgress || isResultOrTransition) {
      return;
    }
    AppSfx.playUiTap();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enterGameActivityPresence());
    unawaited(RewardedAdManager.instance.warmUp());
    unawaited(_arenaManager.load().then((_) {
      if (mounted) {
        setState(() {});
      }
    }));
    final gameSeed = widget.isOnlineMultiplayer
        ? _multiplayerManager.currentRoom?.seed
        : DateTime.now().millisecondsSinceEpoch;
    final localGameSeed = gameSeed ?? DateTime.now().millisecondsSinceEpoch;

    _playerGame = PuzzleGame(
      isCpuMode: false,
      seed: gameSeed,
      autoStart: false,
      useConstantFallSpeed: _usesConstantFallSpeed,
      manualPieceSpawning: widget.isTutorialMode,
      wallColor: Colors.blueAccent,
    );

    if (widget.isTutorialMode) {
      _cpuGame = PuzzleGame(
        isCpuMode: false,
        seed: gameSeed,
        autoStart: false,
        useConstantFallSpeed: true,
        manualPieceSpawning: true,
        wallColor: _battleOpponentColor,
      );
      _cpuGame!.onGameOverTriggered = () {
        unawaited(
          _presentBattleResult(
            playerWon: true,
            opponentCrossedDeathLine: true,
          ),
        );
      };
    }

    if (_isOnlineMode) {
      _cpuGame = PuzzleGame(
        isCpuMode: false,
        seed: gameSeed,
        autoStart: false,
        isRemotePlayerMode: true,
        useConstantFallSpeed: true,
        renderDetectedFormationEffects: false,
        wallColor: _battleOpponentColor,
      );
      _cpuGame!.onDeathLineCrossed = () {
        unawaited(_verifyOpponentDeathLineBeforeResult());
      };
    }

    if (_isOnlineMode) {
      _room = _multiplayerManager.currentRoom;
      _multiplayerManager.onRoomUpdated = _handleRoomUpdated;
      _multiplayerManager.onOpponentBoardUpdated = _handleOpponentBoardUpdated;
      _multiplayerManager.onOpponentPieceUpdated = _handleOpponentPieceUpdated;
      _multiplayerManager.onAttackReceived = _handleAttackReceived;
      _multiplayerManager.onOpponentStampReceived =
          _handleOpponentStampReceived;
      _multiplayerManager.onOpponentOjamaSpawned = _handleOpponentOjamaSpawned;
      _multiplayerManager.onOpponentGameOver = _handleOpponentGameOver;
      _multiplayerManager.onOpponentDisconnected = _handleOpponentDisconnected;
      _multiplayerManager.onRematchStarted = _handleRematchStarted;
      _startRealtimeConnectionWatch();
      if (_isOnlineMode) {
        _sendServerAction(
          () => _multiplayerManager.saveActiveSession(
            isArenaMode: widget.isArenaMode,
          ),
        );
      }
      if (_room?.bothPlayersReady ?? false) {
        _onlineGameStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_startOnlineBattleWithReadyGo(_room!.seed));
        });
      } else if (_room?.bothPlayersJoined ?? false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _playMatchedSfxOnce();
          unawaited(_attemptAutoReady());
        });
      }
    }

    if (_isRankedBotMode) {
      _startRealtimeConnectionWatch();
    }

    if (widget.isCpuMode && !widget.isTutorialMode) {
      _cpuGame = PuzzleGame(
        isCpuMode: true,
        seed: gameSeed,
        autoStart: false,
        useConstantFallSpeed: true,
        wallColor: _battleOpponentColor,
      );
      if (_cpuGame!.cpuAgent != null) {
        _cpuGame!.cpuAgent!.setDifficulty(widget.cpuDifficulty);
      }
      _cpuGame!.onGameOverTriggered = () {
        unawaited(
          _presentBattleResult(
            playerWon: true,
            opponentCrossedDeathLine: true,
          ),
        );
      };
    }

    _playerGame.onBoardUpdated = (boardData) {
      if (_isOnlineMode && _onlineGameStarted) {
        _sendServerAction(
          () => _multiplayerManager.sendBoardState(boardData),
          forfeitRankedOnOffline: widget.isRankedMode,
        );
      }
    };
    _playerGame.onActivePieceChanged =
        (action, x, y, rotation, colors, dropSeed) {
      if (_isOnlineMode && _onlineGameStarted) {
        _sendServerAction(
          () => _multiplayerManager.sendActivePiece(
            x,
            y,
            rotation,
            colors,
            action,
            dropSeed,
            _playerGame.nextPieceColors.value
                .map((color) => color.index)
                .toList(),
            _playerGame.isMovingLeft,
            _playerGame.isMovingRight,
            _playerGame.activePieceContactSlideDirection,
          ),
          forfeitRankedOnOffline: widget.isRankedMode,
        );
      }
    };
    _playerGame.onOjamaSpawned = (ojamaData, dropSeed) {
      if (_isOnlineMode && _onlineGameStarted) {
        _sendServerAction(
          () => _multiplayerManager.sendOjamaSpawn(ojamaData, dropSeed),
          forfeitRankedOnOffline: widget.isRankedMode,
        );
      }
    };
    _playerGame.onGameOverTriggered = () {
      if (widget.isCpuMode) {
        unawaited(_presentBattleResult(
            playerWon: false, opponentCrossedDeathLine: false));
        return;
      }
      if (_isOnlineMode) {
        _sendServerAction(
          _multiplayerManager.declareGameOver,
          forfeitRankedOnOffline: widget.isRankedMode,
        );
        unawaited(_presentBattleResult(
            playerWon: false, opponentCrossedDeathLine: false));
      } else {
        unawaited(_presentBattleResult(
            playerWon: false, opponentCrossedDeathLine: false));
      }
    };
    _playerGame.onDeathLineCrossed = () {
      _triggerResultAudio(playerWon: false);
    };
    _playerGame.onWazaFired = (waza, color) {
      _recordPlayerWaza(waza);
      if (widget.isCpuMode || _isOnlineMode) {
        unawaited(_missionManager.recordEvent('use_waza'));
        switch (waza) {
          case WazaType.straight:
            unawaited(_missionManager.recordEvent('use_straight'));
            break;
          case WazaType.pyramid:
            unawaited(_missionManager.recordEvent('use_pyramid'));
            break;
          case WazaType.hexagon:
            unawaited(_missionManager.recordEvent('use_hexagon'));
            break;
          case WazaType.none:
            break;
        }
      }
      if (_isOnlineMode) {
        final task = _createOjamaTaskForAttack(waza, color);
        if (task != null) {
          unawaited(_applyAttackToOpponent(task));
        }
      } else if (widget.isTutorialMode && _cpuGame != null) {
        if (_tutorialPhase == _TutorialPhase.step3Drop ||
            _tutorialPhase == _TutorialPhase.step3Skill) {
          _sendTutorialOjamaWithDelay(_cpuGame!, waza, color);
        }
      } else if (_cpuGame != null) {
        _sendOjamaWithDelay(_cpuGame!, waza, color);
      }
    };
    _playerGame.onBallsCleared = (ballsDestroyed) {
      if (widget.isCpuMode || _isOnlineMode) {
        unawaited(
          _missionManager.recordEvent('clear_balls', amount: ballsDestroyed),
        );
      }
    };
    _playerGame.onMatchCleared = (ballsDestroyed, highestWaza) {
      if (highestWaza == WazaType.none) {
        _playerNormalClearedBalls += ballsDestroyed;
      }
    };

    if (widget.isCpuMode && !widget.isTutorialMode && _cpuGame != null) {
      _cpuGame!.onWazaFired =
          (waza, color) => _sendOjamaWithDelay(_playerGame, waza, color);
    }

    if (widget.isTutorialMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startTutorialBattle());
      });
    } else if (!_isOnlineMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isRankedBotMode) {
          unawaited(_startRankedBotBattleAfterMatchOverlay(localGameSeed));
        } else {
          unawaited(_startLocalBattleWithReadyGo(localGameSeed));
        }
      });
    }
  }

  void _sendOjamaWithDelay(
    PuzzleGame targetGame,
    WazaType waza,
    BallColor? color,
  ) {
    late Timer timer;
    timer = Timer(const Duration(milliseconds: 2500), () {
      _pendingAttackTimers.remove(timer);

      if (targetGame.gameStateWrapper.value == GameState.playing) {
        if (waza == WazaType.hexagon) {
          targetGame.incomingOjama.add(OjamaTask(OjamaType.hexagonSet));
        } else if (waza == WazaType.pyramid) {
          targetGame.incomingOjama.add(OjamaTask(OjamaType.pyramidSet));
        } else if (waza == WazaType.straight) {
          targetGame.incomingOjama.add(
            OjamaTask(OjamaType.straightSet, startColor: color),
          );
        }
      }
    });
    _pendingAttackTimers.add(timer);
  }

  void _sendTutorialOjamaWithDelay(
    PuzzleGame targetGame,
    WazaType waza,
    BallColor? color,
  ) {
    final task = _createOjamaTaskForAttack(waza, color);
    if (task == null) {
      return;
    }
    late Timer timer;
    timer = Timer(const Duration(milliseconds: 2500), () {
      _pendingAttackTimers.remove(timer);
      targetGame.resumeEngine();
      targetGame.forceDropOjamaTask(task);
      unawaited(_ensureTutorialOpponentDefeatAfterOjama(targetGame));
    });
    _pendingAttackTimers.add(timer);
  }

  Future<void> _ensureTutorialOpponentDefeatAfterOjama(
    PuzzleGame opponentGame,
  ) async {
    if (_tutorialOpponentDefeatQueued) {
      return;
    }
    _tutorialOpponentDefeatQueued = true;

    await Future<void>.delayed(const Duration(milliseconds: 700));
    while (mounted &&
        widget.isTutorialMode &&
        opponentGame.gameStateWrapper.value == GameState.playing &&
        (_pendingAttackTimers.isNotEmpty ||
            opponentGame.pendingOjamaSpawns > 0 ||
            opponentGame.hasActiveOjamaAnimation ||
            opponentGame.isBoardProcessing)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (!mounted ||
        !widget.isTutorialMode ||
        opponentGame.gameStateWrapper.value == GameState.gameover ||
        _resultRevealPending) {
      return;
    }

    if (opponentGame.hasOverflowedDeathLine) {
      opponentGame.gameOver();
    }
  }

  void _sendTutorialIncomingOjamaToPlayer() {
    if (!widget.isTutorialMode ||
        _tutorialPhase != _TutorialPhase.step3OpponentAttack ||
        _tutorialOpponentAttackQueued) {
      return;
    }
    _dropTutorialIncomingOjama(_tutorialIncomingStraightOjamaTask());
  }

  void _dropTutorialIncomingOjama(OjamaTask task) {
    if (_tutorialOpponentAttackQueued) {
      return;
    }
    _tutorialOpponentAttackQueued = true;
    _playerGame.resumeEngine();
    _playerGame.forceDropOjamaTask(task);
    setState(() {
      _tutorialPhase = _TutorialPhase.step3OpponentAttack;
    });
    unawaited(_unlockTutorialPlayerAfterIncomingOjama());
  }

  OjamaTask _tutorialIncomingStraightOjamaTask() {
    return OjamaTask(
      OjamaType.straightSet,
      startColor: BallColor.purple,
      presetColors: const [
        BallColor.purple,
        BallColor.red,
        BallColor.green,
        BallColor.green,
        BallColor.yellow,
        BallColor.blue,
        BallColor.red,
        BallColor.blue,
        BallColor.red,
        BallColor.red,
        BallColor.blue,
        BallColor.green,
        BallColor.blue,
        BallColor.blue,
        BallColor.green,
        BallColor.purple,
        BallColor.red,
        BallColor.green,
        BallColor.red,
      ],
    );
  }

  Future<void> _unlockTutorialPlayerAfterIncomingOjama() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    while (mounted &&
        _tutorialPhase == _TutorialPhase.step3OpponentAttack &&
        (_playerGame.pendingOjamaSpawns > 0 ||
            _playerGame.hasActiveOjamaAnimation)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (!mounted || _tutorialPhase != _TutorialPhase.step3OpponentAttack) {
      return;
    }
    _cpuGame?.pauseEngine();
    _playerGame.spawnFixedPiece(
      colors: const [BallColor.green, BallColor.green, BallColor.blue],
      column: 4,
    );
    _tutorialStep3StartX = _playerGame.activePieceX;
    setState(() {
      _tutorialPhase = _TutorialPhase.step3Move;
    });
  }

  void _clearAllPendingAttacks() {
    for (final t in _pendingAttackTimers) {
      t.cancel();
    }
    _pendingAttackTimers.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_suspendBattleBgmForLifecycle());
      unawaited(GameActivityPresence.instance.exit());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeBattleBgmFromLifecycle());
      if (!_isReturningToHome) {
        unawaited(_enterGameActivityPresence());
      }
    }
  }

  Future<void> _suspendBattleBgmForLifecycle() async {
    if (_battleBgmSuspendedByLifecycle) {
      return;
    }
    _battleBgmSuspendedByLifecycle = true;
    await SeamlessBgm.instance.suspendForExternalAudio();
  }

  Future<void> _resumeBattleBgmFromLifecycle() async {
    if (_battleBgmSuspendedByLifecycle) {
      _battleBgmSuspendedByLifecycle = false;
      await SeamlessBgm.instance.resumeFromExternalAudio();
    }
    if (_isBattleBgmPlaying && !SeamlessBgm.instance.isPlaying) {
      await _startBattleBgm();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(GameActivityPresence.instance.exit());
    _clearAllPendingAttacks();
    _rankedAutoStartTimer?.cancel();
    _pendingEmptyOpponentBoardTimer?.cancel();
    _myStampTimer?.cancel();
    _opponentStampTimer?.cancel();
    _stampCooldownTimer?.cancel();
    _tutorialTimer?.cancel();
    _realtimeConnectionSubscription?.cancel();
    _shutdownBattleGames();
    unawaited(SfxPlayer.resetTransientAudio());
    if (!_isReturningToHome) {
      unawaited(_stopBattleBgm());
    }
    if (widget.isOnlineMultiplayer && !_isReturningToHome) {
      unawaited(_multiplayerManager.leaveRoom());
    }
    _playerFocusNode.dispose();
    super.dispose();
  }

  void _shutdownBattleGames() {
    _playerGame.freezeToBoardOnly();
    _cpuGame?.freezeToBoardOnly();
  }

  Future<void> _enterGameActivityPresence() async {
    if (widget.isTutorialMode) {
      return;
    }
    await GameActivityPresence.instance.enter(
      mode: _activityMode,
      roomId: widget.roomId,
    );
  }

  GameActivityMode get _activityMode {
    if (widget.isArenaMode) {
      return GameActivityMode.arena;
    }
    if (widget.isRankedMode) {
      return GameActivityMode.ranked;
    }
    if (widget.isOnlineMultiplayer) {
      return GameActivityMode.friend;
    }
    if (widget.isCpuMode) {
      return GameActivityMode.cpu;
    }
    return GameActivityMode.endless;
  }

  void _handleOpponentStampReceived(String stampId, int level) {
    if (!mounted) return;
    final stamp = GameItemCatalog.byId(stampId);
    if (stamp != null) {
      final displayedStamp = stamp.copyWith(level: level.clamp(1, 4));
      setState(() {
        _opponentFloatingStamp = displayedStamp;
      });
      _opponentStampTimer?.cancel();
      _opponentStampTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _opponentFloatingStamp = null;
          });
        }
      });
    }
  }

  void _sendStamp(GameItem stamp) {
    if (!mounted || _isStampCoolingDown) return;

    AppSfx.playUiTap();
    if (_isOnlineMode) {
      _sendServerAction(
        () => _multiplayerManager.sendStamp(
          stamp.id,
          level: stamp.level,
        ),
      );
    }

    setState(() {
      _currentFloatingStamp = stamp;
      _isStampCoolingDown = true;
    });

    _stampCooldownTimer?.cancel();
    _stampCooldownTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isStampCoolingDown = false;
        });
      }
    });

    _myStampTimer?.cancel();
    _myStampTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _currentFloatingStamp = null;
        });
      }
    });
  }

  void _showStampGrid() {
    final ownedStampsById = {
      for (final item in PlayerDataManager.instance.ownedItems
          .where((item) => item.isStamp))
        item.id: item,
    };
    final equippedStamps = PlayerDataManager.instance.equippedStampIds
        .map((id) => ownedStampsById[id] ?? GameItemCatalog.byId(id))
        .whereType<GameItem>()
        .toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F13).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: _gameCyan.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SEND STAMP',
                style: TextStyle(
                  color: _gameCyan,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              if (equippedStamps.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '装備中のスタンプがありません。\nコレクションから最大6つ装備できます。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: equippedStamps.map((stamp) {
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _sendStamp(stamp);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 140,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: _gameCyan.withValues(alpha: 0.06),
                          border: Border.all(
                            color: _gameCyan.withValues(alpha: 0.36),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: StampWidget(
                            item: stamp,
                            level: stamp.level,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_blocksOnlineExit,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F13),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (_showsOpponentBoard)
                    Expanded(child: _buildOpponentArea(_cpuGame!))
                  else
                    _buildGlobalHeader(),
                  if (_isTutorialStep3) _buildTutorialStep3Message(),
                  if (!_showsOpponentBoard &&
                      !widget.isCpuMode &&
                      !_isOnlineMode)
                    _buildScoreWidget(_playerGame),
                  Expanded(child: _buildPlayerArea(_playerGame)),
                  _buildControls(_playerGame),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.instance.adsRemoved,
                    builder: (context, adsRemoved, child) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 50.0,
                            width: double.infinity,
                            child: adsRemoved
                                ? const SizedBox.shrink()
                                : const BannerAdWidget(),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              if (_isOnlineMode)
                _buildOnlineOverlay()
              else
                _buildGlobalOverlay(),
              if (_rankedBotMatchOverlayVisible) _buildRankedBotMatchOverlay(),
              if (widget.isArenaMode) _buildArenaRecordBadge(),
              if (!_isOnlineMode &&
                  !widget.isTutorialMode &&
                  !_isRankedBotMode &&
                  !_usesEndlessBattleLayout)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _buildBattleSettingsButton(),
                ),
              if (widget.isTutorialMode) _buildTutorialSkipOverlay(),
              if (_readyGoOverlayText != null) _buildReadyGoOverlay(),
              if (_currentFloatingStamp != null)
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.17,
                  left: 12,
                  child: _buildFloatingStampWidget(
                    _currentFloatingStamp!,
                    compact: true,
                  ),
                ),
              if (_opponentFloatingStamp != null)
                Positioned(
                  bottom: MediaQuery.of(context).size.height * 0.24,
                  left: 6,
                  child: _buildFloatingStampWidget(
                    _opponentFloatingStamp!,
                    compact: true,
                    isOpponent: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingStampWidget(
    GameItem stamp, {
    bool compact = false,
    double scale = 1,
    bool isOpponent = false,
  }) {
    final normalizedScale = compact ? scale : 1.0;
    final borderColor = isOpponent ? _battleOpponentColor : _battlePlayerColor;
    return Semantics(
      label: 'stamp',
      child: IgnorePointer(
        child: Container(
          width: compact ? _compactStampWidth * normalizedScale : 260,
          constraints: compact
              ? null
              : const BoxConstraints(
                  minHeight: 74,
                ),
          padding: compact
              ? EdgeInsets.symmetric(
                  horizontal: 12 * normalizedScale,
                  vertical: 8 * normalizedScale,
                )
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: compact ? 0.76 : 0.87),
            borderRadius: BorderRadius.circular(
              compact ? 10 * normalizedScale : 16,
            ),
            border: Border.all(
              color: borderColor.withValues(alpha: compact ? 0.7 : 0.5),
              width: compact ? 1.2 * normalizedScale : 2,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: StampWidget(
              item: stamp,
              level: stamp.level,
              forceLarge: !compact,
              colorOverride:
                  isOpponent ? _battleOpponentColor : _battlePlayerColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlobalHeader() {
    return const SizedBox.shrink();
  }

  Widget _buildArenaRecordBadge() {
    final wins = _arenaMatchResult?.wins ?? _arenaManager.currentWins;
    final losses = _arenaMatchResult?.losses ?? _arenaManager.currentLosses;
    return Positioned(
      top: 8,
      right: 12,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _gameCyan.withValues(alpha: 0.72),
              )),
          child: Text(
            'アリーナ  $wins勝 $losses敗',
            style: const TextStyle(
              color: _gameCyan,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArenaResultSummary() {
    final result = _arenaMatchResult;
    final wins = result?.wins ?? _arenaManager.currentWins;
    final losses = result?.losses ?? _arenaManager.currentLosses;
    final reward = result?.reward;

    if (result?.isCompleted == true && reward != null) {
      return _buildResultInfoRow(
        label: 'アリーナ報酬',
        value: '+${reward.coins}',
        color: const Color(0xFFEAF6FF),
        leadingValue: const HexagonCoinIcon(size: 18),
      );
    }

    return _buildResultInfoRow(
      label: 'アリーナ',
      value: '$wins勝 $losses敗',
      color: _gameCyan,
    );
  }

  Widget _buildResultCoinSummary() {
    final totalCoins = _totalResultCoinsEarned;
    if (totalCoins == null) {
      return const Text(
        '集計中...',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: HexagonCoinIcon(size: 24),
          ),
          Center(
            child: Text(
              '+$totalCoins',
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFFEAF6FF),
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (!AppSettings.instance.adsRemoved.value)
            Align(
              alignment: Alignment.centerRight,
              child: _buildResultCoinTripleButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildResultCoinTripleButton() {
    final waiting = _resultCoinTripleInProgress;
    final claimed = _resultCoinTripleClaimed;
    return InkWell(
      onTap: waiting || claimed || _resultCoinBaseEarned == null
          ? null
          : () {
              unawaited(_claimResultTripleCoinBonus());
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: claimed
              ? _endlessGreen.withValues(alpha: 0.12)
              : Colors.amberAccent.withValues(alpha: waiting ? 0.08 : 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: claimed
                ? _endlessGreen.withValues(alpha: 0.55)
                : Colors.amberAccent.withValues(alpha: waiting ? 0.28 : 0.78),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!claimed && !waiting) ...[
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.amberAccent,
                size: 24,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              claimed
                  ? '獲得済み'
                  : waiting
                      ? '再生中...'
                      : '×3倍',
              style: TextStyle(
                color: claimed
                    ? _endlessGreen
                    : waiting
                        ? Colors.white54
                        : Colors.amberAccent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultExpSummary() {
    final totalExp = _totalResultExpEarned;
    if (totalExp == null) {
      return const Text(
        'EXPを集計中...',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildResultInfoRow(
          label: 'EXP',
          value: '+$totalExp',
          color: Colors.white,
          centerValue: true,
        ),
        if (_didLevelUpFromResultExp) ...[
          const SizedBox(height: 8),
          _buildResultInfoRow(
            label: 'LEVEL UP',
            value: _resultLevelAfterExp == null
                ? ''
                : 'Lv.${_resultLevelAfterExp!}',
            color: _gameCyan,
          ),
        ],
      ],
    );
  }

  Widget _buildResultScoreSummary() {
    return _buildResultInfoRow(
      label: 'スコア',
      value: '$_currentPlayerScore',
      color: _endlessGreen,
      valueColor: Colors.white,
    );
  }

  Widget _buildBattleResultProfiles() {
    if (!widget.isCpuMode && !widget.isTutorialMode && !_isOnlineMode) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildResultProfileCard(
          label: 'あなた',
          accentColor: _battlePlayerColor,
          name: _myDisplayName,
          iconId: _playerDataManager.equippedPlayerIconId,
          iconFrameId: _playerDataManager.equippedIconFrameId,
          badgeIds: _playerDataManager.equippedBadgeIds,
          ratingDelta: _myResultRatingDeltaText(),
          ratingDeltaColor: _myResultRatingDeltaColor(),
          showRatingDelta: true,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'VS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ),
        _buildResultProfileCard(
          label: '相手',
          accentColor: _battleOpponentColor,
          name: _opponentResultName(),
          iconId: _opponentResultIconId(),
          iconFrameId: _opponentResultIconFrameId(),
          badgeIds: _opponentResultBadgeIds(),
          ratingDelta: '',
          ratingDeltaColor: _battleOpponentColor,
          showRatingDelta: false,
        ),
      ],
    );
  }

  Widget _buildResultProfileCard({
    required String label,
    required Color accentColor,
    required String name,
    required String iconId,
    required String iconFrameId,
    required List<String> badgeIds,
    required String ratingDelta,
    required Color ratingDeltaColor,
    required bool showRatingDelta,
  }) {
    final iconFrameColor = _playerIconFrameColor(iconFrameId);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconFrameColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: iconFrameColor,
                    width: 2,
                  ),
                ),
                child: Icon(
                  _playerIconData(iconId),
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildResponsiveResultNameText(name),
                          const SizedBox(height: 6),
                          _buildBadgeIconRow(badgeIds),
                        ],
                      ),
                    ),
                    if (showRatingDelta &&
                        ratingDelta.isNotEmpty &&
                        ratingDelta != 'なし') ...[
                      const SizedBox(width: 10),
                      _buildInlineRatingDelta(
                        value: ratingDelta,
                        color: ratingDeltaColor,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInlineRatingDelta({
    required String value,
    required Color color,
  }) {
    final isRatingValue = value != '変動なし';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRatingValue) ...[
            const HexagonTrophyIcon(size: 16),
            const SizedBox(width: 4),
          ],
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveResultNameText(String name) {
    return SizedBox(
      width: double.infinity,
      height: 24,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            name,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  String _myResultRatingDeltaText() {
    if (widget.isRankedMode && _rankedRatingChange != null) {
      final delta = _rankedRatingChange!.delta;
      return delta >= 0 ? '+$delta' : '$delta';
    }
    if (widget.isArenaMode) {
      return '変動なし';
    }
    return 'なし';
  }

  Color _myResultRatingDeltaColor() {
    return Colors.amberAccent;
  }

  String _opponentResultName() {
    if (widget.isTutorialMode) {
      return _opponentDisplayName;
    }
    if (widget.isCpuMode) {
      return _opponentDisplayName;
    }
    return _displayNameForRole(_multiplayerManager.opponentRoleId) ??
        'Opponent';
  }

  String _opponentResultIconId() {
    if (widget.isTutorialMode) {
      return 'icon_bolt';
    }
    if (widget.isCpuMode) {
      return widget.isRankedMode ? 'default' : 'icon_bolt';
    }
    return _room?.players[_multiplayerManager.opponentRoleId]?.playerIconId ??
        'default';
  }

  String _opponentResultIconFrameId() {
    if (widget.isTutorialMode || widget.isCpuMode) {
      return 'default';
    }
    return _room
            ?.players[_multiplayerManager.opponentRoleId]?.playerIconFrameId ??
        'default';
  }

  List<String> _opponentResultBadgeIds() {
    if (widget.isTutorialMode) {
      return const [];
    }
    if (widget.isCpuMode) {
      return const [];
    }
    return _room?.players[_multiplayerManager.opponentRoleId]?.badgeIds ??
        const [];
  }

  Widget _buildResultInfoRow({
    required String label,
    required String value,
    required Color color,
    Color? valueColor,
    String? trailing,
    Widget? leadingValue,
    bool centerValue = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: centerValue
          ? Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      color: valueColor ?? color,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (leadingValue != null) ...[
                  leadingValue,
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        color: valueColor ?? color,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    trailing,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildScoreWidget(PuzzleGame game) {
    if (widget.isTutorialMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: _buildTutorialMessageCard(
          child: SizedBox(
            height: 58,
            child: Center(
              child: Text(
                _tutorialMessage,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final useEndlessLayout = _usesEndlessBattleLayout;
    final levelColor = useEndlessLayout ? _endlessGreen : Colors.amberAccent;
    final scorePanel = Container(
      margin: EdgeInsets.fromLTRB(
          useEndlessLayout ? 64 : 16, useEndlessLayout ? 18 : 10, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF101827).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _gameCyan.withValues(alpha: 0.42),
            width: 1.2,
          )),
      child: ValueListenableBuilder(
        valueListenable: game.scoreManager.state,
        builder: (context, state, child) {
          return Row(
            children: [
              Container(
                width: 76,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: levelColor.withValues(alpha: 0.42),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'レベル',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${state.level}',
                      style: TextStyle(
                        color: levelColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _gameCyan.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'スコア',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${state.score}',
                          maxLines: 1,
                          style: const TextStyle(
                            color: Color(0xFFEAF6FF),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (!useEndlessLayout) {
      return scorePanel;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        scorePanel,
        Positioned(
          left: 16,
          top: 30,
          child: _buildBattleSettingsButton(),
        ),
      ],
    );
  }

  Widget _buildPlayerArea(PuzzleGame game) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePanelWidth = constraints.maxWidth / 5;
        final isSoloMode =
            !_showsOpponentBoard && !_isOnlineMode && !widget.isCpuMode;
        final boardWidth = isSoloMode
            ? max(0.0, constraints.maxWidth - sidePanelWidth * 2)
            : constraints.maxWidth;
        final nextBallSize = _scaledGridBallDiameter(
          boardWidth: boardWidth,
          boardHeight: constraints.maxHeight,
        );

        return Stack(
          children: [
            if (isSoloMode)
              Positioned(
                top: 0,
                left: 0,
                bottom: 0,
                width: sidePanelWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (_) {
                    if (_handleTutorialBoardTap(game)) {
                      return;
                    }
                    _playUiTap();
                    game.triggerHardDrop();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (_) {
                  if (_handleTutorialBoardTap(game)) {
                    return;
                  }
                  _playUiTap();
                  game.triggerHardDrop();
                },
                child: SizedBox(
                  width: boardWidth,
                  height: constraints.maxHeight,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: _buildGameViewport(game, isPlayer: true),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: sidePanelWidth,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapDown: (_) {
                        if (_handleTutorialBoardTap(game)) {
                          return;
                        }
                        _playUiTap();
                        game.triggerHardDrop();
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildNameBadge(
                          _myDisplayName,
                          isCpu: false,
                          roleLabel: 'あなた',
                        ),
                        const SizedBox(height: 16),
                        _buildNextBadge(
                          game,
                          isCpu: false,
                          ballSize: nextBallSize,
                        ),
                        if (_showsStampButton) ...[
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _isStampCoolingDown
                                ? null
                                : () {
                                    AppSfx.playUiTap();
                                    _showStampGrid();
                                  },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: _gameCyan.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _gameCyan.withValues(alpha: 0.58),
                                  )),
                              child: Icon(
                                Icons.chat,
                                color: _gameCyan.withValues(
                                  alpha: _isStampCoolingDown ? 0.72 : 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isTutorialBoardDropEnabled) _buildTutorialDropTargetOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildOpponentArea(PuzzleGame game) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePanelWidth = constraints.maxWidth / 5;
        final nextBallSize = _scaledGridBallDiameter(
          boardWidth: constraints.maxWidth - 16,
          boardHeight: constraints.maxHeight - 16,
        );

        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: _buildGameViewport(game, isPlayer: false),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: sidePanelWidth,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildNameBadge(
                      _opponentDisplayName,
                      isCpu: true,
                      roleLabel: '相手',
                    ),
                    const SizedBox(height: 16),
                    _buildNextBadge(
                      game,
                      isCpu: true,
                      ballSize: nextBallSize,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _scaledGridBallDiameter({
    required double boardWidth,
    required double boardHeight,
  }) {
    if (boardWidth <= 0 || boardHeight <= 0) {
      return _gridBallDiameter;
    }

    final boardScale = min(
      boardWidth / _gameViewportWidth,
      boardHeight / _gameViewportHeight,
    );
    return _gridBallDiameter * boardScale;
  }

  Widget _buildGameViewport(PuzzleGame game, {required bool isPlayer}) {
    return SizedBox(
      width: _gameViewportWidth,
      height: _gameViewportHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GameWidget(
              game: game,
              focusNode: isPlayer ? _playerFocusNode : null,
              autofocus: isPlayer,
            ),
          ),
          _buildWazaNameInGrid(game),
        ],
      ),
    );
  }

  Widget _buildWazaNameInGrid(PuzzleGame game) {
    final gridTop = game.grid.offset.y;
    final gridHeight = game.grid.floorY - gridTop;
    final top = (gridTop + gridHeight * 0.4 + 4).clamp(0.0, 430.0);
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      height: 48,
      child: ValueListenableBuilder<String?>(
        valueListenable: game.wazaNameNotifier,
        builder: (context, name, child) {
          if (name == null) {
            return const SizedBox.shrink();
          }
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNameBadge(
    String name, {
    required bool isCpu,
    required String roleLabel,
  }) {
    final neonColor = isCpu ? _battleOpponentColor : _battlePlayerColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 112,
              height: 38,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E1E28),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: neonColor.withValues(alpha: 0.8),
                    width: 1.5,
                  )),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F13),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: neonColor.withValues(alpha: 0.85)),
                ),
                child: Text(
                  roleLabel,
                  style: TextStyle(
                    color: neonColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBadgeIconRow(List<String> badgeIds) {
    final badges = badgeIds.map(_badgeIconForId).whereType<Widget>().take(2);
    if (badges.isEmpty) {
      return const SizedBox(height: 24);
    }

    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final badge in badges) badge,
        ],
      ),
    );
  }

  Widget? _badgeIconForId(String id) {
    if (SeasonRankBadge.isSeasonRankBadgeId(id)) {
      return null;
    }
    final badge = BadgeCatalog.findById(id);
    if (badge == null) {
      return null;
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: badge.frameColor.withValues(alpha: 0.7),
        ),
      ),
      child: Icon(
        badge.icon,
        size: 14,
        color: badge.frameColor,
      ),
    );
  }

  Widget _buildNextBadge(
    PuzzleGame game, {
    required bool isCpu,
    required double ballSize,
  }) {
    final neonColor = isCpu ? _battleOpponentColor : _battlePlayerColor;
    return Container(
      width: ballSize * 2 + 16,
      height: ballSize * 2 + 40,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFF1E1E28),
          border: Border.all(
            color: neonColor.withValues(alpha: 0.5),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ballSize * 2 + 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'ネクスト',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: neonColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<BallColor>>(
            valueListenable: game.nextPieceColors,
            builder: (context, colors, child) => _buildPieceIcon(
              colors,
              size: ballSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalOverlay() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _playerGame.gameStateWrapper,
          if (_cpuGame != null) _cpuGame!.gameStateWrapper,
        ]),
        builder: (context, child) {
          final pState = _playerGame.gameStateWrapper.value;
          final cState = _cpuGame?.gameStateWrapper.value ?? GameState.playing;

          if (pState == GameState.playing && cState == GameState.playing) {
            return const SizedBox.shrink();
          }

          if (pState == GameState.ready) {
            return Container(
              color: const Color(0xFF0F0F13).withValues(alpha: 0.90),
              child: Center(
                child: Text(
                  _playerGame.isReadyGoText ? 'GO!' : 'READY',
                  style: TextStyle(
                    fontSize: 48,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w900,
                    color: _playerGame.isReadyGoText
                        ? _battleOpponentColor
                        : Colors.orangeAccent,
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final gameOver = pState == GameState.gameover ||
              (cState == GameState.gameover &&
                  (widget.isCpuMode || widget.isTutorialMode));
          if (!gameOver || _resultRevealPending) {
            return const SizedBox.shrink();
          }

          final cpuPlayerWon =
              _cpuBattlePlayerWon ?? (pState != GameState.gameover);
          final isBattleResult = widget.isCpuMode || widget.isTutorialMode;
          final title =
              isBattleResult ? (cpuPlayerWon ? '勝ち' : '負け') : 'ゲームオーバー';
          final titleColor = isBattleResult
              ? (cpuPlayerWon ? _battlePlayerColor : _battleOpponentColor)
              : _endlessGreen;

          return _buildUnifiedResultSheet(
            title: title,
            titleColor: titleColor,
            children: widget.isTutorialMode
                ? _buildTutorialResultChildren()
                : [
                    _buildBattleResultProfiles(),
                    if (!isBattleResult) ...[
                      const SizedBox(height: 12),
                      _buildResultScoreSummary(),
                    ],
                    const SizedBox(height: 18),
                    _buildResultCoinSummary(),
                    const SizedBox(height: 12),
                    _buildResultExpSummary(),
                    if (_newlyUnlockedBadges.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildBadgeUnlockResultCard(),
                    ],
                    const SizedBox(height: 12),
                    if (!isBattleResult) ...[
                      _buildCyberResultButton(
                        label: 'リスタート',
                        baseColor: _endlessGreen,
                        isWaiting: false,
                        onPressed: () {
                          _clearAllPendingAttacks();
                          unawaited(
                            _startLocalBattleWithReadyGo(
                              DateTime.now().millisecondsSinceEpoch,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildCyberResultButton(
                      label: 'ホームへ戻る',
                      baseColor: _mutedButtonGrey,
                      isWaiting: false,
                      onPressed: () {
                        _clearAllPendingAttacks();
                        unawaited(_returnHomeAfterMatch());
                      },
                    ),
                  ],
          );
        },
      ),
    );
  }

  Widget _buildOnlineOverlay() {
    if (!_onlineGameStarted) {
      return _buildLobbyOverlay();
    }

    if (_onlineResultMessage == null) {
      return const SizedBox.shrink();
    }

    final win = _onlineResultMessage == 'YOU WIN!!';
    final textColor = win ? _battlePlayerColor : _battleOpponentColor;
    final title = win && _onlineResultWasForfeit
        ? '不戦勝'
        : _onlineResultWasOfflineForfeit
            ? '不戦敗'
            : (win ? '勝ち' : '負け');

    return Positioned.fill(
      child: _buildUnifiedResultSheet(
        title: title,
        titleColor: textColor,
        children: [
          _buildBattleResultProfiles(),
          if (widget.isArenaMode) ...[
            const SizedBox(height: 12),
            _buildArenaResultSummary(),
          ],
          const SizedBox(height: 18),
          _buildResultCoinSummary(),
          const SizedBox(height: 12),
          _buildResultExpSummary(),
          if (_newlyUnlockedBadges.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildBadgeUnlockResultCard(),
          ],
          const SizedBox(height: 12),
          if (_canShowRematchButton) ...[
            _buildCyberResultButton(
              label: _isWaitingForRematch ? '相手の準備待ち...' : '再戦',
              baseColor: Colors.blueAccent,
              isWaiting: _isWaitingForRematch,
              onPressed: _isWaitingForRematch
                  ? null
                  : () {
                      _requestRematch();
                    },
            ),
            const SizedBox(height: 12),
          ],
          _buildCyberResultButton(
            label: 'ホームへ戻る',
            baseColor: _mutedButtonGrey,
            isWaiting: false,
            onPressed: () {
              _leaveOnlineBattle();
            },
          ),
        ],
      ),
    );
  }

  bool get _canShowRematchButton {
    if (widget.isRankedMode ||
        _onlineResultWasForfeit ||
        _opponentUnavailableForRematch) {
      return false;
    }
    final room = _room ?? _multiplayerManager.currentRoom;
    if (room == null) {
      return false;
    }
    return !_opponentHasLeft(room);
  }

  bool _opponentHasLeft(MultiplayerRoom room) {
    final opponent = room.players[_multiplayerManager.opponentRoleId];
    return opponent == null || opponent.status == 'left';
  }

  List<Widget> _buildTutorialResultChildren() {
    return [
      const SizedBox(height: 4),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _gameCyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _gameCyan.withValues(alpha: 0.32))),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TutorialResultLine(
              title: '基本ルール',
              body: '同じ色のボールを6つ以上繋げると消えます。盤面を整えながら、消せる場所を増やしていきましょう。',
            ),
            SizedBox(height: 12),
            _TutorialResultLine(
              title: 'フォーメーションの種類',
              body: 'ヘキサゴン：同じ色を六角形に並べる\nピラミッド：同じ色を三角形に並べる\nストレート：同じ色を一直線に並べる',
            ),
            SizedBox(height: 12),
            _TutorialResultLine(
              title: 'フォーメーションの効果',
              body:
                  'フォーメーションを決めると、盤面内にある同じ色のボールがすべて消えます。対戦では、さらに相手に妨害ボールを送れます。',
            ),
            SizedBox(height: 12),
            _TutorialResultLine(
              title: '妨害ボール数',
              body: 'ヘキサゴン 36個\nピラミッド 24個\nストレート 19個',
            ),
            SizedBox(height: 12),
            _TutorialResultLine(
              title: '操作パネル',
              body: '操作パネルの配置は、設定画面から変更できます。',
            ),
            SizedBox(height: 12),
            _TutorialResultLine(
              title: 'チュートリアル',
              body: 'チュートリアルは、設定画面からいつでも見返せます。',
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _buildCyberResultButton(
        label: 'ホームへ戻る',
        baseColor: _mutedButtonGrey,
        isWaiting: false,
        onPressed: () {
          _clearAllPendingAttacks();
          unawaited(_returnHomeAfterMatch());
        },
      ),
    ];
  }

  Widget _buildUnifiedResultSheet({
    required String title,
    required Color titleColor,
    required List<Widget> children,
  }) {
    return Container(
      color: const Color(0xFF0F0F13).withValues(alpha: 0.90),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: const Color(0xFF141421),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: titleColor.withValues(alpha: 0.7),
                      width: 1.5,
                    )),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCyberResultButton({
    required String label,
    required VoidCallback? onPressed,
    required Color baseColor,
    required bool isWaiting,
  }) {
    if (isWaiting) {
      return Container(
        width: 280,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onPressed == null
          ? null
          : () {
              _playUiTap();
              onPressed();
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 280,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
            color: baseColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: baseColor.withValues(alpha: 0.8), width: 2)),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadyGoOverlay() {
    final text = _readyGoOverlayText!;
    final isGo = text == 'GO!';
    final alignment =
        _showsOpponentBoard ? const Alignment(0, -0.18) : Alignment.center;
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: isGo ? 0.18 : 0.38),
          child: Align(
            alignment: alignment,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                text,
                key: ValueKey(text),
                style: TextStyle(
                  color: isGo ? _battleOpponentColor : Colors.white,
                  fontSize: isGo ? 56 : 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyOverlay() {
    final room = _room;
    final isHost = _multiplayerManager.isHost;
    final canShowReady = room?.bothPlayersJoined ?? false;
    final myStatus =
        room?.players[_multiplayerManager.myRoleId]?.status ?? 'waiting';
    final hostReady = room?.players['host']?.status == 'ready';
    final guestReady = room?.players['guest']?.status == 'ready';
    final opponentName =
        _displayNameForRole(_multiplayerManager.opponentRoleId);
    final showAutoStart = widget.isRankedMode || _isFriendMode;

    if (_onlineGameStarted || room == null) {
      return const SizedBox.shrink();
    }

    final lobbyAccent = widget.isArenaMode
        ? _gameCyan
        : widget.isRankedMode
            ? _rankedPurple
            : _friendPink;

    return Positioned.fill(
      child: Container(
        color: const Color(0xEE0F0F13),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF141421),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: lobbyAccent.withValues(alpha: 0.75),
                    width: 1.5,
                  )),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isArenaMode
                        ? 'アリーナマッチが成立しました'
                        : widget.isRankedMode
                            ? 'ランク戦が成立しました'
                            : isHost
                                ? 'フレンド対戦の部屋を作成'
                                : 'フレンド対戦に参加しました',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (isHost && !widget.isRankedMode) ...[
                    const Text(
                      'ルームID',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      room.roomId,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!showAutoStart || !canShowReady) ...[
                    Text(
                      canShowReady && opponentName != null
                          ? '$opponentName が参加しました。READYで開始準備をしてください。'
                          : canShowReady
                              ? '両プレイヤーがそろいました。READYで開始準備をしてください。'
                              : widget.isRankedMode
                                  ? '対戦相手の接続を待っています...'
                                  : '相手の入室を待っています…',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                  _buildLobbyStatusRow(
                    _displayNameForRole('host') ?? 'プレイヤー',
                    hostReady,
                    isOccupied: room.players['host'] != null,
                    badgeIds: room.players['host']?.badgeIds ?? const [],
                    playerIconId:
                        room.players['host']?.playerIconId ?? 'default',
                    playerIconFrameId:
                        room.players['host']?.playerIconFrameId ?? 'default',
                    displayBorderColor: _lobbyPlayerBorderColorForRole('host'),
                    subLabel: widget.isArenaMode
                        ? _buildArenaLobbySubLabel(isHostSlot: true)
                        : widget.isRankedMode
                            ? _buildLobbyRatingLabel(
                                room.players['host']?.rating)
                            : null,
                  ),
                  const SizedBox(height: 12),
                  _buildLobbyStatusRow(
                    _displayNameForRole('guest') ?? '対戦相手',
                    guestReady,
                    isOccupied: room.players['guest'] != null,
                    badgeIds: room.players['guest']?.badgeIds ?? const [],
                    playerIconId:
                        room.players['guest']?.playerIconId ?? 'default',
                    playerIconFrameId:
                        room.players['guest']?.playerIconFrameId ?? 'default',
                    displayBorderColor: _lobbyPlayerBorderColorForRole('guest'),
                    subLabel: widget.isArenaMode
                        ? _buildArenaLobbySubLabel(isHostSlot: false)
                        : widget.isRankedMode
                            ? _buildLobbyRatingLabel(
                                room.players['guest']?.rating)
                            : null,
                  ),
                  const SizedBox(height: 28),
                  if (showAutoStart && canShowReady)
                    SizedBox(
                      height: 56,
                      child: Center(
                        child: Text(
                          'まもなく開始します...',
                          style: TextStyle(
                            color: lobbyAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  else if (canShowReady && !showAutoStart)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: myStatus == 'ready' || _readySubmitting
                            ? null
                            : () {
                                _playUiTap();
                                unawaited(_handleReadyPressed());
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          backgroundColor: Colors.green,
                        ),
                        child: Text(
                          myStatus == 'ready' ? 'READY済み' : 'READY',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  if (!widget.isRankedMode) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          _playUiTap();
                          unawaited(_cancelFriendLobby());
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _mutedButtonGrey,
                          side: BorderSide(
                            color: _mutedButtonGrey.withValues(alpha: 0.8),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'キャンセル',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelFriendLobby() async {
    _clearAllPendingAttacks();
    await _stopBattleBgm();
    await _multiplayerManager.cancelLobby();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Widget _buildRankedBotMatchOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xEE0F0F13),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF141421),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _rankedPurple.withValues(alpha: 0.75),
                    width: 1.5,
                  )),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ランク戦が成立しました',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _buildLobbyStatusRow(
                    _myDisplayName,
                    true,
                    isOccupied: true,
                    badgeIds: _playerDataManager.equippedBadgeIds,
                    playerIconId: _playerDataManager.equippedPlayerIconId,
                    playerIconFrameId: _playerDataManager.equippedIconFrameId,
                    displayBorderColor: _battlePlayerColor,
                    subLabel: _buildLobbyRatingLabel(
                        _multiplayerManager.currentRating),
                  ),
                  const SizedBox(height: 12),
                  _buildLobbyStatusRow(
                    widget.rankedBotName,
                    true,
                    isOccupied: true,
                    badgeIds: const [],
                    playerIconId: 'default',
                    playerIconFrameId: 'default',
                    displayBorderColor: _battleOpponentColor,
                    subLabel: _buildLobbyRatingLabel(widget.rankedBotRating),
                  ),
                  const SizedBox(height: 28),
                  const SizedBox(
                    height: 56,
                    child: Center(
                      child: Text(
                        'まもなく開始します...',
                        style: TextStyle(
                          color: _rankedPurple,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyStatusRow(
    String name,
    bool isReady, {
    required bool isOccupied,
    String? subLabel,
    List<String> badgeIds = const [],
    String playerIconId = 'default',
    String playerIconFrameId = 'default',
    Color? displayBorderColor,
  }) {
    final accentColor =
        isOccupied ? (displayBorderColor ?? _gameCyan) : Colors.white38;
    final iconFrameColor =
        isOccupied ? _playerIconFrameColor(playerIconFrameId) : Colors.white38;
    final nameColor = isOccupied ? Colors.white : Colors.white54;
    final statusText = isOccupied ? '' : '未参加';
    final hasSubLabel = subLabel != null && subLabel.trim().isNotEmpty;
    final hasBadges = isOccupied && badgeIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1220).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: isOccupied ? 0.75 : 0.16),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconFrameColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: iconFrameColor.withValues(alpha: 0.92),
                width: 1.6,
              ),
            ),
            child: Icon(
              _playerIconData(playerIconId),
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildResponsivePlayerNameText(
                  name,
                  color: nameColor,
                  maxFontSize: 16,
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: hasSubLabel
                        ? _buildLobbySubLabelText(subLabel)
                        : hasBadges
                            ? _buildBadgeIconRow(badgeIds)
                            : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          if (hasBadges && hasSubLabel) ...[
            const SizedBox(width: 12),
            _buildBadgeIconRow(badgeIds),
          ] else if (statusText.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isReady
                    ? _endlessGreen.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isReady
                      ? _endlessGreen.withValues(alpha: 0.65)
                      : Colors.white24,
                ),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: isReady ? _endlessGreen : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _buildLobbyRatingLabel(int? rating) {
    return rating == null ? 'rating:-' : 'rating:$rating';
  }

  Color _lobbyPlayerBorderColorForRole(String roleId) {
    return roleId == _multiplayerManager.myRoleId
        ? _battlePlayerColor
        : _battleOpponentColor;
  }

  Widget _buildResponsivePlayerNameText(
    String name, {
    required Color color,
    required double maxFontSize,
  }) {
    return SizedBox(
      width: double.infinity,
      height: maxFontSize + 5,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            name,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: maxFontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbySubLabelText(String value) {
    const baseStyle = TextStyle(
      color: Colors.white70,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.2,
    );
    if (!value.startsWith('rating:')) {
      return Text(value, style: baseStyle);
    }
    final number = value.substring('rating:'.length);
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: 4),
              child: HexagonTrophyIcon(size: 13),
            ),
          ),
          TextSpan(
            text: number,
            style: const TextStyle(
              color: Colors.amberAccent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _buildArenaLobbySubLabel({required bool isHostSlot}) {
    final wins = _arenaManager.currentWins;
    final losses = _arenaManager.currentLosses;
    final myRoleId = _multiplayerManager.myRoleId;
    final isMySlot = (isHostSlot && myRoleId == 'host') ||
        (!isHostSlot && myRoleId == 'guest');
    return isMySlot ? '$wins勝 $losses敗' : '戦績 非公開';
  }

  Future<void> _handleReadyPressed() async {
    setState(() {
      _readySubmitting = true;
    });

    try {
      final connected = await _ensureServerConnection();
      if (!connected) {
        return;
      }
      await _multiplayerManager.setReady();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog('READYの送信に失敗しました', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _readySubmitting = false;
        });
      }
    }
  }

  void _handleRoomUpdated(MultiplayerRoom room) {
    if (!mounted) {
      return;
    }

    setState(() {
      _room = room;
      if (_opponentHasLeft(room)) {
        _opponentUnavailableForRematch = true;
        _isWaitingForRematch = false;
      }
    });

    if (_onlineGameStarted) {
      return;
    }

    final opponentStatus =
        room.players[_multiplayerManager.opponentRoleId]?.status;
    if (room.bothPlayersJoined && opponentStatus == 'left') {
      _handlePreBattleOpponentForfeit(room.seed);
      return;
    }

    if (room.bothPlayersJoined) {
      _playMatchedSfxOnce();
      unawaited(_attemptAutoReady());
    }

    if (room.bothPlayersReady) {
      _scheduleOnlineAutoStart(room);
      return;
    }
  }

  void _scheduleOnlineAutoStart(MultiplayerRoom room) {
    if (_rankedAutoStartScheduled || _onlineGameStarted) {
      return;
    }

    _rankedAutoStartScheduled = true;
    _rankedAutoStartTimer?.cancel();
    _rankedAutoStartTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _onlineGameStarted) {
        return;
      }
      unawaited(_startOnlineBattleWithReadyGo(room.seed));
    });
  }

  void _handlePreBattleOpponentForfeit(int? seed) {
    if (_onlineGameStarted || _pendingPreBattleForfeitWin) {
      return;
    }
    _pendingPreBattleForfeitWin = true;
    _playMatchedSfxOnce();
    _rankedAutoStartTimer?.cancel();
    _rankedAutoStartScheduled = true;
    unawaited(_startOnlineBattleWithReadyGo(seed));
  }

  void _playMatchedSfxOnce() {
    if (_matchingSfxPlayed) {
      return;
    }
    _matchingSfxPlayed = true;
    AppSfx.playMatched();
    unawaited(_playMatchedHaptic());
  }

  Future<void> _playMatchedHaptic() async {
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await HapticFeedback.vibrate();
  }

  void _startRealtimeConnectionWatch() {
    if (_realtimeConnectionSubscription != null) {
      return;
    }

    _realtimeConnectionSubscription =
        RealtimeConnectionGuard.connectedChanges().listen((connected) {
      if (!mounted) {
        return;
      }
      _realtimeConnected = connected;
      if (connected) {
        return;
      }
      _showRealtimeOfflineMessage();
      _forfeitRankedMatchForOfflineIfNeeded();
    });
  }

  void _showRealtimeOfflineMessage() {
    if (!mounted) {
      return;
    }
    final now = DateTime.now();
    final lastShown = _lastRealtimeOfflineMessageAt;
    if (lastShown != null && now.difference(lastShown).inSeconds < 3) {
      return;
    }
    _lastRealtimeOfflineMessageAt = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(RealtimeConnectionGuard.offlineMessage),
        duration: Duration(seconds: 3),
      ),
    );
  }

  bool get _isRankedBattleCurrentlyPlaying {
    if (!widget.isRankedMode || widget.isArenaMode) {
      return false;
    }
    if (_resultRevealPending || _onlineResultMessage != null) {
      return false;
    }
    if (widget.isCpuMode && !_isRankedBotMode) {
      return false;
    }
    if (_isOnlineMode && !_onlineGameStarted) {
      return false;
    }
    return _playerGame.gameStateWrapper.value == GameState.playing;
  }

  void _forfeitRankedMatchForOfflineIfNeeded() {
    if (_rankedOfflineForfeitStarted || !_isRankedBattleCurrentlyPlaying) {
      return;
    }
    _rankedOfflineForfeitStarted = true;
    unawaited(
      _multiplayerManager.saveActiveSession(
        isArenaMode: widget.isArenaMode,
        snapshot: const {'abandonReason': 'offline'},
      ),
    );
    unawaited(
      _presentBattleResult(
        playerWon: false,
        opponentCrossedDeathLine: false,
        resultWasForfeit: true,
        resultWasOfflineForfeit: true,
      ),
    );
  }

  bool _canSendServerAction({bool forfeitRankedOnOffline = false}) {
    if (_realtimeConnected) {
      return true;
    }
    _showRealtimeOfflineMessage();
    if (forfeitRankedOnOffline) {
      _forfeitRankedMatchForOfflineIfNeeded();
    }
    return false;
  }

  void _sendServerAction(
    Future<void> Function() action, {
    bool forfeitRankedOnOffline = false,
  }) {
    if (!_canSendServerAction(
      forfeitRankedOnOffline: forfeitRankedOnOffline,
    )) {
      return;
    }
    unawaited(
      action().catchError((Object _) {
        if (!mounted) {
          return;
        }
        _showRealtimeOfflineMessage();
        if (forfeitRankedOnOffline) {
          _forfeitRankedMatchForOfflineIfNeeded();
        }
      }),
    );
  }

  Future<bool> _ensureServerConnection({
    bool forfeitRankedOnOffline = false,
  }) async {
    if (_realtimeConnected) {
      return true;
    }
    final connected = await RealtimeConnectionGuard.waitForConnected(
      timeout: const Duration(milliseconds: 800),
    );
    _realtimeConnected = connected;
    if (connected) {
      return true;
    }
    _showRealtimeOfflineMessage();
    if (forfeitRankedOnOffline) {
      _forfeitRankedMatchForOfflineIfNeeded();
    }
    return false;
  }

  Future<void> _attemptAutoReady() async {
    final room = _room;
    if (room == null || !room.bothPlayersJoined || _onlineGameStarted) {
      return;
    }

    final myRoleId = _multiplayerManager.myRoleId;
    if (myRoleId == null) {
      return;
    }
    final myStatus = room.players[myRoleId]?.status;
    if (_autoReadyRequested || myStatus == 'ready') {
      return;
    }

    _autoReadyRequested = true;
    try {
      final connected = await _ensureServerConnection();
      if (!connected) {
        _autoReadyRequested = false;
        return;
      }
      await _multiplayerManager.setReady();
    } catch (_) {
      _autoReadyRequested = false;
    }
  }

  Future<void> _startTutorialBattle() async {
    if (!mounted) {
      return;
    }
    await _stopBattleBgm();
    _resetResultProgressionState();
    _playerGame.resumeEngine();
    _cpuGame?.resumeEngine();
    _playerGame.startGame(newSeed: 20260503, spawnInitialPiece: false);
    _cpuGame?.startGame(newSeed: 20260503, spawnInitialPiece: false);
    unawaited(_startTutorialBgm());
    _setupTutorialStep1();
  }

  void _scheduleTutorial(Duration duration, VoidCallback callback) {
    _tutorialTimer?.cancel();
    _tutorialTimer = Timer(duration, callback);
  }

  void _setupTutorialStep1() {
    if (!mounted) {
      return;
    }
    _playerGame.loadFixedBoard({
      const HexCoordinate(0, 11): BallColor.red,
      const HexCoordinate(1, 11): BallColor.red,
      const HexCoordinate(2, 11): BallColor.blue,
      const HexCoordinate(3, 11): BallColor.red,
      const HexCoordinate(4, 11): BallColor.green,
      const HexCoordinate(5, 11): BallColor.green,
      const HexCoordinate(7, 11): BallColor.red,
      const HexCoordinate(8, 11): BallColor.yellow,
      const HexCoordinate(9, 11): BallColor.purple,
      const HexCoordinate(1, 10): BallColor.red,
      const HexCoordinate(3, 10): BallColor.yellow,
      const HexCoordinate(4, 10): BallColor.blue,
      const HexCoordinate(5, 10): BallColor.purple,
      const HexCoordinate(6, 10): BallColor.red,
      const HexCoordinate(7, 10): BallColor.red,
      const HexCoordinate(8, 10): BallColor.blue,
      const HexCoordinate(2, 9): BallColor.yellow,
      const HexCoordinate(3, 9): BallColor.red,
      const HexCoordinate(4, 9): BallColor.purple,
      const HexCoordinate(6, 9): BallColor.red,
      const HexCoordinate(7, 9): BallColor.blue,
      const HexCoordinate(8, 9): BallColor.blue,
      const HexCoordinate(9, 9): BallColor.blue,
      const HexCoordinate(8, 8): BallColor.green,
    });
    _cpuGame?.loadFixedBoard(const {});
    _playerGame.nextPieceColors.value = const [
      BallColor.red,
      BallColor.green,
      BallColor.purple,
    ];
    _playerGame.spawnFixedPiece(
      colors: const [BallColor.red, BallColor.blue, BallColor.blue],
      column: 4,
    );
    _tutorialStep1StartX = _playerGame.activePieceX;
    setState(() {
      _tutorialPhase = _TutorialPhase.step1Move;
    });
  }

  void _setupTutorialStep2() {
    if (!mounted) {
      return;
    }
    _playerGame.spawnFixedPiece(
      colors: const [BallColor.red, BallColor.green, BallColor.purple],
      column: 4,
    );
    _tutorialStep2StartX = _playerGame.activePieceX;
    _tutorialStep2RotationTicks = 0;
    setState(() {
      _tutorialPhase = _TutorialPhase.step2HintIntro;
    });
  }

  void _setupTutorialStep3Incoming() {
    if (!mounted) {
      return;
    }
    _tutorialTimer?.cancel();
    _tutorialOpponentAttackQueued = false;
    _tutorialOpponentDefeatQueued = false;
    setState(() {
      _tutorialPhase = _TutorialPhase.step3Incoming;
    });
    _loadTutorialStep3BoardsAfterLayout();
  }

  void _loadTutorialStep3BoardsAfterLayout() {
    if (!mounted || _tutorialPhase != _TutorialPhase.step3Incoming) {
      return;
    }
    _playerGame.resumeEngine();
    _playerGame.loadFixedBoard(_tutorialPlayerStep3Board());
    _cpuGame?.loadFixedBoard(_tutorialOpponentStep3Board());
    _playerGame.nextPieceColors.value = const [
      BallColor.purple,
      BallColor.yellow,
      BallColor.red,
    ];
    _cpuGame?.nextPieceColors.value = const [
      BallColor.purple,
      BallColor.yellow,
      BallColor.red,
    ];
    _cpuGame?.spawnFixedPiece(
      colors: const [BallColor.green, BallColor.green, BallColor.blue],
      column: 4,
    );
    _tutorialStep3RotationTicks = 0;
    _scheduleTutorial(
      const Duration(milliseconds: 1400),
      _playTutorialOpponentOpeningMove,
    );
  }

  Map<HexCoordinate, BallColor> _tutorialPlayerStep3Board() {
    return {
      const HexCoordinate(2, 4): BallColor.green,
      const HexCoordinate(3, 4): BallColor.red,
      const HexCoordinate(4, 4): BallColor.blue,
      const HexCoordinate(5, 4): BallColor.yellow,
      const HexCoordinate(6, 4): BallColor.purple,
      const HexCoordinate(7, 4): BallColor.purple,
      const HexCoordinate(8, 4): BallColor.green,
      const HexCoordinate(2, 5): BallColor.yellow,
      const HexCoordinate(3, 5): BallColor.blue,
      const HexCoordinate(4, 5): BallColor.red,
      const HexCoordinate(5, 5): BallColor.green,
      const HexCoordinate(6, 5): BallColor.blue,
      const HexCoordinate(7, 5): BallColor.red,
      const HexCoordinate(9, 5): BallColor.red,
      const HexCoordinate(0, 6): BallColor.blue,
      const HexCoordinate(1, 6): BallColor.red,
      const HexCoordinate(2, 6): BallColor.green,
      const HexCoordinate(3, 6): BallColor.purple,
      const HexCoordinate(4, 6): BallColor.yellow,
      const HexCoordinate(5, 6): BallColor.red,
      const HexCoordinate(6, 6): BallColor.purple,
      const HexCoordinate(7, 6): BallColor.green,
      const HexCoordinate(8, 6): BallColor.red,
      const HexCoordinate(0, 7): BallColor.red,
      const HexCoordinate(1, 7): BallColor.yellow,
      const HexCoordinate(2, 7): BallColor.purple,
      const HexCoordinate(3, 7): BallColor.blue,
      const HexCoordinate(4, 7): BallColor.blue,
      const HexCoordinate(5, 7): BallColor.yellow,
      const HexCoordinate(6, 7): BallColor.purple,
      const HexCoordinate(7, 7): BallColor.green,
      const HexCoordinate(8, 7): BallColor.purple,
      const HexCoordinate(9, 7): BallColor.red,
      const HexCoordinate(0, 8): BallColor.blue,
      const HexCoordinate(1, 8): BallColor.green,
      const HexCoordinate(2, 8): BallColor.blue,
      const HexCoordinate(3, 8): BallColor.purple,
      const HexCoordinate(4, 8): BallColor.green,
      const HexCoordinate(5, 8): BallColor.blue,
      const HexCoordinate(6, 8): BallColor.green,
      const HexCoordinate(7, 8): BallColor.purple,
      const HexCoordinate(8, 8): BallColor.purple,
      const HexCoordinate(0, 9): BallColor.red,
      const HexCoordinate(1, 9): BallColor.yellow,
      const HexCoordinate(2, 9): BallColor.red,
      const HexCoordinate(3, 9): BallColor.purple,
      const HexCoordinate(4, 9): BallColor.blue,
      const HexCoordinate(5, 9): BallColor.purple,
      const HexCoordinate(6, 9): BallColor.red,
      const HexCoordinate(7, 9): BallColor.yellow,
      const HexCoordinate(8, 9): BallColor.red,
      const HexCoordinate(9, 9): BallColor.yellow,
      const HexCoordinate(0, 10): BallColor.red,
      const HexCoordinate(1, 10): BallColor.purple,
      const HexCoordinate(2, 10): BallColor.yellow,
      const HexCoordinate(3, 10): BallColor.yellow,
      const HexCoordinate(4, 10): BallColor.blue,
      const HexCoordinate(5, 10): BallColor.purple,
      const HexCoordinate(6, 10): BallColor.yellow,
      const HexCoordinate(7, 10): BallColor.blue,
      const HexCoordinate(8, 10): BallColor.blue,
      const HexCoordinate(0, 11): BallColor.blue,
      const HexCoordinate(1, 11): BallColor.green,
      const HexCoordinate(2, 11): BallColor.purple,
      const HexCoordinate(3, 11): BallColor.yellow,
      const HexCoordinate(4, 11): BallColor.blue,
      const HexCoordinate(5, 11): BallColor.yellow,
      const HexCoordinate(6, 11): BallColor.green,
      const HexCoordinate(7, 11): BallColor.yellow,
      const HexCoordinate(9, 11): BallColor.red,
    };
  }

  Map<HexCoordinate, BallColor> _tutorialOpponentStep3Board() {
    return {
      const HexCoordinate(0, 8): BallColor.red,
      const HexCoordinate(1, 8): BallColor.blue,
      const HexCoordinate(2, 8): BallColor.yellow,
      const HexCoordinate(3, 8): BallColor.green,
      const HexCoordinate(4, 8): BallColor.yellow,
      const HexCoordinate(5, 8): BallColor.red,
      const HexCoordinate(6, 8): BallColor.red,
      const HexCoordinate(7, 8): BallColor.green,
      const HexCoordinate(8, 8): BallColor.yellow,
      const HexCoordinate(0, 9): BallColor.blue,
      const HexCoordinate(1, 9): BallColor.yellow,
      const HexCoordinate(2, 9): BallColor.red,
      const HexCoordinate(3, 9): BallColor.green,
      const HexCoordinate(4, 9): BallColor.purple,
      const HexCoordinate(5, 9): BallColor.blue,
      const HexCoordinate(6, 9): BallColor.purple,
      const HexCoordinate(7, 9): BallColor.red,
      const HexCoordinate(8, 9): BallColor.blue,
      const HexCoordinate(9, 9): BallColor.red,
      const HexCoordinate(0, 10): BallColor.green,
      const HexCoordinate(1, 10): BallColor.purple,
      const HexCoordinate(2, 10): BallColor.green,
      const HexCoordinate(3, 10): BallColor.blue,
      const HexCoordinate(4, 10): BallColor.yellow,
      const HexCoordinate(5, 10): BallColor.blue,
      const HexCoordinate(6, 10): BallColor.green,
      const HexCoordinate(7, 10): BallColor.yellow,
      const HexCoordinate(8, 10): BallColor.red,
      const HexCoordinate(0, 11): BallColor.yellow,
      const HexCoordinate(1, 11): BallColor.blue,
      const HexCoordinate(2, 11): BallColor.green,
      const HexCoordinate(3, 11): BallColor.yellow,
      const HexCoordinate(4, 11): BallColor.red,
      const HexCoordinate(5, 11): BallColor.red,
      const HexCoordinate(6, 11): BallColor.yellow,
      const HexCoordinate(7, 11): BallColor.blue,
      const HexCoordinate(8, 11): BallColor.purple,
      const HexCoordinate(9, 11): BallColor.yellow,
    };
  }

  Future<void> _playTutorialOpponentOpeningMove() async {
    final opponentGame = _cpuGame;
    if (!mounted ||
        opponentGame == null ||
        _tutorialPhase != _TutorialPhase.step3Incoming) {
      return;
    }
    opponentGame.resumeEngine();
    opponentGame.startMovingRight();
    await Future<void>.delayed(const Duration(milliseconds: 75));
    opponentGame.stopMovingRight();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted ||
        opponentGame.gameStateWrapper.value != GameState.playing ||
        _tutorialPhase != _TutorialPhase.step3Incoming) {
      return;
    }
    setState(() {
      _tutorialPhase = _TutorialPhase.step3OpponentAttack;
    });
    opponentGame.triggerHardDrop();
    unawaited(_finishTutorialOpponentOpeningAttack(opponentGame));
  }

  Future<void> _finishTutorialOpponentOpeningAttack(
    PuzzleGame opponentGame,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    while (mounted &&
        _tutorialPhase == _TutorialPhase.step3OpponentAttack &&
        opponentGame.isBoardProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (!mounted ||
        _tutorialPhase != _TutorialPhase.step3OpponentAttack ||
        _tutorialOpponentAttackQueued) {
      return;
    }
    opponentGame.stopMovingLeft();
    opponentGame.stopMovingRight();
    opponentGame.pauseEngine();
    _sendTutorialIncomingOjamaToPlayer();
  }

  Set<_TutorialAction> get _enabledTutorialActions {
    return switch (_tutorialPhase) {
      _TutorialPhase.step1Move => {_TutorialAction.moveRight},
      _TutorialPhase.step1Drop => const <_TutorialAction>{},
      _TutorialPhase.step2HintIntro => {_TutorialAction.moveRight},
      _TutorialPhase.step2Move => {_TutorialAction.moveRight},
      _TutorialPhase.step2Rotate => {
          _TutorialAction.rotateLeft,
          _TutorialAction.rotateRight,
        },
      _TutorialPhase.step2Drop => const <_TutorialAction>{},
      _TutorialPhase.step3Incoming => const <_TutorialAction>{},
      _TutorialPhase.step3OpponentAttack => const <_TutorialAction>{},
      _TutorialPhase.step3Move => {_TutorialAction.moveLeft},
      _TutorialPhase.step3Rotate => {
          _TutorialAction.rotateLeft,
          _TutorialAction.rotateRight,
        },
      _TutorialPhase.step3Drop => const <_TutorialAction>{},
      _ => const <_TutorialAction>{},
    };
  }

  String get _tutorialMessage {
    return switch (_tutorialPhase) {
      _TutorialPhase.step1Move => '同じ色を6つ以上繋げよう！',
      _TutorialPhase.step1Drop => '盤面をタップしてドロップさせよう！',
      _TutorialPhase.step1Clear => 'ナイス！同じ色が繋がって消えたよ！',
      _TutorialPhase.step2HintIntro => '次はフォーメーションを決めてみよう！\n点線でヒントが表示されているよ',
      _TutorialPhase.step2Move => '次はフォーメーションを決めてみよう！\n点線でヒントが表示されているよ',
      _TutorialPhase.step2Rotate => 'ヒントに赤色ボールを合わせよう！',
      _TutorialPhase.step2Drop => '盤面をタップしてドロップしてみよう！',
      _TutorialPhase.step2Clear => 'ピラミッド！フォーメーションで同じ色が全て消えました！',
      _TutorialPhase.step3Incoming => '対戦相手が現れた！',
      _TutorialPhase.step3OpponentAttack => '相手が妨害ボールを送ってきた！',
      _TutorialPhase.step3Move => 'フォーメーションを決めて、相手に反撃しよう！',
      _TutorialPhase.step3Rotate => 'フォーメーションを決めて、相手に反撃しよう！',
      _TutorialPhase.step3Drop => '盤面をタップしてドロップしよう！',
      _TutorialPhase.step3Skill => 'ナイス！妨害ボールを相手に送ったよ！',
      null => 'チュートリアルを開始します。',
    };
  }

  Future<void> _handleTutorialAction(_TutorialAction action) async {
    if (!_enabledTutorialActions.contains(action)) {
      return;
    }
    AppSfx.playUiTap();
    switch (action) {
      case _TutorialAction.moveLeft:
        _playerGame.moveFixedPieceByColumns(-1);
      case _TutorialAction.moveRight:
        _playerGame.moveFixedPieceByColumns(1);
      case _TutorialAction.rotateLeft:
        _playerGame.rotateLeft();
      case _TutorialAction.rotateRight:
        _playerGame.rotateRight();
    }

    switch (_tutorialPhase) {
      case _TutorialPhase.step1Move:
        break;
      case _TutorialPhase.step1Drop:
        await _dropTutorialStep1();
      case _TutorialPhase.step2HintIntro:
      case _TutorialPhase.step2Move:
        final startX = _tutorialStep2StartX;
        final currentX = _playerGame.activePieceX;
        const targetDistance = _gridBallDiameter * 3.5;
        if (startX != null &&
            currentX != null &&
            currentX - startX >= targetDistance) {
          _tutorialRightMoveActive = false;
          _playerGame.stopMovingRight();
          _playerGame.setFixedPieceX(startX + targetDistance);
          setState(() => _tutorialPhase = _TutorialPhase.step2Rotate);
        }
      case _TutorialPhase.step2Rotate:
        _tutorialStep2RotationTicks +=
            action == _TutorialAction.rotateRight ? 1 : -1;
        if (_tutorialStep2RotationTicks.abs() >= 3) {
          setState(() => _tutorialPhase = _TutorialPhase.step2Drop);
        }
      case _TutorialPhase.step2Drop:
        await _dropTutorialStep2();
      case _TutorialPhase.step3Move:
        break;
      case _TutorialPhase.step3Rotate:
        _tutorialStep3RotationTicks +=
            action == _TutorialAction.rotateRight ? 1 : -1;
        if (_tutorialStep3RotationTicks >= 4 ||
            _tutorialStep3RotationTicks <= -2) {
          setState(() => _tutorialPhase = _TutorialPhase.step3Drop);
        }
      case _TutorialPhase.step3Drop:
        break;
      case _:
        break;
    }
  }

  void _handleTutorialControlDown(_TutorialAction action) {
    if (!_enabledTutorialActions.contains(action)) {
      return;
    }
    if (action == _TutorialAction.moveRight &&
        (_tutorialPhase == _TutorialPhase.step1Move ||
            _tutorialPhase == _TutorialPhase.step2HintIntro ||
            _tutorialPhase == _TutorialPhase.step2Move)) {
      _tutorialRightMoveActive = true;
      _playerGame.startMovingRight();
      if (_tutorialPhase == _TutorialPhase.step1Move) {
        _monitorTutorialStep1Move();
      } else {
        _monitorTutorialStep2Move();
      }
      return;
    }
    if (action == _TutorialAction.moveLeft &&
        _tutorialPhase == _TutorialPhase.step3Move) {
      _tutorialLeftMoveActive = true;
      _playerGame.startMovingLeft();
      _monitorTutorialStep3Move();
      return;
    }
    unawaited(_handleTutorialAction(action));
  }

  void _handleTutorialControlUp(_TutorialAction action) {
    if (action == _TutorialAction.moveRight) {
      _tutorialRightMoveActive = false;
      _playerGame.stopMovingRight();
    }
    if (action == _TutorialAction.moveLeft) {
      _tutorialLeftMoveActive = false;
      _playerGame.stopMovingLeft();
    }
  }

  Future<void> _monitorTutorialStep1Move() async {
    final startX = _tutorialStep1StartX;
    if (startX == null) {
      return;
    }
    const targetDistance = _gridBallDiameter * 2.5;
    while (mounted &&
        _tutorialRightMoveActive &&
        _tutorialPhase == _TutorialPhase.step1Move) {
      final currentX = _playerGame.activePieceX;
      if (currentX != null && currentX - startX >= targetDistance) {
        _tutorialRightMoveActive = false;
        _playerGame.stopMovingRight();
        _playerGame.setFixedPieceX(startX + targetDistance);
        setState(() => _tutorialPhase = _TutorialPhase.step1Drop);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _monitorTutorialStep2Move() async {
    final startX = _tutorialStep2StartX;
    if (startX == null) {
      return;
    }
    const targetDistance = _gridBallDiameter * 3.5;
    while (mounted &&
        _tutorialRightMoveActive &&
        (_tutorialPhase == _TutorialPhase.step2HintIntro ||
            _tutorialPhase == _TutorialPhase.step2Move)) {
      final currentX = _playerGame.activePieceX;
      if (currentX != null && currentX - startX >= targetDistance) {
        _tutorialRightMoveActive = false;
        _playerGame.stopMovingRight();
        _playerGame.setFixedPieceX(startX + targetDistance);
        setState(() => _tutorialPhase = _TutorialPhase.step2Rotate);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _monitorTutorialStep3Move() async {
    final startX = _tutorialStep3StartX;
    if (startX == null) {
      return;
    }
    const targetDistance = _gridBallDiameter * 2.5;
    while (mounted &&
        _tutorialLeftMoveActive &&
        _tutorialPhase == _TutorialPhase.step3Move) {
      final currentX = _playerGame.activePieceX;
      if (currentX != null && startX - currentX >= targetDistance) {
        _tutorialLeftMoveActive = false;
        _playerGame.stopMovingLeft();
        setState(() => _tutorialPhase = _TutorialPhase.step3Rotate);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  bool _handleTutorialBoardTap(PuzzleGame game) {
    if (!widget.isTutorialMode) {
      return false;
    }
    if (!_isTutorialBoardDropEnabled) {
      return true;
    }
    _playUiTap();
    game.triggerHardDrop();
    if (_tutorialPhase == _TutorialPhase.step1Drop) {
      setState(() => _tutorialPhase = _TutorialPhase.step1Clear);
      _scheduleTutorial(
        const Duration(milliseconds: 1950),
        _setupTutorialStep2,
      );
    } else if (_tutorialPhase == _TutorialPhase.step2Drop) {
      setState(() => _tutorialPhase = _TutorialPhase.step2Clear);
      _scheduleTutorial(
        const Duration(milliseconds: 3300),
        _setupTutorialStep3Incoming,
      );
    } else if (_tutorialPhase == _TutorialPhase.step3Drop) {
      setState(() => _tutorialPhase = _TutorialPhase.step3Skill);
    }
    return true;
  }

  Future<void> _dropTutorialStep1() async {
    setState(() => _tutorialPhase = _TutorialPhase.step1Clear);
    await _playerGame.dropFixedPieceToHexes(const [
      HexCoordinate(5, 8),
      HexCoordinate(7, 8),
      HexCoordinate(8, 8),
    ]);
    _scheduleTutorial(const Duration(milliseconds: 1950), () {
      if (!mounted) {
        return;
      }
      _setupTutorialStep2();
    });
  }

  Future<void> _dropTutorialStep2() async {
    setState(() => _tutorialPhase = _TutorialPhase.step2Clear);
    await _playerGame.dropFixedPieceToHexes(const [
      HexCoordinate(4, 10),
      HexCoordinate(4, 8),
      HexCoordinate(8, 10),
    ]);
    _scheduleTutorial(
      const Duration(milliseconds: 2650),
      _setupTutorialStep3Incoming,
    );
  }

  Future<void> _finishTutorial() async {
    AppSfx.playUiTap();
    await AppSettings.instance.setOnboardingSeen(true);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _startLocalBattleWithReadyGo(int seed) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _battleIntroLocked = true;
    });
    await _stopBattleBgm();
    _cpuBattlePlayerWon = null;
    _resetResultProgressionState();
    _playerGame.resumeEngine();
    _cpuGame?.resumeEngine();
    _playerGame.startGame(newSeed: seed, spawnInitialPiece: false);
    _cpuGame?.startGame(newSeed: seed, spawnInitialPiece: false);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      return;
    }
    _playerGame.pauseEngine();
    _cpuGame?.pauseEngine();

    await Future<void>.delayed(_preReadyDelay);
    if (!mounted) {
      return;
    }
    setState(() {
      _readyGoOverlayText = 'READY...';
    });
    unawaited(SfxPlayer.play(_readySfx, volume: 1.0));

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }
    setState(() {
      _readyGoOverlayText = 'GO!';
    });
    unawaited(_startBattleBgmAfterGoDelay());

    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) {
      return;
    }
    setState(() {
      _readyGoOverlayText = null;
    });
    await Future<void>.delayed(_postReadyGoBoardPause);
    if (!mounted) {
      return;
    }

    _playerGame.resumeEngine();
    _cpuGame?.resumeEngine();
    _playerGame.spawnInitialPieceAfterReadyGo();
    _cpuGame?.spawnInitialPieceAfterReadyGo();
    if (mounted) {
      setState(() {
        _battleIntroLocked = false;
      });
    }
  }

  Future<void> _startRankedBotBattleAfterMatchOverlay(int seed) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _rankedBotMatchOverlayVisible = true;
    });
    final opponentRating = _rankedBotRating;
    if (opponentRating != null) {
      try {
        await _multiplayerManager.saveRankedBotActiveSession(
          opponentRating: opponentRating,
        );
      } catch (_) {
        // セッション保存に失敗しても、試合開始自体は止めない。
      }
    }
    _playMatchedSfxOnce();

    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) {
      return;
    }

    setState(() {
      _rankedBotMatchOverlayVisible = false;
    });
    await _startLocalBattleWithReadyGo(seed);
  }

  Future<void> _startOnlineBattleWithReadyGo(
    int? seed, {
    Duration preReadyDelay = _preReadyDelay,
  }) async {
    if (!mounted) {
      return;
    }

    _cpuBattlePlayerWon = null;
    _resetResultProgressionState();
    _rankedAutoStartTimer?.cancel();
    _playerGame.resumeEngine();
    _cpuGame?.resumeEngine();
    _playerGame.startGame(newSeed: seed, spawnInitialPiece: false);
    _cpuGame?.startGame(newSeed: seed, spawnInitialPiece: false);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      return;
    }
    _playerGame.pauseEngine();
    _cpuGame?.pauseEngine();

    await Future<void>.delayed(preReadyDelay);
    if (!mounted) {
      return;
    }
    setState(() {
      _onlineGameStarted = true;
      _readyGoOverlayText = 'READY...';
    });
    unawaited(SfxPlayer.play(_readySfx, volume: 1.0));

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }
    setState(() {
      _readyGoOverlayText = 'GO!';
    });
    unawaited(_startBattleBgmAfterGoDelay());

    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) {
      return;
    }
    setState(() {
      _readyGoOverlayText = null;
    });
    await Future<void>.delayed(_postReadyGoBoardPause);
    if (!mounted) {
      return;
    }

    _playerGame.resumeEngine();
    _cpuGame?.resumeEngine();
    _playerGame.spawnInitialPieceAfterReadyGo();
    if (_pendingPreBattleForfeitWin) {
      _pendingPreBattleForfeitWin = false;
      unawaited(
        _presentBattleResult(
          playerWon: true,
          opponentCrossedDeathLine: false,
          resultWasForfeit: true,
        ),
      );
    }
  }

  String? _displayNameForRole(String? roleId) {
    if (roleId == null) {
      return null;
    }
    final name = _room?.players[roleId]?.name.trim();
    if (name == null || name.isEmpty) {
      return null;
    }
    return name;
  }

  IconData _playerIconData(String? iconId) {
    return switch (iconId) {
      'icon_bolt' => Icons.bolt,
      'icon_star' => Icons.star,
      'icon_gamepad' => Icons.sports_esports,
      'icon_sword' => Icons.gavel,
      'icon_hexagon' => Icons.hexagon,
      'icon_trophy' => Icons.emoji_events,
      'icon_medal' => Icons.military_tech,
      'icon_crown' => Icons.workspace_premium,
      'icon_diamond' => Icons.diamond,
      'icon_fire' => Icons.local_fire_department,
      'icon_water' => Icons.water_drop,
      'icon_moon' => Icons.dark_mode,
      'icon_visibility' => Icons.visibility,
      'icon_rocket' => Icons.rocket_launch,
      'icon_shield' => Icons.shield,
      'icon_terminal' => Icons.terminal,
      'icon_smile' => Icons.sentiment_satisfied_alt,
      'icon_ribbon' => Icons.workspace_premium,
      'icon_heart' => Icons.favorite,
      'icon_music' => Icons.music_note,
      'icon_cafe' => Icons.coffee,
      'icon_flower' => Icons.local_florist,
      'icon_bell' => Icons.notifications,
      'icon_skull' => Icons.dangerous,
      _ => Icons.person,
    };
  }

  Color _playerIconFrameColor(String? frameId) {
    final frame = GameItemCatalog.byId(frameId ?? 'default');
    return switch (frame?.colorName) {
      'red' => Colors.redAccent,
      'orange' => Colors.orangeAccent,
      'yellow' => _computerYellow,
      'lime' => Colors.limeAccent,
      'green' => _endlessGreen,
      'blue' => _battlePlayerColor,
      'purple' => Colors.purpleAccent,
      'black' => Colors.white70,
      _ => _gameCyan,
    };
  }

  void _handleOpponentBoardUpdated(Map<String, dynamic> boardData) {
    final ignoreUntil = _ignoreEmptyOpponentBoardUntil;
    if (boardData.isEmpty &&
        ignoreUntil != null &&
        DateTime.now().isBefore(ignoreUntil)) {
      return;
    }
    final opponentGame = _cpuGame;
    final currentOpponentBoardIsNotEmpty =
        opponentGame?.exportBoardState().isNotEmpty ?? false;
    final opponentRoleId = _multiplayerManager.opponentRoleId;
    final opponentStatus =
        _multiplayerManager.currentRoom?.players[opponentRoleId]?.status;
    if (boardData.isEmpty &&
        currentOpponentBoardIsNotEmpty &&
        (_onlineGameStarted ||
            _resultRevealPending ||
            _onlineResultMessage != null ||
            _opponentGameOverVerificationPending ||
            opponentStatus == 'dead')) {
      _ignoreEmptyOpponentBoardUntil =
          DateTime.now().add(const Duration(seconds: 3));
      _pendingEmptyOpponentBoardTimer?.cancel();
      _pendingEmptyOpponentBoardTimer =
          Timer(const Duration(milliseconds: 1500), () {
        _pendingEmptyOpponentBoardTimer = null;
        if (!mounted ||
            _resultRevealPending ||
            _onlineResultMessage != null ||
            _opponentGameOverVerificationPending) {
          return;
        }
        final latestStatus = _multiplayerManager
            .currentRoom?.players[_multiplayerManager.opponentRoleId]?.status;
        if (latestStatus != 'dead') {
          _cpuGame?.applyRemoteBoardState(const {});
        }
      });
      return;
    }
    if (boardData.isNotEmpty) {
      _ignoreEmptyOpponentBoardUntil = null;
      _pendingEmptyOpponentBoardTimer?.cancel();
      _pendingEmptyOpponentBoardTimer = null;
    }
    opponentGame?.applyRemoteBoardState(boardData);
  }

  void _handleOpponentPieceUpdated(Map<String, dynamic> pieceData) {
    final opponentGame = _cpuGame;
    if (opponentGame == null) {
      return;
    }

    final action = pieceData['action'] as String? ?? 'move';
    final x = (pieceData['x'] as num?)?.toDouble();
    final y = (pieceData['y'] as num?)?.toDouble();
    final rotation = (pieceData['rotation'] as num?)?.toInt();
    final colors = _parseColors(pieceData['colors']);
    final nextColors = _parseColors(pieceData['nextColors']);
    final dropSeed = (pieceData['dropSeed'] as num?)?.toInt();
    final contactSlideDirection =
        (pieceData['contactSlideDirection'] as num?)?.toDouble();
    var movingLeft = pieceData['movingLeft'] == true;
    var movingRight = pieceData['movingRight'] == true;
    if (!pieceData.containsKey('movingLeft') ||
        !pieceData.containsKey('movingRight')) {
      movingLeft = opponentGame.isMovingLeft;
      movingRight = opponentGame.isMovingRight;
      switch (action) {
        case 'start_left':
          movingLeft = true;
          break;
        case 'stop_left':
          movingLeft = false;
          break;
        case 'start_right':
          movingRight = true;
          break;
        case 'stop_right':
          movingRight = false;
          break;
        case 'spawn':
        case 'hard_drop':
          movingLeft = false;
          movingRight = false;
          break;
      }
    }
    opponentGame.syncRemoteActivePieceInputState(
      movingLeft: movingLeft,
      movingRight: movingRight,
      contactSlideDirection: contactSlideDirection,
    );
    if (dropSeed != null) {
      opponentGame.currentDropSeed = dropSeed;
      opponentGame.syncDropRng = Random(dropSeed);
    }
    if (nextColors.isNotEmpty) {
      opponentGame.nextPieceColors.value = nextColors;
    }

    if (action != 'spawn' && action != 'hard_drop') {
      _ensureOpponentActivePiece(opponentGame, colors);
      opponentGame.syncRemoteActivePieceInputState(
        movingLeft: movingLeft,
        movingRight: movingRight,
        contactSlideDirection: contactSlideDirection,
      );
    }

    switch (action) {
      case 'spawn':
        if (colors.length == 3) {
          opponentGame.spawnRemotePiece(colors);
        }
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.1,
          );
        }
        break;
      case 'rotate_left':
      case 'rotate_right':
      case 'start_left':
      case 'stop_left':
      case 'start_right':
      case 'stop_right':
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: action.startsWith('rotate') ? 0.08 : 0.05,
          );
        }
        break;
      case 'hard_drop':
        opponentGame.hardDrop();
        break;
      default:
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
          );
        }
        break;
    }
  }

  void _ensureOpponentActivePiece(
      PuzzleGame opponentGame, List<BallColor> colors) {
    if (opponentGame.activePiece != null || colors.length != 3) {
      return;
    }
    opponentGame.spawnRemotePiece(colors);
  }

  void _handleAttackReceived(OjamaTask task) {
    _cpuGame?.showRemoteAttackFormation(task.type);
    _queueOjamaTask(_playerGame, task);
  }

  void _handleOpponentOjamaSpawned(List<dynamic> ojamaData, int dropSeed) {
    _cpuGame?.spawnRemoteOjama(ojamaData, dropSeed);
  }

  void _handleOpponentGameOver() {
    if (_resultRevealPending || _onlineResultMessage != null) {
      return;
    }
    _opponentGameOverVerificationPending = false;
    unawaited(
      _presentBattleResult(
        playerWon: true,
        opponentCrossedDeathLine: true,
      ),
    );
  }

  Future<void> _verifyOpponentDeathLineBeforeResult() async {
    if (!_isOnlineMode ||
        _opponentGameOverVerificationPending ||
        _resultRevealPending ||
        _onlineResultMessage != null) {
      return;
    }
    _opponentGameOverVerificationPending = true;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || _resultRevealPending || _onlineResultMessage != null) {
      _opponentGameOverVerificationPending = false;
      return;
    }

    final opponentRoleId = _multiplayerManager.opponentRoleId;
    final opponentStatus =
        _multiplayerManager.currentRoom?.players[opponentRoleId]?.status;
    if (opponentStatus == 'dead') {
      _handleOpponentGameOver();
      return;
    }

    final roomId = _multiplayerManager.currentRoomId;
    if (roomId != null) {
      try {
        final snapshot = await _multiplayerManager.loadRoomBattleSnapshot(
          roomId: roomId,
          roleId: opponentRoleId,
        );
        if (snapshot != null && mounted) {
          _cpuGame?.restoreFromSnapshot(snapshot);
        }
      } catch (_) {
        // 最終盤面補正に失敗した場合も、相手のdead通知を待つ。
      }
    }
    _opponentGameOverVerificationPending = false;
  }

  Future<void> _applyRankedRatingResult({
    required bool isWin,
    bool applyOpponentResult = false,
  }) async {
    if (!widget.isRankedMode || _rankedRatingApplied) {
      return;
    }

    _rankedRatingApplied = true;
    try {
      final connected = await _ensureServerConnection();
      if (!connected) {
        if (mounted) {
          setState(() {
            _rankedRatingChange = null;
          });
        }
        return;
      }
      final change = await _multiplayerManager.applyRankedResult(
        isWin: isWin,
        applyOpponentResult: applyOpponentResult,
      );
      if (change != null) {
        await _playerDataManager.setCurrentRating(change.newRating);
        await _playerDataManager.updateLatestRankedHistory(
          ratingAfter: change.newRating,
          ratingDelta: change.delta,
        );
        await _syncPlayerProfileOnline(
          rating: change.newRating,
          incrementDailyWin: change.delta != 0 && isWin,
          incrementSeasonLoss: change.delta != 0 && !isWin,
        );
      }
      if (!mounted || change == null) {
        return;
      }
      _refreshNewlyUnlockedBadgesFromSnapshot();
      setState(() {
        _rankedRatingChange = change;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showRealtimeOfflineMessage();
      setState(() {
        _rankedRatingChange = null;
      });
    }
  }

  Future<void> _applyRankedBotRatingResult({required bool isWin}) async {
    final opponentRating = _rankedBotRating;
    if (!widget.isRankedMode ||
        !widget.isCpuMode ||
        _rankedRatingApplied ||
        opponentRating == null) {
      return;
    }

    _rankedRatingApplied = true;
    try {
      final connected = await _ensureServerConnection();
      if (!connected) {
        if (mounted) {
          setState(() {
            _rankedRatingChange = null;
          });
        }
        return;
      }
      final change = await _multiplayerManager.applyRankedBotResult(
        isWin: isWin,
        opponentRating: opponentRating,
      );
      await _multiplayerManager.clearSavedSession();
      await _playerDataManager.setCurrentRating(change.newRating);
      await _playerDataManager.updateLatestRankedHistory(
        ratingAfter: change.newRating,
        ratingDelta: change.delta,
      );
      await _syncPlayerProfileOnline(
        rating: change.newRating,
        incrementDailyWin: change.delta != 0 && isWin,
        incrementSeasonLoss: change.delta != 0 && !isWin,
      );
      if (!mounted) {
        return;
      }
      _refreshNewlyUnlockedBadgesFromSnapshot();
      setState(() {
        _rankedRatingChange = change;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showRealtimeOfflineMessage();
      setState(() {
        _rankedRatingChange = null;
      });
    }
  }

  void _resetResultProgressionState() {
    _matchExpApplied = false;
    _matchExpEarned = null;
    _soloExpApplied = false;
    _soloExpEarned = null;
    _resultCoinApplied = false;
    _resultCoinBaseEarned = null;
    _resultCoinTripleClaimed = false;
    _resultCoinTripleInProgress = false;
    _didLevelUpFromResultExp = false;
    _resultLevelAfterExp = null;
    _resultUnlockedBadgeIdsBefore = null;
    _newlyUnlockedBadges = const [];
    _arenaResultApplied = false;
    _arenaMatchResult = null;
    _onlineResultWasForfeit = false;
    _onlineResultWasOfflineForfeit = false;
    _opponentUnavailableForRematch = false;
    _autoReadyRequested = false;
    _rankedOfflineForfeitStarted = false;
    _opponentGameOverVerificationPending = false;
    _tutorialOpponentDefeatQueued = false;
    _resultRevealPending = false;
    _resultAudioStarted = false;
    _resultAudioStartedAt = null;
    _playerWazaCounts[WazaType.straight] = 0;
    _playerWazaCounts[WazaType.pyramid] = 0;
    _playerWazaCounts[WazaType.hexagon] = 0;
    _playerNormalClearedBalls = 0;
  }

  void _recordPlayerWaza(WazaType waza) {
    if (waza == WazaType.none) {
      return;
    }
    _playerWazaCounts[waza] = (_playerWazaCounts[waza] ?? 0) + 1;
  }

  Future<void> _captureResultBadgeSnapshot() async {
    if (_resultUnlockedBadgeIdsBefore != null) {
      return;
    }
    await _playerDataManager.load();
    _resultUnlockedBadgeIdsBefore = _playerDataManager.unlockedBadgeIds.toSet();
  }

  void _refreshNewlyUnlockedBadgesFromSnapshot() {
    final before = _resultUnlockedBadgeIdsBefore;
    if (before == null) {
      return;
    }
    final after = _playerDataManager.unlockedBadgeIds.toSet();
    final newlyUnlocked = BadgeCatalog.visibleBadgesFor(after)
        .where(
            (badge) => after.contains(badge.id) && !before.contains(badge.id))
        .toList();
    if (newlyUnlocked.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _newlyUnlockedBadges = newlyUnlocked;
    });
  }

  Future<void> _syncPlayerProfileOnline({
    int? rating,
    bool incrementDailyWin = false,
    bool incrementSeasonLoss = false,
  }) async {
    final syncRating = rating ?? _playerDataManager.currentRating;
    await Future.wait<void>(
      [
        _runRequiredProfileSyncTask(
          () => _multiplayerManager
              .updateUserName(_playerDataManager.playerName)
              .timeout(_playerProfileSyncTimeout),
        ),
        _runRequiredProfileSyncTask(
          () => _rankingManager
              .updateMyRating(
                rating: syncRating,
                displayName: _playerDataManager.displayPlayerName,
                incrementDailyWin: incrementDailyWin,
                incrementSeasonLoss: incrementSeasonLoss,
              )
              .timeout(_playerProfileSyncTimeout),
        ),
        _runRequiredProfileSyncTask(
          () => _playerDataManager
              .syncRecordSummary(force: true, rethrowErrors: true)
              .timeout(_playerProfileSyncTimeout),
        ),
      ],
      eagerError: false,
    );
  }

  Future<void> _runRequiredProfileSyncTask(
    Future<void> Function() task,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await task();
        return;
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(
              Duration(milliseconds: 250 * (attempt + 1)));
        }
      }
    }
  }

  Widget _buildBadgeUnlockResultCard() {
    if (_newlyUnlockedBadges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.amberAccent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.amberAccent.withValues(alpha: 0.68),
            width: 1.4,
          )),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'バッジ解放',
            style: TextStyle(
              color: Colors.amberAccent,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final badge in _newlyUnlockedBadges)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: badge.frameColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: badge.frameColor.withValues(alpha: 0.72),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badge.icon, color: badge.frameColor, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        badge.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  int _calculateMatchExp({required bool isWin}) {
    final baseExp = isWin ? 500 : 100;
    final straightBonus = (_playerWazaCounts[WazaType.straight] ?? 0) * 20;
    final pyramidBonus = (_playerWazaCounts[WazaType.pyramid] ?? 0) * 50;
    final hexagonBonus = (_playerWazaCounts[WazaType.hexagon] ?? 0) * 80;
    return baseExp + straightBonus + pyramidBonus + hexagonBonus;
  }

  int _calculateBattleCoinReward({required bool isWin}) {
    final baseCoins = isWin ? 50 : 10;
    final straightBonus = _straightCount * 10;
    final pyramidBonus = _pyramidCount * 15;
    final hexagonBonus = _hexagonCount * 20;
    return baseCoins + straightBonus + pyramidBonus + hexagonBonus;
  }

  Future<void> _applyBattleCoinReward({required bool isWin}) async {
    if (_resultCoinApplied) {
      return;
    }

    _resultCoinApplied = true;
    final earnedCoins = _calculateBattleCoinReward(isWin: isWin);
    final adsRemoved = AppSettings.instance.adsRemoved.value;
    await _playerDataManager.addCoins(earnedCoins * (adsRemoved ? 3 : 1));
    if (!mounted) {
      return;
    }
    setState(() {
      _resultCoinBaseEarned = earnedCoins;
      _resultCoinTripleClaimed = adsRemoved;
    });
    if (!adsRemoved) {
      unawaited(RewardedAdManager.instance.warmUp());
    }
  }

  Future<void> _claimResultTripleCoinBonus() async {
    final baseCoins = _resultCoinBaseEarned;
    if (_resultCoinTripleInProgress ||
        _resultCoinTripleClaimed ||
        baseCoins == null ||
        baseCoins <= 0) {
      return;
    }

    setState(() {
      _resultCoinTripleInProgress = true;
    });

    try {
      final rewarded = await RewardedAdManager.instance.showDoubleRewardAd();
      if (!rewarded) {
        if (mounted) {
          await _showErrorDialog('広告エラー', '動画の視聴が完了しませんでした。');
        }
        return;
      }

      await _playerDataManager.addCoins(baseCoins * 2);
      if (!mounted) {
        return;
      }
      setState(() {
        _resultCoinTripleClaimed = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _resultCoinTripleInProgress = false;
        });
      }
    }
  }

  Future<void> _applyMatchExpReward({
    required bool isWin,
    bool isForfeitWin = false,
    bool grantLocalExp = true,
  }) async {
    if (_matchExpApplied) {
      return;
    }

    _matchExpApplied = true;
    final earnedExp = _calculateMatchExp(isWin: isWin);
    final displayedExp = grantLocalExp ? earnedExp : 0;

    try {
      await _playerDataManager.load();
      final previousLevel = _playerDataManager.level;
      if (grantLocalExp) {
        await _playerDataManager.addExp(earnedExp);
      }
      final currentLevel = _playerDataManager.level;
      if (!mounted) {
        return;
      }
      _refreshNewlyUnlockedBadgesFromSnapshot();
      setState(() {
        _matchExpEarned = displayedExp;
        if (grantLocalExp && currentLevel > previousLevel) {
          _didLevelUpFromResultExp = true;
          _resultLevelAfterExp = currentLevel;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      _refreshNewlyUnlockedBadgesFromSnapshot();
      setState(() {
        _matchExpEarned = displayedExp;
      });
    }

    try {
      await _recordMatchStats(isWin: isWin, isForfeitWin: isForfeitWin);
    } catch (_) {
      if (mounted) {
        _showRealtimeOfflineMessage();
      }
    }
  }

  int _calculateSoloExp() {
    final scoreState = _playerGame.scoreManager.state.value;
    final scoreBonus = scoreState.score ~/ 120;
    final levelBonus = scoreState.level * 45;
    return max(100, scoreBonus + levelBonus);
  }

  Future<void> _applySoloExpReward() async {
    if (_soloExpApplied) {
      return;
    }

    _soloExpApplied = true;
    final earnedExp = _calculateSoloExp();

    try {
      await _playerDataManager.load();
      final previousLevel = _playerDataManager.level;
      await _playerDataManager.addExp(earnedExp);
      final currentLevel = _playerDataManager.level;
      if (!mounted) {
        return;
      }
      _refreshNewlyUnlockedBadgesFromSnapshot();
      setState(() {
        _soloExpEarned = earnedExp;
        if (currentLevel > previousLevel) {
          _didLevelUpFromResultExp = true;
          _resultLevelAfterExp = currentLevel;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _soloExpEarned = earnedExp;
      });
    }
  }

  Future<void> _recordMatchStats({
    required bool isWin,
    bool isForfeitWin = false,
  }) async {
    final mode = widget.isArenaMode
        ? 'ARENA'
        : widget.isRankedMode
            ? 'RANKED'
            : widget.isCpuMode
                ? 'CPU'
                : 'FRIEND';
    final opponentName = widget.isCpuMode
        ? _opponentDisplayName
        : _displayNameForRole(_multiplayerManager.opponentRoleId) ?? 'UNKNOWN';
    final opponentPlayer = _room?.players[_multiplayerManager.opponentRoleId] ??
        _multiplayerManager
            .currentRoom?.players[_multiplayerManager.opponentRoleId];
    await _playerDataManager.recordMatchResult(
      isWin: isWin,
      mode: mode,
      opponentName: opponentName,
      opponentUid: widget.isCpuMode ? '' : opponentPlayer?.uid ?? '',
      opponentPublicId: widget.isCpuMode ? '' : opponentPlayer?.publicId ?? '',
      wazaCounts: {
        'straight': _playerWazaCounts[WazaType.straight] ?? 0,
        'pyramid': _playerWazaCounts[WazaType.pyramid] ?? 0,
        'hexagon': _playerWazaCounts[WazaType.hexagon] ?? 0,
      },
      clearedBalls: _playerGame.scoreManager.state.value.totalClearedBalls,
      normalClearedBalls: _playerNormalClearedBalls,
      maxChain: _playerGame.scoreManager.maxChainThisRun,
      isForfeitWin: isForfeitWin && isWin,
      ratingAfter: _rankedRatingChange?.newRating,
      ratingDelta: _rankedRatingChange?.delta,
    );
    await _syncPlayerProfileOnline(
      rating:
          _rankedRatingChange?.newRating ?? _playerDataManager.currentRating,
    );
    _refreshNewlyUnlockedBadgesFromSnapshot();
  }

  Future<void> _recordSoloStats() async {
    await _playerDataManager.recordMatchResult(
      isWin: false,
      mode: 'SOLO',
      opponentName: 'エンドレス',
      wazaCounts: {
        'straight': _playerWazaCounts[WazaType.straight] ?? 0,
        'pyramid': _playerWazaCounts[WazaType.pyramid] ?? 0,
        'hexagon': _playerWazaCounts[WazaType.hexagon] ?? 0,
      },
      clearedBalls: _playerGame.scoreManager.state.value.totalClearedBalls,
      normalClearedBalls: _playerNormalClearedBalls,
      maxChain: _playerGame.scoreManager.maxChainThisRun,
      score: _currentPlayerScore,
    );
    try {
      await _syncPlayerProfileOnline(rating: _playerDataManager.currentRating);
    } catch (_) {
      if (mounted) {
        _showRealtimeOfflineMessage();
      }
    }
    _refreshNewlyUnlockedBadgesFromSnapshot();
  }

  Future<void> _recordArenaResult({required bool isWin}) async {
    if (!widget.isArenaMode || _arenaResultApplied) {
      return;
    }

    _arenaResultApplied = true;
    await _playerDataManager.load();
    final previousLevel = _playerDataManager.level;
    final result = await _arenaManager.recordArenaMatch(isWin);
    if (isWin) {
      unawaited(_missionManager.recordEvent('win_arena_match'));
    }
    try {
      await _syncPlayerProfileOnline(
        rating: _playerDataManager.currentRating,
        incrementDailyWin: isWin,
      );
    } catch (_) {
      if (mounted) {
        _showRealtimeOfflineMessage();
      }
    }
    final currentLevel = _playerDataManager.level;
    if (!mounted) {
      return;
    }
    _refreshNewlyUnlockedBadgesFromSnapshot();
    setState(() {
      _arenaMatchResult = result;
      if (currentLevel > previousLevel) {
        _didLevelUpFromResultExp = true;
        _resultLevelAfterExp = currentLevel;
      }
    });
  }

  Future<void> _returnHomeAfterMatch() async {
    if (_isReturningToHome || _isCheckingHomeReturnConnection) {
      return;
    }
    _isCheckingHomeReturnConnection = true;
    try {
      var connected = _realtimeConnected;
      if (connected) {
        final currentConnected =
            await RealtimeConnectionGuard.currentConnected();
        if (currentConnected != null) {
          connected = currentConnected;
        } else {
          connected = await RealtimeConnectionGuard.waitForConnected(
            timeout: const Duration(milliseconds: 700),
          );
        }
      }
      _realtimeConnected = connected;
      if (!connected) {
        if (mounted) {
          await _showCyberAlertDialog(
            'ランク戦に失敗しました',
            RealtimeConnectionGuard.offlineMessage,
          );
        }
        return;
      }
    } finally {
      _isCheckingHomeReturnConnection = false;
    }
    if (!mounted || _isReturningToHome) {
      return;
    }
    _isReturningToHome = true;
    await GameActivityPresence.instance.exit();
    _shutdownBattleGames();
    _myStampTimer?.cancel();
    _opponentStampTimer?.cancel();
    _stampCooldownTimer?.cancel();
    await _stopBattleBgm();
    if (_isOnlineMode) {
      await _multiplayerManager.leaveRoom();
      await _multiplayerManager.clearSavedSession();
    }
    await SfxPlayer.resetTransientAudio();
    if (widget.returnToCallerOnExit) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      return;
    }
    final bootstrapFuture = prepareHomeBootstrapData();
    if (!_resultCoinTripleClaimed) {
      await InterstitialAdManager.instance.showAfterGame();
      await InterstitialAdManager.instance.settleAfterGame();
    }
    await SfxPlayer.resetTransientAudio();
    final bootstrapData = await bootstrapFuture;
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(bootstrapData: bootstrapData),
      ),
    );
  }

  void _handleOpponentDisconnected() {
    if (!_onlineGameStarted) {
      _handlePreBattleOpponentForfeit(_room?.seed);
      return;
    }

    final resultAlreadyShown = _onlineResultMessage != null ||
        _playerGame.gameStateWrapper.value == GameState.gameover;
    if (resultAlreadyShown) {
      if (mounted) {
        setState(() {
          _opponentUnavailableForRematch = true;
          _isWaitingForRematch = false;
        });
      }
      return;
    }

    if (!mounted || _isDisconnectDialogVisible) {
      return;
    }

    _isDisconnectDialogVisible = true;
    unawaited(
      _presentBattleResult(
        playerWon: true,
        opponentCrossedDeathLine: false,
        resultWasForfeit: true,
      ).whenComplete(() {
        _isDisconnectDialogVisible = false;
      }),
    );
  }

  void _handleRematchStarted(int newSeed) {
    if (!mounted) {
      return;
    }
    unawaited(_startRematchBattleWithReadyGo(newSeed));
  }

  Future<void> _startRematchBattleWithReadyGo(int newSeed) async {
    if (!mounted) {
      return;
    }

    _cpuBattlePlayerWon = null;
    _resetResultProgressionState();
    _clearAllPendingAttacks();
    _cpuGame?.clearRemoteActivePiece();
    setState(() {
      _onlineGameStarted = true;
      _onlineResultMessage = null;
      _onlineResultWasForfeit = false;
      _onlineResultWasOfflineForfeit = false;
      _opponentUnavailableForRematch = false;
      _isWaitingForRematch = false;
    });
    await _startOnlineBattleWithReadyGo(
      newSeed,
      preReadyDelay: const Duration(seconds: 1),
    );
    if (_isOnlineMode) {
      _sendServerAction(
        () => _multiplayerManager.saveActiveSession(
          isArenaMode: widget.isArenaMode,
        ),
      );
    }
  }

  Future<void> _startBattleBgmAfterGoDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      return;
    }
    await _startBattleBgm();
  }

  Future<void> _startBattleBgm() async {
    if (_isBattleBgmPlaying && SeamlessBgm.instance.isPlaying) {
      return;
    }
    _isBattleBgmPlaying = true;
    try {
      await SeamlessBgm.instance.setMasterVolume(
        AppSettings.instance.musicVolume.value,
      );
      await SeamlessBgm.instance.play(
        assetPath: 'audio/battle_bgm01.wav',
        duration: _battleBgmDuration,
        volume: 0.2448,
        owner: _bgmOwner,
      );
    } catch (_) {
      _isBattleBgmPlaying = false;
    }
  }

  Future<void> _startTutorialBgm() async {
    if (_isBattleBgmPlaying && SeamlessBgm.instance.isPlaying) {
      return;
    }
    _isBattleBgmPlaying = true;
    try {
      await SeamlessBgm.instance.setMasterVolume(
        AppSettings.instance.musicVolume.value,
      );
      await SeamlessBgm.instance.play(
        assetPath: 'audio/home_screen_bgm01.wav',
        duration: _homeBgmDuration,
        volume: 0.576,
        owner: _bgmOwner,
      );
    } catch (_) {
      _isBattleBgmPlaying = false;
    }
  }

  void _freezeBattleBoards() {
    _applyBattleFinishEffect(_playerGame);
    _playerGame.gameStateWrapper.value = GameState.gameover;
    if (_playerGame.activePiece != null) {
      _playerGame.activePiece!.isLocked = true;
    }
    if (_playerGame.ghostPiece != null) {
      _playerGame.ghostPiece!.isLocked = true;
    }
    if (_cpuGame != null) {
      _applyBattleFinishEffect(_cpuGame!);
      _cpuGame!.gameStateWrapper.value = GameState.gameover;
      if (_cpuGame!.activePiece != null) {
        _cpuGame!.activePiece!.isLocked = true;
      }
      if (_cpuGame!.ghostPiece != null) {
        _cpuGame!.ghostPiece!.isLocked = true;
      }
    }
  }

  void _applyBattleFinishEffect(PuzzleGame game) {
    final piece = game.activePiece;
    if (piece == null || piece.isLocked) {
      return;
    }
    final ghostPiece = game.ghostPiece;

    piece.add(
      ScaleEffect.to(
        Vector2.all(1.08),
        EffectController(duration: 0.18, curve: Curves.easeOutCubic),
      ),
    );
    piece.add(
      RotateEffect.by(
        0.16,
        EffectController(duration: 0.28, curve: Curves.easeOutCubic),
      ),
    );

    for (var i = 0; i < piece.absoluteBallPositions.length; i++) {
      final position = piece.absoluteBallPositions[i];
      final color = piece.colors[i];
      game.add(
        BallPopRingEffect(
          position: position.clone(),
          ringColor: color.glowColor,
        ),
      );
      game.add(
        SparkEffect(
          position: position.clone(),
          sparkColor: color.glowColor,
        ),
      );
    }
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (piece.parent != null) {
        piece.removeFromParent();
      }
      if (ghostPiece?.parent != null) {
        ghostPiece?.removeFromParent();
      }
      if (identical(game.activePiece, piece)) {
        game.activePiece = null;
      }
      if (identical(game.ghostPiece, ghostPiece)) {
        game.ghostPiece = null;
      }
    });
  }

  void _triggerResultAudio({required bool playerWon}) {
    if (_resultAudioStarted) {
      return;
    }
    _resultAudioStarted = true;
    _resultAudioStartedAt = DateTime.now();
    unawaited(_stopBattleBgm());
    if (playerWon) {
      AppSfx.playWin();
    } else {
      AppSfx.playLose();
    }
  }

  Future<void> _waitForResultAudioLead({required bool playerWon}) async {
    final startedAt = _resultAudioStartedAt;
    final expected = playerWon
        ? const Duration(milliseconds: 1400)
        : const Duration(milliseconds: 1800);
    if (startedAt == null) {
      await Future<void>.delayed(expected);
      return;
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remaining = expected - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> _stopBattleBgm() async {
    if (widget.isTutorialMode) {
      _isBattleBgmPlaying = false;
      return;
    }
    if (!_isBattleBgmPlaying && !SeamlessBgm.instance.isPlaying) {
      return;
    }
    _isBattleBgmPlaying = false;
    try {
      await SeamlessBgm.instance.stop(owner: _bgmOwner);
    } catch (_) {
      // BGM停止失敗で画面遷移や破棄を止めない。
    }
  }

  Future<void> _showErrorDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E32),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            FilledButton(
              onPressed: () {
                _playUiTap();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCyberAlertDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _gameCyan,
          title: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _buildCyberDialogButton(
                label: 'OK',
                accentColor: _gameCyan,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCyberDialog({
    required String title,
    required Widget child,
    required Color accentColor,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: const Color(0xFF141421),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.78),
              width: 1.5,
            )),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accentColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCyberDialogButton({
    required String label,
    required Color accentColor,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: () {
        _playUiTap();
        onPressed();
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.75),
          width: 1.4,
        ),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.6,
        ),
      ),
    );
  }

  Widget _buildBattleSettingsButton() {
    final canOpen = _canOpenBattleSettings;
    return SafeArea(
      child: IconButton(
        onPressed: canOpen
            ? () {
                _playUiTap();
                unawaited(_showSettingsMenu());
              }
            : null,
        icon: Icon(
          Icons.settings,
          color: canOpen ? Colors.white : Colors.white38,
        ),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.45),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
    );
  }

  Future<void> _showSettingsMenu() {
    if (_blocksOnlineExit || !_canOpenBattleSettings) {
      return Future<void>.value();
    }

    final shouldResumeBattle = _pauseBattleForSettings();

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: const Color(0xFF141421),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _gameCyan.withValues(alpha: 0.72),
                  width: 1.4,
                )),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '設定',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _gameCyan,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () {
                    _playUiTap();
                    Navigator.of(dialogContext).pop();
                    unawaited(_returnHomeFromSettings());
                  },
                  icon: const Icon(Icons.home, size: 18),
                  label: const Text('ホーム画面に戻る'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gameCyan,
                    side: BorderSide(
                      color: _gameCyan.withValues(alpha: 0.72),
                      width: 1.3,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (!_isOnlineMode && !widget.isCpuMode) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      _playUiTap();
                      Navigator.of(dialogContext).pop();
                      _clearAllPendingAttacks();
                      unawaited(
                        _startLocalBattleWithReadyGo(
                          DateTime.now().millisecondsSinceEpoch,
                        ),
                      );
                    },
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('リスタート'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _gameCyan,
                      side: BorderSide(
                        color: _gameCyan.withValues(alpha: 0.72),
                        width: 1.3,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    _playUiTap();
                    Navigator.of(dialogContext).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.36),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.4,
                    ),
                  ),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (shouldResumeBattle) {
        _resumeBattleFromSettings();
      }
    });
  }

  bool _pauseBattleForSettings() {
    if (_isOnlineMode ||
        !_isBattleInProgress ||
        _readyGoOverlayText != null ||
        _resultRevealPending) {
      return false;
    }
    _playerGame.pauseEngine();
    _cpuGame?.pauseEngine();
    return true;
  }

  void _resumeBattleFromSettings() {
    if (!mounted || _isReturningToHome) {
      return;
    }
    _playerGame.resumeEngine();
    _cpuGame?.resumeEngine();
  }

  Future<void> _returnHomeFromSettings() async {
    _isReturningToHome = true;
    await GameActivityPresence.instance.exit();
    _clearAllPendingAttacks();
    _playerGame.pauseEngine();
    _cpuGame?.pauseEngine();
    await _stopBattleBgm();
    if (_isOnlineMode) {
      if (!_onlineGameStarted && !widget.isRankedMode) {
        await _multiplayerManager.cancelLobby();
      } else {
        await _multiplayerManager.leaveRoom();
      }
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _requestRematch() async {
    if (!_canShowRematchButton) {
      return;
    }
    setState(() {
      _isWaitingForRematch = true;
    });

    try {
      final connected = await _ensureServerConnection();
      if (!connected) {
        if (mounted) {
          setState(() {
            _isWaitingForRematch = false;
          });
        }
        return;
      }
      await _multiplayerManager.requestRematch();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isWaitingForRematch = false;
      });
      await _showErrorDialog('再戦の送信に失敗しました', '$error');
    }
  }

  void _leaveOnlineBattle() {
    _clearAllPendingAttacks();
    unawaited(_returnHomeAfterMatch());
  }

  void _queueOjamaTask(PuzzleGame targetGame, OjamaTask task) {
    late Timer timer;
    timer = Timer(const Duration(milliseconds: 2500), () {
      _pendingAttackTimers.remove(timer);
      if (targetGame.gameStateWrapper.value != GameState.playing) {
        return;
      }

      targetGame.incomingOjama.add(
        OjamaTask(
          task.type,
          startColor: task.startColor,
          presetColors: task.presetColors == null
              ? null
              : List<BallColor>.from(task.presetColors!),
        ),
      );
    });
    _pendingAttackTimers.add(timer);
  }

  Future<void> _applyAttackToOpponent(OjamaTask task) async {
    final connected = await _ensureServerConnection(
      forfeitRankedOnOffline: widget.isRankedMode,
    );
    if (!connected) {
      return;
    }
    try {
      await _multiplayerManager.sendAttack(task);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showRealtimeOfflineMessage();
      if (widget.isRankedMode) {
        _forfeitRankedMatchForOfflineIfNeeded();
      }
    }
  }

  Future<void> _presentBattleResult({
    required bool playerWon,
    required bool opponentCrossedDeathLine,
    bool resultWasForfeit = false,
    bool resultWasOfflineForfeit = false,
  }) async {
    if (_resultRevealPending) {
      return;
    }

    _resultRevealPending = true;
    if (widget.isRankedMode && !widget.isArenaMode) {
      unawaited(
        _multiplayerManager.markSavedSessionResultKnown(isWin: playerWon),
      );
    }
    if (!resultWasForfeit) {
      await Future<void>.delayed(_resultFreezeDelay);
      if (!mounted) {
        return;
      }
    }
    _freezeBattleBoards();
    final targetGame = playerWon &&
            _cpuGame != null &&
            (opponentCrossedDeathLine || resultWasForfeit)
        ? _cpuGame!
        : _playerGame;
    if (!resultWasForfeit && opponentCrossedDeathLine) {
      await Future<void>.delayed(_resultOpponentDisplayGrace);
      if (!mounted) {
        return;
      }
    }
    _triggerResultAudio(playerWon: playerWon);
    await targetGame.animateDeathLineToRed();
    await Future<void>.delayed(_resultBoardSettleDelay);
    await _waitForResultAudioLead(playerWon: playerWon);
    if (!mounted) {
      return;
    }

    if (widget.isTutorialMode) {
      _cpuBattlePlayerWon = playerWon;
      await AppSettings.instance.setOnboardingSeen(true);
      if (!mounted) {
        return;
      }
      setState(() {
        _resultCoinBaseEarned = 0;
        _matchExpEarned = 0;
        _resultRevealPending = false;
      });
      return;
    }

    await _captureResultBadgeSnapshot();
    if (!mounted) {
      return;
    }

    if (widget.isCpuMode) {
      if (!_resultCoinTripleClaimed) {
        unawaited(InterstitialAdManager.instance.warmUp());
      }
      _cpuBattlePlayerWon = playerWon;
      unawaited(_missionManager.recordEvent('play_match'));
      unawaited(_missionManager.recordEvent('play_cpu'));
      if (playerWon) {
        unawaited(_missionManager.recordEvent('win_match'));
        if (widget.isRankedMode) {
          unawaited(_missionManager.recordEvent('win_ranked_match'));
        }
      }
      unawaited(_applyBattleCoinReward(isWin: playerWon));
      unawaited(
        _applyMatchExpReward(
          isWin: playerWon,
          grantLocalExp: true,
        ),
      );
      unawaited(_applyRankedBotRatingResult(isWin: playerWon));
      setState(() {
        _resultRevealPending = false;
      });
      return;
    }

    if (_isOnlineMode) {
      if (!_resultCoinTripleClaimed) {
        unawaited(InterstitialAdManager.instance.warmUp());
      }
      unawaited(_missionManager.recordEvent('play_match'));
      if (playerWon) {
        unawaited(_missionManager.recordEvent('win_match'));
        if (widget.isRankedMode && !widget.isArenaMode) {
          unawaited(_missionManager.recordEvent('win_ranked_match'));
        }
      }
      unawaited(_applyBattleCoinReward(isWin: playerWon));
      unawaited(
        _applyMatchExpReward(
          isWin: playerWon,
          isForfeitWin: resultWasForfeit && playerWon,
          grantLocalExp: true,
        ),
      );
      unawaited(
        _applyRankedRatingResult(
          isWin: playerWon,
          applyOpponentResult: resultWasForfeit,
        ),
      );
      unawaited(_recordArenaResult(isWin: playerWon));
      unawaited(_multiplayerManager.clearSavedSession());
      setState(() {
        _onlineResultMessage = playerWon ? 'YOU WIN!!' : 'YOU LOSE...';
        _onlineResultWasForfeit = resultWasForfeit;
        _onlineResultWasOfflineForfeit = resultWasOfflineForfeit;
        _isWaitingForRematch = false;
        _resultRevealPending = false;
      });
      return;
    }

    unawaited(_applyBattleCoinReward(isWin: false));
    if (!_resultCoinTripleClaimed) {
      unawaited(InterstitialAdManager.instance.warmUp());
    }
    if (_currentPlayerScore >= 10000) {
      unawaited(_missionManager.recordEvent('score_endless_10000'));
    }
    unawaited(_applySoloExpReward());
    unawaited(_recordSoloStats());
    setState(() {
      _resultRevealPending = false;
    });
  }

  OjamaTask? _createOjamaTaskForAttack(WazaType waza, BallColor? color) {
    switch (waza) {
      case WazaType.hexagon:
        return OjamaTask(OjamaType.hexagonSet);
      case WazaType.pyramid:
        return OjamaTask(OjamaType.pyramidSet);
      case WazaType.straight:
        final startColor = color ?? BallColor.blue;
        return OjamaTask(
          OjamaType.straightSet,
          startColor: startColor,
          presetColors: _generateStraightOjamaColors(startColor),
        );
      case WazaType.none:
        return null;
    }
  }

  List<BallColor> _parseColors(Object? rawColors) {
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
        .map((value) => value is num ? value.toInt() : int.tryParse('$value'))
        .whereType<int>()
        .where((index) => index >= 0 && index < BallColor.values.length)
        .map((index) => BallColor.values[index])
        .toList();
  }

  List<BallColor> _generateStraightOjamaColors(BallColor startColor) {
    const loopColors = [
      BallColor.blue,
      BallColor.purple,
      BallColor.yellow,
      BallColor.red,
      BallColor.green,
    ];
    final bottomStart = loopColors.indexOf(startColor);
    final colors = <BallColor>[];

    for (var i = 0; i < 10; i++) {
      colors.add(loopColors[(bottomStart + i) % loopColors.length]);
    }
    for (var i = 0; i < 9; i++) {
      colors.add(loopColors[(bottomStart + i) % loopColors.length]);
    }

    return colors;
  }

  Widget _buildPieceIcon(List<BallColor> colors, {required double size}) {
    if (colors.length != 3) {
      return const SizedBox.shrink();
    }

    final hSpacing = size + 2;
    final vSpacing = size;

    return SizedBox(
      width: hSpacing + size,
      height: vSpacing + size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: hSpacing / 2,
            top: 0,
            child: MiniBallWidget(ballColor: colors[0], size: size),
          ),
          Positioned(
            left: 0,
            top: vSpacing,
            child: MiniBallWidget(ballColor: colors[1], size: size),
          ),
          Positioned(
            left: hSpacing,
            top: vSpacing,
            child: MiniBallWidget(ballColor: colors[2], size: size),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(PuzzleGame game) {
    return ValueListenableBuilder<ControlLayoutPreset>(
      valueListenable: AppSettings.instance.controlLayout,
      builder: (context, preset, child) {
        final actions = _controlActionsFor(
          game,
          widget.isTutorialMode
              ? ControlLayoutPreset.rotateMoveMoveRotate
              : preset,
        );
        return Container(
          height: 96,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xEE080A12),
            border: Border(
              top: BorderSide(
                color: _gameCyan.withValues(alpha: 0.22),
                width: 1.2,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                Expanded(
                  child: _buildAreaButton(
                    action: actions[i].tutorialAction,
                    icon: actions[i].icon,
                    onDown: widget.isTutorialMode
                        ? () => _handleTutorialControlDown(
                              actions[i].tutorialAction,
                            )
                        : actions[i].onDown,
                    onUp: widget.isTutorialMode
                        ? () =>
                            _handleTutorialControlUp(actions[i].tutorialAction)
                        : actions[i].onUp,
                  ),
                ),
                if (i != actions.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTutorialStep3Message() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: _buildTutorialMessageCard(
        child: Text(
          _tutorialMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.32,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildTutorialMessageCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xDD101827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _gameCyan.withValues(alpha: 0.64),
            width: 1.3,
          )),
      child: child,
    );
  }

  Widget _buildTutorialSkipOverlay() {
    return Positioned(
      top: 8,
      right: 8,
      child: _buildTutorialSkipChip(),
    );
  }

  Widget _buildTutorialSkipChip() {
    return TextButton(
      onPressed: () => unawaited(_finishTutorial()),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white70,
        backgroundColor: Colors.black.withValues(alpha: 0.72),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: const Text(
        'SKIP',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildTutorialDropTargetOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: _gameCyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _gameCyan.withValues(alpha: 0.82),
                  width: 2.4,
                )),
            child: Center(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(
                  'tutorial-board-drop-${DateTime.now().millisecondsSinceEpoch ~/ 760}',
                ),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 760),
                builder: (context, value, child) {
                  final pulse = sin(value * pi);
                  return Transform.translate(
                    offset: Offset(0, -pulse * 12),
                    child: Transform.scale(
                      scale: 0.94 + pulse * 0.12,
                      child: child,
                    ),
                  );
                },
                onEnd: () {
                  if (mounted && _isTutorialBoardDropEnabled) {
                    setState(() {});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  child: const Icon(
                    Icons.touch_app,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_ControlAction> _controlActionsFor(
    PuzzleGame game,
    ControlLayoutPreset preset,
  ) {
    final rotateLeft = _ControlAction(
      icon: Icons.rotate_left,
      tutorialAction: _TutorialAction.rotateLeft,
      onDown: game.rotateLeft,
    );
    final moveLeft = _ControlAction(
      icon: Icons.arrow_left,
      tutorialAction: _TutorialAction.moveLeft,
      onDown: game.startMovingLeft,
      onUp: game.stopMovingLeft,
    );
    final moveRight = _ControlAction(
      icon: Icons.arrow_right,
      tutorialAction: _TutorialAction.moveRight,
      onDown: game.startMovingRight,
      onUp: game.stopMovingRight,
    );
    final rotateRight = _ControlAction(
      icon: Icons.rotate_right,
      tutorialAction: _TutorialAction.rotateRight,
      onDown: game.rotateRight,
    );

    return switch (preset) {
      ControlLayoutPreset.rotateMoveMoveRotate => [
          rotateLeft,
          moveLeft,
          moveRight,
          rotateRight,
        ],
      ControlLayoutPreset.moveMoveRotateRotate => [
          moveLeft,
          moveRight,
          rotateLeft,
          rotateRight,
        ],
      ControlLayoutPreset.rotateRotateMoveMove => [
          rotateLeft,
          rotateRight,
          moveLeft,
          moveRight,
        ],
      ControlLayoutPreset.moveRotateRotateMove => [
          moveLeft,
          rotateLeft,
          rotateRight,
          moveRight,
        ],
    };
  }

  Widget _buildAreaButton({
    required _TutorialAction action,
    required IconData icon,
    required VoidCallback onDown,
    VoidCallback? onUp,
  }) {
    final enabled =
        !widget.isTutorialMode || _enabledTutorialActions.contains(action);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (!enabled) {
          return;
        }
        _playUiTap();
        onDown();
      },
      onTapUp: (_) {
        if (enabled && onUp != null) {
          onUp();
        }
      },
      onTapCancel: () {
        if (enabled && onUp != null) {
          onUp();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          gradient: enabled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _gameCyan.withValues(alpha: 0.16),
                    GameThemeColors.blueSide.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: 0.035),
                  ],
                )
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? _gameCyan.withValues(alpha: 0.58)
                : Colors.white.withValues(alpha: 0.12),
            width: enabled ? 1.4 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: enabled ? 1 : 0.24,
              child: Icon(
                icon,
                color: enabled ? _gameCyan : Colors.white38,
                size: 32,
              ),
            ),
            if (widget.isTutorialMode && enabled)
              Positioned(
                top: -18,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(
                      'tutorial-finger-${action.name}-${DateTime.now().millisecondsSinceEpoch ~/ 700}'),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, -sin(value * pi) * 8),
                      child: Transform.scale(
                        scale: 0.94 + sin(value * pi) * 0.1,
                        child: child,
                      ),
                    );
                  },
                  onEnd: () {
                    if (mounted && widget.isTutorialMode) {
                      setState(() {});
                    }
                  },
                  child: const Icon(
                    Icons.touch_app,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ControlAction {
  const _ControlAction({
    required this.icon,
    required this.tutorialAction,
    required this.onDown,
    this.onUp,
  });

  final IconData icon;
  final _TutorialAction tutorialAction;
  final VoidCallback onDown;
  final VoidCallback? onUp;
}

class _TutorialResultLine extends StatelessWidget {
  const _TutorialResultLine({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _gameCyan,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
