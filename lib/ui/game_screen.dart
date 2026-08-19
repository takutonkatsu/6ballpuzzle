import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ads/ranked_interstitial_debt_manager.dart';
import '../app_settings.dart';
import '../audio/audio_selection_manager.dart';
import '../audio/seamless_bgm.dart';
import '../audio/sfx.dart';
import '../audio/sfx_player.dart';
import '../data/models/badge_item.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../friends/friend_manager.dart';
import '../game/arena_manager.dart';
import '../game/components/ball_component.dart';
import '../game/components/effect_components.dart';
import '../game/daily_challenge_manager.dart';
import '../game/friend_match_limit_manager.dart';
import '../game/game_models.dart';
import '../game/mission_manager.dart';
import '../game/puzzle_game.dart';
import '../game/score_manager.dart';
import '../invite/invite_manager.dart';
import '../network/multiplayer_manager.dart';
import '../network/game_activity_presence.dart';
import '../network/ranked_season_manager.dart';
import '../network/ranking_manager.dart';
import '../network/realtime_connection_guard.dart';
import '../network/server_time_manager.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/game_pressable.dart';
import 'components/interstitial_ad_manager.dart';
import 'components/player_icon_image.dart';
import 'components/rewarded_ad_manager.dart';
import 'components/screen_bottom_banner_ad.dart';
import 'components/season_rank_badge_icon.dart';
import 'components/stamp_widget.dart';
import 'components/stamp_square_tile.dart';
import 'home_screen.dart';
import 'theme/game_theme_colors.dart';

const Color _gameCyan = GameThemeColors.cyan;
const Color _battlePlayerColor = GameThemeColors.blueSide;
const Color _battleOpponentColor = GameThemeColors.redSide;
const Color _rankedPurple = GameThemeColors.ranked;
const Color _endlessGreen = GameThemeColors.endless;
const Color _computerYellow = GameThemeColors.computer;
const Color _friendPink = GameThemeColors.friend;
const Color _dailyBlue = GameThemeColors.blueSide;
const Color _mutedButtonGrey = GameThemeColors.mutedButton;
const Duration _playerProfileSyncTimeout = Duration(seconds: 15);
const String _rankedWinReviewPromptPendingKey =
    'ranked_win_review_prompt_pending';
const String _shareAppIconAsset = 'assets/images/Hexagon_icon02_1024x1024.png';
const String _shareSeasonBadgeAsset =
    'assets/images/Badge/Ranking_Badge_Rank.png';
const String _shareStoreQrAsset = 'assets/images/QRcode_Hexagon_iOS.png';
const String _shareCoinAsset = 'assets/images/Hexagon_Coin.png';
const String _shareTrophyAsset = 'assets/images/Hexagon_Trophy.png';
const String _rankedBotDefaultName = 'プレイヤー';

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
  final String rankedBotIconId;
  final String rankedBotFrameId;
  final bool isTutorialMode;
  final bool returnToCallerOnExit;
  final bool isDailyMode;
  final String? dailyDateKey;
  final int? dailySeed;
  final String? friendInviteTargetUid;
  final String? friendInviteId;

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
    this.rankedBotName = _rankedBotDefaultName,
    this.rankedBotIconId = 'default',
    this.rankedBotFrameId = 'default',
    this.isTutorialMode = false,
    this.returnToCallerOnExit = false,
    this.isDailyMode = false,
    this.dailyDateKey,
    this.dailySeed,
    this.friendInviteTargetUid,
    this.friendInviteId,
  });

  const GameScreen.online({
    super.key,
    this.roomId,
    this.isHost = false,
    this.isRankedMode = false,
    this.isArenaMode = false,
    this.friendInviteTargetUid,
    this.friendInviteId,
  })  : cpuDifficulty = CPUDifficulty.hard,
        rankedBotRating = null,
        rankedBotName = _rankedBotDefaultName,
        rankedBotIconId = 'default',
        rankedBotFrameId = 'default',
        isTutorialMode = false,
        returnToCallerOnExit = false,
        isDailyMode = false,
        dailyDateKey = null,
        dailySeed = null,
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

class _GameScreenState extends State<GameScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Object _bgmOwner = 'game_screen';

  static const double _gameViewportWidth = 308;
  static const double _gameViewportHeight = 480;
  static const double _gridBallDiameter = 30;
  static const double _compactStampWidth = 118;
  static const Duration _postReadyGoBoardPause = Duration(milliseconds: 350);
  static const Duration _preReadyDelay = Duration(milliseconds: 500);
  static const Duration _defaultReadyToGoDelay = Duration(milliseconds: 1200);
  static const Duration _countdownReadyToGoDelay = Duration(milliseconds: 2600);
  static const Duration _resultFreezeDelay = Duration(milliseconds: 700);
  static const Duration _resultBoardSettleDelay = Duration(milliseconds: 650);
  static const Duration _resultOpponentDisplayGrace =
      Duration(milliseconds: 450);
  static const Duration _rankedOfflineForfeitGrace = Duration(seconds: 10);
  static const Duration _opponentDisconnectForfeitGrace = Duration(seconds: 2);
  static const String _readySfx = 'readyGo01_メニューを開く3.mp3';
  static const String _countdownReadySfx =
      'readyGo03_3_2_1_GO!!!_レースのスタート音.mp3';

  final MultiplayerManager _multiplayerManager = MultiplayerManager();
  final RankingManager _rankingManager = RankingManager.instance;
  final PlayerDataManager _playerDataManager = PlayerDataManager.instance;
  final ArenaManager _arenaManager = ArenaManager.instance;
  final MissionManager _missionManager = MissionManager.instance;
  static const MethodChannel _shareImageChannel =
      MethodChannel('hexagon/share_image');
  late final PuzzleGame _playerGame;
  PuzzleGame? _cpuGame;
  final FocusNode _playerFocusNode = FocusNode();
  MultiplayerRoom? _room;
  bool _onlineGameStarted = false;
  bool _readySubmitting = false;
  bool _friendLobbyMatchAllowanceConsumed = true;
  String? _onlineResultMessage;
  bool _onlineResultWasForfeit = false;
  bool _onlineResultWasOfflineForfeit = false;
  bool _activeResultWasForfeit = false;
  bool _battleResultWasOfflineForfeitLoss = false;
  bool _isWaitingForRematch = false;
  bool _opponentRequestedRematch = false;
  bool _opponentUnavailableForRematch = false;
  bool _friendDisconnectDialogShown = false;
  bool _friendInviteDeclineHandled = false;
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
  bool _battleResultStarted = false;
  bool _arenaResultApplied = false;
  ArenaMatchResult? _arenaMatchResult;
  bool _matchExpApplied = false;
  int? _matchExpEarned;
  bool _soloExpApplied = false;
  int? _soloExpEarned;
  bool _dailyResultRecorded = false;
  Timer? _dailyChallengeTimer;
  int _dailyRemainingSeconds = DailyChallengeManager.durationSeconds;
  bool _resultCoinApplied = false;
  int? _resultCoinBaseEarned;
  bool _resultCoinTripleClaimed = false;
  bool _resultCoinTripleInProgress = false;
  bool _resultShareInProgress = false;
  late final AnimationController _resultTriplePromptController;
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
  bool _isStampGridVisible = false;
  GameItem? _currentFloatingStamp;
  GameItem? _opponentFloatingStamp;
  bool _tutorialRightMoveActive = false;
  bool _tutorialLeftMoveActive = false;
  Timer? _myStampTimer;
  Timer? _opponentStampTimer;
  Timer? _stampCooldownTimer;
  StreamSubscription<String>? _friendInviteStatusSubscription;
  Timer? _tutorialTimer;
  StreamSubscription<bool>? _realtimeConnectionSubscription;
  bool _realtimeConnected = true;
  bool _rankedOfflineForfeitStarted = false;
  bool _pendingOfflineForfeitCommit = false;
  Timer? _rankedOfflineForfeitTimer;
  Timer? _opponentDisconnectForfeitTimer;
  bool _opponentRealtimeDisconnected = false;
  DateTime? _rankedOfflineSince;
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
  final Set<int> _processedOpponentTerminalPieceIds = <int>{};
  final Map<int, int> _lastOpponentEventSeqByPieceId = <int, int>{};
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

  String get _friendPresenceMode {
    if (widget.isRankedMode) {
      return 'ranked';
    }
    if (widget.isArenaMode) {
      return 'arena';
    }
    if (_isFriendMode) {
      return 'friend';
    }
    if (widget.isDailyMode) {
      return 'daily';
    }
    if (widget.isCpuMode) {
      return 'computer';
    }
    if (widget.isTutorialMode) {
      return 'tutorial';
    }
    return 'endless';
  }

  int get _playerBoardRows {
    final room = _room ?? _multiplayerManager.currentRoom;
    final roleId = _multiplayerManager.myRoleId;
    if (!_isFriendMode || room == null || roleId == null) {
      return 12;
    }
    return room.boardRowsForRole(roleId);
  }

  int get _opponentBoardRows {
    final room = _room ?? _multiplayerManager.currentRoom;
    if (!_isFriendMode || room == null) {
      return 12;
    }
    return room.boardRowsForRole(_multiplayerManager.opponentRoleId);
  }

  int get _currentPlayerScore => _playerGame.scoreManager.state.value.score;

  int get _currentPlayerLevel => _playerGame.scoreManager.state.value.level;

  Color get _readyGoThemeColor {
    if (widget.isDailyMode) {
      return _dailyBlue;
    }
    if (widget.isRankedMode) {
      return _rankedPurple;
    }
    if (widget.isArenaMode) {
      return _gameCyan;
    }
    if (widget.isCpuMode) {
      return _computerYellow;
    }
    if (_isFriendMode) {
      return _friendPink;
    }
    if (_usesEndlessBattleLayout) {
      return _endlessGreen;
    }
    return _gameCyan;
  }

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
    _resultTriplePromptController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat(reverse: true);
    unawaited(_enterGameActivityPresence());
    unawaited(FriendManager.instance.markPresence(
      online: true,
      inBattle: true,
      mode: _friendPresenceMode,
    ));
    _startFriendInviteStatusMonitorIfNeeded();
    unawaited(RewardedAdManager.instance.warmUp());
    unawaited(_arenaManager.load().then((_) {
      if (mounted) {
        setState(() {});
      }
    }));
    final gameSeed = widget.isDailyMode
        ? widget.dailySeed
        : widget.isOnlineMultiplayer
            ? _multiplayerManager.currentRoom?.seed
            : DateTime.now().millisecondsSinceEpoch;
    final localGameSeed = gameSeed ?? DateTime.now().millisecondsSinceEpoch;
    final playerHintGuideEnabled =
        AppSettings.instance.hintGuideEnabled.value &&
            !widget.isTutorialMode &&
            (widget.isCpuMode ||
                (widget.isOnlineMultiplayer &&
                    !widget.isRankedMode &&
                    !widget.isArenaMode));

    _playerGame = PuzzleGame(
      isCpuMode: false,
      seed: gameSeed,
      autoStart: false,
      useConstantFallSpeed: _usesConstantFallSpeed,
      manualPieceSpawning: widget.isTutorialMode,
      hintGuideEnabled: playerHintGuideEnabled,
      scoreMode: widget.isDailyMode ? ScoreMode.daily : ScoreMode.endless,
      wallColor: Colors.blueAccent,
      ballSkinId: _playerDataManager.equippedBallSkinId,
      formationEffectId: _playerDataManager.equippedFormationEffectId,
      gridRows: _playerBoardRows,
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
        renderDetectedFormationEffects: true,
        wallColor: _battleOpponentColor,
        ballSkinId: _opponentBallSkinId(),
        formationEffectId: _opponentFormationEffectId(),
        sfxSelectionIds: _opponentSfxSelectionIds(),
        gridRows: _opponentBoardRows,
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
      _multiplayerManager.onOpponentGameOver =
          _handleOpponentGameOverWithFinalBoard;
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
      if ((_room?.status == 'playing') ||
          ((_room?.isRanked ?? false) && (_room?.bothPlayersReady ?? false))) {
        _onlineGameStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_startOnlineBattleWithReadyGo(_room!.seed));
        });
      } else if (_room?.bothPlayersJoined ?? false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _playMatchedSfxOnce();
          if (!_isFriendMode) {
            unawaited(_attemptAutoReady());
          }
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
        sfxSelectionIds: AudioSelectionManager.defaultSfxSelectionIds(),
      );
      if (_cpuGame!.cpuAgent != null) {
        _cpuGame!.cpuAgent!.setDifficulty(widget.cpuDifficulty);
      }
      _cpuGame!.onGameOverTriggered = () {
        unawaited(
          _presentRankedSafeBattleResult(
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
          forfeitRankedOnOffline: widget.isRankedMode || _isOnlineMode,
        );
      }
    };
    _cpuGame?.onRemoteBoardCorrectionApplied = (reason) {
      if (_isOnlineMode && _onlineGameStarted) {
        _multiplayerManager.reportRealtimeMetric(
          'opponent_board_correction',
          payload: {
            'reason': reason,
            'mode': widget.isRankedMode ? 'ranked' : 'friend',
          },
        );
      }
    };
    _playerGame.onActivePieceChanged = (action, x, y, rotation, colors,
        dropSeed, pieceId, eventSeq, lockedCells) {
      if (_isOnlineMode && _onlineGameStarted) {
        _sendServerAction(
          () => _multiplayerManager.sendActivePiece(
            x,
            y,
            rotation,
            colors,
            action,
            dropSeed,
            pieceId,
            eventSeq,
            _playerGame.nextPieceColors.value
                .map((color) => color.index)
                .toList(),
            _playerGame.isMovingLeft,
            _playerGame.isMovingRight,
            _playerGame.activePieceContactSlideDirection,
            x - _playerGame.boardOriginX,
            y - _playerGame.boardOriginY,
            _playerGame.ballSkinId,
            lockedCells,
          ),
          forfeitRankedOnOffline: widget.isRankedMode || _isOnlineMode,
        );
      }
    };
    _playerGame.onOjamaSpawned = (ojamaData, dropSeed) {
      if (_isOnlineMode && _onlineGameStarted) {
        _sendServerAction(
          () => _multiplayerManager.sendOjamaSpawn(ojamaData, dropSeed),
          forfeitRankedOnOffline: widget.isRankedMode || _isOnlineMode,
        );
      }
    };
    _playerGame.onGameOverTriggered = () {
      if (widget.isDailyMode) {
        unawaited(_finishDailyChallenge());
        return;
      }
      if (widget.isCpuMode) {
        unawaited(
          _presentRankedSafeBattleResult(
            playerWon: false,
            opponentCrossedDeathLine: false,
          ),
        );
        return;
      }
      if (_isOnlineMode) {
        unawaited(
          () {
            _markRankedResultKnownIfNeeded(isWin: false);
            _sendServerAction(
              () => _multiplayerManager.declareGameOver(
                finalBoard: _playerGame.exportBoardState(),
              ),
              forfeitRankedOnOffline: widget.isRankedMode || _isOnlineMode,
            );
            return _presentBattleResult(
              playerWon: false,
              opponentCrossedDeathLine: false,
            );
          }(),
        );
      } else {
        unawaited(
          _presentRankedSafeBattleResult(
            playerWon: false,
            opponentCrossedDeathLine: false,
          ),
        );
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
        _sendOjamaWithDelay(
          _cpuGame!,
          waza,
          color,
          ballSkinId: _playerDataManager.equippedBallSkinId,
        );
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
      _cpuGame!.onWazaFired = (waza, color) => _sendOjamaWithDelay(
            _playerGame,
            waza,
            color,
            ballSkinId: _cpuGame!.ballSkinId,
            effectSkinId: 'effect_ojama_default',
          );
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
    BallColor? color, {
    String? ballSkinId,
    String? effectSkinId,
  }) {
    final task = _createOjamaTaskForAttack(
      waza,
      color,
      ballSkinId: ballSkinId,
      effectSkinId: effectSkinId,
    );
    if (task == null) {
      return;
    }
    late Timer timer;
    timer = Timer(const Duration(milliseconds: 2500), () {
      _pendingAttackTimers.remove(timer);

      if (targetGame.gameStateWrapper.value == GameState.playing) {
        targetGame.incomingOjama.add(task);
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
    unawaited(FriendManager.instance.markPresence(online: true));
    _clearAllPendingAttacks();
    _dailyChallengeTimer?.cancel();
    _rankedAutoStartTimer?.cancel();
    _pendingEmptyOpponentBoardTimer?.cancel();
    _myStampTimer?.cancel();
    _opponentStampTimer?.cancel();
    _stampCooldownTimer?.cancel();
    _tutorialTimer?.cancel();
    _realtimeConnectionSubscription?.cancel();
    _friendInviteStatusSubscription?.cancel();
    _rankedOfflineForfeitTimer?.cancel();
    _opponentDisconnectForfeitTimer?.cancel();
    _resultTriplePromptController.dispose();
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
      _isStampGridVisible = false;
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

  void _toggleStampGrid() {
    setState(() {
      _isStampGridVisible = !_isStampGridVisible;
    });
  }

  void _dismissStampGrid() {
    if (!_isStampGridVisible || !mounted) {
      return;
    }
    setState(() {
      _isStampGridVisible = false;
    });
  }

  List<GameItem?> _equippedStampSlots() {
    final ownedStampsById = {
      for (final item in PlayerDataManager.instance.ownedItems
          .where((item) => item.isStamp))
        item.id: item,
    };
    return PlayerDataManager.instance.equippedStampIds
        .take(PlayerDataManager.maxEquippedStampCount)
        .map((id) => id == PlayerDataManager.emptyStampSlotId
            ? null
            : ownedStampsById[id] ?? GameItemCatalog.byId(id))
        .toList();
  }

  Widget _buildStampGridOverlay() {
    final equippedStamps = _equippedStampSlots();
    final hasAnyStamp = equippedStamps.any((stamp) => stamp != null);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(constraints.maxWidth - 24, 369.0);
        final gap = width < 338 ? 8.0 : 10.0;
        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F13).withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _gameCyan.withValues(alpha: 0.48)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: hasAnyStamp
                ? GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: PlayerDataManager.maxEquippedStampCount,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: gap,
                    ),
                    itemBuilder: (context, index) {
                      final stamp = index < equippedStamps.length
                          ? equippedStamps[index]
                          : null;
                      return StampSquareTile(
                        item: stamp,
                        level: stamp?.level,
                        compact: true,
                        onTap: stamp == null ? null : () => _sendStamp(stamp),
                      );
                    },
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '装備スタンプがありません',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
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
        bottomNavigationBar: const ScreenBottomBannerAd(
          reserveSpaceWhenHidden: true,
        ),
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
                  const SizedBox(height: 48),
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
              if (_isStampGridVisible)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (_) => _dismissStampGrid(),
                    child: const SizedBox.expand(),
                  ),
                ),
              if (_isStampGridVisible)
                Positioned(
                  top: _showsOpponentBoard ? 18 : 82,
                  left: 0,
                  right: 0,
                  child: _buildStampGridOverlay(),
                ),
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

  Widget _buildResultRewardSummaryRow({
    bool highlightTripleReward = false,
    bool includeRankedRating = false,
  }) {
    final expSummary = _buildResultExpSummary();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (includeRankedRating) ...[
          _buildRankedRatingAnimationSummary(),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: _buildResultCoinSummary(
                compact: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: expSummary),
          ],
        ),
        if (!AppSettings.instance.adRemovalBenefitsEnabled) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _buildResultCoinTripleButton(
              highlight: highlightTripleReward,
            ),
          ),
        ],
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

  Widget _buildResultCoinSummary({
    bool compact = false,
  }) {
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

    return SizedBox(
      height: compact ? 58 : null,
      width: double.infinity,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 14,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: HexagonCoinIcon(size: compact ? 18 : 24),
            ),
            Center(
              child: TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: totalCoins),
                duration: const Duration(milliseconds: 620),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Text(
                    '$value',
                    maxLines: 1,
                    style: TextStyle(
                      color: const Color(0xFFEAF6FF),
                      fontSize: compact ? 18 : 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCoinTripleButton({
    required bool highlight,
    bool compact = false,
  }) {
    if (!AppSettings.instance.canRequestRewardedAds) {
      return const SizedBox.shrink();
    }
    final waiting = _resultCoinTripleInProgress;
    final claimed = _resultCoinTripleClaimed;
    final shouldAnimate = highlight && !waiting && !claimed;
    final button = GamePressable(
      enabled: !waiting && !claimed && _resultCoinBaseEarned != null,
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        unawaited(_claimResultTripleCoinBonus());
      },
      child: Container(
        width: compact ? 68 : 92,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 6 : 8,
        ),
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
              Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.amberAccent,
                size: compact ? 18 : 20,
              ),
              SizedBox(width: compact ? 3 : 5),
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
                fontSize: compact ? 10.5 : 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
    if (!shouldAnimate) {
      return button;
    }
    return AnimatedBuilder(
      animation: _resultTriplePromptController,
      child: button,
      builder: (context, child) {
        final t = _resultTriplePromptController.value;
        final lift = sin(t * pi) * -3.0;
        final scale = 1.0 + sin(t * pi) * 0.06;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(0, lift),
              child: Transform.scale(scale: scale, child: child),
            ),
            Positioned(
              top: -8 + lift,
              right: -7,
              child: Opacity(
                opacity: 0.45 + sin(t * pi) * 0.45,
                child: const Icon(
                  Icons.keyboard_double_arrow_down_rounded,
                  color: Color(0xFFFFF59D),
                  size: 18,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultExpSummary() {
    final totalExp = _totalResultExpEarned;
    return SizedBox(
      height: 58,
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
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
              child: Text(
                'EXP',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Center(
              child: totalExp == null
                  ? const SizedBox.shrink()
                  : TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: totalExp),
                      duration: const Duration(milliseconds: 620),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Text(
                          '$value',
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultScoreSummary() {
    return _buildResultInfoRow(
      label: 'スコア',
      value: '$_currentPlayerScore点',
      color: _endlessGreen,
      valueColor: Colors.white,
    );
  }

  Widget _buildResultWazaSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildResultWazaCountItem(
              assetPath: 'assets/images/ResultWaza/result_hexagon.png',
              count: _hexagonCount,
            ),
          ),
          Expanded(
            child: _buildResultWazaCountItem(
              assetPath: 'assets/images/ResultWaza/result_pyramid.png',
              count: _pyramidCount,
            ),
          ),
          Expanded(
            child: _buildResultWazaCountItem(
              assetPath: 'assets/images/ResultWaza/result_straight.png',
              count: _straightCount,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultWazaCountItem({
    required String assetPath,
    required int count,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          assetPath,
          width: 32,
          height: 32,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.hexagon, color: _gameCyan, size: 24);
          },
        ),
        const SizedBox(width: 5),
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
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
          showRatingDelta: !widget.isRankedMode,
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

  Widget _buildRankedRatingAnimationSummary() {
    final change = _rankedRatingChange;
    final deltaColor =
        (change?.delta ?? 0) >= 0 ? _battlePlayerColor : _battleOpponentColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _rankedPurple.withValues(alpha: 0.62)),
        boxShadow: [
          BoxShadow(
            color: _rankedPurple.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '現在レート',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const HexagonTrophyIcon(size: 24),
                    const SizedBox(width: 8),
                    if (change == null)
                      const SizedBox(height: 26, width: 58)
                    else
                      TweenAnimationBuilder<int>(
                        tween: IntTween(
                          begin: change.oldRating,
                          end: change.newRating,
                        ),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Text(
                            '$value',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                              height: 1.0,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (change == null)
            const SizedBox(width: 58, height: 36)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: deltaColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: deltaColor.withValues(alpha: 0.52)),
              ),
              child: TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: change.delta),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  final deltaText = value > 0 ? '+$value' : '$value';
                  return Text(
                    deltaText,
                    style: TextStyle(
                      color: deltaColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
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
              _buildPlayerIconAvatar(
                iconId: iconId,
                frameId: iconFrameId,
                color: iconFrameColor,
                size: 42,
                iconSize: 22,
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
    final change = _rankedRatingChange;
    if (change != null) {
      return change.delta >= 0 ? _battlePlayerColor : _battleOpponentColor;
    }
    return Colors.amberAccent;
  }

  String _opponentResultName() {
    if (widget.isTutorialMode) {
      return _opponentDisplayName;
    }
    if (widget.isCpuMode) {
      return _opponentDisplayName;
    }
    return _opponentSharePlayer()?.name.trim().isNotEmpty == true
        ? _opponentSharePlayer()!.name.trim()
        : 'Opponent';
  }

  String _opponentResultIconId() {
    if (widget.isTutorialMode) {
      return 'icon_bolt';
    }
    if (widget.isCpuMode) {
      return widget.isRankedMode ? widget.rankedBotIconId : 'icon_bolt';
    }
    return _opponentSharePlayer()?.playerIconId ?? 'default';
  }

  String _opponentResultIconFrameId() {
    if (widget.isTutorialMode) {
      return 'default';
    }
    if (widget.isCpuMode) {
      return widget.isRankedMode ? widget.rankedBotFrameId : 'default';
    }
    return _opponentSharePlayer()?.playerIconFrameId ?? 'default';
  }

  String _opponentBallSkinId() {
    if (widget.isTutorialMode || widget.isCpuMode) {
      return 'default';
    }
    return _room?.players[_multiplayerManager.opponentRoleId]?.ballSkinId ??
        _multiplayerManager.currentRoom
            ?.players[_multiplayerManager.opponentRoleId]?.ballSkinId ??
        'default';
  }

  String _opponentFormationEffectId() {
    if (widget.isTutorialMode || widget.isCpuMode) {
      return 'effect_formation_default';
    }
    return _room
            ?.players[_multiplayerManager.opponentRoleId]?.formationEffectId ??
        _multiplayerManager.currentRoom
            ?.players[_multiplayerManager.opponentRoleId]?.formationEffectId ??
        'effect_formation_default';
  }

  Map<String, String> _opponentSfxSelectionIds() {
    if (widget.isTutorialMode || widget.isCpuMode) {
      return const {};
    }
    return _room
            ?.players[_multiplayerManager.opponentRoleId]?.sfxSelectionIds ??
        _multiplayerManager.currentRoom
            ?.players[_multiplayerManager.opponentRoleId]?.sfxSelectionIds ??
        const {};
  }

  List<String> _opponentResultBadgeIds() {
    if (widget.isTutorialMode) {
      return const [];
    }
    if (widget.isCpuMode) {
      return const [];
    }
    return _opponentSharePlayer()?.badgeIds ?? const [];
  }

  MultiplayerPlayer? _opponentSharePlayer() {
    final room = _room ?? _multiplayerManager.currentRoom;
    if (room == null) {
      return null;
    }
    final rolePlayer = room.players[_multiplayerManager.opponentRoleId];
    if (rolePlayer != null && !_isLocalSharePlayer(rolePlayer)) {
      return rolePlayer;
    }
    for (final entry in room.players.entries) {
      final player = entry.value;
      if (!_isLocalSharePlayer(player)) {
        return player;
      }
    }
    return rolePlayer;
  }

  bool _isLocalSharePlayer(MultiplayerPlayer player) {
    final myUid = _multiplayerManager.myUid ?? '';
    if (myUid.isNotEmpty && player.uid == myUid) {
      return true;
    }
    final myPublicId = _playerDataManager.playerId;
    if (myPublicId.isNotEmpty && player.publicId == myPublicId) {
      return true;
    }
    return false;
  }

  Widget _buildResultInfoRow({
    required String label,
    required String value,
    required Color color,
    Color? valueColor,
    String? trailing,
    Widget? leadingValue,
    bool centerValue = false,
    bool compactHeight = false,
  }) {
    return SizedBox(
      height: compactHeight ? 58 : null,
      width: double.infinity,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compactHeight ? 8 : 10,
        ),
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
    final levelColor = widget.isDailyMode
        ? _dailyBlue
        : useEndlessLayout
            ? _endlessGreen
            : Colors.amberAccent;
    final scorePanelBorderColor = widget.isDailyMode ? _dailyBlue : _gameCyan;
    final scorePanel = Container(
      margin: EdgeInsets.fromLTRB(
          useEndlessLayout ? 64 : 16, useEndlessLayout ? 18 : 10, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF101827).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scorePanelBorderColor.withValues(alpha: 0.42),
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
                    Text(
                      widget.isDailyMode ? '残り' : 'レベル',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.isDailyMode
                          ? '$_dailyRemainingSeconds'
                          : '${state.level}',
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
                          useEndlessLayout
                              ? '${state.score}点'
                              : '${state.score}',
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
                                    _toggleStampGrid();
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
                              child: Opacity(
                                opacity: _isStampCoolingDown ? 0.62 : 1,
                                child: Image.asset(
                                  'assets/images/BattleStamps/battle_message_stamp.png',
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      Icons.chat,
                                      color: _gameCyan.withValues(
                                        alpha: _isStampCoolingDown ? 0.72 : 1,
                                      ),
                                    );
                                  },
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
    final badges = badgeIds.map(_badgeIconForId).whereType<Widget>().take(3);
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
    final seasonBadge = SeasonRankBadge.fromId(id);
    if (seasonBadge != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SeasonRankBadgeIcon(
          rank: seasonBadge.rank,
          kind: seasonBadge.kind,
          size: 24,
        ),
      );
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
              ballSkinId: game.ballSkinId,
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
                        ? _readyGoThemeColor
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
          final isOfflineForfeitLoss = isBattleResult &&
              !cpuPlayerWon &&
              _battleResultWasOfflineForfeitLoss;
          final title = isBattleResult
              ? (isOfflineForfeitLoss
                  ? '不戦敗'
                  : cpuPlayerWon
                      ? '勝ち'
                      : '負け')
              : widget.isDailyMode
                  ? '${_formatShareNumber(_currentPlayerScore)}点'
                  : 'ゲームオーバー';
          final titleColor = isBattleResult
              ? (cpuPlayerWon ? _battlePlayerColor : _battleOpponentColor)
              : widget.isDailyMode
                  ? Colors.white
                  : _endlessGreen;

          return _buildUnifiedResultSheet(
            title: title,
            titleColor: titleColor,
            borderColor: widget.isDailyMode ? _dailyBlue : titleColor,
            children: widget.isTutorialMode
                ? _buildTutorialResultChildren()
                : [
                    _buildBattleResultProfiles(),
                    if (!isBattleResult && !widget.isDailyMode) ...[
                      const SizedBox(height: 12),
                      _buildResultScoreSummary(),
                    ],
                    const SizedBox(height: 10),
                    _buildResultWazaSummary(),
                    const SizedBox(height: 18),
                    _buildResultRewardSummaryRow(
                      highlightTripleReward: isBattleResult && cpuPlayerWon,
                      includeRankedRating: widget.isRankedMode,
                    ),
                    if (_newlyUnlockedBadges.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildBadgeUnlockResultCard(),
                    ],
                    const SizedBox(height: 12),
                    if (!isBattleResult && !widget.isDailyMode) ...[
                      _buildCyberResultButton(
                        label: 'リスタート',
                        baseColor: _endlessGreen,
                        isWaiting: false,
                        onPressed: () async {
                          _clearAllPendingAttacks();
                          await _showPostGameInterstitialIfNeeded();
                          if (!mounted) {
                            return;
                          }
                          unawaited(
                            _startLocalBattleWithReadyGo(
                              DateTime.now().millisecondsSinceEpoch,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildResultShareHomeButtonRow(
                      onHomePressed: () {
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
        : !win && (_onlineResultWasOfflineForfeit || _onlineResultWasForfeit)
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
          const SizedBox(height: 10),
          _buildResultWazaSummary(),
          const SizedBox(height: 18),
          _buildResultRewardSummaryRow(
            highlightTripleReward: win,
            includeRankedRating: widget.isRankedMode,
          ),
          if (_newlyUnlockedBadges.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildBadgeUnlockResultCard(),
          ],
          const SizedBox(height: 12),
          if (_canShowRematchButton) ...[
            if (_opponentRequestedRematch) ...[
              _buildRematchRequestNotice(),
              const SizedBox(height: 10),
            ],
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
          _buildResultShareHomeButtonRow(
            homeLabel: _isFriendMode ? 'ロビーへ戻る' : 'ホームへ戻る',
            onHomePressed: () {
              if (_isFriendMode) {
                unawaited(_returnFriendLobbyAfterResult());
              } else {
                _leaveOnlineBattle();
              }
            },
          ),
        ],
      ),
    );
  }

  bool get _canShowRematchButton {
    if (_isFriendMode ||
        widget.isRankedMode ||
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

  Widget _buildRematchRequestNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.blueAccent.withValues(alpha: 0.58),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.refresh_rounded,
            color: Colors.lightBlueAccent,
            size: 18,
          ),
          SizedBox(width: 8),
          Text(
            '相手が再戦を希望しています！',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
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
    Color? borderColor,
    required List<Widget> children,
  }) {
    final effectiveBorderColor = borderColor ?? titleColor;
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
                      color: effectiveBorderColor.withValues(alpha: 0.7),
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

  Widget _buildResultShareHomeButtonRow({
    required VoidCallback onHomePressed,
    String homeLabel = 'ホームへ戻る',
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildCyberResultButton(
            label: _resultShareInProgress ? '共有準備中...' : '結果をシェア',
            baseColor: _gameCyan,
            icon: Icons.ios_share_rounded,
            isWaiting: _resultShareInProgress,
            compact: true,
            onPressed: _resultShareInProgress
                ? null
                : () => unawaited(_shareCurrentResult()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildCyberResultButton(
            label: homeLabel,
            baseColor: _mutedButtonGrey,
            isWaiting: false,
            compact: true,
            onPressed: onHomePressed,
          ),
        ),
      ],
    );
  }

  Widget _buildCyberResultButton({
    required String label,
    required VoidCallback? onPressed,
    required Color baseColor,
    required bool isWaiting,
    IconData? icon,
    bool compact = false,
  }) {
    if (isWaiting) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: compact ? 13 : 18),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Center(
          child: _buildResultButtonContent(
            label: label,
            icon: icon,
            color: Colors.white54,
            compact: compact,
          ),
        ),
      );
    }

    return GamePressable(
      enabled: onPressed != null,
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed == null
          ? null
          : () {
              _playUiTap();
              onPressed();
            },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: compact ? 13 : 18),
        decoration: BoxDecoration(
            color: baseColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: baseColor.withValues(alpha: 0.8), width: 2)),
        child: Center(
          child: _buildResultButtonContent(
            label: label,
            icon: icon,
            color: Colors.white,
            compact: compact,
          ),
        ),
      ),
    );
  }

  Widget _buildResultButtonContent({
    required String label,
    required IconData? icon,
    required Color color,
    bool compact = false,
  }) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: compact ? 13.5 : 20,
        fontWeight: FontWeight.w900,
        letterSpacing: compact ? 0.2 : 1.2,
      ),
    );
    if (icon == null) {
      return text;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: compact ? 18 : 24),
        SizedBox(width: compact ? 5 : 9),
        Flexible(child: text),
      ],
    );
  }

  Future<void> _shareCurrentResult() async {
    if (_resultShareInProgress) {
      return;
    }
    setState(() {
      _resultShareInProgress = true;
    });
    try {
      final data = await _buildResultShareData();
      final pngBytes = await _renderResultShareImage(data);
      if (!mounted) {
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      try {
        await _shareImageChannel.invokeMethod<bool>('shareResultImage', {
          'title': 'ヘキサゴン リザルト',
          'text': '',
          'imageBytes': pngBytes,
        });
      } catch (error, stackTrace) {
        debugPrint('Failed to share result image natively: $error');
        debugPrintStack(stackTrace: stackTrace);
        await _shareResultImageViaFile(pngBytes, box);
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to share result image: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      try {
        final data = await _buildResultShareData();
        await _shareResultText(data.shareText, box);
      } catch (fallbackError, fallbackStackTrace) {
        debugPrint('Failed to share result text fallback: $fallbackError');
        debugPrintStack(stackTrace: fallbackStackTrace);
        if (!mounted) {
          return;
        }
        await _showShareErrorDialog();
      }
    } finally {
      if (mounted) {
        setState(() {
          _resultShareInProgress = false;
        });
      }
    }
  }

  Future<void> _shareResultText(String text, RenderBox? box) {
    return SharePlus.instance.share(
      ShareParams(
        title: 'ヘキサゴン リザルト',
        text: text,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _shareResultImageViaFile(
    Uint8List pngBytes,
    RenderBox? box,
  ) async {
    final directory = Directory.systemTemp.createTempSync('hexagon_share_');
    final file = File('${directory.path}/hexagon_result.png');
    await file.writeAsBytes(pngBytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        title: 'ヘキサゴン リザルト',
        files: [
          XFile(
            file.path,
            mimeType: 'image/png',
            name: 'hexagon_result.png',
          ),
        ],
        fileNameOverrides: const ['hexagon_result.png'],
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<_ResultShareData> _buildResultShareData() async {
    final ranked = widget.isRankedMode && !widget.isArenaMode;
    final daily = widget.isDailyMode;
    final endless =
        !daily && !widget.isCpuMode && !_isOnlineMode && !widget.isTutorialMode;
    final playerWon = _sharePlayerWon;
    final seasonLabel =
        seasonIdForLabel(_room?.seasonId ?? _playerDataManager.rankedSeasonId);
    final modeLabel = daily
        ? 'デイリー'
        : endless
            ? 'エンドレス'
            : ranked
                ? 'ランク戦'
                : widget.isArenaMode
                    ? 'アリーナ'
                    : widget.isCpuMode
                        ? 'コンピュータ対戦'
                        : 'フレンド対戦';
    final accentColor = daily
        ? _dailyBlue
        : endless
            ? _endlessGreen
            : ranked
                ? _rankedPurple
                : widget.isCpuMode
                    ? _computerYellow
                    : _friendPink;
    final title = daily || endless
        ? ''
        : playerWon
            ? '勝ち'
            : '負け';
    final ratingChange = _rankedRatingChange;
    final ratingDeltaLabel = ratingChange == null
        ? ''
        : ratingChange.delta >= 0
            ? '+${ratingChange.delta}'
            : '${ratingChange.delta}';
    final rankedSummary = ranked ? await _fetchShareRankingSummary() : null;
    final rankLabel = _shareRankLabel(rankedSummary?.ratingRankLabel);
    final dailyWinRankLabel = _shareRankLabel(rankedSummary?.dailyWinRankLabel);
    final dailyWinsLabel = rankedSummary == null
        ? ''
        : _formatShareNumber(rankedSummary.dailyWins);
    final endlessBestScore = max(
      _currentPlayerScore,
      _playerDataManager.highestEndlessScore,
    );
    final endlessRankLabel = endless ? await _fetchShareEndlessRankLabel() : '';
    final dailyDateKey = widget.dailyDateKey ??
        await DailyChallengeManager.instance.currentDateKey();
    final dailyRankLabel =
        daily ? await _fetchShareDailyRankLabel(dailyDateKey) : '';
    final appIcon = await _loadShareImage(_shareAppIconAsset);
    final seasonBadgeIcon = await _loadShareImage(_shareSeasonBadgeAsset);
    final storeQrImage = await _loadShareImage(_shareStoreQrAsset);
    final coinIcon = await _loadShareImage(_shareCoinAsset);
    final trophyIcon = await _loadShareImage(_shareTrophyAsset);
    final playerIconId = _playerDataManager.equippedPlayerIconId;
    final opponentIconId = _opponentResultIconId();
    final playerIconImage = await _loadPlayerIconShareImage(playerIconId);
    final opponentIconImage = await _loadPlayerIconShareImage(opponentIconId);
    final inviteCode = await _shareInviteCode();
    final playerPreRating = ratingChange?.oldRating ??
        (_room?.players[_multiplayerManager.myRoleId]?.rating ??
            _playerDataManager.currentRating);

    return _ResultShareData(
      isRanked: ranked,
      isEndless: endless,
      isDaily: daily,
      seasonLabel: ranked ? seasonLabel : '',
      modeLabel: modeLabel,
      title: title,
      titleColor: playerWon ? _battlePlayerColor : _battleOpponentColor,
      accentColor: accentColor,
      scoreLabel:
          (daily || endless) ? _formatShareNumber(_currentPlayerScore) : '',
      endlessLevelLabel: endless ? 'Lv.$_currentPlayerLevel' : '',
      endlessBestScoreLabel: daily
          ? _shareDateLabel(dailyDateKey)
          : endless
              ? _formatShareNumber(endlessBestScore)
              : '',
      endlessRankLabel: daily ? dailyRankLabel : endlessRankLabel,
      ratingDeltaLabel: ratingDeltaLabel,
      newRatingLabel: ratingChange == null
          ? ''
          : _formatShareNumber(ratingChange.newRating),
      rankLabel: rankLabel,
      dailyWinsLabel: dailyWinsLabel,
      dailyWinRankLabel: dailyWinRankLabel,
      player: _ShareParticipant(
        name: _playerDataManager.displayPlayerName,
        iconId: playerIconId,
        frameId: _playerDataManager.equippedIconFrameId,
        badgeIds: _playerDataManager.equippedBadgeIds,
        ratingLabel: ranked ? _formatShareNumber(playerPreRating) : '',
        sideColor: _battlePlayerColor,
        iconImage: playerIconImage,
      ),
      opponent: _ShareParticipant(
        name: _opponentResultName(),
        iconId: opponentIconId,
        frameId: _opponentResultIconFrameId(),
        badgeIds: _opponentResultBadgeIds(),
        ratingLabel: ranked ? _opponentShareRatingLabel() : '',
        sideColor: _battleOpponentColor,
        iconImage: opponentIconImage,
      ),
      inviteCode: inviteCode,
      generatedAtLabel: _shareGeneratedAtLabel(DateTime.now()),
      appIcon: appIcon,
      seasonBadgeIcon: seasonBadgeIcon,
      storeQrImage: storeQrImage,
      coinIcon: coinIcon,
      trophyIcon: trophyIcon,
    );
  }

  String seasonIdForLabel(String seasonId) {
    return seasonId.isEmpty ? '' : RankedSeasonManager.seasonName(seasonId);
  }

  String _shareGeneratedAtLabel(DateTime dateTime) {
    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}/$month/$day $hour:$minute';
  }

  Future<String> _shareInviteCode() async {
    try {
      return await InviteManager.instance
          .ensureInviteCode(
            displayName: _playerDataManager.displayPlayerName,
            publicId: _playerDataManager.playerId,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return '';
    }
  }

  Future<ui.Image?> _loadShareImage(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image?> _loadPlayerIconShareImage(String iconId) async {
    final assetPath = playerIconAssetPath(iconId);
    if (assetPath == null) {
      return null;
    }
    return _loadShareImage(assetPath);
  }

  bool get _sharePlayerWon {
    if (_onlineResultMessage != null) {
      return _onlineResultMessage == 'YOU WIN!!';
    }
    if (widget.isCpuMode || widget.isTutorialMode) {
      return _cpuBattlePlayerWon ?? false;
    }
    return false;
  }

  Future<RankingSummary?> _fetchShareRankingSummary() async {
    try {
      return await _rankingManager
          .fetchMySummary(forceRefresh: true)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  String _shareRankLabel(String? rawLabel) {
    final label = rawLabel?.trim() ?? '';
    return label.isEmpty || label == '圏外' ? '' : label;
  }

  Future<String> _fetchShareEndlessRankLabel() async {
    try {
      final entries = await _rankingManager
          .fetchTopEndlessScoreRankings(forceRefresh: true)
          .timeout(const Duration(seconds: 2));
      final publicId = _playerDataManager.playerId;
      final uid = _multiplayerManager.myUid ?? '';
      final index = entries.indexWhere((entry) =>
          (uid.isNotEmpty && entry.uid == uid) ||
          (publicId.isNotEmpty && entry.publicId == publicId));
      if (index == -1) {
        return '';
      }
      final myScore = entries[index].highestEndlessScore;
      final rank =
          entries.where((entry) => entry.highestEndlessScore > myScore).length +
              1;
      return '$rank位';
    } catch (_) {
      return '';
    }
  }

  Future<String> _fetchShareDailyRankLabel(String dateKey) async {
    try {
      await DailyChallengeManager.instance
          .submitScore(dateKey: dateKey, score: _currentPlayerScore)
          .timeout(const Duration(seconds: 2));
      final entries = await DailyChallengeManager.instance
          .fetchTopRankings(dateKey: dateKey)
          .timeout(const Duration(seconds: 2));
      final publicId = _playerDataManager.playerId;
      final uid = _multiplayerManager.myUid ?? '';
      final index = entries.indexWhere((entry) =>
          (uid.isNotEmpty && entry.uid == uid) ||
          (publicId.isNotEmpty && entry.publicId == publicId));
      if (index == -1) {
        return '';
      }
      final myScore = entries[index].score;
      final rank = entries.where((entry) => entry.score > myScore).length + 1;
      return '$rank位';
    } catch (_) {
      return '';
    }
  }

  String _shareDateLabel(String dateKey) {
    final normalized = dateKey.replaceAll('-', '/');
    final parts = normalized.split('/');
    if (parts.length != 3) {
      return normalized;
    }
    return '${parts[0]}/${parts[1].padLeft(2, '0')}/${parts[2].padLeft(2, '0')}';
  }

  String _opponentShareRatingLabel() {
    if (widget.isCpuMode) {
      final rating = widget.rankedBotRating;
      return rating == null ? '' : _formatShareNumber(rating);
    }
    final player = _opponentSharePlayer();
    final rating = player?.rating;
    return rating == null ? '' : _formatShareNumber(rating);
  }

  Future<Uint8List> _renderResultShareImage(_ResultShareData data) async {
    const width = 1080.0;
    const height = 1350.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(width, height);
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(width, height),
        [
          const Color(0xFF080914),
          Color.lerp(const Color(0xFF101426), data.accentColor, 0.22)!,
          const Color(0xFF07070B),
        ],
        [0.0, 0.52, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);
    _drawShareHexPattern(canvas, size, data.accentColor);

    _drawShareHeader(canvas, data, width);
    if (data.scoreLabel.isNotEmpty) {
      _drawShareEndlessLayout(canvas, data, width);
    } else {
      _drawShareBattleLayout(canvas, data, width);
    }
    _drawShareFooter(canvas, data, width);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('share image encoding failed');
    }
    return bytes.buffer.asUint8List();
  }

  void _drawShareHeader(Canvas canvas, _ResultShareData data, double width) {
    final iconRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(72, 48, 96, 96),
      const Radius.circular(24),
    );
    canvas.drawRRect(
      iconRect,
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    if (data.appIcon != null) {
      canvas.save();
      canvas.clipRRect(iconRect);
      _drawShareImageCover(
        canvas,
        data.appIcon!,
        iconRect.outerRect,
      );
      canvas.restore();
    } else {
      _drawShareIcon(
        canvas,
        Icons.hexagon,
        iconRect.outerRect.center,
        size: 52,
        color: data.accentColor,
      );
    }
    _drawShareText(
      canvas,
      'ヘキサゴン',
      const Offset(188, 64),
      fontSize: 56,
      color: Colors.white,
      weight: FontWeight.w900,
      letterSpacing: 2,
    );
    final modeRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(635, 66, 370, 68),
      const Radius.circular(30),
    );
    canvas.drawRRect(
      modeRect,
      Paint()..color = Colors.black.withValues(alpha: 0.34),
    );
    canvas.drawRRect(
      modeRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = data.accentColor.withValues(alpha: 0.7),
    );
    _drawShareFittedText(
      canvas,
      data.modeLabel,
      const Rect.fromLTWH(655, 78, 330, 44),
      fontSize: 31,
      minFontSize: 19,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
  }

  void _drawShareBattleLayout(
      Canvas canvas, _ResultShareData data, double width) {
    _drawShareResultBadge(
      canvas,
      rect: Rect.fromLTWH(118, data.isRanked ? 206 : 218, 844, 104),
      text: data.title,
      color: data.titleColor,
      ratingDelta: data.isRanked ? data.ratingDeltaLabel : '',
    );
    if (data.isRanked) {
      _drawShareRatingRankPill(
        canvas,
        rect: const Rect.fromLTWH(108, 348, 410, 92),
        season: data.seasonLabel,
        rating: data.newRatingLabel.isEmpty ? '-' : data.newRatingLabel,
        rank: data.rankLabel.isEmpty ? '-' : data.rankLabel,
        color: Colors.amberAccent,
        trophyIcon: data.trophyIcon,
      );
      _drawShareRankPill(
        canvas,
        rect: const Rect.fromLTWH(562, 348, 410, 92),
        wins: data.dailyWinsLabel.isEmpty ? '0' : data.dailyWinsLabel,
        rank: data.dailyWinRankLabel.isEmpty ? '-' : data.dailyWinRankLabel,
      );
    }

    _drawShareProfileCard(
      canvas,
      rect: Rect.fromLTWH(62, data.isRanked ? 520 : 456, 430, 330),
      label: '自分',
      participant: data.player,
      seasonBadgeIcon: data.seasonBadgeIcon,
      trophyIcon: data.trophyIcon,
    );
    _drawShareProfileCard(
      canvas,
      rect: Rect.fromLTWH(588, data.isRanked ? 520 : 456, 430, 330),
      label: '相手',
      participant: data.opponent,
      seasonBadgeIcon: data.seasonBadgeIcon,
      trophyIcon: data.trophyIcon,
    );
  }

  void _drawShareEndlessLayout(
    Canvas canvas,
    _ResultShareData data,
    double width,
  ) {
    final scoreRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(84, 292, 912, 224),
      const Radius.circular(34),
    );
    canvas.drawRRect(
      scoreRect,
      Paint()..color = const Color(0xFF101522).withValues(alpha: 0.9),
    );
    canvas.drawRRect(
      scoreRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = data.accentColor.withValues(alpha: 0.9),
    );
    _drawShareFittedText(
      canvas,
      '${data.scoreLabel}点',
      const Rect.fromLTWH(120, 346, 840, 116),
      fontSize: 78,
      minFontSize: 44,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
    _drawShareEndlessBestPanel(canvas, data);
    _drawShareProfileCard(
      canvas,
      rect: const Rect.fromLTWH(250, 670, 580, 250),
      label: 'プレイヤー',
      participant: data.player,
      compact: true,
      seasonBadgeIcon: data.seasonBadgeIcon,
      trophyIcon: data.trophyIcon,
    );
  }

  void _drawShareEndlessBestPanel(Canvas canvas, _ResultShareData data) {
    if (data.isDaily) {
      const rect = Rect.fromLTWH(260, 548, 560, 86);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));
      canvas.drawRRect(
        rrect,
        Paint()..color = Colors.black.withValues(alpha: 0.24),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = data.accentColor.withValues(alpha: 0.42),
      );
      _drawShareText(
        canvas,
        '日付',
        Offset(rect.left + 18, rect.top + 12),
        fontSize: 17,
        color: Colors.white54,
        weight: FontWeight.w900,
        maxLines: 1,
      );
      _drawShareFittedText(
        canvas,
        data.endlessBestScoreLabel.isEmpty ? '-' : data.endlessBestScoreLabel,
        Rect.fromLTWH(rect.left + 18, rect.top + 32, 330, 42),
        fontSize: 34,
        minFontSize: 18,
        color: Colors.white,
        weight: FontWeight.w900,
        align: TextAlign.center,
      );
      if (data.endlessRankLabel.isNotEmpty) {
        canvas.drawLine(
          Offset(rect.left + 365, rect.top + 20),
          Offset(rect.left + 365, rect.bottom - 20),
          Paint()
            ..strokeWidth = 1.4
            ..color = Colors.white.withValues(alpha: 0.16),
        );
        _drawShareFittedText(
          canvas,
          data.endlessRankLabel,
          Rect.fromLTWH(rect.left + 382, rect.top + 32, rect.width - 398, 42),
          fontSize: 32,
          minFontSize: 20,
          color: Colors.white,
          weight: FontWeight.w900,
          align: TextAlign.center,
        );
      }
      return;
    }

    const levelRect = Rect.fromLTWH(164, 548, 205, 86);
    final levelRrect =
        RRect.fromRectAndRadius(levelRect, const Radius.circular(18));
    canvas.drawRRect(
      levelRrect,
      Paint()..color = Colors.black.withValues(alpha: 0.24),
    );
    canvas.drawRRect(
      levelRrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = data.accentColor.withValues(alpha: 0.42),
    );
    _drawShareFittedText(
      canvas,
      data.endlessLevelLabel,
      levelRect.deflate(12),
      fontSize: 34,
      minFontSize: 22,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
    const rect = Rect.fromLTWH(390, 548, 526, 86);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.black.withValues(alpha: 0.24),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = data.accentColor.withValues(alpha: 0.42),
    );
    final bestText = data.endlessBestScoreLabel.isEmpty
        ? '-'
        : '${data.endlessBestScoreLabel}点';
    _drawShareText(
      canvas,
      'ハイスコア',
      Offset(rect.left + 18, rect.top + 12),
      fontSize: 17,
      color: Colors.white54,
      weight: FontWeight.w900,
      maxLines: 1,
    );
    _drawShareFittedText(
      canvas,
      bestText,
      Rect.fromLTWH(rect.left + 18, rect.top + 32, 330, 42),
      fontSize: 34,
      minFontSize: 16,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
    if (data.endlessRankLabel.isNotEmpty) {
      canvas.drawLine(
        Offset(rect.left + 365, rect.top + 20),
        Offset(rect.left + 365, rect.bottom - 20),
        Paint()
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.16),
      );
      _drawShareFittedText(
        canvas,
        data.endlessRankLabel,
        Rect.fromLTWH(rect.left + 382, rect.top + 32, rect.width - 398, 42),
        fontSize: 32,
        minFontSize: 20,
        color: Colors.white,
        weight: FontWeight.w900,
        align: TextAlign.center,
      );
    }
  }

  void _drawShareFooter(Canvas canvas, _ResultShareData data, double width) {
    _drawShareInvitePanel(canvas, data);
    _drawShareQrPanel(canvas, data);
    _drawShareText(
      canvas,
      data.generatedAtLabel,
      const Offset(76, 1264),
      fontSize: 20,
      color: Colors.white38,
      weight: FontWeight.w800,
      maxLines: 1,
    );
  }

  void _drawShareProfileCard(
    Canvas canvas, {
    required Rect rect,
    required String label,
    required _ShareParticipant participant,
    bool compact = false,
    ui.Image? seasonBadgeIcon,
    ui.Image? trophyIcon,
  }) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawRRect(
      rrect,
      Paint()..color = const Color(0xFF101522).withValues(alpha: 0.88),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = participant.sideColor.withValues(alpha: 0.78),
    );
    _drawShareText(
      canvas,
      label,
      rect.topLeft + const Offset(24, 22),
      fontSize: 22,
      color: participant.sideColor,
      weight: FontWeight.w900,
      letterSpacing: 2,
    );
    final avatarSize = compact ? 116.0 : 112.0;
    final avatarCenter = Offset(
      rect.left + 92,
      rect.top + (compact ? 130 : 170),
    );
    _drawShareAvatar(
      canvas,
      center: avatarCenter,
      iconId: participant.iconId,
      frameId: participant.frameId,
      size: avatarSize,
      color: participant.sideColor,
      iconImage: participant.iconImage,
    );
    _drawShareProfileNameText(
      canvas,
      participant.name,
      Rect.fromLTWH(
        rect.left + (compact ? 182 : 166),
        rect.top + (compact ? 76 : 104),
        rect.width - (compact ? 210 : 190),
        48,
      ),
      fontSize: compact ? 29 : 32,
      minFontSize: 10,
      color: Colors.white,
      weight: FontWeight.w900,
    );
    _drawShareBadges(
      canvas,
      participant.badgeIds,
      Offset(
        rect.left + (compact ? 172 : 180),
        rect.top + (compact ? 150 : 184),
      ),
      participant.sideColor,
      seasonBadgeIcon: seasonBadgeIcon,
      alignLeft: true,
    );
    if (participant.ratingLabel.isNotEmpty) {
      _drawShareProfileRatingPill(
        canvas,
        Rect.fromLTWH(
          rect.left + (rect.width - (compact ? 220 : 230)) / 2,
          rect.top + (compact ? 186 : 248),
          compact ? 220 : 230,
          compact ? 50 : 56,
        ),
        participant.ratingLabel,
        trophyIcon,
        fontSize: compact ? 24 : 26,
      );
    }
  }

  void _drawShareAvatar(
    Canvas canvas, {
    required Offset center,
    required String iconId,
    required String frameId,
    required double size,
    required Color color,
    ui.Image? iconImage,
  }) {
    final frame = GameItemCatalog.byId(frameId);
    final radius = size / 2;
    if (frame?.colorName == 'rainbow') {
      canvas.drawCircle(
        center,
        radius - 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..shader = ui.Gradient.sweep(
            center,
            const [
              Color(0xFFFF4D6D),
              Color(0xFFFFD54A),
              Color(0xFF35F0FF),
              Color(0xFFB91DFF),
              Color(0xFFFF4D6D),
            ],
            const [0.0, 0.25, 0.5, 0.75, 1.0],
          ),
      );
    } else {
      final frameColor = frame == null ? color : _playerIconFrameColor(frameId);
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = frameColor.withValues(alpha: 0.95),
      );
      canvas.drawCircle(
        center,
        radius - 8,
        Paint()
          ..color = playerIconInnerBackgroundColor(
            iconId,
            const Color(0xFF101827),
            frameId: frameId,
          ),
      );
    }
    if (playerIconAssetPath(iconId) != null && iconImage != null) {
      _drawShareImageContain(
        canvas,
        iconImage,
        Rect.fromCircle(
          center: center,
          radius: (radius - 16) * playerIconImageScale(iconId),
        ),
      );
    } else {
      _drawShareIcon(
        canvas,
        _playerIconData(iconId),
        center,
        size: 58,
        color: Colors.white,
      );
    }
  }

  void _drawShareBadges(
    Canvas canvas,
    List<String> badgeIds,
    Offset center,
    Color color, {
    ui.Image? seasonBadgeIcon,
    bool alignLeft = false,
  }) {
    final ids = badgeIds.take(3).toList();
    if (ids.isEmpty) {
      return;
    }
    final totalWidth = ids.length * 58.0 + (ids.length - 1) * 12.0;
    var x = alignLeft ? center.dx + 29 : center.dx - totalWidth / 2 + 29;
    for (final id in ids) {
      final seasonBadge = SeasonRankBadge.fromId(id);
      if (seasonBadge != null) {
        _drawShareSeasonRankBadge(
          canvas,
          center: Offset(x, center.dy),
          rank: seasonBadge.rank,
          color: color,
          badgeImage: seasonBadgeIcon,
        );
      } else {
        canvas.drawCircle(
          Offset(x, center.dy),
          28,
          Paint()..color = Colors.black.withValues(alpha: 0.58),
        );
        canvas.drawCircle(
          Offset(x, center.dy),
          27,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.9),
        );
        final badge = BadgeCatalog.findById(id);
        _drawShareIcon(
          canvas,
          badge?.icon ?? Icons.star,
          Offset(x, center.dy),
          size: 25,
          color: badge?.frameColor ?? color,
        );
      }
      x += 70;
    }
  }

  void _drawShareRatingRankPill(
    Canvas canvas, {
    required Rect rect,
    required String season,
    required String rating,
    required String rank,
    required Color color,
    required ui.Image? trophyIcon,
  }) {
    _drawSharePillBase(canvas, rect);
    _drawShareFittedText(
      canvas,
      season.isEmpty ? '今シーズン' : season,
      Rect.fromLTWH(rect.left + 18, rect.top + 10, rect.width - 36, 24),
      fontSize: 20,
      minFontSize: 13,
      color: Colors.white60,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
    _drawShareIconValue(
      canvas,
      Offset(rect.left + 62, rect.top + 42),
      icon: trophyIcon,
      value: rating,
      color: color,
      fontSize: 36,
    );
    canvas.drawLine(
      Offset(rect.left + 250, rect.top + 42),
      Offset(rect.left + 250, rect.bottom - 16),
      Paint()
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.16),
    );
    _drawShareFittedText(
      canvas,
      rank,
      Rect.fromLTWH(rect.left + 264, rect.top + 42, rect.width - 282, 40),
      fontSize: 34,
      minFontSize: 18,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
  }

  void _drawShareRankPill(
    Canvas canvas, {
    required Rect rect,
    required String wins,
    required String rank,
  }) {
    _drawSharePillBase(canvas, rect);
    _drawShareFittedText(
      canvas,
      '今日の勝利数',
      Rect.fromLTWH(rect.left + 20, rect.top + 14, rect.width - 40, 28),
      fontSize: 20,
      minFontSize: 15,
      color: Colors.white54,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
    _drawShareFittedText(
      canvas,
      '$wins勝',
      Rect.fromLTWH(rect.left + 70, rect.top + 48, 145, 34),
      fontSize: 34,
      minFontSize: 17,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
    canvas.drawLine(
      Offset(rect.left + 250, rect.top + 42),
      Offset(rect.left + 250, rect.bottom - 16),
      Paint()
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.16),
    );
    _drawShareFittedText(
      canvas,
      rank,
      Rect.fromLTWH(rect.left + 264, rect.top + 42, rect.width - 282, 40),
      fontSize: 34,
      minFontSize: 18,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
  }

  void _drawSharePillBase(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );
  }

  void _drawShareProfileRatingPill(
    Canvas canvas,
    Rect rect,
    String value,
    ui.Image? trophyIcon, {
    required double fontSize,
  }) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.black.withValues(alpha: 0.24),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = Colors.amberAccent.withValues(alpha: 0.55),
    );
    final iconSize = fontSize + 7;
    final estimatedTextWidth = value.length * fontSize * 0.58;
    final startX = rect.center.dx - (iconSize + 8 + estimatedTextWidth) / 2;
    _drawShareIconValue(
      canvas,
      Offset(startX, rect.top + (rect.height - iconSize) / 2),
      icon: trophyIcon,
      value: value,
      color: Colors.amberAccent,
      fontSize: fontSize,
      iconSize: iconSize,
    );
  }

  void _drawShareIconValue(
    Canvas canvas,
    Offset offset, {
    required ui.Image? icon,
    required String value,
    required Color color,
    required double fontSize,
    double? iconSize,
  }) {
    final size = iconSize ?? fontSize + 4;
    if (icon != null) {
      _drawShareImageContain(
        canvas,
        icon,
        Rect.fromLTWH(offset.dx, offset.dy, size, size),
      );
    } else {
      _drawShareIcon(
        canvas,
        Icons.emoji_events,
        Offset(offset.dx + size / 2, offset.dy + size / 2),
        size: size,
        color: color,
      );
    }
    _drawShareText(
      canvas,
      value,
      Offset(offset.dx + size + 8, offset.dy + 2),
      fontSize: fontSize,
      color: color,
      weight: FontWeight.w900,
      maxLines: 1,
    );
  }

  void _drawShareResultBadge(
    Canvas canvas, {
    required Rect rect,
    required String text,
    required Color color,
    String ratingDelta = '',
  }) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(32));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            color.withValues(alpha: 0.92),
            Color.lerp(color, Colors.black, 0.4)!.withValues(alpha: 0.86),
          ],
        ),
    );
    _drawShareFittedText(
      canvas,
      text,
      rect.deflate(18),
      fontSize: 58,
      minFontSize: 36,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
      letterSpacing: 2,
    );
    if (ratingDelta.isEmpty) {
      return;
    }
    final deltaRect = Rect.fromLTWH(rect.right - 224, rect.top + 22, 184, 60);
    final deltaRrect =
        RRect.fromRectAndRadius(deltaRect, const Radius.circular(22));
    final deltaColor =
        ratingDelta.startsWith('-') ? _battleOpponentColor : _battlePlayerColor;
    canvas.drawRRect(
      deltaRrect,
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawRRect(
      deltaRrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.42),
    );
    _drawShareFittedText(
      canvas,
      ratingDelta.isEmpty ? '-' : ratingDelta,
      deltaRect.deflate(12),
      fontSize: 34,
      minFontSize: 22,
      color: deltaColor,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
  }

  void _drawShareInvitePanel(Canvas canvas, _ResultShareData data) {
    const rect = Rect.fromLTWH(76, 1010, 650, 220);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(30));
    canvas.drawRRect(
      rrect,
      Paint()..color = const Color(0xFF0E1422).withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = data.accentColor.withValues(alpha: 0.58),
    );
    _drawShareText(
      canvas,
      '友達招待コード',
      Offset(rect.left + 32, rect.top + 24),
      fontSize: 26,
      color: data.accentColor,
      weight: FontWeight.w900,
      letterSpacing: 1.4,
      maxLines: 1,
    );
    _drawShareText(
      canvas,
      'インストール時に招待コードを入力',
      Offset(rect.left + 32, rect.top + 68),
      fontSize: 22,
      color: Colors.white,
      weight: FontWeight.w900,
      maxLines: 1,
    );
    _drawShareText(
      canvas,
      '友達とあなたに',
      Offset(rect.left + 32, rect.top + 102),
      fontSize: 22,
      color: Colors.white,
      weight: FontWeight.w900,
      maxLines: 1,
    );
    _drawShareCoinReward(
      canvas,
      Offset(rect.left + 210, rect.top + 98),
      data.coinIcon,
    );
    _drawShareText(
      canvas,
      '※1日最大3人まで',
      Offset(rect.left + 420, rect.top + 106),
      fontSize: 17,
      color: Colors.white60,
      weight: FontWeight.w800,
      maxLines: 1,
    );
    final codeRect = Rect.fromLTWH(rect.left + 100, rect.top + 142, 450, 58);
    final codeRrect =
        RRect.fromRectAndRadius(codeRect, const Radius.circular(18));
    canvas.drawRRect(
      codeRrect,
      Paint()..color = data.accentColor.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      codeRrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = data.accentColor.withValues(alpha: 0.45),
    );
    _drawShareFittedText(
      canvas,
      data.inviteCode.isEmpty ? 'アプリ内で確認' : data.inviteCode,
      codeRect.deflate(12),
      fontSize: 39,
      minFontSize: 28,
      color: data.accentColor,
      weight: FontWeight.w900,
      align: TextAlign.center,
      letterSpacing: 2,
    );
  }

  void _drawShareQrPanel(Canvas canvas, _ResultShareData data) {
    const rect = Rect.fromLTWH(790, 1018, 186, 186);
    if (data.storeQrImage != null) {
      _drawShareImageContain(canvas, data.storeQrImage!, rect);
    }
    _drawShareText(
      canvas,
      'App Store で入手',
      Offset(rect.left, rect.bottom + 16),
      fontSize: 20,
      color: Colors.white70,
      weight: FontWeight.w900,
      align: TextAlign.center,
      width: rect.width,
      maxLines: 1,
    );
  }

  void _drawShareCoinReward(
    Canvas canvas,
    Offset offset,
    ui.Image? coinIcon,
  ) {
    const color = Color(0xFFEAF6FF);
    const iconSize = 34.0;
    if (coinIcon != null) {
      _drawShareImageContain(
        canvas,
        coinIcon,
        Rect.fromLTWH(offset.dx, offset.dy - 1, iconSize, iconSize),
      );
    } else {
      _drawShareIcon(
        canvas,
        Icons.monetization_on,
        Offset(offset.dx + iconSize / 2, offset.dy + iconSize / 2),
        size: iconSize,
        color: color,
      );
    }
    _drawShareText(
      canvas,
      '50000',
      Offset(offset.dx + iconSize + 8, offset.dy),
      fontSize: 29,
      color: color,
      weight: FontWeight.w900,
      maxLines: 1,
    );
  }

  void _drawShareSeasonRankBadge(
    Canvas canvas, {
    required Offset center,
    required int rank,
    required Color color,
    required ui.Image? badgeImage,
  }) {
    const size = 58.0;
    final rect = Rect.fromCenter(center: center, width: size, height: size);
    if (badgeImage != null) {
      _drawShareImageCover(canvas, badgeImage, rect);
    } else {
      canvas.drawCircle(
        center,
        size / 2,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            size / 2,
            [
              const Color(0xFFFFF3A3),
              color.withValues(alpha: 0.95),
              const Color(0xFF36210A),
            ],
            const [0.0, 0.55, 1.0],
          ),
      );
    }
    final labelRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 5),
      width: 50,
      height: 24,
    );
    final labelBg =
        RRect.fromRectAndRadius(labelRect, const Radius.circular(12));
    canvas.drawRRect(
      labelBg,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );
    _drawShareFittedText(
      canvas,
      '#$rank',
      labelRect.deflate(3),
      fontSize: 18,
      minFontSize: 12,
      color: Colors.white,
      weight: FontWeight.w900,
      align: TextAlign.center,
    );
  }

  void _drawShareHexPattern(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = Colors.white.withValues(alpha: 0.07);
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withValues(alpha: 0.045);
    const radius = 34.0;
    final stepX = sqrt(3) * radius;
    const stepY = radius * 1.5;
    for (var y = -radius; y < size.height + radius; y += stepY) {
      for (var x = -stepX; x < size.width + stepX; x += stepX) {
        final shiftedX = x + (((y / stepY).round()).isEven ? 0 : stepX / 2);
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final angle = pi / 3 * i - pi / 6;
          final point = Offset(
            shiftedX + cos(angle) * radius,
            y + sin(angle) * radius,
          );
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawShareImageCover(Canvas canvas, ui.Image image, Rect rect) {
    final srcSize = Size(image.width.toDouble(), image.height.toDouble());
    final srcRatio = srcSize.width / srcSize.height;
    final dstRatio = rect.width / rect.height;
    Rect src;
    if (srcRatio > dstRatio) {
      final width = srcSize.height * dstRatio;
      src =
          Rect.fromLTWH((srcSize.width - width) / 2, 0, width, srcSize.height);
    } else {
      final height = srcSize.width / dstRatio;
      src = Rect.fromLTWH(
          0, (srcSize.height - height) / 2, srcSize.width, height);
    }
    canvas.drawImageRect(
        image, src, rect, Paint()..filterQuality = FilterQuality.high);
  }

  void _drawShareImageContain(Canvas canvas, ui.Image image, Rect rect) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final srcRatio = src.width / src.height;
    final dstRatio = rect.width / rect.height;
    Rect dst;
    if (srcRatio > dstRatio) {
      final height = rect.width / srcRatio;
      dst = Rect.fromLTWH(
        rect.left,
        rect.top + (rect.height - height) / 2,
        rect.width,
        height,
      );
    } else {
      final width = rect.height * srcRatio;
      dst = Rect.fromLTWH(
        rect.left + (rect.width - width) / 2,
        rect.top,
        width,
        rect.height,
      );
    }
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _drawShareIcon(
    Canvas canvas,
    IconData icon,
    Offset center, {
    required double size,
    required Color color,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _drawShareText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double fontSize,
    required Color color,
    required FontWeight weight,
    double letterSpacing = 0,
    TextAlign align = TextAlign.left,
    double? width,
    double? top,
    int maxLines = 2,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          height: 1.05,
        ),
      ),
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width ?? 10000);
    painter.paint(canvas, Offset(offset.dx, top ?? offset.dy));
  }

  void _drawShareFittedText(
    Canvas canvas,
    String text,
    Rect rect, {
    required double fontSize,
    required double minFontSize,
    required Color color,
    required FontWeight weight,
    TextAlign align = TextAlign.left,
    double letterSpacing = 0,
  }) {
    var size = fontSize;
    TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            letterSpacing: letterSpacing,
            height: 1.05,
          ),
        ),
        textAlign: align,
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width);
      final fits = painter.width <= rect.width && painter.height <= rect.height;
      if (fits || size <= minFontSize) {
        break;
      }
      size -= 2;
    }
    final dx = switch (align) {
      TextAlign.center => rect.left + (rect.width - painter.width) / 2,
      TextAlign.right || TextAlign.end => rect.right - painter.width,
      _ => rect.left,
    };
    final dy = rect.top + (rect.height - painter.height) / 2;
    painter.paint(canvas, Offset(dx, dy));
  }

  void _drawShareProfileNameText(
    Canvas canvas,
    String text,
    Rect rect, {
    required double fontSize,
    required double minFontSize,
    required Color color,
    required FontWeight weight,
  }) {
    var size = fontSize;
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            letterSpacing: 0,
            height: 1.05,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if ((painter.width <= rect.width && painter.height <= rect.height) ||
          size <= minFontSize) {
        break;
      }
      size -= 1;
    }

    final scaleX =
        painter.width <= rect.width ? 1.0 : (rect.width / painter.width);
    final dy = rect.top + (rect.height - painter.height) / 2;
    canvas.save();
    canvas.translate(rect.left, dy);
    canvas.scale(scaleX.clamp(0.72, 1.0), 1.0);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  String _formatShareNumber(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
  }

  Future<void> _showShareErrorDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF141421),
        title: const Text(
          'シェア',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'シェア画像を作成できませんでした。しばらくしてからもう一度お試しください。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
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
                  color: isGo ? _readyGoThemeColor : Colors.white,
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
    final showAutoStart = widget.isRankedMode || widget.isArenaMode;
    final showLobbyTitle =
        widget.isRankedMode || widget.isArenaMode || !_isFriendMode;

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
                  if (showLobbyTitle) ...[
                    Text(
                      widget.isArenaMode
                          ? 'アリーナマッチが成立しました'
                          : widget.isRankedMode
                              ? 'ランク戦が成立しました'
                              : 'フレンド対戦',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_isFriendMode || (isHost && !widget.isRankedMode)) ...[
                    Text(
                      'ルームID',
                      style: TextStyle(
                        color: _friendPink.withValues(alpha: 0.86),
                        fontSize: 18,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      room.roomId,
                      style: const TextStyle(
                        color: _friendPink,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!_isFriendMode && (!showAutoStart || !canShowReady)) ...[
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
                  if (_isFriendMode)
                    _buildFriendLobbyActions(room: room, isHost: isHost)
                  else if (showAutoStart && canShowReady)
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
                    SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: lobbyAccent,
                          backgroundColor: lobbyAccent.withValues(alpha: 0.12),
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
                          'ホーム画面へ戻る',
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

  Widget _buildFriendLobbyActions({
    required MultiplayerRoom room,
    required bool isHost,
  }) {
    final canShowReady = room.bothPlayersJoined;
    final guestReady = room.players['guest']?.status == 'ready';
    final guestReadyInLobby = room.status == 'waiting' && guestReady;
    final myStatus =
        room.players[_multiplayerManager.myRoleId]?.status ?? 'waiting';
    final message = !canShowReady
        ? '相手の入室を待っています…'
        : isHost
            ? guestReadyInLobby
                ? '相手の準備が完了しました。ゲームを開始できます。'
                : room.status == 'waiting'
                    ? '相手の準備完了を待っています。'
                    : '相手がロビーに戻るまでお待ちください。'
            : myStatus == 'ready'
                ? 'ホストの開始を待っています。'
                : '準備ができたらボタンを押してください。';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        _buildFriendHandicapSummary(room: room, isHost: isHost),
        const SizedBox(height: 10),
        _buildFriendAllowanceStatus(),
        const SizedBox(height: 12),
        if (isHost)
          _buildFriendLobbyPrimaryButton(
            label: guestReadyInLobby ? 'ゲーム開始' : '相手の準備待ち',
            color: _friendPink,
            enabled: canShowReady && guestReadyInLobby && !_readySubmitting,
            allowAdRestoreWithoutReady: true,
            onPressed: _handleFriendStartPressed,
          )
        else
          _buildFriendLobbyPrimaryButton(
            label: myStatus == 'ready' ? '準備完了済み' : '準備完了',
            color: _friendPink,
            enabled: canShowReady && myStatus != 'ready' && !_readySubmitting,
            onPressed: _handleReadyPressed,
          ),
      ],
    );
  }

  Widget _buildFriendLobbyPrimaryButton({
    required String label,
    required Color color,
    required bool enabled,
    required Future<void> Function() onPressed,
    bool allowAdRestoreWithoutReady = false,
  }) {
    return FutureBuilder<FriendMatchLimitSnapshot>(
      future: FriendMatchLimitManager.instance.loadSnapshot(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final needsAdRestore = !_friendLobbyMatchAllowanceConsumed &&
            data != null &&
            !data.isUnlimited &&
            data.remaining <= 0;
        final canTap = needsAdRestore && allowAdRestoreWithoutReady
            ? !_readySubmitting
            : enabled &&
                !_readySubmitting &&
                (_friendLobbyMatchAllowanceConsumed || data != null);
        return _buildFriendLobbyButton(
          label: needsAdRestore ? '動画広告を見る' : label,
          color: color,
          onPressed: canTap
              ? () {
                  _playUiTap();
                  unawaited(onPressed());
                }
              : null,
        );
      },
    );
  }

  Widget _buildFriendLobbyButton({
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool outlined = false,
  }) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.56 : 1,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: outlined
                ? color.withValues(alpha: 0.08)
                : color.withValues(alpha: disabled ? 0.16 : 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: outlined ? 0.72 : 0.95),
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: outlined ? color : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendHandicapSummary({
    required MultiplayerRoom room,
    required bool isHost,
  }) {
    final myRoleId = _multiplayerManager.myRoleId;
    final myRows =
        myRoleId == 'guest' ? room.guestBoardRows : room.hostBoardRows;
    final opponentRows =
        myRoleId == 'guest' ? room.hostBoardRows : room.guestBoardRows;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _friendPink.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
                children: [
                  const TextSpan(text: 'ハンデ  '),
                  TextSpan(
                    text: 'あなた:$myRows段',
                    style: const TextStyle(color: _battlePlayerColor),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: '相手:$opponentRows段',
                    style: const TextStyle(color: _battleOpponentColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: isHost
                ? () {
                    _playUiTap();
                    unawaited(_showFriendHandicapDialog(room));
                  }
                : null,
            tooltip: isHost ? 'ハンデ設定' : 'ホストのみ設定できます',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.settings_rounded,
              color: isHost ? _friendPink : Colors.white30,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendAllowanceStatus() {
    return FutureBuilder<FriendMatchLimitSnapshot>(
      future: FriendMatchLimitManager.instance.loadSnapshot(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data != null && data.isUnlimited) {
          return const SizedBox.shrink();
        }
        final text = data == null
            ? 'フレンド対戦回数を確認中...'
            : data.remaining > 0
                ? '本日の残り無料対戦 ${data.displayRemaining}/${data.displayAllowance}回'
                : '次の対戦には動画広告の視聴が必要です';
        final color = data == null
            ? Colors.white54
            : data.remaining > 0
                ? _friendPink
                : Colors.white70;
        return Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        );
      },
    );
  }

  Future<bool> _consumeFriendLobbyMatchAllowanceIfNeeded() async {
    if (!_isFriendMode || _friendLobbyMatchAllowanceConsumed) {
      return true;
    }
    if (await FriendMatchLimitManager.instance.canStartMatch()) {
      final consumed = await FriendMatchLimitManager.instance.consumeMatch();
      if (!consumed) {
        if (mounted) {
          await _showCyberAlertDialog(
            'フレンド対戦',
            '本日の無料フレンド対戦回数を使い切りました。',
          );
        }
        return false;
      }
      if (mounted) {
        setState(() {
          _friendLobbyMatchAllowanceConsumed = true;
        });
      } else {
        _friendLobbyMatchAllowanceConsumed = true;
      }
      return true;
    }

    if (!mounted) {
      return false;
    }
    unawaited(RewardedAdManager.instance.warmUp());
    final shouldWatchAd = await _showFriendMatchRestoreDialog();
    if (!mounted || shouldWatchAd != true) {
      return false;
    }
    final rewarded = await RewardedAdManager.instance.showDoubleRewardAd();
    if (!mounted) {
      return false;
    }
    if (!rewarded) {
      await _showCyberAlertDialog('広告エラー', '動画の視聴が完了しませんでした。');
      return false;
    }
    await FriendMatchLimitManager.instance.addRewardedMatches();
    if (!mounted) {
      return false;
    }
    setState(() {});
    await _showCyberAlertDialog(
      'フレンド対戦',
      'フレンド対戦が2戦分回復しました。',
    );
    return false;
  }

  Future<void> _handleFriendStartPressed() async {
    setState(() {
      _readySubmitting = true;
    });
    try {
      final hasAllowance = await _consumeFriendLobbyMatchAllowanceIfNeeded();
      if (!hasAllowance) {
        return;
      }
      final connected = await _ensureServerConnection();
      if (!connected) {
        return;
      }
      await _multiplayerManager.startFriendMatchFromLobby();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog('ゲーム開始に失敗しました', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _readySubmitting = false;
        });
      }
    }
  }

  Future<void> _showFriendHandicapDialog(MultiplayerRoom room) async {
    var hostRows = room.hostBoardRows.toDouble();
    var guestRows = room.guestBoardRows.toDouble();
    final hostController =
        FixedExtentScrollController(initialItem: 12 - hostRows.round());
    final guestController =
        FixedExtentScrollController(initialItem: 12 - guestRows.round());
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Widget rowPicker({
                required String label,
                required double rows,
                required ValueChanged<double> onChanged,
                required Color color,
                required FixedExtentScrollController controller,
              }) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.62)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                color: color,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${rows.round()}段',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 112,
                        height: 132,
                        child: CupertinoPicker(
                          scrollController: controller,
                          itemExtent: 38,
                          magnification: 1.12,
                          squeeze: 0.92,
                          useMagnifier: true,
                          selectionOverlay: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                  color: color.withValues(alpha: 0.62),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                          onSelectedItemChanged: (index) {
                            onChanged((12 - index).toDouble());
                          },
                          children: [
                            for (var value = 12; value >= 3; value -= 1)
                              Center(
                                child: Text(
                                  '$value段',
                                  style: TextStyle(
                                    color: value == rows.round()
                                        ? color
                                        : Colors.white70,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return _buildCyberDialog(
                accentColor: _friendPink,
                title: 'ハンデ設定',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    rowPicker(
                      label: 'あなた',
                      rows: hostRows,
                      color: _battlePlayerColor,
                      controller: hostController,
                      onChanged: (value) =>
                          setDialogState(() => hostRows = value),
                    ),
                    const SizedBox(height: 10),
                    rowPicker(
                      label: '相手',
                      rows: guestRows,
                      color: _battleOpponentColor,
                      controller: guestController,
                      onChanged: (value) =>
                          setDialogState(() => guestRows = value),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildCyberDialogButton(
                            label: 'キャンセル',
                            accentColor: _mutedButtonGrey,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCyberDialogButton(
                            label: '保存',
                            accentColor: _friendPink,
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              unawaited(
                                _saveFriendHandicapRows(
                                  hostRows.round(),
                                  guestRows.round(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      hostController.dispose();
      guestController.dispose();
    }
  }

  Future<void> _saveFriendHandicapRows(int hostRows, int guestRows) async {
    try {
      await _multiplayerManager.updateFriendHandicapRows(
        hostRows: hostRows,
        guestRows: guestRows,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog('ハンデ設定に失敗しました', '$error');
    }
  }

  Future<void> _cancelFriendLobby() async {
    _clearAllPendingAttacks();
    await _stopBattleBgm();
    final inviteTargetUid = widget.friendInviteTargetUid;
    final inviteId = widget.friendInviteId;
    if (inviteTargetUid != null &&
        inviteTargetUid.isNotEmpty &&
        inviteId != null &&
        inviteId.isNotEmpty) {
      unawaited(
        FriendManager.instance.updateInviteStatus(
          targetUid: inviteTargetUid,
          inviteId: inviteId,
          status: 'cancelled',
        ),
      );
    }
    await _multiplayerManager.cancelLobby();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _startFriendInviteStatusMonitorIfNeeded() {
    final inviteTargetUid = widget.friendInviteTargetUid;
    final inviteId = widget.friendInviteId;
    if (!widget.isOnlineMultiplayer ||
        !widget.isHost ||
        inviteTargetUid == null ||
        inviteTargetUid.isEmpty ||
        inviteId == null ||
        inviteId.isEmpty) {
      return;
    }
    _friendInviteStatusSubscription?.cancel();
    _friendInviteStatusSubscription = FriendManager.instance
        .watchInviteStatus(
      targetUid: inviteTargetUid,
      inviteId: inviteId,
    )
        .listen((status) {
      if (status == 'declined') {
        unawaited(_handleFriendInviteDeclined());
      }
    });
  }

  Future<void> _handleFriendInviteDeclined() async {
    if (_friendInviteDeclineHandled) {
      return;
    }
    _friendInviteDeclineHandled = true;
    await _friendInviteStatusSubscription?.cancel();
    _friendInviteStatusSubscription = null;
    _clearAllPendingAttacks();
    await _stopBattleBgm();
    await _multiplayerManager.cancelLobby();
    if (!mounted) {
      return;
    }
    await _showCyberAlertDialog(
      'フレンド対戦',
      '相手が招待を辞退しました。ルームを解散しました。',
    );
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
                    playerIconId: widget.rankedBotIconId,
                    playerIconFrameId: widget.rankedBotFrameId,
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
          _buildPlayerIconAvatar(
            iconId: playerIconId,
            frameId: playerIconFrameId,
            color: iconFrameColor,
            size: 34,
            iconSize: 19,
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
      if (_isFriendMode) {
        final hasAllowance = await _consumeFriendLobbyMatchAllowanceIfNeeded();
        if (!hasAllowance) {
          return;
        }
      }
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
      if (_isOnlineMode && _cpuGame != null) {
        _cpuGame!.ballSkinId = _opponentBallSkinId();
        _cpuGame!.setSfxSelectionIds(_opponentSfxSelectionIds());
        if (!_onlineGameStarted) {
          _playerGame.configureGridRows(_playerBoardRows);
          _cpuGame!.configureGridRows(_opponentBoardRows);
        }
      }
      final opponentStatus =
          room.players[_multiplayerManager.opponentRoleId]?.status;
      if (opponentStatus != 'left' && !_opponentRealtimeDisconnected) {
        _opponentDisconnectForfeitTimer?.cancel();
        _opponentDisconnectForfeitTimer = null;
      }
      final myStatus = room.players[_multiplayerManager.myRoleId]?.status;
      _opponentRequestedRematch = _onlineResultMessage != null &&
          opponentStatus == 'rematch_ready' &&
          myStatus != 'rematch_ready' &&
          !_isWaitingForRematch;
      if (_opponentHasLeft(room)) {
        _opponentUnavailableForRematch = true;
        _isWaitingForRematch = false;
        _opponentRequestedRematch = false;
      }
    });

    if (_onlineGameStarted) {
      _handleRoomGameOverResultIfNeeded(room);
      return;
    }

    final opponentStatus =
        room.players[_multiplayerManager.opponentRoleId]?.status;
    if (room.bothPlayersJoined && opponentStatus == 'left') {
      if (_isFriendMode) {
        unawaited(_showFriendDisconnectedReturnHome());
      } else {
        _handlePreBattleOpponentForfeit(room.seed);
      }
      return;
    }

    if (room.status == 'playing') {
      _scheduleOnlineAutoStart(room);
      return;
    }

    if (room.bothPlayersJoined) {
      _playMatchedSfxOnce();
      if (!_isFriendMode) {
        unawaited(_attemptAutoReady());
      }
    }

    if (!_isFriendMode && room.bothPlayersReady) {
      _scheduleOnlineAutoStart(room);
      return;
    }
  }

  void _handleRoomGameOverResultIfNeeded(MultiplayerRoom room) {
    if (room.status != 'game_over' ||
        _battleResultStarted ||
        _resultRevealPending ||
        _onlineResultMessage != null) {
      return;
    }

    final myRoleId = _multiplayerManager.myRoleId;
    if (myRoleId == null) {
      return;
    }
    final opponentRoleId = _multiplayerManager.opponentRoleId;
    final myStatus = room.players[myRoleId]?.status;
    final opponentStatus = room.players[opponentRoleId]?.status;
    bool? inferredWin;
    if (myStatus == 'forfeit_win') {
      inferredWin = true;
    } else if (myStatus == 'dead' && opponentStatus == 'forfeit_win') {
      inferredWin = false;
    }

    unawaited(() async {
      final roomResult = await _multiplayerManager.loadCurrentRoomResult();
      if (!mounted ||
          _battleResultStarted ||
          _resultRevealPending ||
          _onlineResultMessage != null) {
        return;
      }
      final isWin = roomResult?.isWin ?? inferredWin;
      if (isWin == null) {
        return;
      }
      final resultWasForfeit = roomResult?.isForfeit ??
          myStatus == 'forfeit_win' || opponentStatus == 'forfeit_win';
      await _presentRankedSafeBattleResult(
        playerWon: isWin,
        opponentCrossedDeathLine: isWin,
        resultWasForfeit: resultWasForfeit,
        resultWasOfflineForfeit:
            !isWin && (roomResult?.reason == 'offline_forfeit'),
      );
    }());
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

  Future<Duration> _playReadySfx() async {
    var fileName = _readySfx;
    try {
      fileName = await AudioSelectionManager.selectedSfxFile(
        'ready',
        _readySfx,
      );
      unawaited(SfxPlayer.play(fileName, volume: 1.0));
    } catch (_) {
      // READY SEの再生失敗で開始演出は止めない。
    }
    return fileName == _countdownReadySfx || _onlineRoomUsesCountdownReadySfx()
        ? _countdownReadyToGoDelay
        : _defaultReadyToGoDelay;
  }

  bool _onlineRoomUsesCountdownReadySfx() {
    final room = _room ?? _multiplayerManager.currentRoom;
    if (room == null || !_isOnlineMode) {
      return false;
    }
    return room.players.values.any((player) => player.readySfxId == 'ready_03');
  }

  Future<void> _playMatchedHaptic() async {
    if (!AppSettings.instance.hapticsEnabled.value) {
      return;
    }
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
        _rankedOfflineSince = null;
        _rankedOfflineForfeitTimer?.cancel();
        _rankedOfflineForfeitTimer = null;
        if (_isOnlineMode && _onlineGameStarted && !_battleResultStarted) {
          unawaited(
            _multiplayerManager.markCurrentPlayerPlayingIfNeeded().catchError(
              (_) {
                // 復帰通知に失敗しても、次の同期送信やルーム更新で再評価される。
              },
            ),
          );
        }
        if (_isOnlineMode && _onlineGameStarted) {
          unawaited(_consumeQueuedIncomingOjamaAfterReconnect());
        }
        if (_pendingOfflineForfeitCommit) {
          unawaited(_commitPendingOfflineForfeitAfterReconnect());
        }
        return;
      }
      _showRealtimeOfflineMessage();
      _scheduleRankedOfflineForfeitIfNeeded();
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

  bool get _isOfflineForfeitBattleCurrentlyPlaying {
    if (widget.isArenaMode) {
      return false;
    }
    if (_resultRevealPending || _onlineResultMessage != null) {
      return false;
    }
    if (!_isOnlineMode && !_isRankedBotMode) {
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
    if (_rankedOfflineForfeitStarted ||
        !_isOfflineForfeitBattleCurrentlyPlaying) {
      return;
    }
    _rankedOfflineForfeitTimer?.cancel();
    _rankedOfflineForfeitTimer = null;
    _rankedOfflineForfeitStarted = true;
    unawaited(
      () async {
        final connected = await RealtimeConnectionGuard.currentConnected(
              timeout: const Duration(milliseconds: 500),
            ) ??
            false;
        if (!mounted) {
          return;
        }
        _realtimeConnected = connected;
        if (!connected) {
          _pendingOfflineForfeitCommit = true;
          _showRealtimeOfflineMessage();
          unawaited(
            _multiplayerManager.saveActiveSession(
              isArenaMode: widget.isArenaMode,
              snapshot: const {
                'abandonReason': 'offline',
                'resultKnown': true,
                'isWin': false,
              },
            ),
          );
          await _presentRankedSafeBattleResult(
            playerWon: false,
            opponentCrossedDeathLine: false,
            resultWasForfeit: true,
            resultWasOfflineForfeit: true,
          );
          return;
        }

        final recorded = await _multiplayerManager.recordOfflineForfeitLoss();
        if (!mounted) {
          return;
        }
        if (!recorded) {
          _rankedOfflineForfeitStarted = false;
          _rankedOfflineSince = DateTime.now();
          _showRealtimeOfflineMessage();
          _scheduleRankedOfflineForfeitIfNeeded();
          return;
        }

        await _multiplayerManager.saveActiveSession(
          isArenaMode: widget.isArenaMode,
          snapshot: const {
            'abandonReason': 'offline',
            'resultKnown': true,
            'isWin': false,
          },
        );
        if (mounted) {
          await _presentRankedSafeBattleResult(
            playerWon: false,
            opponentCrossedDeathLine: false,
            resultWasForfeit: true,
            resultWasOfflineForfeit: true,
          );
        }
      }(),
    );
  }

  void _scheduleRankedOfflineForfeitIfNeeded() {
    if (_rankedOfflineForfeitStarted ||
        !_isOfflineForfeitBattleCurrentlyPlaying) {
      return;
    }
    final offlineSince = _rankedOfflineSince ?? DateTime.now();
    _rankedOfflineSince = offlineSince;
    final elapsed = DateTime.now().difference(offlineSince);
    final remaining = _rankedOfflineForfeitGrace - elapsed;
    if (remaining <= Duration.zero) {
      _forfeitRankedMatchForOfflineIfNeeded();
      return;
    }
    _rankedOfflineForfeitTimer ??= Timer(remaining, () async {
      _rankedOfflineForfeitTimer = null;
      final connected =
          await RealtimeConnectionGuard.currentConnected() ?? false;
      if (!mounted) {
        return;
      }
      _realtimeConnected = connected;
      if (connected) {
        _rankedOfflineSince = null;
        return;
      }
      _forfeitRankedMatchForOfflineIfNeeded();
    });
  }

  bool _canSendServerAction({bool forfeitRankedOnOffline = false}) {
    if (_realtimeConnected) {
      return true;
    }
    _showRealtimeOfflineMessage();
    if (forfeitRankedOnOffline) {
      _scheduleRankedOfflineForfeitIfNeeded();
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
          _scheduleRankedOfflineForfeitIfNeeded();
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
      _scheduleRankedOfflineForfeitIfNeeded();
    }
    return false;
  }

  Future<void> _attemptAutoReady() async {
    final room = _room;
    if (_isFriendMode ||
        room == null ||
        !room.bothPlayersJoined ||
        _onlineGameStarted) {
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
    final readyToGoDelay = await _playReadySfx();

    await Future<void>.delayed(readyToGoDelay);
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
    _startDailyChallengeTimerIfNeeded();
    if (mounted) {
      setState(() {
        _battleIntroLocked = false;
      });
    }
  }

  void _startDailyChallengeTimerIfNeeded() {
    if (!widget.isDailyMode || _dailyChallengeTimer != null) {
      return;
    }
    setState(() {
      _dailyRemainingSeconds = DailyChallengeManager.durationSeconds;
    });
    _dailyChallengeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted ||
          _resultRevealPending ||
          _battleResultStarted ||
          _playerGame.gameStateWrapper.value != GameState.playing) {
        timer.cancel();
        if (_dailyChallengeTimer == timer) {
          _dailyChallengeTimer = null;
        }
        return;
      }
      final next = max(0, _dailyRemainingSeconds - 1);
      setState(() {
        _dailyRemainingSeconds = next;
      });
      if (next <= 0) {
        timer.cancel();
        if (_dailyChallengeTimer == timer) {
          _dailyChallengeTimer = null;
        }
        unawaited(_finishDailyChallenge());
      }
    });
  }

  Future<void> _finishDailyChallenge() async {
    if (!widget.isDailyMode || _battleResultStarted || _resultRevealPending) {
      return;
    }
    _dailyChallengeTimer?.cancel();
    _dailyChallengeTimer = null;
    _playerGame.scoreManager.addDailyEndBonus(
      noDanger: _playerGame.dailyNoDangerBonusEligible,
    );
    _playerGame.gameStateWrapper.value = GameState.gameover;
    await _presentBattleResult(
      playerWon: true,
      opponentCrossedDeathLine: false,
    );
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
    if (_isFriendMode) {
      _playerGame.configureGridRows(_playerBoardRows);
      _cpuGame?.configureGridRows(_opponentBoardRows);
    }
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
    final readyToGoDelay = await _playReadySfx();

    await Future<void>.delayed(readyToGoDelay);
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
        _presentRankedSafeBattleResult(
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
      'icon_hexagon2' => Icons.hexagon,
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
      'white' => Colors.white,
      'black' => const Color(0xFF05070D),
      'rainbow' => const Color(0xFFFFD54A),
      _ => _gameCyan,
    };
  }

  Widget _buildPlayerIconAvatar({
    required String iconId,
    required String frameId,
    required Color color,
    required double size,
    required double iconSize,
  }) {
    final icon = PlayerIconImage(
      iconId: iconId,
      fallbackIcon: _playerIconData(iconId),
      color: Colors.white,
      size: iconSize,
    );
    if (GameItemCatalog.byId(frameId)?.colorName == 'rainbow') {
      return RainbowFrameRing(
        size: size,
        strokeWidth: size >= 40 ? 3.2 : 2.4,
        child: icon,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: playerIconInnerBackgroundColor(
          iconId,
          color.withValues(alpha: 0.16),
          frameId: frameId,
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.92),
          width: size >= 40 ? 2 : 1.6,
        ),
      ),
      child: icon,
    );
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
      _pendingEmptyOpponentBoardTimer = null;
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
    final pieceId = _intValue(pieceData['pieceId']);
    final eventSeq = _intValue(pieceData['eventSeq']);
    final isTerminalAction = action == 'hard_drop' || action == 'lock';
    if (pieceId != null &&
        action == 'spawn' &&
        _processedOpponentTerminalPieceIds.contains(pieceId)) {
      return;
    }
    if (pieceId != null && eventSeq != null && action == 'spawn') {
      final lastSeq = _lastOpponentEventSeqByPieceId[pieceId];
      if (lastSeq != null && eventSeq <= lastSeq) {
        return;
      }
    }
    if (pieceId != null &&
        isTerminalAction &&
        _processedOpponentTerminalPieceIds.contains(pieceId)) {
      return;
    }
    if (pieceId != null && eventSeq != null && action != 'spawn') {
      final lastSeq = _lastOpponentEventSeqByPieceId[pieceId] ?? 0;
      if (eventSeq <= lastSeq) {
        return;
      }
      _lastOpponentEventSeqByPieceId[pieceId] = eventSeq;
    }
    final rawX = (pieceData['x'] as num?)?.toDouble();
    final rawY = (pieceData['y'] as num?)?.toDouble();
    final relativeX = (pieceData['relativeX'] as num?)?.toDouble();
    final relativeY = (pieceData['relativeY'] as num?)?.toDouble();
    final x = relativeX == null ? rawX : opponentGame.boardOriginX + relativeX;
    final y = relativeY == null ? rawY : opponentGame.boardOriginY + relativeY;
    final rotation = (pieceData['rotation'] as num?)?.toInt();
    final colors = _parseColors(pieceData['colors']);
    final nextColors = _parseColors(pieceData['nextColors']);
    final lockedHexes = _parseLockedHexes(pieceData['lockedCells']);
    final lockedCells = _parseLockedCells(pieceData['lockedCells']);
    final pieceBallSkinId = pieceData['ballSkinId']?.toString();
    if (pieceBallSkinId != null && pieceBallSkinId.isNotEmpty) {
      opponentGame.ballSkinId = pieceBallSkinId;
    }
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
        case 'lock':
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

    if (action != 'spawn') {
      _ensureOpponentActivePiece(opponentGame, colors);
      opponentGame.syncRemoteActivePieceInputState(
        movingLeft: movingLeft,
        movingRight: movingRight,
        contactSlideDirection: contactSlideDirection,
      );
    }

    switch (action) {
      case 'spawn':
        if (pieceId != null) {
          _processedOpponentTerminalPieceIds.remove(pieceId);
          _lastOpponentEventSeqByPieceId[pieceId] = eventSeq ?? 0;
        }
        if (colors.length == 3) {
          opponentGame.spawnRemotePieceWithId(
            colors: colors,
            pieceId: pieceId,
          );
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
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.08,
          );
        }
        break;
      case 'start_left':
      case 'stop_left':
      case 'start_right':
      case 'stop_right':
      case 'contact_slide':
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: action.startsWith('stop_') ? 0.035 : 0.05,
          );
        }
        break;
      case 'move':
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.07,
          );
        }
        break;
      case 'hard_drop':
        if (pieceId != null) {
          _processedOpponentTerminalPieceIds.add(pieceId);
          _ignoreEmptyOpponentBoardUntil =
              DateTime.now().add(const Duration(seconds: 2));
        }
        unawaited(
          opponentGame.applyRemoteHardDrop(
            x: x,
            y: y,
            rotation: rotation,
            lockedHexes: lockedHexes,
            lockedCells: lockedCells,
          ),
        );
        break;
      case 'lock':
        if (pieceId != null) {
          _processedOpponentTerminalPieceIds.add(pieceId);
          _ignoreEmptyOpponentBoardUntil =
              DateTime.now().add(const Duration(seconds: 2));
        }
        unawaited(
          opponentGame.applyRemoteHardDrop(
            x: x,
            y: y,
            rotation: rotation,
            lockedHexes: lockedHexes,
            lockedCells: lockedCells,
            playHardDropEffects: false,
          ),
        );
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

  List<HexCoordinate>? _parseLockedHexes(Object? raw) {
    final items = raw is List
        ? raw
        : raw is Map
            ? raw.values.toList()
            : null;
    if (items == null) {
      return null;
    }
    final hexes = <HexCoordinate>[];
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final row =
          (item['row'] as num?)?.toInt() ?? int.tryParse('${item['row']}');
      final col =
          (item['col'] as num?)?.toInt() ?? int.tryParse('${item['col']}');
      if (row == null || col == null) {
        continue;
      }
      hexes.add(HexCoordinate(col, row));
    }
    return hexes.isEmpty ? null : hexes;
  }

  List<Map<String, dynamic>>? _parseLockedCells(Object? raw) {
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
      if (item is! Map) {
        continue;
      }
      final row =
          (item['row'] as num?)?.toInt() ?? int.tryParse('${item['row']}');
      final col =
          (item['col'] as num?)?.toInt() ?? int.tryParse('${item['col']}');
      if (row == null || col == null) {
        continue;
      }
      final hitOffsetX = (item['hitOffsetX'] as num?)?.toDouble() ??
          double.tryParse('${item['hitOffsetX']}') ??
          0.0;
      cells.add({
        'row': row,
        'col': col,
        'hitOffsetX': hitOffsetX,
      });
    }
    return cells.isEmpty ? null : cells;
  }

  void _handleAttackReceived(OjamaTask task) {
    _cpuGame?.showRemoteAttackFormation(task.type);
    _queueOjamaTask(_playerGame, task);
  }

  void _handleOpponentOjamaSpawned(List<dynamic> ojamaData, int dropSeed) {
    _cpuGame?.spawnRemoteOjama(ojamaData, dropSeed);
  }

  void _handleOpponentGameOver() {
    _handleOpponentGameOverWithFinalBoard();
  }

  void _handleOpponentGameOverWithFinalBoard({
    Map<String, dynamic>? finalBoard,
    String? reason,
  }) {
    if (_resultRevealPending || _onlineResultMessage != null) {
      return;
    }
    if (finalBoard != null && finalBoard.isNotEmpty) {
      _ignoreEmptyOpponentBoardUntil =
          DateTime.now().add(const Duration(seconds: 4));
      _cpuGame?.applyRemoteBoardState(finalBoard);
    }
    _opponentGameOverVerificationPending = false;
    final resultWasForfeit =
        reason == 'offline_forfeit' || reason == 'opponent_offline_forfeit';
    unawaited(
      _presentRankedSafeBattleResult(
        playerWon: true,
        opponentCrossedDeathLine: true,
        resultWasForfeit: resultWasForfeit,
      ),
    );
  }

  int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  Future<void> _presentRankedSafeBattleResult({
    required bool playerWon,
    required bool opponentCrossedDeathLine,
    bool resultWasForfeit = false,
    bool resultWasOfflineForfeit = false,
  }) async {
    _markRankedResultKnownIfNeeded(isWin: playerWon);
    await _presentBattleResult(
      playerWon: playerWon,
      opponentCrossedDeathLine: opponentCrossedDeathLine,
      resultWasForfeit: resultWasForfeit,
      resultWasOfflineForfeit: resultWasOfflineForfeit,
    );
  }

  void _markRankedResultKnownIfNeeded({required bool isWin}) {
    if (!widget.isRankedMode || widget.isArenaMode) {
      return;
    }
    unawaited(
      _multiplayerManager.markSavedSessionResultKnown(isWin: isWin).catchError(
        (_) {
          // 復帰用セッションの補助保存なので、通常のリザルト進行は止めない。
        },
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
    String? reason,
  }) async {
    if (!widget.isRankedMode || _rankedRatingApplied) {
      return;
    }

    _rankedRatingApplied = true;
    try {
      final connected = await _ensureServerConnection();
      if (!connected) {
        return;
      }
      await _ensureRankedSeasonReadyForResult();
      final change = await _multiplayerManager.applyRankedResult(
        isWin: isWin,
        applyOpponentResult: applyOpponentResult,
        reason: reason,
      );
      if (!mounted || change == null) {
        return;
      }
      setState(() {
        _rankedRatingChange = change;
      });
      await _playerDataManager.setCurrentRating(change.newRating);
      await _playerDataManager.updateLatestRankedHistory(
        ratingAfter: change.newRating,
        ratingDelta: change.delta,
      );
      await _syncPlayerProfileOnline(
        rating: change.newRating,
      );
      if (!mounted) {
        return;
      }
      _refreshNewlyUnlockedBadgesFromSnapshot();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showRealtimeOfflineMessage();
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
        return;
      }
      await _ensureRankedSeasonReadyForResult();
      final change = await _multiplayerManager.applyRankedBotResult(
        isWin: isWin,
        opponentRating: opponentRating,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _rankedRatingChange = change;
      });
      await _multiplayerManager.clearSavedSession();
      await _playerDataManager.setCurrentRating(change.newRating);
      await _playerDataManager.updateLatestRankedHistory(
        ratingAfter: change.newRating,
        ratingDelta: change.delta,
      );
      await _syncPlayerProfileOnline(
        rating: change.newRating,
      );
      if (!mounted) {
        return;
      }
      _refreshNewlyUnlockedBadgesFromSnapshot();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showRealtimeOfflineMessage();
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
    _activeResultWasForfeit = false;
    _battleResultWasOfflineForfeitLoss = false;
    _opponentUnavailableForRematch = false;
    _autoReadyRequested = false;
    _rankedOfflineForfeitStarted = false;
    _pendingOfflineForfeitCommit = false;
    _opponentDisconnectForfeitTimer?.cancel();
    _opponentDisconnectForfeitTimer = null;
    _opponentGameOverVerificationPending = false;
    _tutorialOpponentDefeatQueued = false;
    _resultRevealPending = false;
    _battleResultStarted = false;
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
    final results = await Future.wait<bool>(
      [
        _runBestEffortProfileSyncTask(
          'userName',
          () => _multiplayerManager
              .updateUserName(_playerDataManager.playerName)
              .timeout(_playerProfileSyncTimeout),
        ),
        _runBestEffortProfileSyncTask(
          'rankings',
          () => _rankingManager
              .updateMyRating(
                rating: syncRating,
                displayName: _playerDataManager.displayPlayerName,
                incrementDailyWin: incrementDailyWin,
                incrementSeasonLoss: incrementSeasonLoss,
              )
              .timeout(_playerProfileSyncTimeout),
        ),
        _runBestEffortProfileSyncTask(
          'recordSummary',
          () => _playerDataManager
              .syncRecordSummary(force: true, rethrowErrors: true)
              .timeout(_playerProfileSyncTimeout),
        ),
      ],
      eagerError: false,
    );
    if (results.any((synced) => !synced)) {
      debugPrint(
        'Some result profile sync tasks failed; local result was kept.',
      );
    }
  }

  Future<bool> _runBestEffortProfileSyncTask(
    String label,
    Future<void> Function() task,
  ) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await task();
        return true;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt < 2) {
          await Future<void>.delayed(
              Duration(milliseconds: 250 * (attempt + 1)));
        }
      }
    }
    debugPrint('Result profile sync task failed: $label: $lastError');
    if (lastStackTrace != null) {
      debugPrintStack(stackTrace: lastStackTrace);
    }
    return false;
  }

  Future<void> _ensureRankedSeasonReadyForResult() async {
    if (!widget.isRankedMode) {
      return;
    }
    await _rankingManager
        .syncSeasonStateForCurrentPlayer()
        .timeout(_playerProfileSyncTimeout);
    await _playerDataManager.load();
    final nowJst = await ServerTimeManager.instance.nowJst(forceRefresh: true);
    final currentSeasonId =
        RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
    if (_playerDataManager.rankedSeasonId != currentSeasonId) {
      throw StateError('ランク戦のシーズン同期に失敗しました。');
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
    final adsRemoved = AppSettings.instance.adRemovalBenefitsEnabled;
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
    if (!AppSettings.instance.canRequestRewardedAds) {
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
      await RankedInterstitialDebtManager.instance.clearPending(
        kind: _interstitialDebtKindForCurrentMode(),
      );
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
    final opponentUid = widget.isCpuMode ? '' : opponentPlayer?.uid ?? '';
    if (mode == 'RANKED') {
      await _ensureRankedSeasonReadyForResult();
    }
    await _playerDataManager.recordMatchResult(
      isWin: isWin,
      mode: mode,
      opponentName: opponentName,
      opponentUid: opponentUid,
      opponentPublicId: widget.isCpuMode ? '' : opponentPlayer?.publicId ?? '',
      isPvp: opponentUid.trim().isNotEmpty,
      wazaCounts: {
        'straight': _playerWazaCounts[WazaType.straight] ?? 0,
        'pyramid': _playerWazaCounts[WazaType.pyramid] ?? 0,
        'hexagon': _playerWazaCounts[WazaType.hexagon] ?? 0,
      },
      clearedBalls: _playerGame.scoreManager.state.value.totalClearedBalls,
      normalClearedBalls: _playerNormalClearedBalls,
      maxChain: _playerGame.scoreManager.maxChainThisRun,
      isForfeitWin: isWin && (isForfeitWin || _activeResultWasForfeit),
      ratingAfter: _rankedRatingChange?.newRating,
      ratingDelta: _rankedRatingChange?.delta,
    );
    await _syncPlayerProfileOnline(
      rating:
          _rankedRatingChange?.newRating ?? _playerDataManager.currentRating,
    );
    if (mode == 'RANKED') {
      await _rankingManager.syncRankedResultAbsolute(
        rating:
            _rankedRatingChange?.newRating ?? _playerDataManager.currentRating,
        isWin: isWin,
        reason: isForfeitWin ? 'ranked_forfeit_result' : 'ranked_result',
      );
    }
    _refreshNewlyUnlockedBadgesFromSnapshot();
  }

  Future<void> _recordSoloStats() async {
    try {
      await _rankingManager
          .syncEndlessSeasonStateForCurrentPlayer()
          .timeout(_playerProfileSyncTimeout);
    } catch (_) {
      // 週間スコアの境界同期に失敗しても、結果保存と後続同期は試す。
    }
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
    await _syncPlayerProfileOnline(rating: _playerDataManager.currentRating);
    _refreshNewlyUnlockedBadgesFromSnapshot();
  }

  Future<void> _recordDailyChallengeStats() async {
    if (_dailyResultRecorded) {
      return;
    }
    _dailyResultRecorded = true;
    await DailyChallengeManager.instance.submitScore(
      dateKey: widget.dailyDateKey ??
          DailyChallengeManager.dateKeyFor(DateTime.now().toLocal()),
      score: _currentPlayerScore,
    );
    await _playerDataManager.recordMatchResult(
      isWin: true,
      mode: 'DAILY',
      opponentName: 'デイリー',
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
    unawaited(_missionManager.recordEvent('play_daily'));
    await _syncPlayerProfileOnline(rating: _playerDataManager.currentRating);
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
    await _markRankedWinReviewPromptPendingIfNeeded();
    final isOfflineForfeitResult =
        _pendingOfflineForfeitCommit || _onlineResultWasOfflineForfeit;
    if (isOfflineForfeitResult) {
      await _returnHomeAfterOfflineForfeit();
      return;
    }
    if (_isOnlineMode &&
        widget.isRankedMode &&
        !widget.isArenaMode &&
        !isOfflineForfeitResult) {
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
          debugPrint(
              'Realtime connection unavailable on ranked result return.');
        }
      } finally {
        _isCheckingHomeReturnConnection = false;
      }
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
      try {
        await _multiplayerManager.leaveRoom().timeout(
          const Duration(seconds: 2),
          onTimeout: () async {
            await _multiplayerManager.suspendActiveSession();
          },
        );
      } catch (_) {
        await _multiplayerManager.suspendActiveSession();
      }
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
    await _showPostGameInterstitialIfNeeded();
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

  Future<void> _markRankedWinReviewPromptPendingIfNeeded() async {
    if (!widget.isRankedMode || widget.isArenaMode || !_sharePlayerWon) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rankedWinReviewPromptPendingKey, true);
    } catch (_) {
      // レビュー依頼フラグ保存失敗でホーム遷移を止めない。
    }
  }

  Future<void> _returnHomeAfterOfflineForfeit() async {
    if (!mounted || _isReturningToHome) {
      return;
    }
    _isReturningToHome = true;
    try {
      await GameActivityPresence.instance.exit().timeout(
            const Duration(milliseconds: 600),
            onTimeout: () {},
          );
    } catch (_) {}
    _shutdownBattleGames();
    _myStampTimer?.cancel();
    _opponentStampTimer?.cancel();
    _stampCooldownTimer?.cancel();
    try {
      await _stopBattleBgm().timeout(
        const Duration(milliseconds: 800),
        onTimeout: () {},
      );
    } catch (_) {}
    if (_isOnlineMode) {
      try {
        await _multiplayerManager.suspendActiveSession().timeout(
              const Duration(seconds: 1),
              onTimeout: () {},
            );
      } catch (_) {}
    }
    try {
      await SfxPlayer.resetTransientAudio().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    } catch (_) {}
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _showPostGameInterstitialIfNeeded() async {
    final deferRankedHumanInterstitial =
        widget.isRankedMode && _isOnlineMode && !widget.isArenaMode;
    if (_resultCoinTripleClaimed ||
        deferRankedHumanInterstitial ||
        AppSettings.instance.isInterstitialSkipActive) {
      return;
    }
    final shouldRequireForSoloMode = widget.isCpuMode || !_isOnlineMode;
    final interstitialShown = shouldRequireForSoloMode
        ? await InterstitialAdManager.instance.showRequired(
            loadTimeout: const Duration(seconds: 2),
          )
        : await InterstitialAdManager.instance.showAfterGame();
    if (interstitialShown) {
      await RankedInterstitialDebtManager.instance.clearPending(
        kind: _interstitialDebtKindForCurrentMode(),
      );
    }
    await InterstitialAdManager.instance.settleAfterGame();
  }

  InterstitialDebtKind _interstitialDebtKindForCurrentMode() {
    if (widget.isRankedMode && _isOnlineMode && !widget.isArenaMode) {
      return InterstitialDebtKind.rankedHuman;
    }
    if (widget.isRankedMode && widget.isCpuMode && !widget.isArenaMode) {
      return InterstitialDebtKind.rankedBot;
    }
    if (widget.isCpuMode) {
      return InterstitialDebtKind.computer;
    }
    return InterstitialDebtKind.endless;
  }

  void _handleOpponentDisconnected() {
    if (_isFriendMode) {
      unawaited(_showFriendDisconnectedReturnHome());
      return;
    }
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

    if (!mounted || _opponentDisconnectForfeitTimer != null) {
      return;
    }

    _opponentRealtimeDisconnected = true;
    _opponentDisconnectForfeitTimer =
        Timer(_opponentDisconnectForfeitGrace, () {
      _opponentDisconnectForfeitTimer = null;
      unawaited(_resolveOpponentDisconnectForfeitIfNeeded());
    });
  }

  Future<void> _resolveOpponentDisconnectForfeitIfNeeded() async {
    if (!mounted ||
        !_onlineGameStarted ||
        _battleResultStarted ||
        _resultRevealPending ||
        _onlineResultMessage != null) {
      return;
    }

    final room = _room ?? _multiplayerManager.currentRoom;
    final opponentStatus =
        room?.players[_multiplayerManager.opponentRoleId]?.status;
    if (opponentStatus != 'left' && !_opponentRealtimeDisconnected) {
      return;
    }

    try {
      await _multiplayerManager.forceOpponentGameOver();
    } catch (_) {
      return;
    }
    if (!mounted ||
        _battleResultStarted ||
        _resultRevealPending ||
        _onlineResultMessage != null) {
      return;
    }

    await _presentRankedSafeBattleResult(
      playerWon: true,
      opponentCrossedDeathLine: false,
      resultWasForfeit: true,
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
      _opponentRealtimeDisconnected = false;
      _isWaitingForRematch = false;
      _opponentRequestedRematch = false;
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
      final selectedBgm = await AudioSelectionManager.selectedBattleBgm();
      await SeamlessBgm.instance.setMasterVolume(
        AppSettings.instance.musicVolume.value,
      );
      await SeamlessBgm.instance.play(
        assetPath: selectedBgm.assetPath,
        duration: selectedBgm.duration,
        volume: 0.2448 * selectedBgm.volumeMultiplier,
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
        assetPath: AudioSelectionManager.defaultHomeBgm.assetPath,
        duration: AudioSelectionManager.defaultHomeBgm.duration,
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
          title: Text(
            AppSettings.instance.translate(title),
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            AppSettings.instance.translate(message),
            style: const TextStyle(color: Colors.white70),
          ),
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
              AppSettings.instance.translate(title),
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
        AppSettings.instance.translate(label),
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
    var shouldResumeAfterSettings = shouldResumeBattle;

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
                OutlinedButton(
                  onPressed: () {
                    _playUiTap();
                    Navigator.of(dialogContext).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gameCyan,
                    side: BorderSide(
                      color: _gameCyan.withValues(alpha: 0.76),
                      width: 1.4,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  child: const Text('ゲームに戻る'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    _playUiTap();
                    final confirmed = await _showAbortCurrentPlayConfirmDialog(
                      title: 'ホーム画面に戻りますか？',
                    );
                    if (confirmed != true || !dialogContext.mounted) {
                      return;
                    }
                    shouldResumeAfterSettings = false;
                    Navigator.of(dialogContext).pop();
                    unawaited(_returnHomeFromSettings());
                  },
                  icon: const Icon(Icons.home, size: 18),
                  label: const Text('ホーム画面に戻る'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.30),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                if (!_isOnlineMode && !widget.isCpuMode) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      _playUiTap();
                      final confirmed =
                          await _showAbortCurrentPlayConfirmDialog(
                        title: 'リスタートしますか？',
                      );
                      if (confirmed != true || !dialogContext.mounted) {
                        return;
                      }
                      shouldResumeAfterSettings = false;
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
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.30),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (shouldResumeAfterSettings) {
        _resumeBattleFromSettings();
      }
    });
  }

  Future<bool?> _showAbortCurrentPlayConfirmDialog({
    required String title,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (confirmContext) {
        return _buildCyberDialog(
          title: title,
          accentColor: _mutedButtonGrey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '現在のプレイが中断されますが、よろしいですか？',
                style: TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'キャンセル',
                      accentColor: _gameCyan,
                      onPressed: () => Navigator.of(confirmContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '中断する',
                      accentColor: _mutedButtonGrey,
                      onPressed: () => Navigator.of(confirmContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
    if (_isFriendMode && !await _ensureFriendMatchAllowanceForRematch()) {
      return;
    }

    setState(() {
      _isWaitingForRematch = true;
      _opponentRequestedRematch = false;
    });

    var consumedFriendMatch = false;
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
      if (_isFriendMode) {
        consumedFriendMatch =
            await FriendMatchLimitManager.instance.consumeMatch();
        if (!consumedFriendMatch) {
          if (mounted) {
            setState(() {
              _isWaitingForRematch = false;
            });
            await _showCyberAlertDialog(
              'フレンド対戦',
              '本日の無料フレンド対戦回数を使い切りました。',
            );
          }
          return;
        }
      }
      await _multiplayerManager.requestRematch();
    } catch (error) {
      if (consumedFriendMatch) {
        await FriendMatchLimitManager.instance.restoreConsumedMatch();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isWaitingForRematch = false;
      });
      await _showErrorDialog('再戦の送信に失敗しました', '$error');
    }
  }

  Future<bool> _ensureFriendMatchAllowanceForRematch() async {
    if (await FriendMatchLimitManager.instance.canStartMatch()) {
      return true;
    }
    if (!mounted) {
      return false;
    }

    if (!AppSettings.instance.canRequestRewardedAds) {
      await _showCyberAlertDialog(
        'フレンド対戦',
        '現在、動画広告による回復は利用できません。',
      );
      return false;
    }

    unawaited(RewardedAdManager.instance.warmUp());
    final shouldWatchAd = await _showFriendMatchRestoreDialog();
    if (!mounted || shouldWatchAd != true) {
      return false;
    }

    final rewarded = await RewardedAdManager.instance.showDoubleRewardAd();
    if (!mounted) {
      return false;
    }
    if (!rewarded) {
      await _showCyberAlertDialog('広告エラー', '動画の視聴が完了しませんでした。');
      return false;
    }

    await FriendMatchLimitManager.instance.addRewardedMatches();
    if (!mounted) {
      return false;
    }
    await _showCyberAlertDialog(
      'フレンド対戦',
      'フレンド対戦が2戦分回復しました。',
    );
    return false;
  }

  Future<bool?> _showFriendMatchRestoreDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _friendPink,
          title: 'フレンド対戦',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '本日の無料フレンド対戦回数を使い切りました。\n動画広告を見ると2戦分回復します。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'キャンセル',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '動画広告を見る',
                      accentColor: _friendPink,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _leaveOnlineBattle() {
    _clearAllPendingAttacks();
    unawaited(_returnHomeAfterMatch());
  }

  Future<void> _returnFriendLobbyAfterResult() async {
    if (!_isFriendMode || _isReturningToHome) {
      _leaveOnlineBattle();
      return;
    }
    try {
      _clearAllPendingAttacks();
      _rankedAutoStartTimer?.cancel();
      _rankedAutoStartScheduled = false;
      await _stopBattleBgm();
      await _multiplayerManager.returnFriendRoomToLobby();
      if (!mounted) {
        return;
      }
      _playerGame.configureGridRows(_playerBoardRows);
      _cpuGame?.configureGridRows(_opponentBoardRows);
      setState(() {
        _onlineGameStarted = false;
        _friendLobbyMatchAllowanceConsumed = false;
        _onlineResultMessage = null;
        _onlineResultWasForfeit = false;
        _onlineResultWasOfflineForfeit = false;
        _activeResultWasForfeit = false;
        _battleResultWasOfflineForfeitLoss = false;
        _battleResultStarted = false;
        _resultRevealPending = false;
        _isWaitingForRematch = false;
        _opponentRequestedRematch = false;
        _opponentUnavailableForRematch = false;
        _opponentRealtimeDisconnected = false;
        _pendingPreBattleForfeitWin = false;
        _readyGoOverlayText = null;
        _autoReadyRequested = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog('ロビーへ戻れませんでした', '$error');
    }
  }

  Future<void> _showFriendDisconnectedReturnHome() async {
    if (!mounted || _friendDisconnectDialogShown || _isReturningToHome) {
      return;
    }
    _friendDisconnectDialogShown = true;
    _isReturningToHome = true;
    _clearAllPendingAttacks();
    _rankedAutoStartTimer?.cancel();
    _playerGame.pauseEngine();
    _cpuGame?.pauseEngine();
    await _stopBattleBgm();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _friendPink,
          title: '接続切断',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '接続が切断されました。\nホーム画面へ戻ります。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              _buildCyberDialogButton(
                label: '確認',
                accentColor: _friendPink,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
    try {
      await _multiplayerManager.leaveRoom(forceRemove: true);
      await GameActivityPresence.instance.exit();
    } catch (_) {
      // 切断時の後始末に失敗しても、ユーザーはホームへ戻す。
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
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
          ballSkinId: task.ballSkinId,
          effectSkinId: task.effectSkinId,
        ),
      );
    });
    _pendingAttackTimers.add(timer);
  }

  Future<void> _applyAttackToOpponent(OjamaTask task) async {
    final connected = await _ensureServerConnection(
      forfeitRankedOnOffline: widget.isRankedMode || _isOnlineMode,
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
        _scheduleRankedOfflineForfeitIfNeeded();
      }
    }
  }

  Future<void> _consumeQueuedIncomingOjamaAfterReconnect() async {
    try {
      final tasks = await _multiplayerManager.consumeQueuedIncomingOjama();
      if (!mounted || tasks.isEmpty) {
        return;
      }
      for (final task in tasks) {
        _handleAttackReceived(task);
      }
    } catch (_) {
      // 復帰時の補助取得なので、対戦進行自体は止めない。
    }
  }

  Future<void> _commitPendingOfflineForfeitAfterReconnect() async {
    if (!_pendingOfflineForfeitCommit) {
      return;
    }
    final recorded = await _multiplayerManager.recordOfflineForfeitLoss();
    if (recorded && mounted) {
      _pendingOfflineForfeitCommit = false;
      await _multiplayerManager.saveActiveSession(
        isArenaMode: widget.isArenaMode,
        snapshot: const {
          'abandonReason': 'offline',
          'resultKnown': true,
          'isWin': false,
        },
      );
    }
  }

  Future<void> _presentBattleResult({
    required bool playerWon,
    required bool opponentCrossedDeathLine,
    bool resultWasForfeit = false,
    bool resultWasOfflineForfeit = false,
  }) async {
    if (_battleResultStarted || _resultRevealPending) {
      return;
    }

    if (_isStampGridVisible && mounted) {
      setState(() {
        _isStampGridVisible = false;
      });
    }
    _battleResultStarted = true;
    _resultRevealPending = true;
    _activeResultWasForfeit = resultWasForfeit;
    _battleResultWasOfflineForfeitLoss = !playerWon && resultWasOfflineForfeit;
    if (widget.isRankedMode && !widget.isArenaMode) {
      _markRankedResultKnownIfNeeded(isWin: playerWon);
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
        _activeResultWasForfeit = false;
        _isStampGridVisible = false;
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
        if (widget.isRankedMode && !widget.isArenaMode) {
          await RankedInterstitialDebtManager.instance
              .recordRankedMatchCompleted(
            isHumanOpponent: false,
          );
        } else {
          await RankedInterstitialDebtManager.instance.recordMatchCompleted(
            InterstitialDebtKind.computer,
          );
        }
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
      setState(() {
        _activeResultWasForfeit = false;
        _isStampGridVisible = false;
        _resultRevealPending = false;
      });
      if (widget.isRankedMode && !widget.isArenaMode) {
        await _applyRankedBotRatingResult(isWin: playerWon);
        if (_rankedRatingChange == null) {
          return;
        }
      }
      if (!mounted) {
        return;
      }
      unawaited(
        _applyMatchExpReward(
          isWin: playerWon,
          grantLocalExp: true,
        ),
      );
      return;
    }

    if (_isOnlineMode) {
      if (!_resultCoinTripleClaimed) {
        if (widget.isRankedMode && !widget.isArenaMode) {
          await RankedInterstitialDebtManager.instance
              .recordRankedMatchCompleted(
            isHumanOpponent: true,
          );
        }
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
      unawaited(_recordArenaResult(isWin: playerWon));
      unawaited(_multiplayerManager.clearSavedSession());
      setState(() {
        _onlineResultMessage = playerWon ? 'YOU WIN!!' : 'YOU LOSE...';
        _onlineResultWasForfeit = resultWasForfeit;
        _onlineResultWasOfflineForfeit = resultWasOfflineForfeit;
        _isWaitingForRematch = false;
        _isStampGridVisible = false;
        _resultRevealPending = false;
      });
      if (widget.isRankedMode && !widget.isArenaMode) {
        await _applyRankedRatingResult(
          isWin: playerWon,
          applyOpponentResult: resultWasForfeit,
          reason: resultWasForfeit && playerWon
              ? 'opponent_offline_forfeit'
              : resultWasOfflineForfeit
                  ? 'offline_forfeit'
                  : null,
        );
        if (_rankedRatingChange == null) {
          return;
        }
      }
      if (!mounted) {
        return;
      }
      unawaited(
        _applyMatchExpReward(
          isWin: playerWon,
          isForfeitWin: resultWasForfeit && playerWon,
          grantLocalExp: true,
        ),
      );
      return;
    }

    if (widget.isDailyMode) {
      unawaited(_applyBattleCoinReward(isWin: true));
      unawaited(_applySoloExpReward());
      unawaited(_recordDailyChallengeStats());
      setState(() {
        _activeResultWasForfeit = false;
        _isStampGridVisible = false;
        _resultRevealPending = false;
      });
      return;
    }

    unawaited(_applyBattleCoinReward(isWin: false));
    if (!_resultCoinTripleClaimed) {
      await RankedInterstitialDebtManager.instance.recordMatchCompleted(
        InterstitialDebtKind.endless,
      );
      unawaited(InterstitialAdManager.instance.warmUp());
    }
    unawaited(_applySoloExpReward());
    unawaited(_recordSoloStats());
    setState(() {
      _activeResultWasForfeit = false;
      _isStampGridVisible = false;
      _resultRevealPending = false;
    });
  }

  OjamaTask? _createOjamaTaskForAttack(
    WazaType waza,
    BallColor? color, {
    String? ballSkinId,
    String? effectSkinId,
  }) {
    final resolvedBallSkinId =
        ballSkinId ?? _playerDataManager.equippedBallSkinId;
    final resolvedEffectSkinId =
        effectSkinId ?? _playerDataManager.equippedOjamaEffectId;
    switch (waza) {
      case WazaType.hexagon:
        return OjamaTask(
          OjamaType.hexagonSet,
          ballSkinId: resolvedBallSkinId,
          effectSkinId: resolvedEffectSkinId,
        );
      case WazaType.pyramid:
        return OjamaTask(
          OjamaType.pyramidSet,
          ballSkinId: resolvedBallSkinId,
          effectSkinId: resolvedEffectSkinId,
        );
      case WazaType.straight:
        final startColor = color ?? BallColor.blue;
        return OjamaTask(
          OjamaType.straightSet,
          startColor: startColor,
          presetColors: _generateStraightOjamaColors(startColor),
          ballSkinId: resolvedBallSkinId,
          effectSkinId: resolvedEffectSkinId,
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

  Widget _buildPieceIcon(
    List<BallColor> colors, {
    required double size,
    required String ballSkinId,
  }) {
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
            child: MiniBallWidget(
              ballColor: colors[0],
              size: size,
              ballSkinId: ballSkinId,
            ),
          ),
          Positioned(
            left: 0,
            top: vSpacing,
            child: MiniBallWidget(
              ballColor: colors[1],
              size: size,
              ballSkinId: ballSkinId,
            ),
          ),
          Positioned(
            left: hSpacing,
            top: vSpacing,
            child: MiniBallWidget(
              ballColor: colors[2],
              size: size,
              ballSkinId: ballSkinId,
            ),
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
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
    return GamePressable(
      enabled: enabled,
      borderRadius: BorderRadius.circular(14),
      onTapDown: () {
        _playUiTap();
        onDown();
      },
      onTapUp: onUp,
      onTapCancel: onUp,
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

class _ResultShareData {
  const _ResultShareData({
    required this.isRanked,
    required this.isEndless,
    required this.isDaily,
    required this.seasonLabel,
    required this.modeLabel,
    required this.title,
    required this.titleColor,
    required this.accentColor,
    required this.scoreLabel,
    required this.endlessLevelLabel,
    required this.endlessBestScoreLabel,
    required this.endlessRankLabel,
    required this.ratingDeltaLabel,
    required this.newRatingLabel,
    required this.rankLabel,
    required this.dailyWinsLabel,
    required this.dailyWinRankLabel,
    required this.player,
    required this.opponent,
    required this.inviteCode,
    required this.generatedAtLabel,
    required this.appIcon,
    required this.seasonBadgeIcon,
    required this.storeQrImage,
    required this.coinIcon,
    required this.trophyIcon,
  });

  final bool isRanked;
  final bool isEndless;
  final bool isDaily;
  final String seasonLabel;
  final String modeLabel;
  final String title;
  final Color titleColor;
  final Color accentColor;
  final String scoreLabel;
  final String endlessLevelLabel;
  final String endlessBestScoreLabel;
  final String endlessRankLabel;
  final String ratingDeltaLabel;
  final String newRatingLabel;
  final String rankLabel;
  final String dailyWinsLabel;
  final String dailyWinRankLabel;
  final _ShareParticipant player;
  final _ShareParticipant opponent;
  final String inviteCode;
  final String generatedAtLabel;
  final ui.Image? appIcon;
  final ui.Image? seasonBadgeIcon;
  final ui.Image? storeQrImage;
  final ui.Image? coinIcon;
  final ui.Image? trophyIcon;

  String get shareText {
    final buffer = StringBuffer('ヘキサゴンのリザルトをシェアしました！');
    if (scoreLabel.isNotEmpty) {
      buffer.write('\nスコア: $scoreLabel点');
    } else {
      buffer.write('\n$title');
      if (newRatingLabel.isNotEmpty) {
        buffer.write(' / レート: $newRatingLabel');
      }
      if (ratingDeltaLabel.isNotEmpty) {
        buffer.write(' ($ratingDeltaLabel)');
      }
      if (rankLabel.isNotEmpty) {
        buffer.write(' / 順位: $rankLabel');
      }
    }
    return buffer.toString();
  }
}

class _ShareParticipant {
  const _ShareParticipant({
    required this.name,
    required this.iconId,
    required this.frameId,
    required this.badgeIds,
    required this.ratingLabel,
    required this.sideColor,
    required this.iconImage,
  });

  final String name;
  final String iconId;
  final String frameId;
  final List<String> badgeIds;
  final String ratingLabel;
  final Color sideColor;
  final ui.Image? iconImage;
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
