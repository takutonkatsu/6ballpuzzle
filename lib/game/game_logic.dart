import 'dart:math';
import 'package:vector_math/vector_math_64.dart';
import 'game_models.dart';

class CPUWeights {
  final double safety;
  final double shape;
  final double flatness;
  final double connection;

  const CPUWeights({
    this.safety = 1.87,
    this.shape = 0.98,
    this.flatness = 0.99,
    this.connection = 2.05,
  });
}

class SimGridResult {
   final Set<HexCoordinate> matched;
   final WazaType waza;
   SimGridResult(this.matched, this.waza);
}

class SimDropResult {
  final SimGrid simGrid;
  final Map<HexCoordinate, BallColor> newBalls;
  final Set<HexCoordinate> allMatched;
  SimDropResult(this.simGrid, this.newBalls, this.allMatched);
}

class SimGrid {
  final int numRows;
  final Map<HexCoordinate, BallColor> board;

  SimGrid(this.numRows, Map<HexCoordinate, BallColor> original) 
    : board = Map.from(original);

  int getColumnsForRow(int row) => row.isOdd ? 10 : 9;

  HexCoordinate? getNeighbor(HexCoordinate hex, String dir) {
    int r = hex.row;
    int c = hex.col;
    bool isEven = r.isEven;

    if (dir == 'a') return HexCoordinate(c - 1, r);
    if (dir == 'd') return HexCoordinate(c + 1, r);
    if (dir == 'b') return isEven ? HexCoordinate(c, r + 1) : HexCoordinate(c - 1, r + 1);
    if (dir == 'c') return isEven ? HexCoordinate(c + 1, r + 1) : HexCoordinate(c, r + 1);
    if (dir == 'e') return HexCoordinate(c, r + 2);
    if (dir == 'f') return isEven ? HexCoordinate(c, r - 1) : HexCoordinate(c - 1, r - 1);
    if (dir == 'g') return isEven ? HexCoordinate(c + 1, r - 1) : HexCoordinate(c, r - 1);
    return null;
  }

  bool isOutOfBounds(HexCoordinate? hex) {
    if (hex == null) return true;
    if (hex.row >= numRows) return true;
    if (hex.col < 0 || hex.col >= getColumnsForRow(hex.row)) return true;
    return false;
  }

  bool isOccupied(HexCoordinate? hex) {
    if (hex == null) return false;
    return board.containsKey(hex);
  }

  HexCoordinate findNearestEmpty(HexCoordinate start) {
    if (!isOccupied(start)) return start;
    final queue = [start];
    final visited = {start};
    while (queue.isNotEmpty) {
      var curr = queue.removeAt(0);
      for (var dir in ['f', 'g', 'a', 'd', 'b', 'c']) {
        var n = getNeighbor(curr, dir);
        if (n != null && !isOutOfBounds(n) && !visited.contains(n)) {
          if (!isOccupied(n)) return n;
          visited.add(n);
          queue.add(n);
        }
      }
    }
    return start;
  }

  HexCoordinate dropBall(HexCoordinate start, double offsetX) {
      HexCoordinate curr = start;
      while (true) {
         if (curr.row >= numRows - 1) break;

         var a = getNeighbor(curr, 'a');
         var b = getNeighbor(curr, 'b');
         var c = getNeighbor(curr, 'c');
         var d = getNeighbor(curr, 'd');
         var e = getNeighbor(curr, 'e');

         bool bEmpty = !isOccupied(b) && !isOutOfBounds(b);
         bool cEmpty = !isOccupied(c) && !isOutOfBounds(c);
         bool aOccupied = isOccupied(a);
         bool dOccupied = isOccupied(d);

         HexCoordinate next = curr;

         if (bEmpty && cEmpty) {
             if (aOccupied && !dOccupied) {
                 next = c!;
             } else if (!aOccupied && dOccupied) {
                 next = b!;
             } else {
                 bool eEmpty = !isOccupied(e) && !isOutOfBounds(e);
                 if (eEmpty) {
                     next = e!;
                 } else {
                     if (offsetX == 0.0) {
                         next = Random().nextBool() ? b! : c!;
                     } else {
                         next = (offsetX < 0) ? b! : c!;
                     }
                 }
             }
         } else if (bEmpty && !cEmpty) {
             if (!aOccupied) {
                 next = b!;
             } else if (isOutOfBounds(c)) {
                 next = b!;
             }
         } else if (!bEmpty && cEmpty) {
             if (!dOccupied) {
                 next = c!;
             } else if (isOutOfBounds(b)) {
                 next = c!;
             }
         }

         if (next == curr) break;
         curr = next;
      }
      return curr;
  }

  SimGridResult? checkMatchesFrom(HexCoordinate start, BallColor color) {
     Set<HexCoordinate> visited = {};
     Set<HexCoordinate> group = {};
     List<HexCoordinate> queue = [start];
     visited.add(start);

     while (queue.isNotEmpty) {
       var curr = queue.removeAt(0);
       for (var dir in ['a', 'b', 'c', 'd', 'f', 'g']) {
         var n = getNeighbor(curr, dir);
         if (n != null && board.containsKey(n)) {
            if (!visited.contains(n) && board[n] == color) {
               visited.add(n);
               group.add(n);
               queue.add(n);
            }
         }
       }
     }

     if (group.length >= 4) {
        WazaType waza = WazaType.none;
        // Simplified headless waza check
        if (group.length >= 6) {
           waza = group.length >= 7 ? WazaType.pyramid : WazaType.straight;
        }
        return SimGridResult(group, waza);
     }
     return null;
  }
}

double evaluateBoardLogic(SimGrid simGrid, Map<HexCoordinate, BallColor> newBalls, CPUWeights weights, {bool isEasy = false}) {
  double score = 0.0;
  
  // 1. Safety (致死回避)
  int minRow = simGrid.numRows;
  for (var h in simGrid.board.keys) {
     if (h.row < minRow) minRow = h.row;
  }
  
  double safetyWeightPenalty = isEasy ? 1000.0 : 1000000.0;
  safetyWeightPenalty *= weights.safety;
  
  if (minRow <= 2) {
     score -= safetyWeightPenalty; // 高さが盤面の80%を超過
  } else {
     score -= (12 - minRow) * 10.0 * weights.safety; // 積み上がっていること自体への軽いペナルティ
  }

  // 2. Shape Score (ワザ・リーチ)
  Set<HexCoordinate> allMatched = {};
  double shapeScore = 0.0;
  
  for (var entry in newBalls.entries) {
     if (allMatched.contains(entry.key)) continue;

     var result = simGrid.checkMatchesFrom(entry.key, entry.value);
     if (result != null) {
        int mLen = result.matched.length;
        if (mLen >= 6) {
            shapeScore += mLen * 100.0; 
            if (result.waza != WazaType.none) {
               shapeScore += result.waza.multiplier * 20000.0; // Enormous reward for actual Waza
            } else {
               shapeScore += 500.0; // Normal match reward 
            }
        } else if (mLen == 5) {
            shapeScore += 5000.0; // Very high reward for Waza setup (5 connected)
        } else if (mLen == 4) {
            shapeScore += 1000.0;
        }
        allMatched.addAll(result.matched);
     }
  }
  score += shapeScore * weights.shape;

  // 3. Flatness (盤面の平坦さ)
  List<int> colHeights = List.filled(10, simGrid.numRows);
  for (var h in simGrid.board.keys) {
     if (h.col >= 0 && h.col < 10 && h.row < colHeights[h.col]) {
        colHeights[h.col] = h.row;
     }
  }
  double flatnessPenalty = 0.0;
  for (int c = 0; c < 9; c++) {
     int diff = (colHeights[c] - colHeights[c+1]).abs();
     flatnessPenalty += diff * 15.0; 
  }
  score -= flatnessPenalty * weights.flatness;

  // 4. Color Clustering (色のグループ化)
  int adjacencyCount = 0;
  for (var entry in newBalls.entries) {
     for (var dir in ['a', 'b', 'c', 'd', 'f', 'g']) {
        var n = simGrid.getNeighbor(entry.key, dir);
        if (n != null && simGrid.board[n] == entry.value) {
           adjacencyCount++;
        }
     }
  }
  score += adjacencyCount * 25.0 * weights.connection;

  return score;
}
