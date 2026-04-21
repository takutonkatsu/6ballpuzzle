import 'dart:math';
import 'package:flame/components.dart';
import 'components/ball_component.dart';
import 'game_models.dart';
import 'game_logic.dart';

class GridSystem {
  final int numRows = 12;
  final double ballRadius;
  
  final Map<HexCoordinate, BallComponent> lockedBalls = {};
  
  late double floorY;
  late double leftWallX;
  late double rightWallX;
  late Vector2 offset;

  GridSystem({
    this.ballRadius = 15.0,
    Vector2? offset,
  }) {
    this.offset = offset ?? Vector2.zero();
    updateBounds();
  }

  void updateBounds() {
    double maxCenterY = hexToPixel(HexCoordinate(0, numRows - 1)).y;
    floorY = maxCenterY + ballRadius;

    leftWallX = offset.x - ballRadius;
    rightWallX = offset.x + (10 * ballRadius * 2) - ballRadius;
  }

  int getColumnsForRow(int row) {
    return row.isOdd ? 10 : 9;
  }

  Vector2 hexToPixel(HexCoordinate hex) {
    double xOffset = hex.row.isEven ? ballRadius : 0.0;
    double x = offset.x + xOffset + hex.col * (ballRadius * 2);
    double rowHeight = ballRadius * sqrt(3);
    double y = offset.y + hex.row * rowHeight;
    return Vector2(x, y);
  }

  HexCoordinate pixelToHex(Vector2 point) {
    double rowHeight = ballRadius * sqrt(3);
    int closestRow = ((point.y - offset.y) / rowHeight).round();
    closestRow = min(closestRow, numRows - 1);
    
    double xOffset = closestRow.isEven ? ballRadius : 0.0;
    int closestCol = ((point.x - offset.x - xOffset) / (ballRadius * 2)).round();
    int maxCols = getColumnsForRow(closestRow);
    closestCol = max(0, min(closestCol, maxCols - 1)); // 左右は引き続き制限
    
    return HexCoordinate(closestCol, closestRow);
  }

  bool isOutOfBounds(HexCoordinate? hex) {
    if (hex == null) return true;
    // 12段目を超える分（上空への積み上がり）はエラーとせず行を許可し、後でゲームオーバー判定に使う
    if (hex.row >= numRows) return true; // 下は突き抜けない
    if (hex.col < 0 || hex.col >= getColumnsForRow(hex.row)) return true; // 左右は突き抜けない
    return false;
  }

  bool isOccupied(HexCoordinate? hex) {
    if (hex == null) return false;
    return lockedBalls.containsKey(hex);
  }

  bool isBlocked(HexCoordinate? hex) {
    return isOutOfBounds(hex) || isOccupied(hex);
  }

  HexCoordinate? getNeighbor(HexCoordinate hex, String dir) {
    int r = hex.row;
    int c = hex.col;
    bool isEven = r.isEven;

    if (dir == 'a') return HexCoordinate(c - 1, r); // 左
    if (dir == 'd') return HexCoordinate(c + 1, r); // 右
    if (dir == 'b') return isEven ? HexCoordinate(c, r + 1) : HexCoordinate(c - 1, r + 1); // 左下
    if (dir == 'c') return isEven ? HexCoordinate(c + 1, r + 1) : HexCoordinate(c, r + 1); // 右下
    if (dir == 'e') return HexCoordinate(c, r + 2); // 真下(2段下)
    if (dir == 'f') return isEven ? HexCoordinate(c, r - 1) : HexCoordinate(c - 1, r - 1); // 左上
    if (dir == 'g') return isEven ? HexCoordinate(c + 1, r - 1) : HexCoordinate(c, r - 1); // 右上

    return null;
  }

  /// 指定したマスの周囲の空いているマスを探す（落下中の干渉防止用）
  HexCoordinate findNearestEmpty(HexCoordinate start) {
    if (!isBlocked(start)) return start;
    
    final queue = [start];
    final visited = {start.toString()};
    
    while(queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      if (!isBlocked(curr)) return curr;

      for (var dir in ['a', 'd', 'b', 'c', 'f', 'g']) {
        var next = getNeighbor(curr, dir);
        if (next != null && !isOutOfBounds(next) && !visited.contains(next.toString())) {
          visited.add(next.toString());
          queue.add(next);
        }
      }
    }
    return start; // Fallback
  }

  /// 連結したボールを消滅させる判定・およびワザの検知
  List<MatchResult> findMatchesAndWazas() {
    Set<HexCoordinate> visited = {};
    List<MatchResult> results = [];
    
    // 全ボールから同色の連結成分を探す
    for (var hex in lockedBalls.keys) {
      if (visited.contains(hex)) continue;
      
      var color = lockedBalls[hex]!.ballColor;
      Set<HexCoordinate> component = {hex};
      List<HexCoordinate> queue = [hex];
      visited.add(hex);
      
      while (queue.isNotEmpty) {
        var curr = queue.removeAt(0);
        for (var dir in ['a', 'b', 'c', 'd', 'f', 'g']) {
          var neighbor = getNeighbor(curr, dir);
          if (neighbor != null && lockedBalls.containsKey(neighbor)) {
             if (!visited.contains(neighbor) && lockedBalls[neighbor]!.ballColor == color) {
                visited.add(neighbor);
                component.add(neighbor);
                queue.add(neighbor);
             }
          }
        }
      }
      
      // 6個以上繋がっていた場合
      if (component.length >= 6) {
         Set<HexCoordinate> groupToDestroy = {};
         var wazaResult = _checkWazaWithPattern(component);
         WazaType waza = wazaResult.type;
         
         if (waza != WazaType.none) {
            // ワザ発動: 盤面にある同色ボールをすべて消去対象に
            for (var target in lockedBalls.keys) {
               if (lockedBalls[target]!.ballColor == color) {
                  groupToDestroy.add(target);
               }
            }
         } else {
            // 通常消去
            groupToDestroy.addAll(component);
         }
         
         results.add(MatchResult(
           groupToDestroy, 
           waza,
           wazaPattern: wazaResult.pattern,
           wazaColor: color,
         ));
      }
    }
    
    // ワザの優先度降順でソート
    results.sort((a, b) => b.highestWaza.multiplier.compareTo(a.highestWaza.multiplier));
    
    return results;
  }

  _WazaResult _checkWazaWithPattern(Set<HexCoordinate> group) {
     var hexResult = _checkHexagonWithPattern(group);
     if (hexResult != null) return _WazaResult(WazaType.hexagon, hexResult);
     var pyramidResult = _checkPyramidWithPattern(group);
     if (pyramidResult != null) return _WazaResult(WazaType.pyramid, pyramidResult);
     var straightResult = _checkStraightWithPattern(group);
     if (straightResult != null) return _WazaResult(WazaType.straight, straightResult);
     return _WazaResult(WazaType.none, []);
  }

  // ---- パターン順序付きワザ検知メソッド ----

  List<List<HexCoordinate>>? _checkHexagonWithPattern(Set<HexCoordinate> group) {
    // 中心候補を探す
    Set<HexCoordinate> potentialCenters = {};
    for (var hex in group) {
      for (var dir in ['a', 'b', 'c', 'd', 'f', 'g']) {
         var neighbor = getNeighbor(hex, dir);
         if (neighbor != null) potentialCenters.add(neighbor);
      }
    }
    for (var center in potentialCenters) {
       List<HexCoordinate> ring = [];
       bool ok = true;
       // 右上から時計回り: g, d, c, b, a, f
       for (var dir in ['g', 'd', 'c', 'b', 'a', 'f']) {
           var n = getNeighbor(center, dir);
           if (n == null || !group.contains(n)) { ok = false; break; }
           ring.add(n);
       }
       if (ok) return ring.map((h) => [h]).toList(); // 1個ずつ発光
    }
    return null;
  }

  List<List<HexCoordinate>>? _checkPyramidWithPattern(Set<HexCoordinate> group) {
    for (var hex in group) {
       // 上向きピラミッド（hexが頂点）: 下段→中段→上段
       var bl1 = getNeighbor(hex, 'b');
       var br1 = getNeighbor(hex, 'c');
       if (bl1 != null && br1 != null && group.contains(bl1) && group.contains(br1)) {
           var bl2 = getNeighbor(bl1, 'b');
           var br2 = getNeighbor(bl1, 'c');
           var br3 = getNeighbor(br1, 'c');
           if (bl2 != null && br2 != null && br3 != null &&
               group.contains(bl2) && group.contains(br2) && group.contains(br3)) {
               return [[bl2, br2, br3], [bl1, br1], [hex]]; // 下段→中段→上段
           }
       }
       // 下向きピラミッド（hexが底）: 上段→中段→下段
       var tl1 = getNeighbor(hex, 'f');
       var tr1 = getNeighbor(hex, 'g');
       if (tl1 != null && tr1 != null && group.contains(tl1) && group.contains(tr1)) {
           var tl2 = getNeighbor(tl1, 'f');
           var tr2 = getNeighbor(tl1, 'g');
           var tr3 = getNeighbor(tr1, 'g');
           if (tl2 != null && tr2 != null && tr3 != null &&
               group.contains(tl2) && group.contains(tr2) && group.contains(tr3)) {
               return [[tl2, tr2, tr3], [tl1, tr1], [hex]]; // 上段→中段→下段
           }
       }
    }
    return null;
  }

  List<List<HexCoordinate>>? _checkStraightWithPattern(Set<HexCoordinate> group) {
    for (var hex in group) {
       for (var dir in ['d', 'c', 'b']) {
          List<HexCoordinate> line = [hex];
          var curr = hex;
          bool ok = true;
          for (int i = 0; i < 5; i++) {
             var n = getNeighbor(curr, dir);
             if (n == null || !group.contains(n)) { ok = false; break; }
             line.add(n);
             curr = n;
          }
          if (ok) return line.map((h) => [h]).toList(); // 1個ずつ左から(もしくは下から)
       }
    }
    return null;
  }

  /// ワザまであと1〜2個のヒント: 優先順位(ヘキサゴン>ピラミッド>ストレート)で1ワザのみ表示
  Map<HexCoordinate, Set<BallColor>> getHintHexes() {
    final Map<HexCoordinate, Set<BallColor>> result = {};
    final Set<BallColor> presentColors = lockedBalls.values.map((b) => b.ballColor).toSet();

    // 盤面全体の座標リストを一度だけ生成
    final allHexes = <HexCoordinate>[];
    for (int r = 0; r < numRows; r++) {
      for (int c = 0; c < getColumnsForRow(r); c++) {
        allHexes.add(HexCoordinate(c, r));
      }
    }

    // 全パターンを一度だけ生成（パフォーマンス改善）
    final hexagonPatterns = _generateHexagonPatterns(allHexes);
    final pyramidPatterns = _generatePyramidPatterns(allHexes);
    final straightPatterns = _generateStraightPatterns(allHexes);

    for (var color in presentColors) {
      // 優先順位1: ヘキサゴン
      List<HexCoordinate>? spots = _findBestHintSpots(color, hexagonPatterns);
      // 優先順位2: ピラミッド
      spots ??= _findBestHintSpots(color, pyramidPatterns);
      // 優先順位3: ストレート
      spots ??= _findBestHintSpots(color, straightPatterns);

      if (spots != null) {
        for (var h in spots) {
          result.putIfAbsent(h, () => {}).add(color);
        }
      }
    }

    return result;
  }

  /// 盤面全体のヘキサゴンパターン（6個のリング）を列挙する
  List<List<HexCoordinate>> _generateHexagonPatterns(List<HexCoordinate> allHexes) {
    final patterns = <List<HexCoordinate>>[];
    for (var center in allHexes) {
      final ring = <HexCoordinate>[];
      bool valid = true;
      for (var dir in ['a', 'b', 'c', 'd', 'f', 'g']) {
        final n = getNeighbor(center, dir);
        if (n == null || isOutOfBounds(n)) { valid = false; break; }
        ring.add(n);
      }
      if (valid && ring.length == 6) patterns.add(ring);
    }
    return patterns;
  }

  /// 盤面全体のピラミッドパターン（上向き・下向き）を列挙する
  List<List<HexCoordinate>> _generatePyramidPatterns(List<HexCoordinate> allHexes) {
    final patterns = <List<HexCoordinate>>[];
    for (var hex in allHexes) {
      // 上向きピラミッド
      final bl1 = getNeighbor(hex, 'b');
      final br1 = getNeighbor(hex, 'c');
      if (bl1 != null && br1 != null && !isOutOfBounds(bl1) && !isOutOfBounds(br1)) {
        final bl2 = getNeighbor(bl1, 'b');
        final br2 = getNeighbor(bl1, 'c');
        final br3 = getNeighbor(br1, 'c');
        if (bl2 != null && br2 != null && br3 != null &&
            !isOutOfBounds(bl2) && !isOutOfBounds(br2) && !isOutOfBounds(br3)) {
          patterns.add([hex, bl1, br1, bl2, br2, br3]);
        }
      }
      // 下向きピラミッド
      final tl1 = getNeighbor(hex, 'f');
      final tr1 = getNeighbor(hex, 'g');
      if (tl1 != null && tr1 != null && !isOutOfBounds(tl1) && !isOutOfBounds(tr1)) {
        final tl2 = getNeighbor(tl1, 'f');
        final tr2 = getNeighbor(tl1, 'g');
        final tr3 = getNeighbor(tr1, 'g');
        if (tl2 != null && tr2 != null && tr3 != null &&
            !isOutOfBounds(tl2) && !isOutOfBounds(tr2) && !isOutOfBounds(tr3)) {
          patterns.add([hex, tl1, tr1, tl2, tr2, tr3]);
        }
      }
    }
    return patterns;
  }

  /// 盤面全体のストレートパターン（水平・斜め）を列挙する
  List<List<HexCoordinate>> _generateStraightPatterns(List<HexCoordinate> allHexes) {
    final patterns = <List<HexCoordinate>>[];
    for (var hex in allHexes) {
      for (var dir in ['d', 'c', 'b']) {
        final line = <HexCoordinate>[hex];
        var curr = hex;
        bool valid = true;
        for (int i = 0; i < 5; i++) {
          final n = getNeighbor(curr, dir);
          if (n == null || isOutOfBounds(n)) { valid = false; break; }
          line.add(n);
          curr = n;
        }
        if (valid && line.length == 6) patterns.add(line);
      }
    }
    return patterns;
  }

  List<HexCoordinate>? _findBestHintSpots(BallColor color, List<List<HexCoordinate>> patterns) {
    for (final targetFilled in [5, 4]) {
      for (var pattern in patterns) {
        int colorCount = 0;
        final emptySpots = <HexCoordinate>[];
        bool invalid = false;

        for (var h in pattern) {
          if (lockedBalls.containsKey(h)) {
            if (lockedBalls[h]!.ballColor == color) {
              colorCount++;
            } else {
              invalid = true;
              break;
            }
          } else if (isOutOfBounds(h)) {
            invalid = true;
            break;
          } else {
            emptySpots.add(h);
          }
        }

        if (invalid || colorCount != targetFilled || emptySpots.length != 6 - targetFilled) continue;

        // Simulate dropping into these specific empty spots
        Map<HexCoordinate, BallColor> boardCopy = {};
        for (var entry in lockedBalls.entries) boardCopy[entry.key] = entry.value.ballColor;
        SimGrid sim = SimGrid(numRows, boardCopy);
        
        var sortedEmpty = List<HexCoordinate>.from(emptySpots)..sort((a, b) => b.row.compareTo(a.row));
        
        bool canFill = true;
        for (var spot in sortedEmpty) {
           bool isSupported = _isAccessibleFromTop(spot, sim);
           if (isSupported) {
              sim.board[spot] = color;
           } else {
              canFill = false;
              break;
           }
        }
        
        if (canFill) {
            return emptySpots;
        }
      }
    }
    return null;
  }

  bool _isAccessibleFromTop(HexCoordinate start, SimGrid sim) {
     if (start.row <= 0) return true;
     List<HexCoordinate> queue = [start];
     Set<HexCoordinate> visited = {start};
     while (queue.isNotEmpty) {
        var curr = queue.removeAt(0);
        if (curr.row <= 0) return true;
        for (var dir in ['f', 'g', 'a', 'd', 'b', 'c']) {
           var n = sim.getNeighbor(curr, dir);
           if (n != null && !sim.isOutOfBounds(n) && !sim.isOccupied(n) && !visited.contains(n)) {
              if (n.row <= 0) return true;
              visited.add(n);
              queue.add(n);
           }
        }
     }
     return false;
  }

  bool _areHexesContiguous(List<HexCoordinate> hexes) {
    if (hexes.isEmpty) return true;
    final Set<HexCoordinate> hexSet = hexes.toSet();
    final Set<HexCoordinate> visited = {hexes.first};
    final List<HexCoordinate> queue = [hexes.first];
    
    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (var dir in ['a', 'b', 'c', 'd', 'f', 'g']) {
        final n = getNeighbor(curr, dir);
        if (n != null && hexSet.contains(n) && !visited.contains(n)) {
          visited.add(n);
          queue.add(n);
        }
      }
    }
    return visited.length == hexes.length;
  }

  /// あるマスが上空（最上段）から到達可能かどうか（埋もれていないか）を判定する
  bool isReachable(HexCoordinate start) {
    if (start.row == 0) return true;
    
    // BFSで上空へ辿れるかチェック
    final visited = <HexCoordinate>{};
    final queue = <HexCoordinate>[start];
    visited.add(start);

    int idx = 0;
    while (idx < queue.length) {
      final curr = queue[idx++];
      if (curr.row == 0) return true; // 最上段に到達＝経路が開いている

      // 斜め上のマス（f:左上, g:右上）から落下してこれるかを逆順で辿る
      // 厳密には、真上方面にボールがない「空洞経路」があれば落ちてこれる
      final f = getNeighbor(curr, 'f');
      final g = getNeighbor(curr, 'g');

      for (var n in [f, g]) {
        if (n != null && !isOutOfBounds(n) && !isOccupied(n)) {
          if (!visited.contains(n)) {
            visited.add(n);
            queue.add(n);
          }
        }
      }
    }
    return false; // 最上段まで辿り着けなかった＝完全にボールで蓋をされている
  }
}

class _WazaResult {
  final WazaType type;
  final List<List<HexCoordinate>> pattern;
  _WazaResult(this.type, this.pattern);
}
