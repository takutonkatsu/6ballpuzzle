import 'dart:math';
import 'package:vector_math/vector_math_64.dart';
import '../game/game_models.dart';
import '../game/game_logic.dart';

class HeadlessGame {
  final CPUWeights weights;
  final Random _rng = Random();
  
  late Map<HexCoordinate, BallColor> board;
  int score = 0;
  int dropCount = 0;

  HeadlessGame(this.weights);

  List<BallColor> _generatePieceColors() {
    return List.generate(3, (_) => BallColor.values[_rng.nextInt(BallColor.values.length)]);
  }

  double run() {
    board = {};
    score = 0;
    dropCount = 0;

    List<BallColor> currentPiece = _generatePieceColors();
    List<BallColor> nextPiece = _generatePieceColors();

    while (dropCount < 300) { 
      SimDropResult? moveOptions = _computeBestMove(currentPiece, nextPiece);
      
      if (moveOptions == null) {
         break;
      }

      for (var entry in moveOptions.newBalls.entries) {
        board[entry.key] = entry.value;
      }
      
      bool hasMatches = true;
      while (hasMatches) {
         bool changed = true;
         while (changed) {
            changed = false;
            List<HexCoordinate> allHexes = board.keys.toList();
            allHexes.sort((a,b) {
               int rd = b.row.compareTo(a.row);
               if (rd != 0) return rd;
               return a.col.compareTo(b.col);
            });
            
            SimGrid tempGrid = SimGrid(12, board);
            for (var curr in allHexes) {
               BallColor c = board.remove(curr)!;
               HexCoordinate n = tempGrid.dropBall(curr, 0); 
               if (n != curr) {
                  changed = true;
                  board[n] = c;
                  tempGrid.board.remove(curr);
                  tempGrid.board[n] = c;
               } else {
                  board[curr] = c;
               }
            }
         }
         
         SimGrid mGrid = SimGrid(12, board);
         Set<HexCoordinate> visited = {};
         List<SimGridResult> wazaResults = [];
         
         for (var hex in board.keys) {
            if (visited.contains(hex)) continue;
            var r = mGrid.checkMatchesFrom(hex, board[hex]!);
            if (r != null) {
               wazaResults.add(r);
               visited.addAll(r.matched);
            } else {
               visited.add(hex);
            }
         }

         if (wazaResults.isEmpty) {
            hasMatches = false;
         } else {
            for (var w in wazaResults) {
               score += w.matched.length * 50;
               if (w.waza != WazaType.none) {
                  score += (w.waza.multiplier * 2000).toInt();
               }
               
               // 消去処理
               for (var target in w.matched) {
                  board.remove(target);
               }
               // ワザの場合は同色全消し
               if (w.waza != WazaType.none) {
                  BallColor colorToRemove = board[w.matched.first] ?? BallColor.blue; // dummy if already gone
                  board.removeWhere((h, c) => c == colorToRemove);
               }
            }
         }
      }
      
      bool dead = false;
      for (var h in board.keys) {
         if (h.row < 0) dead = true;
      }
      if (dead) break;

      currentPiece = nextPiece;
      nextPiece = _generatePieceColors();
      dropCount++;
    }

    return score.toDouble();
  }

  SimDropResult? _computeBestMove(List<BallColor> curr, List<BallColor> nextPiece) {
     int maxCols = 10;
     List<MoveOption> options = [];
     Map<int, SimDropResult> drops = {};
     int dropId = 0;

     for (int col1 = 0; col1 < maxCols; col1++) {
       double x1 = col1 * 30.0;
       
       for (int rot1 = 0; rot1 < 6; rot1++) {
         SimDropResult sim1 = _simulateDropHeadless(board, x1, curr, rot1);
         double score1 = evaluateBoardLogic(sim1.simGrid, sim1.newBalls, weights);

         if (score1 <= -500000.0) {
            continue;
         }

         double bestNextScore = 0.0;
         
         // Headless Lookahead: 30% probability to skip for speed
         if (_rng.nextDouble() < 0.3) {
            int id = dropId++;
            drops[id] = sim1;
            options.add(MoveOption(id.toDouble(), rot1, score1));
            continue;
         }

         bestNextScore = -double.infinity;
         
         Map<HexCoordinate, BallColor> boardFor2 = Map.from(sim1.simGrid.board);
         for (var hex in sim1.allMatched) {
             boardFor2.remove(hex);
         }
         
         for (int col2 = 0; col2 < maxCols; col2++) {
           double x2 = col2 * 30.0;
           for (int rot2 = 0; rot2 < 6; rot2++) {
              SimDropResult sim2 = _simulateDropHeadless(boardFor2, x2, nextPiece, rot2);
              double score2 = evaluateBoardLogic(sim2.simGrid, sim2.newBalls, weights);
              if (score2 > bestNextScore) {
                 bestNextScore = score2;
              }
           }
         }
         
         int id = dropId++;
         drops[id] = sim1;
         options.add(MoveOption(id.toDouble(), rot1, score1 + bestNextScore));
       }
     }

     options.sort((a,b) => b.score.compareTo(a.score));
     if (options.isEmpty) return null;
     
     return drops[options.first.x.toInt()];
  }

  SimDropResult _simulateDropHeadless(Map<HexCoordinate, BallColor> curBoard, double xPos, List<BallColor> colors, int rot) {
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

     SimGrid simGrid = SimGrid(12, curBoard);
     Map<HexCoordinate, BallColor> placingBalls = {};
     
     for (int i=0; i<3; i++) {
        var startHex = HexCoordinate((absolutePositions[i].x / 30.0).round(), -1); 
        startHex = simGrid.findNearestEmpty(startHex);
        
        HexCoordinate finalHex = simGrid.dropBall(startHex, 0.0);
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
