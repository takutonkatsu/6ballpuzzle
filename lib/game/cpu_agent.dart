// ignore_for_file: curly_braces_in_flow_control_structures, non_constant_identifier_names, unnecessary_non_null_assertion, use_super_parameters

import 'dart:math';
import 'dart:async';
import 'package:flame/components.dart';
import 'puzzle_game.dart';
import 'game_models.dart';
import 'game_logic.dart';

class _SeedInfo {
  final int needed;
  final WazaType type;
  _SeedInfo(this.needed, this.type);
}

class _EvalOption {
  final double x;
  final int rot;
  final double score;
  double totalScore;
  final ExtendedSimDropResult simResult;

  _EvalOption(this.x, this.rot, this.score, this.simResult)
      : totalScore = score;
}

class _BoardMetrics {
  final int totalHeight;
  final int maxHeight;
  final int holes;
  final int roughness;

  const _BoardMetrics({
    required this.totalHeight,
    required this.maxHeight,
    required this.holes,
    required this.roughness,
  });
}

class ExtendedSimDropResult extends SimDropResult {
  final bool shapeCollapsed;
  ExtendedSimDropResult(SimGrid simGrid, Map<HexCoordinate, BallColor> newBalls,
      Set<HexCoordinate> allMatched,
      {bool wazaCompleted = false,
      double highestWazaMult = 0.0,
      this.shapeCollapsed = false})
      : super(simGrid, newBalls, allMatched,
            wazaCompleted: wazaCompleted, highestWazaMult: highestWazaMult);
}

class CPUAgent {
  final PuzzleGame game;
  CPUDifficulty difficulty;
  final CPUWeights weights;

  double? _targetPixelX;
  int _targetRotationCount = 0;
  bool _isThinking = false;
  bool _isComputing = false;

  double _timer = 0.0;
  double _rotationTimer = 0.0;
  double _dropTimer = 0.0;

  final Random _random = Random();

  CPUAgent(
    this.game, {
    this.difficulty = CPUDifficulty.hard,
    this.weights = const CPUWeights(),
  }) {
    _applyDifficultySettings();
  }

  void setDifficulty(CPUDifficulty nextDifficulty) {
    difficulty = nextDifficulty;
    _applyDifficultySettings();
  }

  void _applyDifficultySettings() {
    switch (difficulty) {
      case CPUDifficulty.easy:
        _thinkDelay = 2.0;
        _moveDelay = 0.24;
        _mistakeRate = 0.30;
        _lookaheadCount = 0;
        break;
      case CPUDifficulty.normal:
        _thinkDelay = 1.0;
        _moveDelay = 0.16;
        _mistakeRate = 0.0;
        _lookaheadCount = 0;
        break;
      case CPUDifficulty.hard:
        _thinkDelay = 0.5;
        _moveDelay = 0.09;
        _mistakeRate = 0.0;
        _lookaheadCount = 12;
        break;
      case CPUDifficulty.oni:
        _thinkDelay = 0.3;
        _moveDelay = 0.04;
        _mistakeRate = 0.0;
        _lookaheadCount = 0;
        break;
    }
  }

  double _thinkDelay = 0;
  double _moveDelay = 0;
  double _mistakeRate = 0;
  int _lookaheadCount = 4;
  double _lastCpuX = -9999.0;

  void update(double dt) {
    if (game.gameStateWrapper.value != GameState.playing) return;
    if (game.activePiece == null || game.activePiece!.isLocked) {
      _resetState();
      return;
    }

    if (_targetPixelX == null && !_isThinking && !_isComputing) {
      _isThinking = true;
      _timer = _thinkDelay;
    }
    if (_isThinking && (_timer -= dt) <= 0) {
      _isThinking = false;
      _isComputing = true;
      _computeBestMoveAsync();
    }

    if (_targetPixelX != null && !_isComputing) {
      if (_targetRotationCount != 0) {
        if ((_rotationTimer -= dt) <= 0) {
          if (_targetRotationCount > 0) {
            game.rotateRight();
            _targetRotationCount--;
          } else {
            game.rotateLeft();
            _targetRotationCount++;
          }
          _rotationTimer = _moveDelay;
        }
      }

      double currentX = game.activePiece!.position.x;
      double step = game.moveSpeed * dt;

      bool isStuck = (_lastCpuX - currentX).abs() < 0.1 &&
          (currentX - _targetPixelX!).abs() > step;
      _lastCpuX = currentX;

      bool reachedTarget = false;
      if ((currentX - _targetPixelX!).abs() > step && !isStuck) {
        game.activePiece!.position.x +=
            (currentX > _targetPixelX! ? -step : step);
      } else {
        game.activePiece!.position.x = isStuck ? currentX : _targetPixelX!;
        reachedTarget = true;
      }

      if (reachedTarget && _targetRotationCount == 0) {
        if ((_dropTimer -= dt) <= 0) {
          game.hardDrop();
          _resetState();
        }
      } else {
        _dropTimer = _moveDelay;
      }
    }
  }

  void _resetState() {
    _targetPixelX = null;
    _targetRotationCount = 0;
    _isThinking = false;
    _isComputing = false;
    _lastCpuX = -9999.0;
    _timer = 0.0;
    _rotationTimer = 0.0;
    _dropTimer = 0.0;
  }

  double _evaluateSim(
      ExtendedSimDropResult sim,
      Map<HexCoordinate, Map<BallColor, _SeedInfo>> wazaSeeds,
      Map<HexCoordinate, BallColor> originalBoard) {
    if (sim.shapeCollapsed) {
      return -100000000000000.0;
    }

    double score = evaluateBoardLogic(sim.simGrid, sim.newBalls, weights);

    if (score <= -900000000.0) score -= 10000000000.0;
    if (sim.wazaCompleted) score += 1000000000000.0 * sim.highestWazaMult;

    if (sim.allMatched.isNotEmpty && !sim.wazaCompleted) {
      bool isPrematureClear = false;
      for (var def in WazaPatterns.detailedPatterns) {
        var pattern = def.hexes;
        BallColor? pColor;
        int colorCount = 0;
        int matchedCount = 0;
        bool isDead = false;

        for (var hex in pattern) {
          if (sim.simGrid.isOccupied(hex) || sim.allMatched.contains(hex)) {
            var c = sim.newBalls[hex] ??
                sim.simGrid.board[hex] ??
                originalBoard[hex];

            if (c != null) {
              if (pColor == null) {
                pColor = c;
                colorCount++;
              } else if (pColor == c) {
                colorCount++;
              } else {
                isDead = true;
                break;
              }

              if (sim.allMatched.contains(hex)) matchedCount++;
            }
          }
        }

        if (!isDead && colorCount >= 4 && colorCount <= 5 && matchedCount > 0) {
          isPrematureClear = true;
          break;
        }
      }

      if (isPrematureClear) {
        score -= 5000000000.0;
      } else {
        score += 3000000.0;
      }
    }

    int harmlessCount = 0;

    for (var entry in sim.newBalls.entries) {
      var pos = entry.key;
      var color = entry.value;

      if (wazaSeeds.containsKey(pos)) {
        var colorNeeds = wazaSeeds[pos]!;
        if (colorNeeds.containsKey(color)) {
          var info = colorNeeds[color]!;
          int needed = info.needed;
          double mult = info.type.multiplier;

          if (needed == 1)
            score += weights.hintBonus * 2.0 * mult;
          else if (needed == 2)
            score += weights.reachBonus * 5.0 * mult;
          else if (needed == 3) score += weights.reachBonus * 2.0 * mult;

          int minOtherNeeded = 99;
          for (var otherColor in colorNeeds.keys) {
            if (otherColor != color &&
                colorNeeds[otherColor]!.needed < minOtherNeeded) {
              minOtherNeeded = colorNeeds[otherColor]!.needed;
            }
          }
          if (minOtherNeeded < needed) {
            if (minOtherNeeded == 1)
              score -= 5000000000.0;
            else if (minOtherNeeded == 2)
              score -= 50000000.0;
            else
              score -= 5000000.0;
          }
        } else {
          int minNeeded = colorNeeds.values
              .map((i) => i.needed)
              .reduce((a, b) => a < b ? a : b);
          if (minNeeded == 1)
            score -= 5000000000.0;
          else if (minNeeded == 2)
            score -= 50000000.0;
          else
            score -= 5000000.0;
        }
      } else {
        harmlessCount++;
      }
    }

    for (var seedPos in wazaSeeds.keys) {
      var colorNeeds = wazaSeeds[seedPos]!;
      int minNeeded = colorNeeds.values
          .map((i) => i.needed)
          .reduce((a, b) => a < b ? a : b);

      if (minNeeded <= 2) {
        if (!sim.simGrid.isOccupied(seedPos) &&
            !sim.allMatched.contains(seedPos)) {
          int colH = 12;
          for (int r = 0; r < 12; r++) {
            if (sim.simGrid.isOccupied(HexCoordinate(seedPos.col, r))) {
              colH = r;
              break;
            }
          }
          bool isOpen = false;
          if (colH > seedPos.row - 1)
            isOpen = true;
          else {
            var upL = sim.simGrid.getNeighbor(seedPos, 'f');
            var upR = sim.simGrid.getNeighbor(seedPos, 'g');
            if ((upL != null && !sim.simGrid.isOccupied(upL)) ||
                (upR != null && !sim.simGrid.isOccupied(upR))) {
              isOpen = true;
            }
          }
          if (!isOpen) {
            if (minNeeded == 1)
              score -= 5000000000.0;
            else if (minNeeded == 2) score -= 50000000.0;
          }
        }
      }
    }

    bool hasCriticalSeed = wazaSeeds.values
        .any((map) => map.values.any((info) => info.needed <= 2));
    if (hasCriticalSeed && harmlessCount > 0) {
      score += harmlessCount * weights.dumpBonus;
    }
    return score;
  }

  Future<void> _computeBestMoveAsync() async {
    if (game.activePiece == null) {
      _isComputing = false;
      return;
    }

    Stopwatch stopwatch = Stopwatch()..start();

    List<BallColor> currentColors = game.activePiece!.colors;
    Map<HexCoordinate, BallColor> board =
        game.grid.lockedBalls.map((k, v) => MapEntry(k, v.ballColor));
    var wazaSeeds = _analyzeWazaSeeds(board);

    List<_EvalOption> depth1Options = [];
    double leftWall = game.grid.leftWallX;
    double rightWall = game.grid.rightWallX;

    Set<double> colXCoords = {};
    for (int r = 0; r < 2; r++) {
      int cols = game.grid.getColumnsForRow(r);
      for (int c = 0; c < cols; c++) {
        colXCoords.add(game.grid.hexToPixel(HexCoordinate(c, r)).x);
      }
    }

    for (int rot = 0; rot < 6; rot++) {
      if (stopwatch.elapsedMilliseconds > 16) {
        await Future.delayed(Duration.zero);
        stopwatch.reset();
      }

      double rad = rot * pi / 3;
      List<Vector2> baseOffsets = [
        Vector2(0, -17.32),
        Vector2(-15, 8.66),
        Vector2(15, 8.66)
      ];
      double minNx = 0, maxNx = 0;
      for (int i = 0; i < 3; i++) {
        double nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
        if (nx < minNx) minNx = nx;
        if (nx > maxNx) maxNx = nx;
      }

      double validMinX = leftWall + 15.0 - minNx + 1.0;
      double validMaxX = rightWall - 15.0 - maxNx - 1.0;

      Set<double> validTargetXs = {};

      for (double cx in colXCoords) {
        for (int i = 0; i < 3; i++) {
          double nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
          double possibleX_R = cx - nx + 0.1;
          double possibleX_L = cx - nx - 0.1;
          if (possibleX_R >= validMinX && possibleX_R <= validMaxX)
            validTargetXs.add(possibleX_R);
          if (possibleX_L >= validMinX && possibleX_L <= validMaxX)
            validTargetXs.add(possibleX_L);
        }
      }

      int steps = 10;
      double stepWidth = (validMaxX - validMinX) / steps;
      for (int s = 0; s <= steps; s++) {
        validTargetXs.add(validMinX + (s * stepWidth));
      }

      for (double targetX in validTargetXs) {
        ExtendedSimDropResult sim =
            _simulateDrop(board, targetX, currentColors, rot);
        double score = _evaluateSim(sim, wazaSeeds, board);
        depth1Options.add(_EvalOption(targetX, rot, score, sim));
      }
    }

    depth1Options.sort((a, b) => b.score.compareTo(a.score));

    if (depth1Options.isEmpty) {
      _isComputing = false;
      return;
    }

    _EvalOption selected;
    switch (difficulty) {
      case CPUDifficulty.easy:
        selected = _selectEasyOption(depth1Options);
        break;
      case CPUDifficulty.normal:
        selected = _selectNormalOption(depth1Options);
        break;
      case CPUDifficulty.hard:
        selected = await _selectHardOption(
          depth1Options,
          game.nextPieceColors.value,
          leftWall,
          rightWall,
          colXCoords,
          stopwatch,
        );
        break;
      case CPUDifficulty.oni:
        selected = _selectDemonOption(depth1Options);
        break;
    }

    if (game.activePiece != null && !game.activePiece!.isLocked) {
      _targetPixelX = selected.x;
      int bestRot = selected.rot;
      _targetRotationCount = bestRot > 3 ? bestRot - 6 : bestRot;
    }

    _isComputing = false;
    _rotationTimer = 0.0;
    _dropTimer = _moveDelay;
  }

  _EvalOption _selectEasyOption(List<_EvalOption> options) {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _normalImmediateScore(b).compareTo(
            _normalImmediateScore(a),
          ));

    if (ranked.length > 1 && _random.nextDouble() < _mistakeRate) {
      final inefficientStart = max(1, ranked.length ~/ 2);
      final inefficientPool = ranked.sublist(inefficientStart);
      if (inefficientPool.isNotEmpty) {
        return inefficientPool[_random.nextInt(inefficientPool.length)];
      }
    }

    return ranked.first;
  }

  _EvalOption _selectNormalOption(List<_EvalOption> options) {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _normalImmediateScore(b).compareTo(
            _normalImmediateScore(a),
          ));
    return ranked.first;
  }

  Future<_EvalOption> _selectHardOption(
    List<_EvalOption> options,
    List<BallColor> nextColors,
    double leftWall,
    double rightWall,
    Set<double> colXCoords,
    Stopwatch stopwatch,
  ) async {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _hardImmediateScore(b).compareTo(
            _hardImmediateScore(a),
          ));

    if (nextColors.isEmpty) {
      return ranked.first;
    }

    final checkCount = min(_lookaheadCount, ranked.length);
    for (int i = 0; i < checkCount; i++) {
      if (stopwatch.elapsedMilliseconds > 16) {
        await Future.delayed(Duration.zero);
        stopwatch.reset();
      }

      final opt1 = ranked[i];
      if (opt1.simResult.wazaCompleted || opt1.score <= -10000000000.0) {
        opt1.totalScore = _hardImmediateScore(opt1);
        continue;
      }

      final board2 = opt1.simResult.simGrid.board;
      final wazaSeeds2 = _analyzeWazaSeeds(board2);
      double maxDepth2Score = -double.infinity;

      for (int rot2 = 0; rot2 < 6; rot2++) {
        final validTargetXs2 = _validTargetXsForRotation(
          rot2,
          leftWall,
          rightWall,
          colXCoords,
        );

        for (final targetX2 in validTargetXs2) {
          final sim2 = _simulateDrop(board2, targetX2, nextColors, rot2);
          final score2 = _evaluateSim(sim2, wazaSeeds2, board2);
          final hardScore2 = _hardSimScore(sim2, score2);
          if (hardScore2 > maxDepth2Score) {
            maxDepth2Score = hardScore2;
          }
        }
      }

      opt1.totalScore = _hardImmediateScore(opt1) + (maxDepth2Score * 0.55);
    }

    final topOptions = ranked.sublist(0, checkCount)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return topOptions.first;
  }

  _EvalOption _selectDemonOption(List<_EvalOption> options) {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _demonAttackScore(b).compareTo(
            _demonAttackScore(a),
          ));
    return ranked.first;
  }

  double _normalImmediateScore(_EvalOption option) {
    final sim = option.simResult;
    final clearBonus = sim.allMatched.isEmpty ? 0.0 : 1000000000.0;
    final wazaBonus =
        sim.wazaCompleted ? 10000000000.0 * sim.highestWazaMult : 0.0;
    final clearSizeBonus = sim.allMatched.length * 1000000.0;
    return clearBonus +
        wazaBonus +
        clearSizeBonus +
        _boardControlScore(sim.simGrid) +
        (option.score * 0.001);
  }

  double _hardImmediateScore(_EvalOption option) {
    return _hardSimScore(option.simResult, option.score);
  }

  double _hardSimScore(ExtendedSimDropResult sim, double baseScore) {
    final wazaBonus =
        sim.wazaCompleted ? 20000000000.0 * sim.highestWazaMult : 0.0;
    final chainBonus = sim.allMatched.length * 7000000.0;
    return baseScore + wazaBonus + chainBonus + _boardControlScore(sim.simGrid);
  }

  double _demonAttackScore(_EvalOption option) {
    final sim = option.simResult;
    final attackBonus =
        sim.wazaCompleted ? 1000000000000000.0 * sim.highestWazaMult : 0.0;
    final clearBonus = sim.allMatched.length * 100000000000.0;
    return attackBonus +
        clearBonus +
        option.score +
        (_boardControlScore(sim.simGrid) * 0.05);
  }

  double _boardControlScore(SimGrid simGrid) {
    final metrics = _measureBoard(simGrid);
    return -(metrics.holes * 50000000.0) -
        (metrics.maxHeight * 3000000.0) -
        (metrics.totalHeight * 500000.0) -
        (metrics.roughness * 350000.0);
  }

  _BoardMetrics _measureBoard(SimGrid simGrid) {
    const columnCount = 10;
    final heights = <int>[];
    int holes = 0;

    for (int col = 0; col < columnCount; col++) {
      int? topRow;
      for (int row = 0; row < simGrid.numRows; row++) {
        if (col >= simGrid.getColumnsForRow(row)) {
          continue;
        }

        final hex = HexCoordinate(col, row);
        final occupied = simGrid.isOccupied(hex);
        if (occupied && topRow == null) {
          topRow = row;
        } else if (!occupied && topRow != null) {
          holes++;
        }
      }

      heights.add(topRow == null ? 0 : simGrid.numRows - topRow);
    }

    int roughness = 0;
    for (int i = 0; i < heights.length - 1; i++) {
      roughness += (heights[i] - heights[i + 1]).abs();
    }

    return _BoardMetrics(
      totalHeight: heights.fold(0, (sum, height) => sum + height),
      maxHeight: heights.fold(0, max),
      holes: holes,
      roughness: roughness,
    );
  }

  Set<double> _validTargetXsForRotation(
    int rot,
    double leftWall,
    double rightWall,
    Set<double> colXCoords,
  ) {
    final rad = rot * pi / 3;
    final baseOffsets = [
      Vector2(0, -17.32),
      Vector2(-15, 8.66),
      Vector2(15, 8.66)
    ];
    double minNx = 0;
    double maxNx = 0;

    for (int i = 0; i < 3; i++) {
      final nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
      if (nx < minNx) minNx = nx;
      if (nx > maxNx) maxNx = nx;
    }

    final validMinX = leftWall + 15.0 - minNx + 1.0;
    final validMaxX = rightWall - 15.0 - maxNx - 1.0;
    final targets = <double>{};

    for (final cx in colXCoords) {
      for (int i = 0; i < 3; i++) {
        final nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
        final possibleRight = cx - nx + 0.1;
        final possibleLeft = cx - nx - 0.1;
        if (possibleRight >= validMinX && possibleRight <= validMaxX) {
          targets.add(possibleRight);
        }
        if (possibleLeft >= validMinX && possibleLeft <= validMaxX) {
          targets.add(possibleLeft);
        }
      }
    }

    final stepWidth = (validMaxX - validMinX) / 10;
    for (int step = 0; step <= 10; step++) {
      targets.add(validMinX + (step * stepWidth));
    }

    return targets;
  }

  Map<HexCoordinate, Map<BallColor, _SeedInfo>> _analyzeWazaSeeds(
      Map<HexCoordinate, BallColor> board) {
    Map<HexCoordinate, Map<BallColor, _SeedInfo>> seeds = {};
    SimGrid sim = SimGrid(12, board);
    WazaPatterns.init(12);

    for (var def in WazaPatterns.detailedPatterns) {
      var pattern = def.hexes;
      BallColor? pColor;
      int colorCount = 0;
      bool isDead = false;
      List<HexCoordinate> emptySpots = [];

      for (var hex in pattern) {
        if (sim.isOccupied(hex)) {
          if (pColor == null)
            pColor = sim.board[hex];
          else if (pColor != sim.board[hex]) {
            isDead = true;
            break;
          }
          colorCount++;
        } else {
          emptySpots.add(hex);
        }
      }

      if (!isDead && colorCount >= 3 && colorCount <= 5) {
        int needed = 6 - colorCount;
        for (var e in emptySpots) {
          seeds.putIfAbsent(e, () => {});
          if (!seeds[e]!.containsKey(pColor!) ||
              seeds[e]![pColor!]!.needed > needed) {
            seeds[e]![pColor] = _SeedInfo(needed, def.type);
          } else if (seeds[e]![pColor!]!.needed == needed) {
            if (def.type.multiplier > seeds[e]![pColor!]!.type.multiplier) {
              seeds[e]![pColor] = _SeedInfo(needed, def.type);
            }
          }
        }
      }
    }
    return seeds;
  }

  ExtendedSimDropResult _simulateDrop(Map<HexCoordinate, BallColor> board,
      double x, List<BallColor> colors, int rot) {
    double rad = rot * pi / 3;
    List<Vector2> baseOffsets = [
      Vector2(0, -17.32),
      Vector2(-15, 8.66),
      Vector2(15, 8.66)
    ];
    SimGrid sim = SimGrid(12, board);
    Map<HexCoordinate, BallColor> newBalls = {};

    List<_BallDrop> drops = [];
    for (int i = 0; i < 3; i++) {
      double nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
      double ny = baseOffsets[i].x * sin(rad) + baseOffsets[i].y * cos(rad);
      drops.add(_BallDrop(colors[i], nx, ny));
    }

    double minGy = game.grid.floorY + 1000.0;
    for (var drop in drops) {
      double hitY = game.grid.floorY - 15.0 - drop.ny;
      if (hitY < minGy) minGy = hitY;

      double ballAx = x + drop.nx;
      for (var lockedHex in board.keys) {
        Vector2 lockedPx = game.grid.hexToPixel(lockedHex);
        double dx = ballAx - lockedPx.x;
        if (dx.abs() <= 30.0) {
          double dy = sqrt(900.0 - dx * dx);
          double hitLockedY = lockedPx.y - dy - drop.ny;
          if (hitLockedY < minGy) minGy = hitLockedY;
        }
      }
    }

    drops.sort((a, b) => b.ny.compareTo(a.ny));

    bool shapeCollapsed = false;
    Set<HexCoordinate> initialStartHexes = {};

    for (var drop in drops) {
      Vector2 finalPx = Vector2(x + drop.nx, minGy + drop.ny);
      var start = game.grid.pixelToHex(finalPx);

      if (initialStartHexes.contains(start)) {
        shapeCollapsed = true;
      }
      initialStartHexes.add(start);

      start = sim.findNearestEmpty(start);
      double localOffset = finalPx.x - game.grid.hexToPixel(start).x;

      var finalHex = sim.dropBall(start, localOffset);
      sim.board[finalHex] = drop.color;
      newBalls[finalHex] = drop.color;
    }

    bool wazaCompleted = false;
    double highestWazaMult = 0.0;
    Set<BallColor> wazaColors = {};
    WazaPatterns.init(sim.numRows);

    for (var def in WazaPatterns.detailedPatterns) {
      var pattern = def.hexes;
      BallColor? pColor;
      int colorCount = 0;
      bool isDead = false;
      for (var hex in pattern) {
        if (sim.isOccupied(hex)) {
          if (pColor == null)
            pColor = sim.board[hex];
          else if (pColor != sim.board[hex]) {
            isDead = true;
            break;
          }
          colorCount++;
        }
      }
      if (!isDead && colorCount == 6) {
        bool involvesNew = false;
        for (var hex in pattern) {
          if (newBalls.containsKey(hex)) {
            involvesNew = true;
            break;
          }
        }
        if (involvesNew) {
          wazaCompleted = true;
          wazaColors.add(pColor!);
          if (def.type.multiplier > highestWazaMult) {
            highestWazaMult = def.type.multiplier;
          }
        }
      }
    }

    Set<HexCoordinate> allMatched = {};
    for (var entry in newBalls.entries) {
      if (allMatched.contains(entry.key)) continue;
      var match = sim.checkMatchesFrom(entry.key, entry.value);
      if (match != null && match.matched.length >= 6) {
        allMatched.addAll(match.matched);
      }
    }

    for (var hex in sim.board.keys.toList()) {
      if (wazaColors.contains(sim.board[hex])) {
        allMatched.add(hex);
      }
    }

    for (var hex in allMatched) {
      sim.board.remove(hex);
    }

    return ExtendedSimDropResult(sim, newBalls, allMatched,
        wazaCompleted: wazaCompleted,
        highestWazaMult: highestWazaMult,
        shapeCollapsed: shapeCollapsed);
  }
}

class _BallDrop {
  final BallColor color;
  final double nx;
  final double ny;
  _BallDrop(this.color, this.nx, this.ny);
}
