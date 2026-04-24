import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';

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

class _GameScreenState extends State<GameScreen> {
  static const double _gameViewportWidth = 308;
  static const double _gameViewportHeight = 480;
  static const double _gridBallDiameter = 30;
  static const double _compactStampWidth = 96;
  static const Duration _postReadyGoBoardPause = Duration(milliseconds: 350);
  static const Duration _battleBgmStartDelay = Duration(milliseconds: 1000);
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
  bool _isReturningToHome = false;
  bool _cpuBattleFinished = false;
  bool? _cpuBattlePlayerWon;
  bool _rankedRatingApplied = false;
  RankedRatingChange? _rankedRatingChange;
  Timer? _rankedAutoStartTimer;
  bool _rankedAutoStartScheduled = false;
  String? _readyGoOverlayText;
  bool _isBattleBgmPlaying = false;
  bool _arenaResultApplied = false;
  ArenaMatchResult? _arenaMatchResult;
  bool _matchExpApplied = false;
  int? _matchExpEarned;
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

  final List<Timer> _pendingAttackTimers = [];

  bool get _isOnlineMode => widget.isOnlineMultiplayer;
  bool get _showsOpponentBoard => widget.isCpuMode || _isOnlineMode;
  bool get _blocksOnlineExit =>
      _isOnlineMode && _onlineGameStarted && _onlineResultMessage == null;

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
    final matchExp = _matchExpEarned;
    if (matchExp == null) {
      return null;
    }
    return matchExp + _arenaRewardExp;
  }

  @override
  void initState() {
    super.initState();
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
      } else if (widget.isRankedMode && (_room?.bothPlayersJoined ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduleRankedAutoStart(_room!);
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
        _finishCpuBattle(playerWon: true);
        unawaited(_stopBattleBgm());
      };
    }

    _playerGame.onBoardUpdated = (boardData) {
      if (_isOnlineMode && _onlineGameStarted) {
        unawaited(_multiplayerManager.sendBoardState(boardData));
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
      }
    };
    _playerGame.onOjamaSpawned = (ojamaData, dropSeed) {
      if (_isOnlineMode && _onlineGameStarted) {
        unawaited(_multiplayerManager.sendOjamaSpawn(ojamaData, dropSeed));
      }
    };
    _playerGame.onGameOverTriggered = () {
      unawaited(_stopBattleBgm());
      if (widget.isCpuMode) {
        _finishCpuBattle(playerWon: false);
        return;
      }
      if (_isOnlineMode) {
        _freezeBattleBoards();
        unawaited(_missionManager.recordEvent('play_match'));
        setState(() {
          _onlineResultMessage = 'YOU LOSE...';
          _isWaitingForRematch = false;
        });
        unawaited(_applyMatchExpReward(isWin: false));
        unawaited(_applyRankedRatingResult(isWin: false));
        unawaited(_recordArenaResult(isWin: false));
        unawaited(_multiplayerManager.declareGameOver());
      }
    };
    _playerGame.onWazaFired = (waza, color) {
      _recordPlayerWaza(waza);
      if (_isOnlineMode) {
        final task = _createOjamaTaskForAttack(waza, color);
        if (task != null) {
          unawaited(_multiplayerManager.sendAttack(task));
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
  void dispose() {
    _clearAllPendingAttacks();
    _rankedAutoStartTimer?.cancel();
    if (!_isReturningToHome) {
      unawaited(_stopBattleBgm());
    }
    if (widget.isOnlineMultiplayer && !_isReturningToHome) {
      unawaited(_multiplayerManager.leaveRoom());
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
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      _sendStamp(stamp);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 90,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.06),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.36),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(stamp.emoji ?? '',
                              style: const TextStyle(fontSize: 28, shadows: [
                                Shadow(color: Colors.cyanAccent, blurRadius: 2)
                              ])),
                          const SizedBox(height: 4),
                          Text(
                            stamp.text ?? stamp.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stamp.emoji ?? '',
                style: TextStyle(
                  fontSize: compact ? 32 : 64,
                  height: 1,
                  shadows: [
                    Shadow(
                      color: Colors.cyanAccent,
                      blurRadius: compact ? 4 * normalizedScale : 16,
                    )
                  ],
                ),
              ),
              SizedBox(height: compact ? 4 * normalizedScale : 8),
              Text(
                stamp.text ?? stamp.name,
                textAlign: TextAlign.center,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: compact ? 9 * normalizedScale : 18,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  shadows: [
                    Shadow(
                      color: Colors.cyanAccent,
                      blurRadius: compact ? 2 * normalizedScale : 8,
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlobalHeader() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildBattleSettingsButton(),
          const Text(
            'TIME ∞',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Flexible(
            child: Text(
              widget.isOnlineMultiplayer
                  ? widget.isArenaMode
                      ? 'ARENA'
                      : widget.isRankedMode
                          ? 'RANDOM MATCH'
                          : 'FRIEND BATTLE'
                  : widget.isCpuMode
                      ? 'CPU LEVEL: GA-Optimized'
                      : '1P MODE',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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
            'ARENA  $wins勝 $losses敗',
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
        ? reward.title == null
            ? 'REWARD  COIN +${reward.coins} / EXP +${reward.exp} / TICKET +${reward.gachaTickets}'
            : 'REWARD  COIN +${reward.coins} / EXP +${reward.exp} / TITLE ${reward.title}'
        : 'RUN  $wins WINS / $losses LOSSES';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.lightBlueAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.lightBlueAccent.withValues(alpha: 0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(color: Colors.lightBlueAccent.withValues(alpha: 0.2), blurRadius: 10),
        ],
      ),
      child: Text(
        rewardText,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.lightBlueAccent,
          fontSize: 14,
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          shadows: [Shadow(color: Colors.lightBlueAccent, blurRadius: 4)],
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

    final straightCount = _playerWazaCounts[WazaType.straight] ?? 0;
    final pyramidCount = _playerWazaCounts[WazaType.pyramid] ?? 0;
    final hexagonCount = _playerWazaCounts[WazaType.hexagon] ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.6),
            ),
            boxShadow: const [
              BoxShadow(color: Colors.greenAccent, blurRadius: 14),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TOTAL EXP  +$totalExp',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'STRAIGHT x$straightCount  /  PYRAMID x$pyramidCount  /  HEXAGON x$hexagonCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        if (_didLevelUpFromResultExp) ...[
          const SizedBox(height: 16),
          const Text(
            'LEVEL UP!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.6,
              shadows: [
                Shadow(color: Colors.cyanAccent, blurRadius: 18),
                Shadow(color: Colors.white, blurRadius: 10),
              ],
            ),
          ),
          if (_resultLevelAfterExp != null) ...[
            const SizedBox(height: 4),
            Text(
              'NOW LEVEL ${_resultLevelAfterExp!}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ],
      ],
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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => game.triggerHardDrop(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sidePanelWidth = constraints.maxWidth / 5;
          final nextBallSize = _scaledGridBallDiameter(
            boardWidth: constraints.maxWidth,
            boardHeight: constraints.maxHeight,
          );

          return Stack(
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: _buildGameViewport(game, isPlayer: true),
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
                      _buildNameBadge(_myDisplayName, isCpu: false),
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
                            child: Icon(Icons.chat,
                                color: Colors.cyanAccent.withValues(
                                  alpha: _isStampCoolingDown ? 0.72 : 1,
                                )),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
                    _buildNameBadge(_opponentDisplayName, isCpu: true),
                    const SizedBox(height: 16),
                    _buildNextBadge(
                      game,
                      isCpu: true,
                      ballSize: nextBallSize,
                    ),
                    if (!_blocksOnlineExit) ...[
                      const SizedBox(height: 24),
                      _buildBattleSettingsButton(),
                    ],
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
    return Tooltip(
      message: 'Settings',
      child: InkWell(
        onTap: _showSettingsMenu,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.34),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withValues(alpha: 0.08),
                blurRadius: 8,
              ),
            ],
          ),
          child: const Icon(
            Icons.settings,
            color: Colors.cyanAccent,
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

  Widget _buildNameBadge(String name, {required bool isCpu}) {
    final neonColor = isCpu ? Colors.pinkAccent : Colors.cyanAccent;
    return Container(
      width: 112,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

          var message = 'WAITING';
          var textColor = Colors.white;

          if (pState == GameState.ready) {
            message = _playerGame.isReadyGoText ? 'GO!' : 'READY';
            textColor = Colors.orangeAccent;
          } else if (pState == GameState.gameover ||
              (cState == GameState.gameover && widget.isCpuMode)) {
            if (widget.isCpuMode) {
              final playerWon =
                  _cpuBattlePlayerWon ?? (pState != GameState.gameover);
              message = playerWon ? 'YOU WIN!!' : 'YOU LOSE...';
              textColor = playerWon ? Colors.amberAccent : Colors.blueGrey;
            } else {
              message = 'GAME OVER';
              textColor = Colors.redAccent;
            }
          } else {
            return const SizedBox.shrink();
          }

          return Container(
            color: const Color(0xFF0F0F13).withValues(alpha: 0.90),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 48,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(color: textColor, blurRadius: 16),
                        const Shadow(color: Colors.white, blurRadius: 4),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.isCpuMode &&
                      (pState == GameState.gameover ||
                          cState == GameState.gameover)) ...[
                    const SizedBox(height: 24),
                    _buildResultExpSummary(),
                  ],
                  if (pState == GameState.gameover ||
                      (cState == GameState.gameover && widget.isCpuMode)) ...[
                    const SizedBox(height: 48),
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
                    const SizedBox(height: 16),
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
                ],
              ),
            ),
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
      child: Container(
        color: const Color(0xFF0F0F13).withValues(alpha: 0.90),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _onlineResultMessage!,
                style: TextStyle(
                  fontSize: 48,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: textColor, blurRadius: 16),
                    const Shadow(color: Colors.white, blurRadius: 4),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildResultExpSummary(),
              const SizedBox(height: 24),
              if (widget.isRankedMode) ...[
                _buildRankedRatingChange(),
                const SizedBox(height: 24),
                if (widget.isArenaMode) ...[
                  _buildArenaResultSummary(),
                  const SizedBox(height: 24),
                ],
              ] else ...[
                _buildCyberResultButton(
                  label: _isWaitingForRematch ? '相手の準備待ち...' : 'REMATCH (再戦)',
                  baseColor: Colors.blueAccent,
                  isWaiting: _isWaitingForRematch,
                  onPressed: _isWaitingForRematch ? null : _requestRematch,
                ),
                const SizedBox(height: 16),
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
        ),
      ),
    );
  }

  Widget _buildRankedRatingChange() {
    final change = _rankedRatingChange;
    if (change == null) {
      return const Text(
        'Ratingを更新中...',
        style: TextStyle(
          color: Colors.cyanAccent,
          fontSize: 18,
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 8)],
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
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: glowColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: glowColor.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: 0.2),
                blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'RATING: ${change.oldRating} → $animatedRating ($deltaText)',
                style: TextStyle(
                  color: glowColor,
                  fontSize: 24,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: glowColor, blurRadius: 10),
                    const Shadow(color: Colors.white, blurRadius: 2),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
      onTap: onPressed,
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
                        ? 'ARENAマッチが成立しました'
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
                    widget.isRankedMode && canShowReady
                        ? 'READYで開始準備をしてください。'
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
                    _displayNameForRole('host') ?? 'Player',
                    hostReady,
                    isOccupied: room.players['host'] != null,
                    rating: widget.isRankedMode
                        ? room.players['host']?.rating
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _buildLobbyStatusRow(
                    _displayNameForRole('guest') ?? 'Waiting for player...',
                    guestReady,
                    isOccupied: room.players['guest'] != null,
                    rating: widget.isRankedMode
                        ? room.players['guest']?.rating
                        : null,
                  ),
                  const SizedBox(height: 28),
                  if (widget.isRankedMode && canShowReady)
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
                  else if (canShowReady)
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
    int? rating,
  }) {
    final backgroundColor = isOccupied
        ? Colors.white10
        : const Color(0xFF0D0D15).withValues(alpha: 0.92);
    final borderColor = isOccupied
        ? Colors.cyanAccent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.08);
    final nameColor = isOccupied ? Colors.white : Colors.white54;
    final statusText =
        isOccupied ? (isReady ? 'READY' : 'WAITING') : 'NOT JOINED';
    final statusColor = !isOccupied
        ? Colors.white38
        : isReady
            ? Colors.greenAccent
            : Colors.white70;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rating == null || !isOccupied
                  ? name
                  : '$name  /  RATING: $rating',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: nameColor,
                fontSize: 16,
                fontFamily: 'Courier',
                letterSpacing: 1.2,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: nameColor, blurRadius: 4)],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
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

    try {
      await _multiplayerManager.restoreSession(
        roomId: roomId,
        roleId: widget.isHost ? 'host' : 'guest',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _room = _multiplayerManager.currentRoom;
      });
    } catch (error) {
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
    });

    if (_onlineGameStarted) {
      return;
    }

    if (widget.isRankedMode && room.bothPlayersJoined) {
      _scheduleRankedAutoStart(room);
      return;
    }

    if (!widget.isRankedMode && room.bothPlayersReady) {
      unawaited(_startOnlineBattleWithReadyGo(room.seed));
    }
  }

  void _scheduleRankedAutoStart(MultiplayerRoom room) {
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

  Future<void> _startLocalBattleWithReadyGo(int seed) async {
    if (!mounted) {
      return;
    }

    _cpuBattleFinished = false;
    _cpuBattlePlayerWon = null;
    _resetResultProgressionState();

    setState(() {
      _readyGoOverlayText = 'READY...';
    });
    unawaited(FlameAudio.play(_readySfx, volume: 0.8));

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }
    setState(() {
      _readyGoOverlayText = 'GO!';
    });
    unawaited(_startBattleBgmAfterDelay());

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

    _playerGame.startGame(newSeed: seed);
    _cpuGame?.startGame(newSeed: seed);
  }

  Future<void> _startOnlineBattleWithReadyGo(int? seed) async {
    if (!mounted) {
      return;
    }

    _cpuBattleFinished = false;
    _cpuBattlePlayerWon = null;
    _resetResultProgressionState();
    _rankedAutoStartTimer?.cancel();
    setState(() {
      _onlineGameStarted = true;
      _readyGoOverlayText = 'READY...';
    });
    unawaited(FlameAudio.play(_readySfx, volume: 0.8));

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }
    setState(() {
      _readyGoOverlayText = 'GO!';
    });
    unawaited(_startBattleBgmAfterDelay());

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

    _playerGame.startGame(newSeed: seed);
    _cpuGame?.startGame(newSeed: seed);
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

  void _handleOpponentBoardUpdated(Map<String, dynamic> boardData) {
    _cpuGame?.applyRemoteBoardState(boardData);
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
  }

  void _handleOpponentOjamaSpawned(List<dynamic> ojamaData, int dropSeed) {
    _cpuGame?.spawnRemoteOjama(ojamaData, dropSeed);
  }

  void _handleOpponentGameOver() {
    _finishOnlineWin();
  }

  void _finishOnlineWin() {
    if (!mounted) {
      return;
    }

    setState(() {
      _onlineResultMessage = 'YOU WIN!!';
      _isWaitingForRematch = false;
    });
    unawaited(_stopBattleBgm());
    unawaited(_missionManager.recordEvent('play_match'));
    unawaited(_missionManager.recordEvent('win_match'));
    unawaited(_applyMatchExpReward(isWin: true));
    unawaited(_applyRankedRatingResult(isWin: true));
    unawaited(_recordArenaResult(isWin: true));
    _freezeBattleBoards();
  }

  Future<void> _applyRankedRatingResult({required bool isWin}) async {
    if (!widget.isRankedMode || _rankedRatingApplied) {
      return;
    }

    _rankedRatingApplied = true;
    try {
      final change = await _multiplayerManager.applyRankedResult(
        isWin: isWin,
      );
      if (change != null) {
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
    _didLevelUpFromResultExp = false;
    _resultLevelAfterExp = null;
    _arenaResultApplied = false;
    _arenaMatchResult = null;
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
      if (!mounted) {
        return;
      }
      setState(() {
        _matchExpEarned = earnedExp;
      });
    }
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
    _cpuGame?.pauseEngine();
    _finishOnlineWin();
  }

  void _handleRematchStarted(int newSeed) {
    if (!mounted) {
      return;
    }

    _cpuBattleFinished = false;
    _cpuBattlePlayerWon = null;
    _resetResultProgressionState();
    _clearAllPendingAttacks();
    _cpuGame?.clearRemoteActivePiece();
    setState(() {
      _onlineGameStarted = true;
      _onlineResultMessage = null;
      _isWaitingForRematch = false;
    });
    _playerGame.startGame(newSeed: newSeed);
    _cpuGame?.startGame(newSeed: newSeed);
    unawaited(_startBattleBgm());
  }

  Future<void> _startBattleBgmAfterDelay() async {
    await Future<void>.delayed(_battleBgmStartDelay);
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
      await FlameAudio.bgm.play('battle_bgm01.mp3', volume: 0.102);
    } catch (_) {
      _isBattleBgmPlaying = false;
    }
  }

  void _finishCpuBattle({required bool playerWon}) {
    if (_cpuBattleFinished) {
      return;
    }

    _cpuBattleFinished = true;
    _cpuBattlePlayerWon = playerWon;
    _freezeBattleBoards();
    unawaited(_applyMatchExpReward(isWin: playerWon));
    if (mounted) {
      setState(() {});
    }
  }

  void _freezeBattleBoards() {
    _playerGame.gameStateWrapper.value = GameState.gameover;
    if (_playerGame.activePiece != null) {
      _playerGame.activePiece!.isLocked = true;
    }
    if (_cpuGame != null) {
      _cpuGame!.gameStateWrapper.value = GameState.gameover;
      if (_cpuGame!.activePiece != null) {
        _cpuGame!.activePiece!.isLocked = true;
      }
    }
  }

  Future<void> _stopBattleBgm() async {
    if (!_isBattleBgmPlaying && !FlameAudio.bgm.isPlaying) {
      return;
    }
    _isBattleBgmPlaying = false;
    try {
      await FlameAudio.bgm.stop();
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
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
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
    });
    _pendingAttackTimers.add(timer);
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
    return SizedBox(
      height: 90,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildAreaButton(
              icon: Icons.rotate_left,
              onDown: () => game.rotateLeft(),
            ),
          ),
          Expanded(
            child: _buildAreaButton(
              icon: Icons.arrow_left,
              onDown: () => game.startMovingLeft(),
              onUp: () => game.stopMovingLeft(),
            ),
          ),
          Expanded(
            child: _buildAreaButton(
              icon: Icons.arrow_right,
              onDown: () => game.startMovingRight(),
              onUp: () => game.stopMovingRight(),
            ),
          ),
          Expanded(
            child: _buildAreaButton(
              icon: Icons.rotate_right,
              onDown: () => game.rotateRight(),
            ),
          ),
        ],
      ),
    );
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
