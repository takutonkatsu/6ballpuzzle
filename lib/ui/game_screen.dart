import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../audio/seamless_bgm.dart';
import '../audio/sfx.dart';
import '../data/models/badge_item.dart';
import '../data/player_data_manager.dart';
import '../game/arena_manager.dart';
import '../game/components/ball_component.dart';
import '../game/game_models.dart';
import '../data/models/game_item.dart';
import '../game/mission_manager.dart';
import '../game/puzzle_game.dart';
import '../network/multiplayer_manager.dart';
import '../network/ranking_manager.dart';
import 'components/banner_ad_widget.dart';
import 'components/interstitial_ad_manager.dart';
import 'components/stamp_widget.dart';
import 'home_screen.dart';

class GameScreen extends StatefulWidget {
  final bool isCpuMode;
  final bool isOnlineMultiplayer;
  final String? roomId;
  final bool isHost;
  final bool isRankedMode;
  final bool isArenaMode;
  final CPUDifficulty cpuDifficulty;

  const GameScreen({
    super.key,
    this.isCpuMode = false,
    this.isOnlineMultiplayer = false,
    this.roomId,
    this.isHost = false,
    this.isRankedMode = false,
    this.isArenaMode = false,
    this.cpuDifficulty = CPUDifficulty.hard,
  });

  const GameScreen.online({
    super.key,
    this.roomId,
    this.isHost = false,
    this.isRankedMode = false,
    this.isArenaMode = false,
  })  : cpuDifficulty = CPUDifficulty.hard,
        isCpuMode = false,
        isOnlineMultiplayer = true;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const double _gameViewportWidth = 308;
  static const double _gameViewportHeight = 480;
  static const double _gridBallDiameter = 30;
  static const double _compactStampWidth = 118;
  static const Duration _postReadyGoBoardPause = Duration(milliseconds: 350);
  static const Duration _preReadyDelay = Duration(milliseconds: 500);
  static const Duration _battleBgmDuration = Duration(microseconds: 60007438);
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
  bool _isWaitingForRematch = false;
  bool _isDisconnectDialogVisible = false;
  bool _opponentDisconnectedDuringBattle = false;
  bool _isReturningToHome = false;
  bool? _cpuBattlePlayerWon;
  bool _rankedRatingApplied = false;
  RankedRatingChange? _rankedRatingChange;
  Timer? _rankedAutoStartTimer;
  bool _rankedAutoStartScheduled = false;
  bool _matchingSfxPlayed = false;
  bool _autoReadyRequested = false;
  String? _readyGoOverlayText;
  bool _isBattleBgmPlaying = false;
  bool _resultRevealPending = false;
  bool _arenaResultApplied = false;
  ArenaMatchResult? _arenaMatchResult;
  bool _matchExpApplied = false;
  int? _matchExpEarned;
  bool _soloExpApplied = false;
  int? _soloExpEarned;
  bool _didLevelUpFromResultExp = false;
  int? _resultLevelAfterExp;
  final Map<WazaType, int> _playerWazaCounts = {
    WazaType.straight: 0,
    WazaType.pyramid: 0,
    WazaType.hexagon: 0,
  };

  // Stamp States
  bool _isStampCoolingDown = false;
  GameItem? _currentFloatingStamp;
  GameItem? _opponentFloatingStamp;
  Timer? _myStampTimer;
  Timer? _opponentStampTimer;
  DateTime? _ignoreEmptyOpponentBoardUntil;
  bool _isRestoringOnlineSession = false;
  Map<String, dynamic>? _pendingOpponentBoardData;
  Map<String, dynamic>? _pendingOpponentPieceData;

  final List<Timer> _pendingAttackTimers = [];

  bool get _isOnlineMode => widget.isOnlineMultiplayer;
  bool get _showsOpponentBoard => widget.isCpuMode || _isOnlineMode;
  bool get _blocksOnlineExit =>
      _isOnlineMode && _onlineGameStarted && _onlineResultMessage == null;
  bool get _shouldPreserveOnlineSession =>
      _isOnlineMode &&
      _onlineGameStarted &&
      !_isReturningToHome &&
      _onlineResultMessage == null;

  String get _myDisplayName {
    if (_isOnlineMode) {
      final roleId = _multiplayerManager.myRoleId;
      return _displayNameForRole(roleId) ??
          _multiplayerManager.displayPlayerName;
    }
    return _multiplayerManager.displayPlayerName;
  }

  String get _opponentDisplayName {
    if (widget.isCpuMode) {
      return 'CPU';
    }
    if (_isOnlineMode) {
      return _displayNameForRole(_multiplayerManager.opponentRoleId) ??
          'Opponent';
    }
    return '';
  }

  int get _arenaRewardExp => _arenaMatchResult?.reward.exp ?? 0;

  int? get _totalResultExpEarned {
    final baseExp = _matchExpEarned ?? _soloExpEarned;
    if (baseExp == null) {
      return null;
    }
    return baseExp + _arenaRewardExp;
  }

  bool get _isFriendMode =>
      _isOnlineMode && !widget.isRankedMode && !widget.isArenaMode;

  int get _currentPlayerScore => _playerGame.scoreManager.state.value.score;

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      useConstantFallSpeed: false,
      wallColor: Colors.blueAccent,
    );

    if (_isOnlineMode) {
      _cpuGame = PuzzleGame(
        isCpuMode: false,
        seed: gameSeed,
        autoStart: false,
        isRemotePlayerMode: true,
        wallColor: Colors.redAccent,
      );
      _cpuGame!.onGameOverTriggered = () {
        if (_opponentDisconnectedDuringBattle) {
          unawaited(_showOpponentGameOverResult());
        }
      };
      _cpuGame!.onBoardUpdated = (_) {
        if (_opponentDisconnectedDuringBattle) {
          unawaited(_syncDisconnectedOpponentSnapshot());
        }
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
      if (_isOnlineMode) {
        unawaited(_multiplayerManager.saveActiveSession(
          isArenaMode: widget.isArenaMode,
        ));
      }
      if (_room == null && widget.roomId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _restoreOnlineSession();
        });
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

    if (widget.isCpuMode) {
      _cpuGame = PuzzleGame(
        isCpuMode: true,
        seed: gameSeed,
        autoStart: false,
        wallColor: Colors.redAccent,
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
        unawaited(_multiplayerManager.sendBoardState(boardData));
        unawaited(_persistOnlineSessionSnapshot());
      }
    };
    _playerGame.onActivePieceChanged =
        (action, x, y, rotation, colors, dropSeed) {
      if (_isOnlineMode && _onlineGameStarted) {
        unawaited(
          _multiplayerManager.sendActivePiece(
            x,
            y,
            rotation,
            colors,
            action,
            dropSeed,
            _playerGame.nextPieceColors.value
                .map((color) => color.index)
                .toList(),
          ),
        );
        unawaited(_persistOnlineSessionSnapshot());
      }
    };
    _playerGame.onOjamaSpawned = (ojamaData, dropSeed) {
      if (_isOnlineMode && _onlineGameStarted) {
        unawaited(_multiplayerManager.sendOjamaSpawn(ojamaData, dropSeed));
        unawaited(_persistOnlineSessionSnapshot());
      }
    };
    _playerGame.onGameOverTriggered = () {
      if (widget.isCpuMode) {
        unawaited(_presentBattleResult(playerWon: false, opponentCrossedDeathLine: false));
        return;
      }
      if (_isOnlineMode) {
        unawaited(_multiplayerManager.declareGameOver());
        unawaited(_presentBattleResult(playerWon: false, opponentCrossedDeathLine: false));
      } else {
        unawaited(_presentBattleResult(playerWon: false, opponentCrossedDeathLine: false));
      }
    };
    _playerGame.onWazaFired = (waza, color) {
      _recordPlayerWaza(waza);
      if (_isOnlineMode) {
        final task = _createOjamaTaskForAttack(waza, color);
        if (task != null) {
          unawaited(_applyAttackToOpponent(task));
        }
      } else if (_cpuGame != null) {
        _sendOjamaWithDelay(_cpuGame!, waza, color);
      }
    };

    if (widget.isCpuMode && _cpuGame != null) {
      _cpuGame!.onWazaFired =
          (waza, color) => _sendOjamaWithDelay(_playerGame, waza, color);
    }

    if (!_isOnlineMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startLocalBattleWithReadyGo(localGameSeed));
      });
    }
  }

  void _sendOjamaWithDelay(
    PuzzleGame targetGame,
    WazaType waza,
    BallColor? color,
  ) {
    late Timer timer;
    timer = Timer(const Duration(seconds: 2), () {
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

  void _clearAllPendingAttacks() {
    for (final t in _pendingAttackTimers) {
      t.cancel();
    }
    _pendingAttackTimers.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isOnlineMode) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistOnlineSessionSnapshot());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearAllPendingAttacks();
    _rankedAutoStartTimer?.cancel();
    if (!_isReturningToHome) {
      unawaited(_stopBattleBgm());
    }
    if (widget.isOnlineMultiplayer && !_isReturningToHome) {
      if (_shouldPreserveOnlineSession) {
        unawaited(_persistOnlineSessionSnapshot());
        unawaited(_multiplayerManager.suspendActiveSession());
      } else {
        unawaited(_multiplayerManager.leaveRoom());
      }
    }
    _playerFocusNode.dispose();
    super.dispose();
  }

  void _handleOpponentStampReceived(String stampId) {
    if (!mounted) return;
    final stamp = GameItemCatalog.byId(stampId);
    if (stamp != null) {
      setState(() {
        _opponentFloatingStamp = stamp;
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

    unawaited(_multiplayerManager.sendStamp(stamp.id));

    setState(() {
      _currentFloatingStamp = stamp;
      _isStampCoolingDown = true;
    });

    Timer(const Duration(seconds: 5), () {
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F13).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SEND STAMP',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 3)],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: GameItemCatalog.commonStamps.map((stamp) {
                  final ownedList = PlayerDataManager.instance.ownedItems;
                  final ownedMatch = ownedList.firstWhere(
                    (item) => item.id == stamp.id,
                    orElse: () => stamp,
                  );

                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      _sendStamp(ownedMatch);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.06),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.36),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: StampWidget(
                          item: ownedMatch,
                          level: ownedMatch.level,
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
                  if (!widget.isCpuMode && !_isOnlineMode)
                    _buildScoreWidget(_playerGame),
                  Expanded(child: _buildPlayerArea(_playerGame)),
                  _buildControls(_playerGame),
                  const SizedBox(
                    height: 50.0,
                    width: double.infinity,
                    child: BannerAdWidget(),
                  ),
                ],
              ),
              if (_isOnlineMode)
                _buildOnlineOverlay()
              else
                _buildGlobalOverlay(),
              if (widget.isArenaMode) _buildArenaRecordBadge(),
              Positioned(
                top: 8,
                left: 8,
                child: _buildBattleSettingsButton(),
              ),
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
                    scale: 2 / 3,
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
  }) {
    final normalizedScale = compact ? scale : 1.0;
    return Semantics(
      label: 'stamp',
      child: IgnorePointer(
        child: Container(
          width: compact ? _compactStampWidth * normalizedScale : null,
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
              color: Colors.cyanAccent.withValues(alpha: compact ? 0.36 : 0.5),
              width: compact ? 1.2 * normalizedScale : 2,
            ),
            boxShadow: compact
                ? [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.18),
                      blurRadius: 8 * normalizedScale,
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Colors.cyanAccent,
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: StampWidget(
              item: stamp,
              level: stamp.level,
              forceLarge: !compact,
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
              color: Colors.lightBlueAccent.withValues(alpha: 0.72),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.lightBlueAccent.withValues(alpha: 0.22),
                blurRadius: 12,
              ),
            ],
          ),
          child: Text(
            'アリーナ  $wins勝 $losses敗',
            style: const TextStyle(
              color: Colors.lightBlueAccent,
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

    final rewardText = result?.isCompleted == true && reward != null
        ? 'コイン +${reward.coins}'
        : '$wins勝 $losses敗';

    return _buildResultInfoRow(
      label: result?.isCompleted == true ? 'アリーナ報酬' : 'アリーナ',
      value: rewardText,
      color: Colors.lightBlueAccent,
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
          color: Colors.greenAccent,
        ),
        if (_didLevelUpFromResultExp) ...[
          const SizedBox(height: 8),
          _buildResultInfoRow(
            label: 'LEVEL UP',
            value: _resultLevelAfterExp == null
                ? ''
                : 'Lv.${_resultLevelAfterExp!}',
            color: Colors.cyanAccent,
          ),
        ],
      ],
    );
  }

  Widget _buildResultScoreSummary() {
    return _buildResultInfoRow(
      label: 'SCORE',
      value: '$_currentPlayerScore',
      color: Colors.amberAccent,
    );
  }

  Widget _buildOnlineMatchSummary() {
    if (widget.isArenaMode) {
      final wins = _arenaMatchResult?.wins ?? _arenaManager.currentWins;
      final losses = _arenaMatchResult?.losses ?? _arenaManager.currentLosses;
      return _buildResultInfoRow(
        label: 'アリーナ',
        value: '$wins勝 $losses敗',
        color: Colors.lightBlueAccent,
      );
    }
    if (widget.isRankedMode) {
      return _buildRankedRatingChange();
    }
    return _buildResultInfoRow(
      label: 'BATTLE',
      value: 'FRIEND MATCH',
      color: Colors.cyanAccent,
    );
  }

  Widget _buildResultInfoRow({
    required String label,
    required String value,
    required Color color,
    String? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
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
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: color,
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
    return Container(
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ValueListenableBuilder(
        valueListenable: game.scoreManager.state,
        builder: (context, state, child) {
          return Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'SPEED LV',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${state.level}',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'SCORE',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${state.score}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayerArea(PuzzleGame game) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePanelWidth = constraints.maxWidth / 5;
        final isSoloMode = !_isOnlineMode && !widget.isCpuMode;
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
                  onTapDown: (_) => game.triggerHardDrop(),
                  child: const SizedBox.expand(),
                ),
              ),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (_) => game.triggerHardDrop(),
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
                      onTapDown: (_) => game.triggerHardDrop(),
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
                          badgeIds:
                              _badgeIdsForRole(_multiplayerManager.myRoleId),
                          playerIconId:
                              _playerIconIdForRole(_multiplayerManager.myRoleId),
                        ),
                        const SizedBox(height: 16),
                        _buildNextBadge(
                          game,
                          isCpu: false,
                          ballSize: nextBallSize,
                        ),
                        if (_isOnlineMode) ...[
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _isStampCoolingDown ? null : _showStampGrid,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.cyanAccent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      Colors.cyanAccent.withValues(alpha: 0.58),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.cyanAccent.withValues(alpha: 0.12),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.chat,
                                color: Colors.cyanAccent.withValues(
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
                      badgeIds:
                          _badgeIdsForRole(_multiplayerManager.opponentRoleId),
                      playerIconId:
                          _playerIconIdForRole(_multiplayerManager.opponentRoleId),
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

  Widget _buildBattleSettingsButton() {
    final canOpen = _playerGame.gameStateWrapper.value == GameState.playing &&
        _readyGoOverlayText == null &&
        !_resultRevealPending &&
        _onlineResultMessage == null &&
        _cpuBattlePlayerWon == null;
    return Tooltip(
      message: 'Settings',
      child: InkWell(
        onTap: !canOpen
            ? null
            : () {
          _playUiTap();
          _showSettingsMenu();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: canOpen ? 0.34 : 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withValues(alpha: canOpen ? 0.08 : 0.03),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(
            Icons.settings,
            color: Colors.cyanAccent.withValues(alpha: canOpen ? 1 : 0.36),
            size: 20,
          ),
        ),
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
                  shadows: [
                    Shadow(color: Colors.white, blurRadius: 10),
                    Shadow(color: Colors.amberAccent, blurRadius: 18),
                  ],
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
    List<String> badgeIds = const [],
    String playerIconId = 'default',
  }) {
    final neonColor = isCpu ? Colors.pinkAccent : Colors.cyanAccent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 112,
              height: 38,
              padding: const EdgeInsets.fromLTRB(30, 10, 10, 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E28),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: neonColor.withValues(alpha: 0.8),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: neonColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: neonColor, blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 9,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: neonColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: neonColor.withValues(alpha: 0.42),
                  ),
                ),
                child: Icon(
                  _playerIconData(playerIconId),
                  size: 10,
                  color: neonColor,
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
        if (badgeIds.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildBadgeIconRow(badgeIds),
        ],
      ],
    );
  }

  List<String> _badgeIdsForRole(String? roleId) {
    if (roleId == null) {
      return const [];
    }
    return _room?.players[roleId]?.badgeIds ?? const [];
  }

  Widget _buildBadgeIconRow(List<String> badgeIds) {
    final badges = badgeIds
        .map(BadgeCatalog.findById)
        .whereType<BadgeItem>()
        .take(2)
        .toList();
    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final badge in badges)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.7),
              ),
            ),
            child: Icon(
              badge.icon,
              size: 14,
              color: Colors.amberAccent,
            ),
          ),
      ],
    );
  }

  Widget _buildNextBadge(
    PuzzleGame game, {
    required bool isCpu,
    required double ballSize,
  }) {
    final neonColor = isCpu ? Colors.pinkAccent : Colors.cyanAccent;
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
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: neonColor.withValues(alpha: 0.15),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'NEXT',
            style: TextStyle(
              color: neonColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: neonColor, blurRadius: 2)],
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
                  style: const TextStyle(
                    fontSize: 48,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w900,
                    color: Colors.orangeAccent,
                    letterSpacing: 2,
                    shadows: [
                      Shadow(color: Colors.orangeAccent, blurRadius: 16),
                      Shadow(color: Colors.white, blurRadius: 4),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final gameOver = pState == GameState.gameover ||
              (cState == GameState.gameover && widget.isCpuMode);
          if (!gameOver || _resultRevealPending) {
            return const SizedBox.shrink();
          }

          final cpuPlayerWon =
              _cpuBattlePlayerWon ?? (pState != GameState.gameover);
          final title =
              widget.isCpuMode ? (cpuPlayerWon ? '勝利' : '敗北') : 'GAME OVER';
          final titleColor = widget.isCpuMode
              ? (cpuPlayerWon ? Colors.cyanAccent : Colors.pinkAccent)
              : Colors.orangeAccent;

          return _buildUnifiedResultSheet(
            title: title,
            titleColor: titleColor,
          children: [
              _buildResultExpSummary(),
              if (!widget.isCpuMode) ...[
                const SizedBox(height: 12),
                _buildResultScoreSummary(),
              ],
              const SizedBox(height: 18),
              if (!widget.isCpuMode) ...[
                _buildCyberResultButton(
                  label: 'RESTART',
                  baseColor: Colors.cyanAccent,
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
                label: 'HOME',
                baseColor: Colors.white54,
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
    final textColor = win ? Colors.cyanAccent : Colors.pinkAccent;

    return Positioned.fill(
      child: _buildUnifiedResultSheet(
        title: win ? '勝利' : '敗北',
        titleColor: textColor,
        children: [
          _buildResultExpSummary(),
          const SizedBox(height: 12),
          _buildOnlineMatchSummary(),
          if (widget.isArenaMode) ...[
            const SizedBox(height: 12),
            _buildArenaResultSummary(),
          ],
          const SizedBox(height: 18),
          if (!widget.isRankedMode) ...[
            _buildCyberResultButton(
              label: _isWaitingForRematch ? '相手の準備待ち...' : 'REMATCH',
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
            label: 'HOME',
            baseColor: Colors.white54,
            isWaiting: false,
            onPressed: () {
              _leaveOnlineBattle();
            },
          ),
        ],
      ),
    );
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
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: titleColor.withValues(alpha: 0.24),
                      blurRadius: 24,
                    ),
                  ],
                ),
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
                        shadows: [
                          Shadow(color: titleColor, blurRadius: 10),
                        ],
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

  Widget _buildRankedRatingChange() {
    final change = _rankedRatingChange;
    if (change == null) {
      return const Text(
        'レート更新中...',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final isPositive = change.delta >= 0;
    final deltaText = isPositive ? '+${change.delta}' : '${change.delta}';
    final glowColor = isPositive ? Colors.cyanAccent : Colors.pinkAccent;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        final animatedRating = change.oldRating +
            ((change.newRating - change.oldRating) * value).round();
        return _buildResultInfoRow(
          label: 'レート',
          value: '$animatedRating',
          trailing: deltaText,
          color: glowColor,
        );
      },
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
          border: Border.all(color: baseColor.withValues(alpha: 0.8), width: 2),
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.2),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: [Shadow(color: baseColor, blurRadius: 8)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadyGoOverlay() {
    final text = _readyGoOverlayText!;
    final isGo = text == 'GO!';
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: isGo ? 0.18 : 0.38),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                text,
                key: ValueKey(text),
                style: TextStyle(
                  color: isGo ? Colors.amberAccent : Colors.white,
                  fontSize: isGo ? 56 : 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 16),
                  ],
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
                  color: (widget.isArenaMode
                          ? Colors.lightBlueAccent
                          : widget.isRankedMode
                              ? Colors.pinkAccent
                              : Colors.cyanAccent)
                      .withValues(alpha: 0.75),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (widget.isArenaMode
                            ? Colors.lightBlueAccent
                            : widget.isRankedMode
                                ? Colors.pinkAccent
                                : Colors.cyanAccent)
                        .withValues(alpha: 0.32),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.purpleAccent.withValues(alpha: 0.16),
                    blurRadius: 36,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isArenaMode
                        ? 'アリーナマッチが成立しました'
                        : widget.isRankedMode
                            ? 'ランダムマッチが成立しました'
                            : isHost
                                ? 'フレンドバトルの部屋を作成しました'
                                : 'フレンドバトルに参加しました',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      shadows: [
                        Shadow(color: Colors.cyanAccent, blurRadius: 10),
                      ],
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
                  Text(
                    showAutoStart && canShowReady
                        ? 'マッチ成立です。まもなく自動で開始します。'
                        : canShowReady && opponentName != null
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
                  _buildLobbyStatusRow(
                    _displayNameForRole('host') ?? 'プレイヤー',
                    hostReady,
                    isOccupied: room.players['host'] != null,
                    badgeIds: room.players['host']?.badgeIds ?? const [],
                    playerIconId:
                        room.players['host']?.playerIconId ?? 'default',
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
                    subLabel: widget.isArenaMode
                        ? _buildArenaLobbySubLabel(isHostSlot: false)
                        : widget.isRankedMode
                            ? _buildLobbyRatingLabel(
                                room.players['guest']?.rating)
                            : null,
                  ),
                  const SizedBox(height: 28),
                  if (showAutoStart && canShowReady)
                    const SizedBox(
                      height: 56,
                      child: Center(
                        child: Text(
                          'まもなく開始します...',
                          style: TextStyle(
                            color: Colors.amberAccent,
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
                            : _handleReadyPressed,
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
                        onPressed: _cancelFriendLobby,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.pinkAccent,
                          side: BorderSide(
                            color: Colors.pinkAccent.withValues(alpha: 0.8),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'CANCEL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
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
    _playUiTap();
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

  Widget _buildLobbyStatusRow(
    String name,
    bool isReady, {
    required bool isOccupied,
    String? subLabel,
    List<String> badgeIds = const [],
    String playerIconId = 'default',
  }) {
    final accentColor = isOccupied ? Colors.cyanAccent : Colors.white38;
    final nameColor = isOccupied ? Colors.white : Colors.white54;
    final statusText = isOccupied ? (isReady ? 'READY' : '') : '未参加';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1220).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: isOccupied ? 0.34 : 0.16),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: accentColor.withValues(alpha: 0.42)),
            ),
            child: Icon(
              _playerIconData(playerIconId),
              color: accentColor,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: nameColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  !isOccupied ? '-' : (subLabel ?? '-'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
                if (isOccupied && badgeIds.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildBadgeIconRow(badgeIds),
                ],
              ],
            ),
          ),
          if (statusText.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isReady
                    ? Colors.greenAccent.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isReady
                      ? Colors.greenAccent.withValues(alpha: 0.65)
                      : Colors.white24,
                ),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: isReady ? Colors.greenAccent : Colors.white54,
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
    return rating == null ? 'レート -' : 'レート $rating';
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

  Future<void> _restoreOnlineSession() async {
    final roomId = widget.roomId;
    if (roomId == null) {
      return;
    }

    _isRestoringOnlineSession = true;
    _pendingOpponentBoardData = null;
    _pendingOpponentPieceData = null;
    try {
      final savedSession = await _multiplayerManager.loadSavedSession();
      final roleId = widget.isHost ? 'host' : 'guest';
      await _multiplayerManager.restoreSession(
        roomId: roomId,
        roleId: roleId,
      );
      if (!mounted) {
        return;
      }
      final room = _multiplayerManager.currentRoom;
      final roomSnapshot = await _multiplayerManager.loadRoomBattleSnapshot(
        roomId: roomId,
        roleId: roleId,
      );
      if (!mounted) {
        return;
      }
      final canResumeBattle = room?.status == 'playing' &&
          ((roomSnapshot != null && roomSnapshot.isNotEmpty) ||
              (savedSession != null &&
                  savedSession.roomId == roomId &&
                  savedSession.roleId == roleId &&
                  savedSession.snapshot != null));
      setState(() {
        _room = room;
        _opponentDisconnectedDuringBattle =
            room?.players[_multiplayerManager.opponentRoleId]?.status == 'left';
        if (canResumeBattle) {
          _onlineGameStarted = true;
        }
      });
      if (canResumeBattle) {
        await _playerGame.ready();
        if (_cpuGame != null) {
          await _cpuGame!.ready();
        }
        if (!mounted) {
          return;
        }
        final opponentRoleId = roleId == 'host' ? 'guest' : 'host';
        final opponentSnapshot = await _multiplayerManager.loadRoomBattleSnapshot(
          roomId: roomId,
          roleId: opponentRoleId,
        );
        if (!mounted) {
          return;
        }
        _playerGame.restoreFromSnapshot(
          roomSnapshot ??
              savedSession!.snapshot!,
        );
        if (_cpuGame != null) {
          if (opponentSnapshot != null && opponentSnapshot.isNotEmpty) {
            _cpuGame!.restoreFromSnapshot(opponentSnapshot);
            final opponentBoard = opponentSnapshot['board'];
            if (opponentBoard is Map && opponentBoard.isNotEmpty) {
              _ignoreEmptyOpponentBoardUntil = DateTime.now().add(
                const Duration(seconds: 2),
              );
            }
          } else {
            _cpuGame!.startGame(newSeed: room?.seed, spawnInitialPiece: false);
          }
          _cpuGame!.setAutonomousRemotePreviewEnabled(
            _opponentDisconnectedDuringBattle,
          );
        }
        _playerGame.resumeEngine();
        _cpuGame?.resumeEngine();
        _isRestoringOnlineSession = false;
        final pendingBoard = _pendingOpponentBoardData;
        final pendingPiece = _pendingOpponentPieceData;
        _pendingOpponentBoardData = null;
        _pendingOpponentPieceData = null;
        if (pendingBoard != null && pendingBoard.isNotEmpty) {
          _handleOpponentBoardUpdated(pendingBoard);
        }
        if (pendingPiece != null && pendingPiece.isNotEmpty) {
          _handleOpponentPieceUpdated(pendingPiece);
        }
        unawaited(_startBattleBgm());
        unawaited(_multiplayerManager.clearQueuedProxyOjamaForSelf());
        unawaited(_persistOnlineSessionSnapshot());
      }
    } catch (error) {
      _isRestoringOnlineSession = false;
      if (!mounted) {
        return;
      }
      await _showErrorDialog('ルーム接続に失敗しました', '$error');
    }
  }

  void _handleRoomUpdated(MultiplayerRoom room) {
    if (!mounted) {
      return;
    }

    setState(() {
      _room = room;
      _opponentDisconnectedDuringBattle =
          room.players[_multiplayerManager.opponentRoleId]?.status == 'left';
    });
    _cpuGame?.setAutonomousRemotePreviewEnabled(
      _opponentDisconnectedDuringBattle,
    );

    if (_onlineGameStarted) {
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
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await HapticFeedback.vibrate();
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
      await _multiplayerManager.setReady();
    } catch (_) {
      _autoReadyRequested = false;
    }
  }

  Future<void> _startLocalBattleWithReadyGo(int seed) async {
    if (!mounted) {
      return;
    }

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
    unawaited(FlameAudio.play(_readySfx, volume: 1.0));

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
  }

  Future<void> _startOnlineBattleWithReadyGo(int? seed) async {
    if (!mounted) {
      return;
    }

    _cpuBattlePlayerWon = null;
    _resetResultProgressionState();
    _rankedAutoStartTimer?.cancel();
    await Future<void>.delayed(_preReadyDelay);
    if (!mounted) {
      return;
    }
    setState(() {
      _onlineGameStarted = true;
      _opponentDisconnectedDuringBattle = false;
      _readyGoOverlayText = 'READY...';
    });
    unawaited(FlameAudio.play(_readySfx, volume: 1.0));

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
    _cpuGame?.startGame(newSeed: seed);
    _playerGame.startGame(newSeed: seed);
    unawaited(_persistOnlineSessionSnapshot());
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
      'bolt' => Icons.bolt,
      'star' => Icons.star,
      'gamepad' => Icons.sports_esports,
      _ => Icons.person,
    };
  }

  String _playerIconIdForRole(String? roleId) {
    if (roleId == null) {
      return 'default';
    }
    return _room?.players[roleId]?.playerIconId ??
        (roleId == _multiplayerManager.myRoleId
            ? _playerDataManager.equippedPlayerIconId
            : 'default');
  }

  void _handleOpponentBoardUpdated(Map<String, dynamic> boardData) {
    if (_isRestoringOnlineSession) {
      _pendingOpponentBoardData = Map<String, dynamic>.from(boardData);
      return;
    }
    final ignoreUntil = _ignoreEmptyOpponentBoardUntil;
    if (boardData.isEmpty &&
        ignoreUntil != null &&
        DateTime.now().isBefore(ignoreUntil)) {
      return;
    }
    if (boardData.isNotEmpty) {
      _ignoreEmptyOpponentBoardUntil = null;
    }
    _cpuGame?.applyRemoteBoardState(boardData);
  }

  void _handleOpponentPieceUpdated(Map<String, dynamic> pieceData) {
    if (_isRestoringOnlineSession) {
      _pendingOpponentPieceData = Map<String, dynamic>.from(pieceData);
      return;
    }
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
    if (dropSeed != null) {
      opponentGame.currentDropSeed = dropSeed;
      opponentGame.syncDropRng = Random(dropSeed);
    }
    if (nextColors.isNotEmpty) {
      opponentGame.nextPieceColors.value = nextColors;
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
        opponentGame.rotateLeft();
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.08,
          );
        }
        break;
      case 'rotate_right':
        opponentGame.rotateRight();
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
        opponentGame.startMovingLeft();
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.05,
          );
        }
        break;
      case 'stop_left':
        opponentGame.stopMovingLeft();
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.05,
          );
        }
        break;
      case 'start_right':
        opponentGame.startMovingRight();
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.05,
          );
        }
        break;
      case 'stop_right':
        opponentGame.stopMovingRight();
        if (x != null && y != null && rotation != null) {
          opponentGame.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.05,
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

  void _handleAttackReceived(OjamaTask task) {
    _queueOjamaTask(_playerGame, task);
    if (_isOnlineMode) {
      unawaited(_persistOnlineSessionSnapshot());
    }
  }

  void _handleOpponentOjamaSpawned(List<dynamic> ojamaData, int dropSeed) {
    _cpuGame?.spawnRemoteOjama(ojamaData, dropSeed);
  }

  void _handleOpponentGameOver() {
    if (_resultRevealPending || _onlineResultMessage != null) {
      return;
    }
    unawaited(_showOpponentGameOverResult());
  }

  Future<void> _showOpponentGameOverResult() async {
    if (_resultRevealPending || _onlineResultMessage != null) {
      return;
    }
    await _waitForOpponentOverflowVisualization();
    if (!mounted || _resultRevealPending || _onlineResultMessage != null) {
      return;
    }
    await _syncDisconnectedOpponentSnapshot();
    await _presentBattleResult(
      playerWon: true,
      opponentCrossedDeathLine: true,
    );
  }

  Future<void> _waitForOpponentOverflowVisualization() async {
    final opponentGame = _cpuGame;
    if (opponentGame == null) {
      return;
    }

    for (var i = 0; i < 12; i++) {
      final overflowVisible = opponentGame.hasOverflowedDeathLine;
      final ojamaSettled = !opponentGame.hasActiveOjamaAnimation;
      if (overflowVisible && ojamaSettled) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  Future<void> _applyRankedRatingResult({required bool isWin}) async {
    if (!widget.isRankedMode || _rankedRatingApplied) {
      return;
    }

    _rankedRatingApplied = true;
    try {
      final change = await _multiplayerManager.applyRankedResult(
        isWin: isWin,
        applyOpponentResult: _opponentDisconnectedDuringBattle,
      );
      if (change != null) {
        unawaited(_playerDataManager.setCurrentRating(change.newRating));
        unawaited(
          _playerDataManager.updateLatestRankedHistory(
            ratingAfter: change.newRating,
            ratingDelta: change.delta,
          ),
        );
        unawaited(
          _rankingManager.updateMyRating(
            rating: change.newRating,
          ),
        );
      }
      if (!mounted || change == null) {
        return;
      }
      setState(() {
        _rankedRatingChange = change;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
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
    _didLevelUpFromResultExp = false;
    _resultLevelAfterExp = null;
    _arenaResultApplied = false;
    _arenaMatchResult = null;
    _opponentDisconnectedDuringBattle = false;
    _autoReadyRequested = false;
    _resultRevealPending = false;
    _playerWazaCounts[WazaType.straight] = 0;
    _playerWazaCounts[WazaType.pyramid] = 0;
    _playerWazaCounts[WazaType.hexagon] = 0;
  }

  void _recordPlayerWaza(WazaType waza) {
    if (waza == WazaType.none) {
      return;
    }
    _playerWazaCounts[waza] = (_playerWazaCounts[waza] ?? 0) + 1;
  }

  int _calculateMatchExp({required bool isWin}) {
    final baseExp = isWin ? 500 : 100;
    final straightBonus = (_playerWazaCounts[WazaType.straight] ?? 0) * 20;
    final pyramidBonus = (_playerWazaCounts[WazaType.pyramid] ?? 0) * 50;
    final hexagonBonus = (_playerWazaCounts[WazaType.hexagon] ?? 0) * 80;
    return baseExp + straightBonus + pyramidBonus + hexagonBonus;
  }

  Future<void> _applyMatchExpReward({required bool isWin}) async {
    if (_matchExpApplied) {
      return;
    }

    _matchExpApplied = true;
    final earnedExp = _calculateMatchExp(isWin: isWin);

    try {
      await _playerDataManager.load();
      final previousLevel = _playerDataManager.level;
      await _playerDataManager.addExp(earnedExp);
      await _recordMatchStats(isWin: isWin);
      final currentLevel = _playerDataManager.level;
      if (!mounted) {
        return;
      }
      setState(() {
        _matchExpEarned = earnedExp;
        if (currentLevel > previousLevel) {
          _didLevelUpFromResultExp = true;
          _resultLevelAfterExp = currentLevel;
        }
      });
    } catch (_) {
      await _recordMatchStats(isWin: isWin);
      if (!mounted) {
        return;
      }
      setState(() {
        _matchExpEarned = earnedExp;
      });
    }
  }

  int _calculateSoloExp() {
    final scoreState = _playerGame.scoreManager.state.value;
    final scoreBonus = scoreState.score ~/ 120;
    final levelBonus = scoreState.level * 45;
    final chainBonus = _playerGame.scoreManager.maxChainThisRun * 30;
    return max(100, scoreBonus + levelBonus + chainBonus);
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

  Future<void> _recordMatchStats({required bool isWin}) async {
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
    await _playerDataManager.recordMatchResult(
      isWin: isWin,
      mode: mode,
      opponentName: opponentName,
      maxCombo: _playerGame.scoreManager.maxChainThisRun,
      wazaCounts: {
        'straight': _playerWazaCounts[WazaType.straight] ?? 0,
        'pyramid': _playerWazaCounts[WazaType.pyramid] ?? 0,
        'hexagon': _playerWazaCounts[WazaType.hexagon] ?? 0,
      },
      ratingAfter: _rankedRatingChange?.newRating,
      ratingDelta: _rankedRatingChange?.delta,
    );
  }

  Future<void> _recordSoloStats() async {
    await _playerDataManager.recordMatchResult(
      isWin: false,
      mode: 'SOLO',
      opponentName: '1Pモード',
      maxCombo: _playerGame.scoreManager.maxChainThisRun,
      wazaCounts: {
        'straight': _playerWazaCounts[WazaType.straight] ?? 0,
        'pyramid': _playerWazaCounts[WazaType.pyramid] ?? 0,
        'hexagon': _playerWazaCounts[WazaType.hexagon] ?? 0,
      },
    );
  }

  Future<void> _recordArenaResult({required bool isWin}) async {
    if (!widget.isArenaMode || _arenaResultApplied) {
      return;
    }

    _arenaResultApplied = true;
    await _playerDataManager.load();
    final previousLevel = _playerDataManager.level;
    final result = await _arenaManager.recordArenaMatch(isWin);
    final currentLevel = _playerDataManager.level;
    if (!mounted) {
      return;
    }
    setState(() {
      _arenaMatchResult = result;
      if (currentLevel > previousLevel) {
        _didLevelUpFromResultExp = true;
        _resultLevelAfterExp = currentLevel;
      }
    });
  }

  Future<void> _returnHomeAfterMatch() async {
    _isReturningToHome = true;
    await _stopBattleBgm();
    if (_isOnlineMode) {
      await _multiplayerManager.leaveRoom();
      await _multiplayerManager.clearSavedSession();
    }
    await InterstitialAdManager.instance.showIfNeeded();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _handleOpponentDisconnected() {
    if (!_onlineGameStarted) {
      _leaveOnlineBattle();
      return;
    }

    final resultAlreadyShown = _onlineResultMessage != null ||
        _playerGame.gameStateWrapper.value == GameState.gameover;
    if (resultAlreadyShown) {
      return;
    }

    if (!mounted || _isDisconnectDialogVisible) {
      return;
    }

    _isDisconnectDialogVisible = true;
    setState(() {
      _opponentDisconnectedDuringBattle = true;
    });
    _cpuGame?.setAutonomousRemotePreviewEnabled(true);
    unawaited(_syncDisconnectedOpponentSnapshot());
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      _isDisconnectDialogVisible = false;
    });
  }

  void _handleRematchStarted(int newSeed) {
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
      _isWaitingForRematch = false;
    });
    _playerGame.resumeEngine();
    _cpuGame?.resumeEngine();
    _cpuGame?.startGame(newSeed: newSeed);
    _playerGame.startGame(newSeed: newSeed);
    if (_isOnlineMode) {
      unawaited(_multiplayerManager.saveActiveSession(
        isArenaMode: widget.isArenaMode,
        snapshot: _playerGame.exportRestorableSnapshot(),
      ));
    }
    unawaited(_startBattleBgm());
  }

  Future<void> _startBattleBgmAfterGoDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      return;
    }
    await _startBattleBgm();
  }

  Future<void> _startBattleBgm() async {
    if (_isBattleBgmPlaying) {
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
        volume: 0.102,
      );
    } catch (_) {
      _isBattleBgmPlaying = false;
    }
  }

  void _freezeBattleBoards() {
    _playerGame.gameStateWrapper.value = GameState.gameover;
    if (_playerGame.activePiece != null) {
      _playerGame.activePiece!.isLocked = true;
    }
    if (_playerGame.ghostPiece != null) {
      _playerGame.ghostPiece!.isLocked = true;
    }
    if (_cpuGame != null) {
      _cpuGame!.gameStateWrapper.value = GameState.gameover;
      if (_cpuGame!.activePiece != null) {
        _cpuGame!.activePiece!.isLocked = true;
      }
      if (_cpuGame!.ghostPiece != null) {
        _cpuGame!.ghostPiece!.isLocked = true;
      }
    }
  }

  Future<void> _stopBattleBgm() async {
    if (!_isBattleBgmPlaying && !SeamlessBgm.instance.isPlaying) {
      return;
    }
    _isBattleBgmPlaying = false;
    try {
      await SeamlessBgm.instance.stop();
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSettingsMenu() {
    if (_blocksOnlineExit) {
      return Future<void>.value();
    }

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
                color: Colors.cyanAccent.withValues(alpha: 0.72),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.24),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.purpleAccent.withValues(alpha: 0.12),
                  blurRadius: 34,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'SETTINGS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    shadows: [
                      Shadow(color: Colors.cyanAccent, blurRadius: 6),
                    ],
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
                    foregroundColor: Colors.amberAccent,
                    side: BorderSide(
                      color: Colors.amberAccent.withValues(alpha: 0.72),
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
                      foregroundColor: Colors.cyanAccent,
                      side: BorderSide(
                        color: Colors.cyanAccent.withValues(alpha: 0.72),
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
                      color: Colors.white.withValues(alpha: 0.24),
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
                  child: const Text('CANCEL'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _returnHomeFromSettings() async {
    _isReturningToHome = true;
    _clearAllPendingAttacks();
    _playerGame.pauseEngine();
    _cpuGame?.pauseEngine();
    await _stopBattleBgm();
    if (_isOnlineMode) {
      await _multiplayerManager.leaveRoom();
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _requestRematch() async {
    setState(() {
      _isWaitingForRematch = true;
    });

    try {
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
    timer = Timer(const Duration(seconds: 2), () {
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
      if (_isOnlineMode && identical(targetGame, _playerGame)) {
        unawaited(_persistOnlineSessionSnapshot());
      }
    });
    _pendingAttackTimers.add(timer);
  }

  Future<void> _persistOnlineSessionSnapshot() async {
    if (!_shouldPreserveOnlineSession) {
      return;
    }
    final snapshot = _playerGame.exportRestorableSnapshot();
    await _multiplayerManager.saveActiveSession(
      isArenaMode: widget.isArenaMode,
      snapshot: snapshot,
    );
    await _multiplayerManager.sendBattleSnapshot(snapshot);
  }

  Future<void> _syncDisconnectedOpponentSnapshot() async {
    if (!_isOnlineMode || !_opponentDisconnectedDuringBattle || _cpuGame == null) {
      return;
    }
    await _multiplayerManager.syncDisconnectedOpponentSnapshot(
      _cpuGame!.exportRestorableSnapshot(),
      clearQueuedOjama: _cpuGame!.activeOjamaBlocks.isEmpty &&
          !_cpuGame!.hasPendingPreviewOjamaSpawns,
    );
  }

  Future<void> _applyAttackToOpponent(OjamaTask task) async {
    if (_opponentDisconnectedDuringBattle) {
      await _multiplayerManager.queueDisconnectedOpponentAttack(task);
      _cpuGame?.simulateOjamaTaskOnPreview(task);
      return;
    }
    await _multiplayerManager.sendAttack(task);
  }

  Future<void> _presentBattleResult({
    required bool playerWon,
    required bool opponentCrossedDeathLine,
  }) async {
    if (_resultRevealPending) {
      return;
    }

    _resultRevealPending = true;
    _freezeBattleBoards();
    final targetGame =
        playerWon && opponentCrossedDeathLine && _cpuGame != null
            ? _cpuGame!
            : _playerGame;
    unawaited(_stopBattleBgm());
    await targetGame.animateDeathLineToRed();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (playerWon) {
      AppSfx.playWin();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
    } else {
      AppSfx.playLose();
      await Future<void>.delayed(const Duration(milliseconds: 1800));
    }
    if (!mounted) {
      return;
    }

    if (widget.isCpuMode) {
      _cpuBattlePlayerWon = playerWon;
      unawaited(_applyMatchExpReward(isWin: playerWon));
      setState(() {
        _resultRevealPending = false;
      });
      return;
    }

    if (_isOnlineMode) {
      if (playerWon &&
          opponentCrossedDeathLine &&
          _opponentDisconnectedDuringBattle) {
        unawaited(_multiplayerManager.forceOpponentGameOver());
      }
      unawaited(_missionManager.recordEvent('play_match'));
      if (playerWon) {
        unawaited(_missionManager.recordEvent('win_match'));
      }
      unawaited(_applyMatchExpReward(isWin: playerWon));
      unawaited(_applyRankedRatingResult(isWin: playerWon));
      unawaited(_recordArenaResult(isWin: playerWon));
      unawaited(_multiplayerManager.clearSavedSession());
      setState(() {
        _onlineResultMessage = playerWon ? 'YOU WIN!!' : 'YOU LOSE...';
        _isWaitingForRematch = false;
        _resultRevealPending = false;
      });
      return;
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
        final actions = _controlActionsFor(game, preset);
        return SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final action in actions)
                Expanded(
                  child: _buildAreaButton(
                    icon: action.icon,
                    onDown: action.onDown,
                    onUp: action.onUp,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<_ControlAction> _controlActionsFor(
    PuzzleGame game,
    ControlLayoutPreset preset,
  ) {
    final rotateLeft = _ControlAction(
      icon: Icons.rotate_left,
      onDown: game.rotateLeft,
    );
    final moveLeft = _ControlAction(
      icon: Icons.arrow_left,
      onDown: game.startMovingLeft,
      onUp: game.stopMovingLeft,
    );
    final moveRight = _ControlAction(
      icon: Icons.arrow_right,
      onDown: game.startMovingRight,
      onUp: game.stopMovingRight,
    );
    final rotateRight = _ControlAction(
      icon: Icons.rotate_right,
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
    required IconData icon,
    required VoidCallback onDown,
    VoidCallback? onUp,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onDown(),
      onTapUp: onUp != null ? (_) => onUp() : null,
      onTapCancel: onUp,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0x1100FFFF), // faint cyan highlight
          border: Border(
            top: BorderSide(color: Colors.cyanAccent, width: 2),
            right: BorderSide(color: Color(0x3300FFFF), width: 1),
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: Colors.cyanAccent,
            size: 32,
            shadows: const [Shadow(color: Colors.cyan, blurRadius: 8)],
          ),
        ),
      ),
    );
  }
}

class _ControlAction {
  const _ControlAction({
    required this.icon,
    required this.onDown,
    this.onUp,
  });

  final IconData icon;
  final VoidCallback onDown;
  final VoidCallback? onUp;
}
