import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/components/ball_component.dart';
import '../game/game_models.dart';
import '../game/puzzle_game.dart';
import '../network/multiplayer_manager.dart';
import 'home_screen.dart';

class GameScreen extends StatefulWidget {
  final bool isCpuMode;
  final bool isOnlineMultiplayer;
  final String? roomId;
  final bool isHost;

  const GameScreen({
    super.key,
    this.isCpuMode = false,
    this.isOnlineMultiplayer = false,
    this.roomId,
    this.isHost = false,
  });

  const GameScreen.online({
    super.key,
    this.roomId,
    this.isHost = false,
  })  : isCpuMode = false,
        isOnlineMultiplayer = true;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final MultiplayerManager _multiplayerManager = MultiplayerManager();
  late final PuzzleGame _playerGame;
  PuzzleGame? _cpuGame;
  final FocusNode _playerFocusNode = FocusNode();
  MultiplayerRoom? _room;
  bool _onlineGameStarted = false;
  bool _readySubmitting = false;
  String? _onlineResultMessage;
  bool _isWaitingForRematch = false;
  bool _isDisconnectDialogVisible = false;

  final List<Timer> _pendingAttackTimers = [];

  bool get _isOnlineMode => widget.isOnlineMultiplayer;
  bool get _showsOpponentBoard => widget.isCpuMode || _isOnlineMode;

  @override
  void initState() {
    super.initState();
    final gameSeed = widget.isOnlineMultiplayer
        ? _multiplayerManager.currentRoom?.seed
        : DateTime.now().millisecondsSinceEpoch;

    _playerGame = PuzzleGame(
      isCpuMode: false,
      seed: gameSeed,
      autoStart: !widget.isOnlineMultiplayer,
      useConstantFallSpeed: widget.isOnlineMultiplayer,
    );

    if (_isOnlineMode) {
      _cpuGame = PuzzleGame(
        isCpuMode: false,
        seed: gameSeed,
        autoStart: false,
        isRemotePlayerMode: true,
      );
    }

    if (_isOnlineMode) {
      _room = _multiplayerManager.currentRoom;
      _multiplayerManager.onRoomUpdated = _handleRoomUpdated;
      _multiplayerManager.onOpponentBoardUpdated = _handleOpponentBoardUpdated;
      _multiplayerManager.onOpponentPieceUpdated = _handleOpponentPieceUpdated;
      _multiplayerManager.onAttackReceived = _handleAttackReceived;
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
          _playerGame.startGame(newSeed: _room?.seed);
          _cpuGame?.startGame(newSeed: _room?.seed);
        });
      }
    }

    if (widget.isCpuMode) {
      _cpuGame = PuzzleGame(isCpuMode: true, seed: gameSeed);
      if (_cpuGame!.cpuAgent != null) {
        _cpuGame!.cpuAgent!.difficulty = CPUDifficulty.oni;
      }
    }

    _playerGame.onBoardUpdated = (boardData) {
      if (_isOnlineMode && _onlineGameStarted) {
        unawaited(_multiplayerManager.sendBoardState(boardData));
      }
    };
    _playerGame.onActivePieceChanged = (action, x, y, rotation, colors) {
      if (_isOnlineMode && _onlineGameStarted) {
        unawaited(
          _multiplayerManager.sendActivePiece(
            x,
            y,
            rotation,
            colors,
            action,
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
      if (_isOnlineMode) {
        setState(() {
          _onlineResultMessage = 'YOU LOSE...';
          _isWaitingForRematch = false;
        });
        unawaited(_multiplayerManager.declareGameOver());
      }
    };
    _playerGame.onWazaFired = (waza, color) {
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
    if (widget.isOnlineMultiplayer) {
      unawaited(_multiplayerManager.leaveRoom());
    }
    _playerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isLandscape =
                    constraints.maxWidth > constraints.maxHeight;
                if (_showsOpponentBoard && isLandscape) {
                  return Column(
                    children: [
                      _buildGlobalHeader(),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildGameBox(_playerGame, isCpu: false),
                            ),
                            Expanded(
                              child: _buildGameBox(_cpuGame!, isCpu: true),
                            ),
                          ],
                        ),
                      ),
                      _buildControls(_playerGame),
                    ],
                  );
                }

                return Column(
                  children: [
                    _buildGlobalHeader(),
                    if (_showsOpponentBoard)
                      Expanded(child: _buildGameBox(_cpuGame!, isCpu: true)),
                    if (!widget.isCpuMode && !_isOnlineMode)
                      _buildScoreWidget(_playerGame),
                    Expanded(child: _buildGameBox(_playerGame, isCpu: false)),
                    _buildControls(_playerGame),
                  ],
                );
              },
            ),
            if (_isOnlineMode) _buildOnlineOverlay() else _buildGlobalOverlay(),
          ],
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
          const Icon(Icons.settings, color: Colors.white54),
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
                  ? 'FRIEND BATTLE'
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

  Widget _buildGameBox(PuzzleGame game, {required bool isCpu}) {
    final isOnlineOpponent = _isOnlineMode && isCpu;
    final panelLabel = isOnlineOpponent ? 'OPPONENT' : (isCpu ? 'CPU' : 'NEXT');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(
          color: isCpu
              ? Colors.redAccent.withValues(alpha: 0.5)
              : Colors.blueAccent.withValues(alpha: 0.8),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: isCpu
            ? []
            : [
                BoxShadow(
                  color: Colors.blueAccent.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 320,
                height: 480,
                child: GameWidget(
                  game: game,
                  focusNode: isCpu ? null : _playerFocusNode,
                  autofocus: !isCpu,
                ),
              ),
            ),
          ),
          if (!isCpu)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (_) => game.hardDrop(),
                child: Container(),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 60,
              height: 80,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black87,
                border: Border.all(
                  color: isCpu
                      ? Colors.redAccent.withValues(alpha: 0.3)
                      : Colors.white24,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    panelLabel,
                    style: TextStyle(
                      color: isCpu ? Colors.redAccent : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: isOnlineOpponent
                        ? const Center(
                            child: Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 22,
                            ),
                          )
                        : ValueListenableBuilder<List<BallColor>>(
                            valueListenable: game.nextPieceColors,
                            builder: (context, colors, child) => Center(
                              child: _buildPieceIcon(colors, size: 16),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<String?>(
              valueListenable: game.wazaNameNotifier,
              builder: (context, name, child) {
                if (name == null) {
                  return const SizedBox.shrink();
                }
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amberAccent, width: 2),
                    ),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.amberAccent,
                        shadows: [
                          Shadow(color: Colors.amber, blurRadius: 10),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
              message =
                  pState == GameState.gameover ? 'YOU LOSE...' : 'YOU WIN!!';
              textColor = pState == GameState.gameover
                  ? Colors.blueGrey
                  : Colors.amberAccent;
            } else {
              message = 'GAME OVER';
              textColor = Colors.redAccent;
            }
          } else {
            return const SizedBox.shrink();
          }

          return Container(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (pState == GameState.gameover ||
                      (cState == GameState.gameover && widget.isCpuMode)) ...[
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        _clearAllPendingAttacks();
                        _playerGame.startGame();
                        if (_cpuGame != null) {
                          _cpuGame!.startGame();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.blueAccent,
                        elevation: 8,
                      ),
                      child: const Text(
                        'RESTART',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _clearAllPendingAttacks();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const HomeScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.grey[800],
                        elevation: 4,
                      ),
                      child: const Text(
                        'HOME',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
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

    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _onlineResultMessage!,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: _onlineResultMessage == 'YOU WIN!!'
                      ? Colors.amberAccent
                      : Colors.blueGrey,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isWaitingForRematch ? null : _requestRematch,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  backgroundColor: Colors.blueAccent,
                ),
                child: Text(
                  _isWaitingForRematch ? '相手の準備待ち...' : 'REMATCH (再戦)',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  _leaveOnlineBattle();
                },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  backgroundColor: Colors.grey[800],
                ),
                child: const Text(
                  'HOME',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
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

    if (_onlineGameStarted || room == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF16162A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isHost ? 'フレンドバトルの部屋を作成しました' : 'フレンドバトルに参加しました',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (isHost) ...[
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
                    canShowReady
                        ? '両プレイヤーがそろいました。READYで開始準備をしてください。'
                        : '相手の入室を待っています…',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _buildLobbyStatusRow('HOST', hostReady),
                  const SizedBox(height: 12),
                  _buildLobbyStatusRow('GUEST', guestReady),
                  const SizedBox(height: 28),
                  if (canShowReady)
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyStatusRow(String label, bool isReady) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            isReady ? 'READY' : 'WAITING',
            style: TextStyle(
              color: isReady ? Colors.greenAccent : Colors.white70,
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

    if (!_onlineGameStarted && room.bothPlayersReady) {
      setState(() {
        _onlineGameStarted = true;
      });
      _playerGame.startGame(newSeed: room.seed);
      _cpuGame?.startGame(newSeed: room.seed);
    }
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
    if (!mounted) {
      return;
    }

    setState(() {
      _onlineResultMessage = 'YOU WIN!!';
      _isWaitingForRematch = false;
    });
    _playerGame.gameStateWrapper.value = GameState.gameover;
    if (_playerGame.activePiece != null) {
      _playerGame.activePiece!.isLocked = true;
    }
  }

  void _handleOpponentDisconnected() {
    if (!mounted || _isDisconnectDialogVisible) {
      return;
    }

    _isDisconnectDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E32),
          title: const Text(
            '通信が切断されました',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            '相手プレイヤーとの接続が失われました。ホーム画面に戻ります。',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _leaveOnlineBattle();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    ).then((_) {
      _isDisconnectDialogVisible = false;
    });
  }

  void _handleRematchStarted(int newSeed) {
    if (!mounted) {
      return;
    }

    _clearAllPendingAttacks();
    _cpuGame?.clearRemoteActivePiece();
    setState(() {
      _onlineGameStarted = true;
      _onlineResultMessage = null;
      _isWaitingForRematch = false;
    });
    _playerGame.startGame(newSeed: newSeed);
    _cpuGame?.startGame(newSeed: newSeed);
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
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
    if (rawColors is! List) {
      return const [];
    }

    return rawColors
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
    final topStart = DateTime.now().microsecondsSinceEpoch % loopColors.length;
    final colors = <BallColor>[];

    for (var i = 0; i < 10; i++) {
      colors.add(loopColors[(bottomStart + i) % loopColors.length]);
    }
    for (var i = 0; i < 9; i++) {
      colors.add(loopColors[(topStart + i) % loopColors.length]);
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
    return Container(
      height: 90,
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(Icons.rotate_left, () => game.rotateLeft()),
          _buildHoldButton(
            Icons.arrow_left,
            () => game.startMovingLeft(),
            () => game.stopMovingLeft(),
          ),
          _buildHoldButton(
            Icons.arrow_right,
            () => game.startMovingRight(),
            () => game.stopMovingRight(),
          ),
          _buildControlButton(Icons.rotate_right, () => game.rotateRight()),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPress) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(35),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white10,
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
          child: Icon(icon, color: Colors.white70, size: 32),
        ),
      ),
    );
  }

  Widget _buildHoldButton(
    IconData icon,
    VoidCallback onDown,
    VoidCallback onUp,
  ) {
    return GestureDetector(
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: onUp,
      child: Container(
        width: 72,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white10,
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Icon(icon, color: Colors.white70, size: 40),
      ),
    );
  }
}
