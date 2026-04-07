import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/puzzle_game.dart';
import '../game/score_manager.dart';
import '../game/components/ball_component.dart';
import '../game/game_models.dart';

class GameScreen extends StatefulWidget {
  final bool isCpuMode;
  const GameScreen({super.key, this.isCpuMode = false});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final PuzzleGame _playerGame;
  PuzzleGame? _cpuGame;
  final FocusNode _playerFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    int gameSeed = DateTime.now().millisecondsSinceEpoch;
    _playerGame = PuzzleGame(isCpuMode: false, seed: gameSeed);
    if (widget.isCpuMode) {
      _cpuGame = PuzzleGame(isCpuMode: true, seed: gameSeed);
      if (_cpuGame!.cpuAgent != null) {
         _cpuGame!.cpuAgent!.difficulty = CPUDifficulty.oni; // Default to Oni for testing
      }
    }
    
    _playerGame.onWazaFired = (waza, color) {
       if (_cpuGame != null) _sendOjama(_cpuGame!, waza, color);
    };
    if (_cpuGame != null) {
       _cpuGame!.onWazaFired = (waza, color) => _sendOjama(_playerGame, waza, color);
    }
  }

  void _sendOjama(PuzzleGame targetGame, WazaType waza, BallColor? color) {
    if (waza == WazaType.hexagon) {
      for (int i = 0; i < 6; i++) targetGame.incomingOjama.add(OjamaTask(OjamaType.colorSet));
    } else if (waza == WazaType.pyramid) {
      for (int i = 0; i < 4; i++) targetGame.incomingOjama.add(OjamaTask(OjamaType.colorSet));
    } else if (waza == WazaType.straight) {
      targetGame.incomingOjama.add(OjamaTask(OjamaType.straightSet, startColor: color));
      targetGame.incomingOjama.add(OjamaTask(OjamaType.straightSet, startColor: color));
    }
  }

  @override
  void dispose() {
    _playerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Header
            _buildGlobalHeader(),
            
            // 2. Sub-board (Opponent and Next)
            _buildSubBoardRow(),
            
            // 3. Main-board (Own)
            Expanded(
              child: _buildMainBoard(),
            ),
            
            // 4. Controls
            _buildControls(_playerGame),
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
          const Text('TIME ∞', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text(
            widget.isCpuMode ? 'CPU LEVEL: GA-Optimized' : '1P MODE', 
            style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14)
          ),
        ],
      ),
    );
  }

  Widget _buildSubBoardRow() {
    return Container(
      height: 220, 
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Opponent board (shrunk) or Score
          Expanded(
            flex: 5,
            child: widget.isCpuMode ? 
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.hardEdge,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 300, 
                    height: 500, 
                    child: GameWidget(game: _cpuGame!), 
                  ),
                ), 
              ) : 
              _buildScoreWidget(_playerGame),
          ),
          
          // CPU Next (only if CPU Mode)
          if (widget.isCpuMode)
             Expanded(
               flex: 2,
               child: Container(
                 padding: const EdgeInsets.all(4),
                 margin: const EdgeInsets.only(right: 8),
                 decoration: BoxDecoration(
                   color: const Color(0xFF2A1A1A),
                   border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 1),
                   borderRadius: BorderRadius.circular(8),
                 ),
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                   children: [
                     const Text('CPU', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                     Expanded(
                       child: ValueListenableBuilder<List<BallColor>>(
                         valueListenable: _cpuGame!.nextPieceColors,
                         builder: (context, colors, child) {
                           return Center(child: _buildPieceIcon(colors, size: 16));
                         },
                       ),
                     ),
                   ],
                 ),
               ),
             ),
             
          // Own Next 
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                border: Border.all(color: Colors.white24, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const Text('NEXT', style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  Expanded(
                    child: ValueListenableBuilder<List<BallColor>>(
                      valueListenable: _playerGame.nextPieceColors,
                      builder: (context, colors, child) {
                        return Center(child: _buildPieceIcon(colors, size: 22));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreWidget(PuzzleGame game) {
     return Container(
         margin: const EdgeInsets.only(right: 8),
         decoration: BoxDecoration(
           color: const Color(0xFF1A1A2E),
           borderRadius: BorderRadius.circular(8),
         ),
         child: const Center(
            child: Text('ENDLESS\nMODE', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
         ),
     );
  }

  Widget _buildMainBoard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.8), width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
           BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 1)
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          GameWidget(
            game: _playerGame,
            focusNode: _playerFocusNode,
            autofocus: true,
          ),
          // Hard drop gesture overlay
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _playerGame.hardDrop(),
              child: Container(),
            ),
          ),
          

          
          // Waza Cut-in overlay
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: ValueListenableBuilder<String?>(
              valueListenable: _playerGame.wazaNameNotifier,
              builder: (context, name, child) {
                if (name == null) return const SizedBox.shrink();
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amberAccent, width: 2),
                    ),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 28, 
                        fontWeight: FontWeight.bold,
                        color: Colors.amberAccent,
                        letterSpacing: 3,
                        shadows: [Shadow(color: Colors.amber, blurRadius: 10)],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Game Over / Title Overlay
          Positioned.fill(
             child: AnimatedBuilder(
                animation: Listenable.merge([
                   _playerGame.gameStateWrapper,
                   if (_cpuGame != null) _cpuGame!.gameStateWrapper
                ]),
                builder: (context, child) {
                   GameState pState = _playerGame.gameStateWrapper.value;
                   GameState cState = _cpuGame?.gameStateWrapper.value ?? GameState.playing;
                   
                   if (pState == GameState.playing && cState == GameState.playing) {
                      return const SizedBox.shrink();
                   }
                   
                   String message = "READY";
                   Color textColor = Colors.white;
                   if (pState == GameState.gameover) {
                      message = widget.isCpuMode ? "YOU LOSE..." : "GAME OVER";
                      textColor = Colors.blueGrey;
                   } else if (cState == GameState.gameover) {
                      message = "YOU WIN!!";
                      textColor = Colors.amberAccent;
                   }
                   
                   return Container(
                      color: Colors.black87,
                      child: Center(
                         child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                               Text(
                                  message,
                                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 2),
                                  textAlign: TextAlign.center,
                               ),
                               const SizedBox(height: 32),
                               ElevatedButton(
                                  onPressed: () {
                                     _playerGame.startGame();
                                     if (_cpuGame != null) _cpuGame!.startGame();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                                    backgroundColor: Colors.blueAccent,
                                    elevation: 8,
                                  ),
                                  child: const Text('START', style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
                                ),
                            ],
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

  Widget _buildPieceIcon(List<BallColor> colors, {required double size}) {
    if (colors.length != 3) return const SizedBox.shrink();
    
    final hSpacing = size + 2;
    final vSpacing = size;
    
    return SizedBox(
      width: hSpacing + size,
      height: vSpacing + size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: hSpacing / 2, top: 0, child: MiniBallWidget(ballColor: colors[0], size: size)),
          Positioned(left: 0, top: vSpacing, child: MiniBallWidget(ballColor: colors[1], size: size)),
          Positioned(left: hSpacing, top: vSpacing, child: MiniBallWidget(ballColor: colors[2], size: size)),
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
          _buildHoldButton(Icons.arrow_left, () => game.startMovingLeft(), () => game.stopMovingLeft()),
          _buildHoldButton(Icons.arrow_right, () => game.startMovingRight(), () => game.stopMovingRight()),
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

  Widget _buildHoldButton(IconData icon, VoidCallback onDown, VoidCallback onUp) {
    return GestureDetector(
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: () => onUp(),
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
