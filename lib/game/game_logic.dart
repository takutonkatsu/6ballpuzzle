import 'dart:math';
import 'game_models.dart';

class CPUWeights {
  final double safety;
  final double shape;
  final double flatness;
  final double connection;

  final double wazaBonus;
  final double hintBonus;
  final double reachBonus;
  final double cavePenalty;
  final double dumpBonus;

  final double hintPenalty;

  const CPUWeights({
    this.safety = 100.0,
    this.shape = 5.0,
    this.flatness = 2.0,
    this.connection = 5.0,
    this.wazaBonus = 10000000.0,
    this.hintBonus = 1000000.0,
    this.reachBonus = 500000.0,
    this.cavePenalty = 1000000.0,
    this.dumpBonus = 10000.0,
    this.hintPenalty = 500000.0,
  });
}

class WazaPatternDef {
  final List<HexCoordinate> hexes;
  final WazaType type;
  WazaPatternDef(this.hexes, this.type);
}

class WazaPatterns {
  static List<List<HexCoordinate>> allPatterns = [];
  static List<WazaPatternDef> detailedPatterns = [];
  static bool _initialized = false;

  static void init(int numRows) {
    if (_initialized) return;
    _initialized = true;
    List<HexCoordinate> allHexes = [];
    for (int r = 0; r < numRows; r++) {
      int cols = r.isOdd ? 10 : 9;
      for (int c = 0; c < cols; c++) {
        allHexes.add(HexCoordinate(c, r));
      }
    }

    for (var center in allHexes) {
      List<HexCoordinate> ring = [];
      bool valid = true;
      for (var dir in ['a', 'b', 'c', 'd', 'f', 'g']) {
        var n = _getN(center, dir, numRows);
        if (n == null) {
          valid = false;
          break;
        }
        ring.add(n);
      }
      if (valid) {
        allPatterns.add(ring);
        detailedPatterns.add(WazaPatternDef(ring, WazaType.hexagon));
      }
    }

    for (var hex in allHexes) {
      var bl1 = _getN(hex, 'b', numRows);
      var br1 = _getN(hex, 'c', numRows);
      if (bl1 != null && br1 != null) {
        var bl2 = _getN(bl1, 'b', numRows);
        var br2 = _getN(bl1, 'c', numRows);
        var br3 = _getN(br1, 'c', numRows);
        if (bl2 != null && br2 != null && br3 != null) {
          var pat = [hex, bl1, br1, bl2, br2, br3];
          allPatterns.add(pat);
          detailedPatterns.add(WazaPatternDef(pat, WazaType.pyramid));
        }
      }
      var tl1 = _getN(hex, 'f', numRows);
      var tr1 = _getN(hex, 'g', numRows);
      if (tl1 != null && tr1 != null) {
        var tl2 = _getN(tl1, 'f', numRows);
        var tr2 = _getN(tl1, 'g', numRows);
        var tr3 = _getN(tr1, 'g', numRows);
        if (tl2 != null && tr2 != null && tr3 != null) {
          var pat = [hex, tl1, tr1, tl2, tr2, tr3];
          allPatterns.add(pat);
          detailedPatterns.add(WazaPatternDef(pat, WazaType.pyramid));
        }
      }
    }

    for (var hex in allHexes) {
      for (var dir in ['d', 'c', 'b']) {
        List<HexCoordinate> line = [hex];
        var curr = hex;
        bool valid = true;
        for (int i = 0; i < 5; i++) {
          var n = _getN(curr, dir, numRows);
          if (n == null) {
            valid = false;
            break;
          }
          line.add(n);
          curr = n;
        }
        if (valid) {
          allPatterns.add(line);
          detailedPatterns.add(WazaPatternDef(line, WazaType.straight));
        }
      }
    }
  }

  static HexCoordinate? _getN(HexCoordinate hex, String dir, int numRows) {
    int r = hex.row;
    int c = hex.col;
    bool isEven = r.isEven;
    HexCoordinate? res;
    if (dir == 'a')
      res = HexCoordinate(c - 1, r);
    else if (dir == 'd')
      res = HexCoordinate(c + 1, r);
    else if (dir == 'b')
      res = isEven ? HexCoordinate(c, r + 1) : HexCoordinate(c - 1, r + 1);
    else if (dir == 'c')
      res = isEven ? HexCoordinate(c + 1, r + 1) : HexCoordinate(c, r + 1);
    else if (dir == 'e')
      res = HexCoordinate(c, r + 2);
    else if (dir == 'f')
      res = isEven ? HexCoordinate(c, r - 1) : HexCoordinate(c - 1, r - 1);
    else if (dir == 'g')
      res = isEven ? HexCoordinate(c + 1, r - 1) : HexCoordinate(c, r - 1);
    if (res != null) {
      if (res.row < 0 || res.row >= numRows) return null;
      int cols = res.row.isOdd ? 10 : 9;
      if (res.col < 0 || res.col >= cols) return null;
    }
    return res;
  }
}

class SimGridResult {
  final Set<HexCoordinate> matched;
  final WazaType waza;
  final int ballsNeeded;
  SimGridResult(this.matched, this.waza, {this.ballsNeeded = 0});
}

class SimDropResult {
  final SimGrid simGrid;
  final Map<HexCoordinate, BallColor> newBalls;
  final Set<HexCoordinate> allMatched;
  final bool wazaCompleted;
  final double highestWazaMult;
  SimDropResult(this.simGrid, this.newBalls, this.allMatched,
      {this.wazaCompleted = false, this.highestWazaMult = 0.0});
}

class SimGrid {
  final int numRows;
  final Map<HexCoordinate, BallColor> board;

  SimGrid(this.numRows, Map<HexCoordinate, BallColor> original)
      : board = Map.from(original);

  int getColumnsForRow(int row) => row.isOdd ? 10 : 9;

  HexCoordinate? getNeighbor(HexCoordinate hex, String dir) {
    return WazaPatterns._getN(hex, dir, numRows);
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

  HexCoordinate dropBall(HexCoordinate start, double offsetX,
      {BallColor? color}) {
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
              next = _deterministicSlideRight(curr, color) ? b! : c!;
            } else {
              next = (offsetX < 0) ? b! : c!;
            }
          }
        }
      } else if (bEmpty && !cEmpty) {
        if (!aOccupied)
          next = b!;
        else if (isOutOfBounds(c)) next = b!;
      } else if (!bEmpty && cEmpty) {
        if (!dOccupied)
          next = c!;
        else if (isOutOfBounds(b)) next = c!;
      }

      if (next == curr) break;
      curr = next;
      offsetX = 0;
    }
    return curr;
  }

  bool _deterministicSlideRight(HexCoordinate curr, BallColor? color) {
    var hash = 17;
    hash = 31 * hash + curr.col;
    hash = 31 * hash + curr.row;
    hash = 31 * hash + (color?.index ?? 0);
    return hash.abs() % 2 == 0;
  }

  SimGridResult? checkMatchesFrom(HexCoordinate start, BallColor color) {
    Set<HexCoordinate> visited = {start};
    Set<HexCoordinate> group = {start};
    List<HexCoordinate> queue = [start];
    while (queue.isNotEmpty) {
      var curr = queue.removeAt(0);
      for (var dir in ['a', 'b', 'c', 'd', 'f', 'g']) {
        var n = getNeighbor(curr, dir);
        if (n != null && board.containsKey(n) && !visited.contains(n)) {
          if (board[n] == color) {
            visited.add(n);
            group.add(n);
            queue.add(n);
          }
        }
      }
    }
    return SimGridResult(group, WazaType.none,
        ballsNeeded: max(0, 6 - group.length));
  }
}

double evaluateBoardLogic(
    SimGrid simGrid, Map<HexCoordinate, BallColor> newBalls, CPUWeights weights,
    {bool isEasy = false, Map<HexCoordinate, Set<BallColor>>? hintHexes}) {
  double score = 0.0;
  WazaPatterns.init(simGrid.numRows);

  List<int> colH = List.filled(10, 12);
  for (var h in simGrid.board.keys) {
    if (h.col >= 0 && h.col < 10 && h.row < colH[h.col]) colH[h.col] = h.row;
  }

  int minRow = 12;
  for (int c = 0; c < 10; c++) if (colH[c] < minRow) minRow = colH[c];

  int maxHeight = 12 - minRow;
  double currentSafety = weights.safety;

  if (maxHeight >= 8)
    currentSafety *= 10.0;
  else if (maxHeight >= 5) currentSafety *= 2.0;

  if (minRow <= 2) return -1000000000.0;
  score -= pow(2, maxHeight) * 10.0 * currentSafety;

  double blueprintScore = 0.0;

  for (var def in WazaPatterns.detailedPatterns) {
    var pattern = def.hexes;
    BallColor? pColor;
    int colorCount = 0;
    bool isDead = false;
    List<HexCoordinate> emptySpots = [];

    for (var hex in pattern) {
      if (simGrid.isOccupied(hex)) {
        var c = simGrid.board[hex]!;
        if (pColor == null) {
          pColor = c;
          colorCount++;
        } else if (pColor == c) {
          colorCount++;
        } else {
          isDead = true;
          break;
        }
      } else {
        emptySpots.add(hex);
      }
    }

    if (isDead || colorCount == 0 || colorCount == 6) continue;

    int openEmpties = 0;
    for (var e in emptySpots) {
      if (colH[e.col] > e.row - 1) {
        openEmpties++;
      } else {
        var upL = simGrid.getNeighbor(e, 'f');
        var upR = simGrid.getNeighbor(e, 'g');
        bool upLOpen = upL != null && !simGrid.isOccupied(upL);
        bool upROpen = upR != null && !simGrid.isOccupied(upR);
        if (upLOpen || upROpen) openEmpties++;
      }
    }

    if (openEmpties < emptySpots.length) continue;

    // 🌟 最大の進化：土台作り（序盤）の価値を数十倍に底上げし、ゴミ掃除より優先させる
    double baseScore = 0.0;
    if (colorCount == 5)
      baseScore = weights.reachBonus * 20.0;
    else if (colorCount == 4)
      baseScore = weights.reachBonus * 5.0;
    else if (colorCount == 3)
      baseScore = weights.reachBonus * 1.0;
    else if (colorCount == 2)
      baseScore = weights.reachBonus * 0.2;
    else if (colorCount == 1) baseScore = weights.reachBonus * 0.05;

    double mult = def.type.multiplier;
    if (def.type == WazaType.hexagon) {
      mult *= 1.5; // 🌟 ヘキサゴンへの凄まじい執着（特効ボーナス）
    }

    blueprintScore += baseScore * (1.0 + (openEmpties * 0.1)) * mult;
  }

  score += blueprintScore;

  Set<HexCoordinate> allMatched = {};
  for (var entry in newBalls.entries) {
    if (allMatched.contains(entry.key)) continue;
    var result = simGrid.checkMatchesFrom(entry.key, entry.value);
    if (result != null) {
      int mLen = result.matched.length;
      if (mLen >= 6) {
        score += 50000.0;
      } else if (mLen >= 4) {
        score -= 50000.0;
      }
      allMatched.addAll(result.matched);
    }
  }

  for (int c = 0; c < 9; c++)
    score -= (colH[c] - colH[c + 1]).abs() * 20.0 * weights.flatness;
  score += newBalls.length * weights.connection;

  return score;
}
