// ignore_for_file: curly_braces_in_flow_control_structures, non_constant_identifier_names, unnecessary_non_null_assertion, unused_element, use_super_parameters

import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flame/components.dart';
import 'puzzle_game.dart';
import 'game_models.dart';
import 'game_logic.dart';
import 'perf_monitor.dart';

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

class _ProtectedWazaBallInfo {
  final int needed;
  final WazaType type;

  const _ProtectedWazaBallInfo(this.needed, this.type);
}

class _BoardAnalysis {
  final Map<HexCoordinate, Map<BallColor, _SeedInfo>> wazaSeeds;
  final Map<HexCoordinate, _ProtectedWazaBallInfo> protectedWazaBalls;

  const _BoardAnalysis({
    required this.wazaSeeds,
    required this.protectedWazaBalls,
  });
}

class _ForcedWazaChoice {
  const _ForcedWazaChoice({
    required this.option,
    required this.wazaMultiplier,
    required this.totalScore,
  });

  final _EvalOption option;
  final double wazaMultiplier;
  final double totalScore;
}

class _CpuMoveRequest {
  const _CpuMoveRequest({
    required this.boardEntries,
    required this.currentColors,
    required this.nextColors,
    required this.difficultyIndex,
    required this.weights,
    required this.leftWallX,
    required this.rightWallX,
    required this.floorY,
    required this.gridOffsetX,
    required this.gridOffsetY,
    required this.randomSeed,
    required this.isAndroid,
  });

  final List<List<int>> boardEntries;
  final List<int> currentColors;
  final List<int> nextColors;
  final int difficultyIndex;
  final CPUWeights weights;
  final double leftWallX;
  final double rightWallX;
  final double floorY;
  final double gridOffsetX;
  final double gridOffsetY;
  final int randomSeed;
  final bool isAndroid;
}

class _CpuMoveResult {
  const _CpuMoveResult({
    required this.x,
    required this.rotation,
    required this.elapsedMicroseconds,
    required this.targetHexes,
    this.isImmediateWaza = false,
  });

  final double x;
  final int rotation;
  final int elapsedMicroseconds;
  final List<HexCoordinate> targetHexes;
  final bool isImmediateWaza;
}

_CpuMoveResult? _computeBestMoveInIsolate(_CpuMoveRequest request) {
  return _CpuMoveComputer(request).compute();
}

class CpuMoveHint {
  const CpuMoveHint({
    required this.x,
    required this.rotation,
    required this.targetHexes,
  });

  final double x;
  final int rotation;
  final List<HexCoordinate> targetHexes;
}

class _RankedCpuProfile {
  const _RankedCpuProfile({
    required this.thinkDelay,
    required this.moveDelay,
    required this.rotationDelay,
    required this.mistakeRate,
    required this.lookaheadCount,
    required this.delayJitterRate,
    required this.hesitationChance,
    required this.maxHesitationDuration,
    required this.targetJitterPixels,
  });

  final double thinkDelay;
  final double moveDelay;
  final double rotationDelay;
  final double mistakeRate;
  final int lookaheadCount;
  final double delayJitterRate;
  final double hesitationChance;
  final double maxHesitationDuration;
  final double targetJitterPixels;
}

class ExtendedSimDropResult extends SimDropResult {
  final bool shapeCollapsed;
  final List<HexCoordinate> orderedTargetHexes;

  ExtendedSimDropResult(SimGrid simGrid, Map<HexCoordinate, BallColor> newBalls,
      Set<HexCoordinate> allMatched,
      {bool wazaCompleted = false,
      double highestWazaMult = 0.0,
      this.shapeCollapsed = false,
      this.orderedTargetHexes = const []})
      : super(simGrid, newBalls, allMatched,
            wazaCompleted: wazaCompleted, highestWazaMult: highestWazaMult);
}

class CPUAgent {
  static const double _hardDropLockYOffset = 5.0;
  static const double _postMoveDropSettleDelay = 0.10;
  static const double _preciseDropSettleDelay = 0.06;
  static const double _preciseWazaDropSettleDelay = 0.14;

  final PuzzleGame game;
  CPUDifficulty difficulty;
  final CPUWeights weights;

  double? _targetPixelX;
  int _targetRotationIndex = 0;
  int _targetRotationCount = 0;
  bool _targetIsImmediateWaza = false;
  bool _isThinking = false;
  bool _isComputing = false;

  double _timer = 0.0;
  double _rotationTimer = 0.0;
  double _dropTimer = 0.0;
  bool _dropSettleStarted = false;

  final Random _random = Random();

  CPUAgent(
    this.game, {
    this.difficulty = CPUDifficulty.hard,
    this.weights = const CPUWeights(),
  }) {
    _applyDifficultySettings();
  }

  static Future<CpuMoveHint?> computeOniMoveHint(PuzzleGame game) async {
    final piece = game.activePiece;
    if (piece == null || piece.isLocked) {
      return null;
    }
    final request = _CpuMoveRequest(
      boardEntries: [
        for (final entry in game.grid.lockedBalls.entries)
          [entry.key.col, entry.key.row, entry.value.ballColor.index],
      ],
      currentColors: piece.colors.map((color) => color.index).toList(),
      nextColors:
          game.nextPieceColors.value.map((color) => color.index).toList(),
      difficultyIndex: CPUDifficulty.oni.index,
      weights: const CPUWeights(),
      leftWallX: game.grid.leftWallX,
      rightWallX: game.grid.rightWallX,
      floorY: game.grid.floorY,
      gridOffsetX: game.grid.offset.x,
      gridOffsetY: game.grid.offset.y,
      randomSeed: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      isAndroid: Platform.isAndroid,
    );
    _CpuMoveResult? result;
    try {
      result = await Isolate.run(
        () => _computeBestMoveInIsolate(request),
        debugName: 'cpu_hint_move',
      );
    } catch (_) {
      result = _computeBestMoveInIsolate(request);
    }
    if (result == null) {
      return null;
    }
    return CpuMoveHint(
      x: result.x,
      rotation: result.rotation,
      targetHexes: result.targetHexes,
    );
  }

  void setDifficulty(CPUDifficulty nextDifficulty) {
    difficulty = nextDifficulty;
    _applyDifficultySettings();
  }

  void _applyDifficultySettings() {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      final profile = _rankedProfile(rankedLevel);
      _thinkDelay = profile.thinkDelay;
      _moveDelay = profile.moveDelay;
      _rotationDelay = profile.rotationDelay;
      _mistakeRate = profile.mistakeRate;
      _lookaheadCount = profile.lookaheadCount;
      return;
    }

    switch (difficulty) {
      case CPUDifficulty.easy:
        _thinkDelay = 2.0;
        _moveDelay = 0.24;
        _rotationDelay = 0.24;
        _mistakeRate = 0.30;
        _lookaheadCount = 0;
        break;
      case CPUDifficulty.normal:
        _thinkDelay = 1.0;
        _moveDelay = 0.16;
        _rotationDelay = 0.16;
        _mistakeRate = 0.12;
        _lookaheadCount = 0;
        break;
      case CPUDifficulty.hard:
        _thinkDelay = 0.5;
        _moveDelay = 0.09;
        _rotationDelay = 0.09;
        _mistakeRate = 0.02;
        _lookaheadCount = 0;
        break;
      case CPUDifficulty.oni:
        _thinkDelay = 0.0;
        _moveDelay = 0.015;
        _rotationDelay = 0.12;
        _mistakeRate = 0.0;
        _lookaheadCount = Platform.isAndroid ? 12 : 16;
        break;
      default:
        break;
    }
  }

  double _thinkDelay = 0;
  double _moveDelay = 0;
  double _rotationDelay = 0;
  double _mistakeRate = 0;
  int _lookaheadCount = 4;
  double _lastCpuX = -9999.0;
  double _humanPauseTimer = 0.0;

  bool get _movesBeforeRotating {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return rankedLevel <= 5;
    }
    return difficulty == CPUDifficulty.easy ||
        difficulty == CPUDifficulty.normal;
  }

  bool get _usesPostRotationDropPause {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return rankedLevel <= 3;
    }
    return difficulty == CPUDifficulty.easy;
  }

  double get _postRotationDropDelay => _usesPostRotationDropPause ? 0.18 : 0.12;

  bool get _usesPreciseDropSnap {
    final rankedLevel = _rankedLevel;
    return difficulty == CPUDifficulty.oni || rankedLevel == 10;
  }

  double get _dropSettleDelay =>
      _usesPreciseDropSnap ? _preciseDropSettleDelay : _postMoveDropSettleDelay;

  bool get _usesHumanImperfections {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return rankedLevel < 10;
    }
    return difficulty != CPUDifficulty.oni;
  }

  double get _delayJitterRate {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return _rankedProfile(rankedLevel).delayJitterRate;
    }
    switch (difficulty) {
      case CPUDifficulty.easy:
        return 0.45;
      case CPUDifficulty.normal:
        return 0.28;
      case CPUDifficulty.hard:
        return 0.14;
      case CPUDifficulty.oni:
        return 0.0;
      default:
        return 0.0;
    }
  }

  double get _hesitationChance {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return _rankedProfile(rankedLevel).hesitationChance;
    }
    switch (difficulty) {
      case CPUDifficulty.easy:
        return 0.24;
      case CPUDifficulty.normal:
        return 0.12;
      case CPUDifficulty.hard:
        return 0.05;
      case CPUDifficulty.oni:
        return 0.0;
      default:
        return 0.0;
    }
  }

  double get _maxHesitationDuration {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return _rankedProfile(rankedLevel).maxHesitationDuration;
    }
    switch (difficulty) {
      case CPUDifficulty.easy:
        return 0.22;
      case CPUDifficulty.normal:
        return 0.13;
      case CPUDifficulty.hard:
        return 0.07;
      case CPUDifficulty.oni:
        return 0.0;
      default:
        return 0.0;
    }
  }

  double get _targetJitterPixels {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return _rankedProfile(rankedLevel).targetJitterPixels;
    }
    switch (difficulty) {
      case CPUDifficulty.easy:
        return 8.0;
      case CPUDifficulty.normal:
        return 4.0;
      case CPUDifficulty.hard:
        return 0.75;
      case CPUDifficulty.oni:
        return 0.0;
      default:
        return 0.0;
    }
  }

  int get _oniDepth2TargetsPerRotation => Platform.isAndroid ? 10 : 12;

  int? get _rankedLevel {
    return switch (difficulty) {
      CPUDifficulty.rankedLv1 => 1,
      CPUDifficulty.rankedLv2 => 2,
      CPUDifficulty.rankedLv3 => 3,
      CPUDifficulty.rankedLv4 => 4,
      CPUDifficulty.rankedLv5 => 5,
      CPUDifficulty.rankedLv6 => 6,
      CPUDifficulty.rankedLv7 => 7,
      CPUDifficulty.rankedLv8 => 8,
      CPUDifficulty.rankedLv9 => 9,
      CPUDifficulty.rankedLv10 => 10,
      _ => null,
    };
  }

  _RankedCpuProfile _rankedProfile(int level) {
    final oniLookahead = Platform.isAndroid ? 12 : 16;
    return switch (level.clamp(1, 10)) {
      1 => const _RankedCpuProfile(
          thinkDelay: 2.3,
          moveDelay: 0.27,
          rotationDelay: 0.27,
          mistakeRate: 0.34,
          lookaheadCount: 0,
          delayJitterRate: 0.50,
          hesitationChance: 0.28,
          maxHesitationDuration: 0.25,
          targetJitterPixels: 9.0,
        ),
      2 => const _RankedCpuProfile(
          thinkDelay: 2.0,
          moveDelay: 0.24,
          rotationDelay: 0.24,
          mistakeRate: 0.28,
          lookaheadCount: 0,
          delayJitterRate: 0.44,
          hesitationChance: 0.23,
          maxHesitationDuration: 0.21,
          targetJitterPixels: 7.5,
        ),
      3 => const _RankedCpuProfile(
          thinkDelay: 1.65,
          moveDelay: 0.21,
          rotationDelay: 0.21,
          mistakeRate: 0.22,
          lookaheadCount: 0,
          delayJitterRate: 0.38,
          hesitationChance: 0.18,
          maxHesitationDuration: 0.18,
          targetJitterPixels: 6.3,
        ),
      4 => const _RankedCpuProfile(
          thinkDelay: 1.30,
          moveDelay: 0.18,
          rotationDelay: 0.18,
          mistakeRate: 0.16,
          lookaheadCount: 0,
          delayJitterRate: 0.32,
          hesitationChance: 0.14,
          maxHesitationDuration: 0.14,
          targetJitterPixels: 5.0,
        ),
      5 => const _RankedCpuProfile(
          thinkDelay: 1.0,
          moveDelay: 0.16,
          rotationDelay: 0.16,
          mistakeRate: 0.12,
          lookaheadCount: 0,
          delayJitterRate: 0.28,
          hesitationChance: 0.12,
          maxHesitationDuration: 0.13,
          targetJitterPixels: 4.0,
        ),
      6 => const _RankedCpuProfile(
          thinkDelay: 0.78,
          moveDelay: 0.125,
          rotationDelay: 0.125,
          mistakeRate: 0.08,
          lookaheadCount: 0,
          delayJitterRate: 0.22,
          hesitationChance: 0.08,
          maxHesitationDuration: 0.10,
          targetJitterPixels: 2.8,
        ),
      7 => const _RankedCpuProfile(
          thinkDelay: 0.60,
          moveDelay: 0.105,
          rotationDelay: 0.105,
          mistakeRate: 0.035,
          lookaheadCount: 0,
          delayJitterRate: 0.12,
          hesitationChance: 0.04,
          maxHesitationDuration: 0.05,
          targetJitterPixels: 1.2,
        ),
      8 => const _RankedCpuProfile(
          thinkDelay: 0.50,
          moveDelay: 0.09,
          rotationDelay: 0.09,
          mistakeRate: 0.02,
          lookaheadCount: 0,
          delayJitterRate: 0.09,
          hesitationChance: 0.03,
          maxHesitationDuration: 0.04,
          targetJitterPixels: 0.8,
        ),
      9 => _RankedCpuProfile(
          thinkDelay: 0.22,
          moveDelay: 0.052,
          rotationDelay: 0.10,
          mistakeRate: 0.0,
          lookaheadCount: Platform.isAndroid ? 8 : 12,
          delayJitterRate: 0.0,
          hesitationChance: 0.0,
          maxHesitationDuration: 0.0,
          targetJitterPixels: 0.0,
        ),
      _ => _RankedCpuProfile(
          thinkDelay: 0.0,
          moveDelay: 0.015,
          rotationDelay: 0.12,
          mistakeRate: 0.0,
          lookaheadCount: oniLookahead,
          delayJitterRate: 0.0,
          hesitationChance: 0.0,
          maxHesitationDuration: 0.0,
          targetJitterPixels: 0.0,
        ),
    };
  }

  void update(double dt) {
    if (game.gameStateWrapper.value != GameState.playing) return;
    if (game.activePiece == null || game.activePiece!.isLocked) {
      _resetState();
      return;
    }
    if (_targetPixelX == null && !_isThinking && !_isComputing) {
      _isThinking = true;
      _timer = _humanizedDelay(_thinkDelay);
    }
    if (_isThinking && (_timer -= dt) <= 0) {
      _isThinking = false;
      _isComputing = true;
      _computeBestMoveAsync();
    }

    if (_targetPixelX != null && !_isComputing) {
      if (_humanPauseTimer > 0) {
        _humanPauseTimer -= dt;
        return;
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

      final canRotateNow = !_movesBeforeRotating || reachedTarget;
      bool rotatedThisFrame = false;
      if (canRotateNow && _targetRotationCount != 0) {
        if ((_rotationTimer -= dt) <= 0) {
          if (_targetRotationCount > 0) {
            game.rotateRight();
            _targetRotationCount--;
          } else {
            game.rotateLeft();
            _targetRotationCount++;
          }
          _rotationTimer = _humanizedDelay(_rotationDelay);
          rotatedThisFrame = true;
          _maybeStartHumanHesitation();
        }
      }

      if (reachedTarget && _targetRotationCount == 0) {
        if (!_dropSettleStarted) {
          _dropSettleStarted = true;
          _dropTimer = max(
            _dropTimer,
            _targetIsImmediateWaza
                ? _preciseWazaDropSettleDelay
                : _humanizedDelay(_dropSettleDelay),
          );
        }
        if (rotatedThisFrame) {
          _dropTimer = max(_dropTimer, _postRotationDropDelay);
        }
        if ((_dropTimer -= dt) <= 0) {
          if (_usesPreciseDropSnap && _targetPixelX != null) {
            game.snapCpuPieceTransformBeforeDrop(
              x: _targetPixelX!,
              rotation: _targetRotationIndex,
            );
          }
          game.refreshGhostPositionForCurrentPiece();
          game.hardDrop();
          _resetState();
        }
      } else {
        _dropTimer = _humanizedDelay(_moveDelay);
        _dropSettleStarted = false;
      }
    }
  }

  void _resetState() {
    _targetPixelX = null;
    _targetRotationIndex = 0;
    _targetRotationCount = 0;
    _targetIsImmediateWaza = false;
    _isThinking = false;
    _isComputing = false;
    _lastCpuX = -9999.0;
    _humanPauseTimer = 0.0;
    _timer = 0.0;
    _rotationTimer = 0.0;
    _dropTimer = 0.0;
    _dropSettleStarted = false;
  }

  void stop() {
    _resetState();
  }

  double _humanizedDelay(double baseDelay) {
    if (!_usesHumanImperfections || baseDelay <= 0) {
      return baseDelay;
    }

    final jitter = _delayJitterRate;
    final minScale = 1.0 - (jitter * 0.45);
    final maxScale = 1.0 + jitter;
    return baseDelay *
        (minScale + _random.nextDouble() * (maxScale - minScale));
  }

  double _initialHumanPause() {
    if (!_usesHumanImperfections) {
      return 0.0;
    }

    final maxPause = _maxHesitationDuration * 0.65;
    return _random.nextDouble() * maxPause;
  }

  void _maybeStartHumanHesitation() {
    if (!_usesHumanImperfections ||
        _maxHesitationDuration <= 0 ||
        _random.nextDouble() >= _hesitationChance) {
      return;
    }

    _humanPauseTimer = max(
      _humanPauseTimer,
      _random.nextDouble() * _maxHesitationDuration,
    );
  }

  double _humanizedTargetX(double targetX) {
    if (!_usesHumanImperfections || _targetJitterPixels <= 0) {
      return targetX;
    }

    final jitter = (_random.nextDouble() * 2 - 1) * _targetJitterPixels;
    final leftLimit = game.grid.leftWallX + 16.0;
    final rightLimit = game.grid.rightWallX - 16.0;
    return (targetX + jitter).clamp(leftLimit, rightLimit).toDouble();
  }

  double _evaluateSim(
      ExtendedSimDropResult sim,
      Map<HexCoordinate, Map<BallColor, _SeedInfo>> wazaSeeds,
      Map<HexCoordinate, BallColor> originalBoard,
      Map<HexCoordinate, _ProtectedWazaBallInfo> protectedWazaBalls) {
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

      for (final clearedHex in sim.allMatched) {
        final info = protectedWazaBalls[clearedHex];
        if (info == null) continue;

        final mult = info.type.multiplier;
        if (info.needed == 1) {
          score -= 10000000000.0 * mult;
        } else if (info.needed == 2) {
          score -= 300000000.0 * mult;
        } else {
          score -= 30000000.0 * mult;
        }
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
          else if (needed == 3)
            score += weights.reachBonus * 2.0 * mult;
          else if (needed == 4) score += weights.reachBonus * 0.55 * mult;

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

    final request = _CpuMoveRequest(
      boardEntries: [
        for (final entry in game.grid.lockedBalls.entries)
          [entry.key.col, entry.key.row, entry.value.ballColor.index],
      ],
      currentColors:
          game.activePiece!.colors.map((color) => color.index).toList(),
      nextColors:
          game.nextPieceColors.value.map((color) => color.index).toList(),
      difficultyIndex: difficulty.index,
      weights: weights,
      leftWallX: game.grid.leftWallX,
      rightWallX: game.grid.rightWallX,
      floorY: game.grid.floorY,
      gridOffsetX: game.grid.offset.x,
      gridOffsetY: game.grid.offset.y,
      randomSeed: _random.nextInt(1 << 31),
      isAndroid: Platform.isAndroid,
    );

    final stopwatch = Stopwatch()..start();
    _CpuMoveResult? selected;
    try {
      selected = await Isolate.run(
        () => _computeBestMoveInIsolate(request),
        debugName: 'cpu_move',
      );
    } catch (_) {
      selected = _computeBestMoveInIsolate(request);
    }
    PerfMonitor.logDuration('cpu.total', stopwatch, warnMs: 12);
    if (selected != null) {
      PerfMonitor.logValue(
        'cpu.workerMs',
        (selected.elapsedMicroseconds / 1000.0).toStringAsFixed(2),
      );
    }

    if (selected == null) {
      _isComputing = false;
      return;
    }

    if (!_matchesCurrentDecisionState(request)) {
      _isComputing = false;
      _targetPixelX = null;
      _targetRotationIndex = 0;
      _targetRotationCount = 0;
      _targetIsImmediateWaza = false;
      _dropSettleStarted = false;
      return;
    }

    if (game.activePiece != null && !game.activePiece!.isLocked) {
      _targetIsImmediateWaza = selected.isImmediateWaza;
      _targetPixelX =
          _targetIsImmediateWaza ? selected.x : _humanizedTargetX(selected.x);
      final bestRot = selected.rotation;
      _targetRotationIndex = bestRot;
      _targetRotationCount = bestRot > 3 ? bestRot - 6 : bestRot;
    }

    _isComputing = false;
    _rotationTimer = 0.0;
    _dropTimer = _humanizedDelay(_moveDelay);
    _dropSettleStarted = false;
    _humanPauseTimer = _initialHumanPause();
  }

  bool _matchesCurrentDecisionState(_CpuMoveRequest request) {
    final piece = game.activePiece;
    if (piece == null || piece.isLocked) {
      return false;
    }
    final currentColors = piece.colors.map((color) => color.index).toList();
    if (currentColors.length != request.currentColors.length) {
      return false;
    }
    for (var i = 0; i < currentColors.length; i++) {
      if (currentColors[i] != request.currentColors[i]) {
        return false;
      }
    }

    final currentBoardKey = _boardKey({
      for (final entry in game.grid.lockedBalls.entries)
        entry.key: entry.value.ballColor,
    });
    final requestBoardKey = _boardKey({
      for (final entry in request.boardEntries)
        if (entry.length >= 3 &&
            entry[2] >= 0 &&
            entry[2] < BallColor.values.length)
          HexCoordinate(entry[0], entry[1]): BallColor.values[entry[2]],
    });
    return currentBoardKey == requestBoardKey;
  }

  _EvalOption _selectEasyOption(List<_EvalOption> options) {
    final candidatePool = options.where(
      (option) => !option.simResult.wazaCompleted,
    );
    final ranked = List<_EvalOption>.from(
      candidatePool.isNotEmpty ? candidatePool : options,
    )..sort((a, b) => _normalImmediateScore(b).compareTo(
          _normalImmediateScore(a),
        ));

    return _selectWithMistake(ranked);
  }

  _EvalOption _selectNormalOption(List<_EvalOption> options) {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _normalImmediateScore(b).compareTo(
            _normalImmediateScore(a),
          ));
    return _selectWithMistake(ranked);
  }

  Future<_EvalOption> _selectOniOption(
    List<_EvalOption> options,
    List<BallColor> nextColors,
    Map<int, Set<double>> validTargetXsByRotation,
    Stopwatch stopwatch,
  ) async {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _demonAttackScore(b).compareTo(
            _demonAttackScore(a),
          ));
    final lookaheadCache = <String, double>{};

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
      final boardKey = _boardKey(opt1.simResult.simGrid.board);
      if (lookaheadCache.containsKey(boardKey)) {
        opt1.totalScore = lookaheadCache[boardKey]!;
        continue;
      }
      if (opt1.simResult.wazaCompleted || opt1.score <= -10000000000.0) {
        opt1.totalScore = _demonAttackScore(opt1);
        lookaheadCache[boardKey] = opt1.totalScore;
        continue;
      }

      final board2 = opt1.simResult.simGrid.board;
      final board2Analysis = _analyzeBoard(board2);
      final depth2TargetXsByRotation = _oniDepth2TargetsByRotation(
        board2Analysis,
        validTargetXsByRotation,
      );
      double maxDepth2Score = -double.infinity;
      double bestNextTurnWazaMult = 0.0;

      for (int rot2 = 0; rot2 < 6; rot2++) {
        final validTargetXs2 =
            depth2TargetXsByRotation[rot2] ?? const <double>{};

        for (final targetX2 in validTargetXs2) {
          final sim2 = _simulateDrop(board2, targetX2, nextColors, rot2);
          final score2 = _evaluateSim(
            sim2,
            board2Analysis.wazaSeeds,
            board2,
            board2Analysis.protectedWazaBalls,
          );
          final oniScore2 = _demonSimScore(sim2, score2);
          if (sim2.wazaCompleted &&
              sim2.highestWazaMult > bestNextTurnWazaMult) {
            bestNextTurnWazaMult = sim2.highestWazaMult;
            if (bestNextTurnWazaMult >= WazaType.hexagon.multiplier) {
              maxDepth2Score = max(maxDepth2Score, oniScore2);
              break;
            }
          }
          if (oniScore2 > maxDepth2Score) {
            maxDepth2Score = oniScore2;
          }
        }
        if (bestNextTurnWazaMult >= WazaType.hexagon.multiplier) {
          break;
        }
      }

      opt1.totalScore = _demonAttackScore(opt1) + (maxDepth2Score * 0.85);
      if (bestNextTurnWazaMult > 0.0) {
        opt1.totalScore += 500000000000000.0 * bestNextTurnWazaMult;
      }
      lookaheadCache[boardKey] = opt1.totalScore;
    }

    final topOptions = ranked.sublist(0, checkCount)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return topOptions.first;
  }

  Map<int, Set<double>> _oniDepth2TargetsByRotation(
    _BoardAnalysis analysis,
    Map<int, Set<double>> validTargetXsByRotation,
  ) {
    return {
      for (final entry in validTargetXsByRotation.entries)
        entry.key: _selectOniDepth2TargetXs(
          analysis,
          entry.value,
        ),
    };
  }

  Set<double> _selectOniDepth2TargetXs(
    _BoardAnalysis analysis,
    Set<double> validTargetXs,
  ) {
    if (validTargetXs.length <= _oniDepth2TargetsPerRotation) {
      return validTargetXs;
    }

    final sortedXs = validTargetXs.toList()..sort();
    final selected = <double>{};

    final seedEntries = analysis.wazaSeeds.entries.toList()
      ..sort((a, b) {
        final needA = _minimumSeedNeed(a.value);
        final needB = _minimumSeedNeed(b.value);
        final needOrder = needA.compareTo(needB);
        if (needOrder != 0) {
          return needOrder;
        }
        return _bestSeedMultiplier(b.value)
            .compareTo(_bestSeedMultiplier(a.value));
      });

    for (final entry in seedEntries) {
      if (selected.length >= _oniDepth2TargetsPerRotation) {
        break;
      }
      final targetPixelX = game.grid.hexToPixel(entry.key).x;
      _addNearestLookaheadXs(sortedXs, targetPixelX, selected);
    }

    if (selected.length < _oniDepth2TargetsPerRotation) {
      _addEvenlySpacedLookaheadXs(sortedXs, selected);
    }

    return selected;
  }

  int _minimumSeedNeed(Map<BallColor, _SeedInfo> colorNeeds) {
    return colorNeeds.values.map((info) => info.needed).reduce(min);
  }

  double _bestSeedMultiplier(Map<BallColor, _SeedInfo> colorNeeds) {
    return colorNeeds.values
        .map((info) => info.type.multiplier)
        .reduce((a, b) => a > b ? a : b);
  }

  void _addNearestLookaheadXs(
    List<double> sortedXs,
    double targetPixelX,
    Set<double> selected,
  ) {
    int bestIndex = 0;
    double bestDistance = double.infinity;
    for (int i = 0; i < sortedXs.length; i++) {
      final distance = (sortedXs[i] - targetPixelX).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    for (final index in [bestIndex, bestIndex - 1, bestIndex + 1]) {
      if (selected.length >= _oniDepth2TargetsPerRotation) {
        return;
      }
      if (index >= 0 && index < sortedXs.length) {
        selected.add(sortedXs[index]);
      }
    }
  }

  void _addEvenlySpacedLookaheadXs(
    List<double> sortedXs,
    Set<double> selected,
  ) {
    final remaining = _oniDepth2TargetsPerRotation - selected.length;
    if (remaining <= 0) {
      return;
    }

    for (int i = 0; i < remaining; i++) {
      if (selected.length >= _oniDepth2TargetsPerRotation) {
        return;
      }
      final t = remaining == 1 ? 0.5 : i / (remaining - 1);
      final index = (t * (sortedXs.length - 1)).round();
      selected.add(sortedXs[index]);
    }
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

  _EvalOption _selectHardImmediateOption(List<_EvalOption> options) {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _hardImmediateScore(b).compareTo(
            _hardImmediateScore(a),
          ));
    return _selectWithMistake(ranked);
  }

  _EvalOption? _selectImmediateWazaOption(List<_EvalOption> ranked) {
    _EvalOption? best;
    var bestScore = -double.infinity;
    for (final option in ranked) {
      if (!option.simResult.wazaCompleted || option.simResult.shapeCollapsed) {
        continue;
      }
      final score = option.simResult.highestWazaMult * 1000000000000000.0 +
          _demonAttackScore(option);
      if (best == null || score > bestScore) {
        best = option;
        bestScore = score;
      }
    }
    return best;
  }

  _ForcedWazaChoice? _selectForcedNextTurnWaza(
    List<_EvalOption> ranked,
    List<BallColor> nextColors,
    Map<int, Set<double>> validTargetXsByRotation,
  ) {
    _ForcedWazaChoice? best;
    for (final opt1 in ranked) {
      if (opt1.simResult.wazaCompleted || opt1.score <= -10000000000.0) {
        continue;
      }

      final board2 = opt1.simResult.simGrid.board;
      final board2Analysis = _analyzeBoard(board2);
      for (int rot2 = 0; rot2 < 6; rot2++) {
        final validTargetXs2 =
            validTargetXsByRotation[rot2] ?? const <double>{};
        for (final targetX2 in validTargetXs2) {
          final sim2 = _simulateDrop(board2, targetX2, nextColors, rot2);
          if (!sim2.wazaCompleted || sim2.shapeCollapsed) {
            continue;
          }
          final score2 = _evaluateSim(
            sim2,
            board2Analysis.wazaSeeds,
            board2,
            board2Analysis.protectedWazaBalls,
          );
          final totalScore = sim2.highestWazaMult * 1000000000000000.0 +
              _demonAttackScore(opt1) +
              _demonSimScore(sim2, score2);
          if (best == null ||
              sim2.highestWazaMult > best.wazaMultiplier ||
              (sim2.highestWazaMult == best.wazaMultiplier &&
                  totalScore > best.totalScore)) {
            best = _ForcedWazaChoice(
              option: opt1,
              wazaMultiplier: sim2.highestWazaMult,
              totalScore: totalScore,
            );
          }
        }
      }
    }
    return best;
  }

  _EvalOption _selectWithMistake(List<_EvalOption> ranked) {
    if (ranked.length <= 1 ||
        _mistakeRate <= 0.0 ||
        _random.nextDouble() >= _mistakeRate) {
      return ranked.first;
    }

    final start = _mistakePoolStart(ranked.length);
    final end = _mistakePoolEnd(ranked.length, start);
    final mistakePool = ranked.sublist(start, end);
    if (mistakePool.isEmpty) {
      return ranked.first;
    }
    return mistakePool[_random.nextInt(mistakePool.length)];
  }

  int _mistakePoolStart(int length) {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return switch (rankedLevel) {
        <= 3 => max(1, (length * 0.45).floor()),
        <= 6 => max(1, (length * 0.18).floor()),
        <= 8 => max(1, (length * 0.08).floor()),
        _ => length,
      };
    }
    switch (difficulty) {
      case CPUDifficulty.easy:
        return max(1, length ~/ 2);
      case CPUDifficulty.normal:
        return max(1, (length * 0.20).floor());
      case CPUDifficulty.hard:
        return max(1, (length * 0.08).floor());
      case CPUDifficulty.oni:
        return length;
      default:
        return length;
    }
  }

  int _mistakePoolEnd(int length, int start) {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return switch (rankedLevel) {
        <= 3 => length,
        <= 6 => min(length, max(start + 1, (length * 0.55).ceil())),
        <= 8 => min(length, max(start + 1, (length * 0.25).ceil())),
        _ => length,
      };
    }
    switch (difficulty) {
      case CPUDifficulty.easy:
        return length;
      case CPUDifficulty.normal:
        return min(length, max(start + 1, (length * 0.55).ceil()));
      case CPUDifficulty.hard:
        return min(length, max(start + 1, (length * 0.25).ceil()));
      case CPUDifficulty.oni:
        return length;
      default:
        return length;
    }
  }

  double _hardSimScore(ExtendedSimDropResult sim, double baseScore) {
    final wazaBonus =
        sim.wazaCompleted ? 20000000000.0 * sim.highestWazaMult : 0.0;
    final chainBonus = sim.allMatched.length * 7000000.0;
    return baseScore + wazaBonus + chainBonus + _boardControlScore(sim.simGrid);
  }

  double _demonAttackScore(_EvalOption option) {
    return _demonSimScore(option.simResult, option.score);
  }

  double _demonSimScore(ExtendedSimDropResult sim, double baseScore) {
    final attackBonus =
        sim.wazaCompleted ? 1000000000000000.0 * sim.highestWazaMult : 0.0;
    final clearBonus = sim.allMatched.length * 100000000000.0;
    return attackBonus +
        clearBonus +
        baseScore +
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

      if (!isDead && colorCount >= 2 && colorCount <= 5) {
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

  _BoardAnalysis _analyzeBoard(Map<HexCoordinate, BallColor> board) {
    return _BoardAnalysis(
      wazaSeeds: _analyzeWazaSeeds(board),
      protectedWazaBalls: _analyzeProtectedWazaBalls(board),
    );
  }

  Map<HexCoordinate, _ProtectedWazaBallInfo> _analyzeProtectedWazaBalls(
      Map<HexCoordinate, BallColor> board) {
    final protected = <HexCoordinate, _ProtectedWazaBallInfo>{};
    final sim = SimGrid(12, board);
    WazaPatterns.init(12);

    for (final def in WazaPatterns.detailedPatterns) {
      final pattern = def.hexes;
      BallColor? color;
      int colorCount = 0;
      bool isDead = false;
      final occupied = <HexCoordinate>[];
      final emptySpots = <HexCoordinate>[];

      for (final hex in pattern) {
        if (sim.isOccupied(hex)) {
          final currentColor = sim.board[hex]!;
          if (color == null) {
            color = currentColor;
          } else if (color != currentColor) {
            isDead = true;
            break;
          }
          colorCount++;
          occupied.add(hex);
        } else {
          emptySpots.add(hex);
        }
      }

      if (isDead || colorCount < 3 || colorCount > 5) {
        continue;
      }

      bool allOpen = true;
      for (final empty in emptySpots) {
        final columnTop = _columnTopRow(sim, empty.col);
        if (columnTop > empty.row - 1) {
          continue;
        }

        final upL = sim.getNeighbor(empty, 'f');
        final upR = sim.getNeighbor(empty, 'g');
        final isOpen = (upL != null && !sim.isOccupied(upL)) ||
            (upR != null && !sim.isOccupied(upR));
        if (!isOpen) {
          allOpen = false;
          break;
        }
      }

      if (!allOpen) {
        continue;
      }

      final needed = 6 - colorCount;
      for (final hex in occupied) {
        final existing = protected[hex];
        if (existing == null ||
            needed < existing.needed ||
            (needed == existing.needed &&
                def.type.multiplier > existing.type.multiplier)) {
          protected[hex] = _ProtectedWazaBallInfo(needed, def.type);
        }
      }
    }

    return protected;
  }

  int _columnTopRow(SimGrid sim, int col) {
    for (int row = 0; row < sim.numRows; row++) {
      if (col >= sim.getColumnsForRow(row)) continue;
      if (sim.isOccupied(HexCoordinate(col, row))) {
        return row;
      }
    }
    return sim.numRows;
  }

  String _boardKey(Map<HexCoordinate, BallColor> board) {
    final entries = board.entries.toList()
      ..sort((a, b) {
        final rowDiff = a.key.row.compareTo(b.key.row);
        if (rowDiff != 0) return rowDiff;
        return a.key.col.compareTo(b.key.col);
      });
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer
        ..write(entry.key.row)
        ..write(',')
        ..write(entry.key.col)
        ..write(':')
        ..write(entry.value.index)
        ..write(';');
    }
    return buffer.toString();
  }

  ExtendedSimDropResult _simulateDrop(Map<HexCoordinate, BallColor> board,
      double x, List<BallColor> colors, int rot) {
    double rad = rot * pi / 3;
    final baseOffsets = _pieceBaseOffsets();
    SimGrid sim = SimGrid(12, board);
    Map<HexCoordinate, BallColor> newBalls = {};

    List<_BallDrop> drops = [];
    final orderedTargetHexes =
        List<HexCoordinate?>.filled(colors.length, null, growable: false);
    for (int i = 0; i < 3; i++) {
      double nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
      double ny = baseOffsets[i].x * sin(rad) + baseOffsets[i].y * cos(rad);
      drops.add(_BallDrop(i, colors[i], nx, ny));
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
      Vector2 finalPx =
          Vector2(x + drop.nx, minGy + _hardDropLockYOffset + drop.ny);
      var start = game.grid.pixelToHex(finalPx);

      if (initialStartHexes.contains(start) || sim.isOccupied(start)) {
        shapeCollapsed = true;
      }
      initialStartHexes.add(start);

      start = sim.findNearestEmpty(start);
      double localOffset = finalPx.x - game.grid.hexToPixel(start).x;

      var finalHex = sim.dropBall(start, localOffset, color: drop.color);
      sim.board[finalHex] = drop.color;
      newBalls[finalHex] = drop.color;
      if (drop.index >= 0 && drop.index < orderedTargetHexes.length) {
        orderedTargetHexes[drop.index] = finalHex;
      }
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
        shapeCollapsed: shapeCollapsed,
        orderedTargetHexes:
            orderedTargetHexes.whereType<HexCoordinate>().toList());
  }
}

class _CpuMoveComputer {
  _CpuMoveComputer(this.request)
      : difficulty = CPUDifficulty.values[request.difficultyIndex],
        _random = Random(request.randomSeed);

  final _CpuMoveRequest request;
  final CPUDifficulty difficulty;
  final Random _random;

  CPUWeights get weights => request.weights;
  int get _oniDepth2TargetsPerRotation => request.isAndroid ? 10 : 12;

  int? get _rankedLevel {
    return switch (difficulty) {
      CPUDifficulty.rankedLv1 => 1,
      CPUDifficulty.rankedLv2 => 2,
      CPUDifficulty.rankedLv3 => 3,
      CPUDifficulty.rankedLv4 => 4,
      CPUDifficulty.rankedLv5 => 5,
      CPUDifficulty.rankedLv6 => 6,
      CPUDifficulty.rankedLv7 => 7,
      CPUDifficulty.rankedLv8 => 8,
      CPUDifficulty.rankedLv9 => 9,
      CPUDifficulty.rankedLv10 => 10,
      _ => null,
    };
  }

  int get _lookaheadCount {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      if (rankedLevel == 9) return request.isAndroid ? 8 : 12;
      if (rankedLevel >= 10) return request.isAndroid ? 12 : 16;
      return 0;
    }
    return difficulty == CPUDifficulty.oni ? (request.isAndroid ? 12 : 16) : 0;
  }

  bool get _usesPreciseImmediateWazaSearch {
    return difficulty == CPUDifficulty.oni || _rankedLevel == 10;
  }

  double get _mistakeRate {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return switch (rankedLevel) {
        <= 1 => 0.34,
        2 => 0.28,
        3 => 0.22,
        4 => 0.16,
        5 => 0.12,
        6 => 0.08,
        7 => 0.035,
        8 => 0.02,
        9 => 0.0,
        _ => 0.0,
      };
    }
    return switch (difficulty) {
      CPUDifficulty.easy => 0.30,
      CPUDifficulty.normal => 0.12,
      CPUDifficulty.hard => 0.02,
      CPUDifficulty.oni => 0.0,
      _ => 0.0,
    };
  }

  _CpuMoveResult? compute() {
    final stopwatch = Stopwatch()..start();
    WazaPatterns.init(12);
    final currentColors = request.currentColors
        .map((index) => BallColor.values[index])
        .toList(growable: false);
    if (currentColors.length != 3) {
      return null;
    }

    final nextColors = request.nextColors
        .where((index) => index >= 0 && index < BallColor.values.length)
        .map((index) => BallColor.values[index])
        .toList(growable: false);
    final board = <HexCoordinate, BallColor>{
      for (final entry in request.boardEntries)
        if (entry.length >= 3 &&
            entry[2] >= 0 &&
            entry[2] < BallColor.values.length)
          HexCoordinate(entry[0], entry[1]): BallColor.values[entry[2]],
    };

    final rootAnalysis = _analyzeBoard(board);
    final validTargetXsByRotation = <int, Set<double>>{};
    final depth1BestByBoard = <String, _EvalOption>{};
    final candidateCenterXs = _candidateCenterXs();
    final shouldSearchImmediateWaza = _usesPreciseImmediateWazaSearch &&
        _hasImmediateWazaPotential(rootAnalysis, currentColors);
    final shouldUseOpeningLineSetup =
        _usesOpeningLineSetup(board, currentColors);
    _EvalOption? bestImmediateWaza;
    _EvalOption? bestOpeningLine;

    for (int rot = 0; rot < 6; rot++) {
      final rad = rot * pi / 3;
      final baseOffsets = _pieceBaseOffsets();
      var minNx = 0.0;
      var maxNx = 0.0;
      for (int i = 0; i < 3; i++) {
        final nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
        if (nx < minNx) minNx = nx;
        if (nx > maxNx) maxNx = nx;
      }

      final validMinX = request.leftWallX + 15.0 - minNx + 1.0;
      final validMaxX = request.rightWallX - 15.0 - maxNx - 1.0;
      final validTargetXs = <double>{};

      if (shouldSearchImmediateWaza) {
        for (final targetX
            in _immediateWazaTargetXs(rot, validMinX, validMaxX)) {
          final sim = _simulateDrop(board, targetX, currentColors, rot);
          if (!sim.wazaCompleted ||
              sim.shapeCollapsed ||
              _isTerminalBoard(sim.simGrid)) {
            continue;
          }
          final score = _evaluateSim(
            sim,
            rootAnalysis.wazaSeeds,
            board,
            rootAnalysis.protectedWazaBalls,
          );
          final option = _EvalOption(targetX, rot, score, sim);
          if (_isBetterImmediateWaza(option, bestImmediateWaza)) {
            bestImmediateWaza = option;
          }
        }
      }

      for (final centerX in candidateCenterXs) {
        for (final targetX in _candidateOffsetsFromCenter(centerX)) {
          if (targetX >= validMinX && targetX <= validMaxX) {
            validTargetXs.add(targetX);
          }
        }
      }
      validTargetXsByRotation[rot] = validTargetXs;

      for (final targetX in validTargetXs) {
        final sim = _simulateDrop(board, targetX, currentColors, rot);
        final score = _evaluateSim(
          sim,
          rootAnalysis.wazaSeeds,
          board,
          rootAnalysis.protectedWazaBalls,
        );
        final option = _EvalOption(targetX, rot, score, sim);
        final boardKey = _boardKey(sim.simGrid.board);
        final existing = depth1BestByBoard[boardKey];
        if (existing == null ||
            _depth1DedupPriority(option) > _depth1DedupPriority(existing)) {
          depth1BestByBoard[boardKey] = option;
        }
        if (shouldUseOpeningLineSetup &&
            _isBetterOpeningLine(option, bestOpeningLine)) {
          bestOpeningLine = option;
        }
      }
    }

    if (bestImmediateWaza != null) {
      return _CpuMoveResult(
        x: bestImmediateWaza.x,
        rotation: bestImmediateWaza.rot,
        elapsedMicroseconds: stopwatch.elapsedMicroseconds,
        targetHexes: bestImmediateWaza.simResult.orderedTargetHexes,
        isImmediateWaza: true,
      );
    }

    if (bestOpeningLine != null) {
      return _CpuMoveResult(
        x: bestOpeningLine.x,
        rotation: bestOpeningLine.rot,
        elapsedMicroseconds: stopwatch.elapsedMicroseconds,
        targetHexes: bestOpeningLine.simResult.orderedTargetHexes,
      );
    }

    final depth1Options = depth1BestByBoard.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (depth1Options.isEmpty) {
      return null;
    }

    final selectableOptions = _survivableOptions(depth1Options);
    final selected = _selectOption(
      selectableOptions,
      nextColors,
      validTargetXsByRotation,
    );
    return _CpuMoveResult(
      x: selected.x,
      rotation: selected.rot,
      elapsedMicroseconds: stopwatch.elapsedMicroseconds,
      targetHexes: selected.simResult.orderedTargetHexes,
    );
  }

  double _depth1DedupPriority(_EvalOption option) {
    final sim = option.simResult;
    var priority = option.score;
    if (!sim.shapeCollapsed && !_isTerminalBoard(sim.simGrid)) {
      priority += 1000000000000.0;
    }
    if (sim.wazaCompleted) {
      priority += 1000000000000000000.0 * sim.highestWazaMult;
    }
    return priority;
  }

  bool _usesOpeningLineSetup(
    Map<HexCoordinate, BallColor> board,
    List<BallColor> currentColors,
  ) {
    return _usesPreciseImmediateWazaSearch &&
        board.isEmpty &&
        currentColors.length == 3 &&
        currentColors.toSet().length == 3;
  }

  bool _isBetterOpeningLine(_EvalOption candidate, _EvalOption? currentBest) {
    final candidateScore = _openingLineScore(candidate);
    if (candidateScore == null) {
      return false;
    }
    final currentScore =
        currentBest == null ? null : _openingLineScore(currentBest);
    return currentScore == null || candidateScore > currentScore;
  }

  double? _openingLineScore(_EvalOption option) {
    final targets = option.simResult.orderedTargetHexes;
    if (targets.length != 3 || option.simResult.shapeCollapsed) {
      return null;
    }
    final row = targets.first.row;
    if (targets.any((hex) => hex.row != row)) {
      return null;
    }

    final cols = targets.map((hex) => hex.col).toList()..sort();
    if (cols.toSet().length != 3 || cols.last - cols.first != 2) {
      return null;
    }

    final middleCol = cols[1];
    final rowCenter = row.isOdd ? 4.5 : 4.0;
    final centerPenalty = (middleCol - rowCenter).abs();
    final rotationPenalty = option.rot == 3 ? 0.0 : 0.25;
    return row * 1000.0 - centerPenalty * 20.0 - rotationPenalty;
  }

  bool _hasImmediateWazaPotential(
    _BoardAnalysis analysis,
    List<BallColor> currentColors,
  ) {
    final colorCounts = <BallColor, int>{};
    for (final color in currentColors) {
      colorCounts[color] = (colorCounts[color] ?? 0) + 1;
    }

    for (final seed in analysis.wazaSeeds.values) {
      for (final entry in seed.entries) {
        if ((colorCounts[entry.key] ?? 0) >= entry.value.needed) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isBetterImmediateWaza(_EvalOption candidate, _EvalOption? currentBest) {
    if (currentBest == null) {
      return true;
    }
    final candidateMult = candidate.simResult.highestWazaMult;
    final bestMult = currentBest.simResult.highestWazaMult;
    if (candidateMult != bestMult) {
      return candidateMult > bestMult;
    }
    return _demonAttackScore(candidate) > _demonAttackScore(currentBest);
  }

  _EvalOption _selectOption(
    List<_EvalOption> depth1Options,
    List<BallColor> nextColors,
    Map<int, Set<double>> validTargetXsByRotation,
  ) {
    final immediateWaza = _selectImmediateWazaOption(depth1Options);
    if (immediateWaza != null) {
      return immediateWaza;
    }

    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      if (rankedLevel <= 3) return _selectEasyOption(depth1Options);
      if (rankedLevel <= 6) return _selectNormalOption(depth1Options);
      if (rankedLevel <= 8) return _selectHardImmediateOption(depth1Options);
      return _selectOniOption(
          depth1Options, nextColors, validTargetXsByRotation);
    }

    return switch (difficulty) {
      CPUDifficulty.easy => _selectEasyOption(depth1Options),
      CPUDifficulty.normal => _selectNormalOption(depth1Options),
      CPUDifficulty.hard => _selectHardImmediateOption(depth1Options),
      CPUDifficulty.oni =>
        _selectOniOption(depth1Options, nextColors, validTargetXsByRotation),
      _ => _selectHardImmediateOption(depth1Options),
    };
  }

  _EvalOption _selectEasyOption(List<_EvalOption> options) {
    final candidatePool = options.where(
      (option) => !option.simResult.wazaCompleted,
    );
    final ranked = List<_EvalOption>.from(
      candidatePool.isNotEmpty ? candidatePool : options,
    )..sort((a, b) => _normalImmediateScore(b).compareTo(
          _normalImmediateScore(a),
        ));
    return _selectWithMistake(ranked);
  }

  _EvalOption _selectNormalOption(List<_EvalOption> options) {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _normalImmediateScore(b).compareTo(
            _normalImmediateScore(a),
          ));
    return _selectWithMistake(ranked);
  }

  List<_EvalOption> _survivableOptions(List<_EvalOption> options) {
    final survivable = options.where(_isSurvivableOption).toList();
    return survivable.isEmpty ? options : survivable;
  }

  bool _isSurvivableOption(_EvalOption option) {
    return !option.simResult.shapeCollapsed &&
        !_isTerminalBoard(option.simResult.simGrid);
  }

  bool _isTerminalBoard(SimGrid simGrid) {
    return simGrid.board.keys.any((hex) => hex.row < 0);
  }

  _EvalOption _selectOniOption(
    List<_EvalOption> options,
    List<BallColor> nextColors,
    Map<int, Set<double>> validTargetXsByRotation,
  ) {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _demonAttackScore(b).compareTo(
            _demonAttackScore(a),
          ));
    final lookaheadCache = <String, double>{};

    final immediateWaza = _selectImmediateWazaOption(ranked);
    if (immediateWaza != null) {
      return immediateWaza;
    }

    if (nextColors.isEmpty) {
      return ranked.first;
    }

    final forcedWaza = _selectForcedNextTurnWaza(
      ranked,
      nextColors,
      validTargetXsByRotation,
    );
    if (forcedWaza != null) {
      return forcedWaza.option;
    }

    final checkCount = min(_lookaheadCount, ranked.length);
    for (int i = 0; i < checkCount; i++) {
      final opt1 = ranked[i];
      final boardKey = _boardKey(opt1.simResult.simGrid.board);
      if (lookaheadCache.containsKey(boardKey)) {
        opt1.totalScore = lookaheadCache[boardKey]!;
        continue;
      }
      if (opt1.simResult.wazaCompleted || opt1.score <= -10000000000.0) {
        opt1.totalScore = _demonAttackScore(opt1);
        lookaheadCache[boardKey] = opt1.totalScore;
        continue;
      }

      final board2 = opt1.simResult.simGrid.board;
      final board2Analysis = _analyzeBoard(board2);
      final depth2TargetXsByRotation = _oniDepth2TargetsByRotation(
        board2Analysis,
        validTargetXsByRotation,
      );
      var maxDepth2Score = -double.infinity;
      var bestNextTurnWazaMult = 0.0;

      for (int rot2 = 0; rot2 < 6; rot2++) {
        final validTargetXs2 =
            depth2TargetXsByRotation[rot2] ?? const <double>{};
        for (final targetX2 in validTargetXs2) {
          final sim2 = _simulateDrop(board2, targetX2, nextColors, rot2);
          if (_isTerminalBoard(sim2.simGrid)) {
            continue;
          }
          final score2 = _evaluateSim(
            sim2,
            board2Analysis.wazaSeeds,
            board2,
            board2Analysis.protectedWazaBalls,
          );
          final oniScore2 = _demonSimScore(sim2, score2);
          if (sim2.wazaCompleted &&
              sim2.highestWazaMult > bestNextTurnWazaMult) {
            bestNextTurnWazaMult = sim2.highestWazaMult;
            if (bestNextTurnWazaMult >= WazaType.hexagon.multiplier) {
              maxDepth2Score = max(maxDepth2Score, oniScore2);
              break;
            }
          }
          if (oniScore2 > maxDepth2Score) {
            maxDepth2Score = oniScore2;
          }
        }
        if (bestNextTurnWazaMult >= WazaType.hexagon.multiplier) {
          break;
        }
      }

      opt1.totalScore = _demonAttackScore(opt1) + (maxDepth2Score * 0.85);
      if (bestNextTurnWazaMult > 0.0) {
        opt1.totalScore += 500000000000000.0 * bestNextTurnWazaMult;
      }
      lookaheadCache[boardKey] = opt1.totalScore;
    }

    final topOptions = ranked.sublist(0, checkCount)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return topOptions.first;
  }

  _EvalOption _selectHardImmediateOption(List<_EvalOption> options) {
    final ranked = List<_EvalOption>.from(options)
      ..sort((a, b) => _hardImmediateScore(b).compareTo(
            _hardImmediateScore(a),
          ));
    return _selectWithMistake(ranked);
  }

  _EvalOption? _selectImmediateWazaOption(List<_EvalOption> ranked) {
    _EvalOption? best;
    var bestScore = -double.infinity;
    for (final option in ranked) {
      if (!option.simResult.wazaCompleted ||
          option.simResult.shapeCollapsed ||
          _isTerminalBoard(option.simResult.simGrid)) {
        continue;
      }
      final score = option.simResult.highestWazaMult * 1000000000000000.0 +
          _demonAttackScore(option);
      if (best == null || score > bestScore) {
        best = option;
        bestScore = score;
      }
    }
    return best;
  }

  _ForcedWazaChoice? _selectForcedNextTurnWaza(
    List<_EvalOption> ranked,
    List<BallColor> nextColors,
    Map<int, Set<double>> validTargetXsByRotation,
  ) {
    _ForcedWazaChoice? best;
    for (final opt1 in ranked) {
      if (opt1.simResult.wazaCompleted || opt1.score <= -10000000000.0) {
        continue;
      }

      final board2 = opt1.simResult.simGrid.board;
      final board2Analysis = _analyzeBoard(board2);
      for (int rot2 = 0; rot2 < 6; rot2++) {
        final validTargetXs2 =
            validTargetXsByRotation[rot2] ?? const <double>{};
        for (final targetX2 in validTargetXs2) {
          final sim2 = _simulateDrop(board2, targetX2, nextColors, rot2);
          if (!sim2.wazaCompleted ||
              sim2.shapeCollapsed ||
              _isTerminalBoard(sim2.simGrid)) {
            continue;
          }
          final score2 = _evaluateSim(
            sim2,
            board2Analysis.wazaSeeds,
            board2,
            board2Analysis.protectedWazaBalls,
          );
          final totalScore = sim2.highestWazaMult * 1000000000000000.0 +
              _demonAttackScore(opt1) +
              _demonSimScore(sim2, score2);
          if (best == null ||
              sim2.highestWazaMult > best.wazaMultiplier ||
              (sim2.highestWazaMult == best.wazaMultiplier &&
                  totalScore > best.totalScore)) {
            best = _ForcedWazaChoice(
              option: opt1,
              wazaMultiplier: sim2.highestWazaMult,
              totalScore: totalScore,
            );
          }
        }
      }
    }
    return best;
  }

  _EvalOption _selectWithMistake(List<_EvalOption> ranked) {
    if (ranked.length <= 1 ||
        _mistakeRate <= 0.0 ||
        _random.nextDouble() >= _mistakeRate) {
      return ranked.first;
    }

    final start = _mistakePoolStart(ranked.length);
    final end = _mistakePoolEnd(ranked.length, start);
    final mistakePool = ranked.sublist(start, end);
    if (mistakePool.isEmpty) {
      return ranked.first;
    }
    return mistakePool[_random.nextInt(mistakePool.length)];
  }

  int _mistakePoolStart(int length) {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return switch (rankedLevel) {
        <= 3 => max(1, (length * 0.45).floor()),
        <= 6 => max(1, (length * 0.18).floor()),
        <= 8 => max(1, (length * 0.08).floor()),
        _ => length,
      };
    }
    return switch (difficulty) {
      CPUDifficulty.easy => max(1, length ~/ 2),
      CPUDifficulty.normal => max(1, (length * 0.20).floor()),
      CPUDifficulty.hard => max(1, (length * 0.08).floor()),
      CPUDifficulty.oni => length,
      _ => length,
    };
  }

  int _mistakePoolEnd(int length, int start) {
    final rankedLevel = _rankedLevel;
    if (rankedLevel != null) {
      return switch (rankedLevel) {
        <= 3 => length,
        <= 6 => min(length, max(start + 1, (length * 0.55).ceil())),
        <= 8 => min(length, max(start + 1, (length * 0.25).ceil())),
        _ => length,
      };
    }
    return switch (difficulty) {
      CPUDifficulty.easy => length,
      CPUDifficulty.normal =>
        min(length, max(start + 1, (length * 0.55).ceil())),
      CPUDifficulty.hard => min(length, max(start + 1, (length * 0.25).ceil())),
      CPUDifficulty.oni => length,
      _ => length,
    };
  }

  double _evaluateSim(
    ExtendedSimDropResult sim,
    Map<HexCoordinate, Map<BallColor, _SeedInfo>> wazaSeeds,
    Map<HexCoordinate, BallColor> originalBoard,
    Map<HexCoordinate, _ProtectedWazaBallInfo> protectedWazaBalls,
  ) {
    if (sim.shapeCollapsed) {
      return -100000000000000.0;
    }

    var score = evaluateBoardLogic(sim.simGrid, sim.newBalls, weights);
    if (_isTerminalBoard(sim.simGrid)) {
      score -= 1000000000000000.0;
    }
    if (score <= -900000000.0) score -= 10000000000.0;
    if (sim.wazaCompleted) score += 1000000000000.0 * sim.highestWazaMult;
    score += _wazaBuildScore(sim.simGrid, sim.newBalls);
    score += _wazaFoundationScore(sim.simGrid, sim.newBalls);

    if (sim.allMatched.isNotEmpty && !sim.wazaCompleted) {
      var isPrematureClear = false;
      for (final def in WazaPatterns.detailedPatterns) {
        final pattern = def.hexes;
        BallColor? patternColor;
        var colorCount = 0;
        var matchedCount = 0;
        var isDead = false;

        for (final hex in pattern) {
          if (sim.simGrid.isOccupied(hex) || sim.allMatched.contains(hex)) {
            final color = sim.newBalls[hex] ??
                sim.simGrid.board[hex] ??
                originalBoard[hex];
            if (color == null) continue;
            if (patternColor == null) {
              patternColor = color;
              colorCount++;
            } else if (patternColor == color) {
              colorCount++;
            } else {
              isDead = true;
              break;
            }
            if (sim.allMatched.contains(hex)) matchedCount++;
          }
        }

        if (!isDead && colorCount >= 4 && colorCount <= 5 && matchedCount > 0) {
          isPrematureClear = true;
          break;
        }
      }

      score += isPrematureClear ? -5000000000.0 : 3000000.0;
      for (final clearedHex in sim.allMatched) {
        final info = protectedWazaBalls[clearedHex];
        if (info == null) continue;
        final mult = info.type.multiplier;
        if (info.needed == 1) {
          score -= 10000000000.0 * mult;
        } else if (info.needed == 2) {
          score -= 300000000.0 * mult;
        } else {
          score -= 30000000.0 * mult;
        }
      }
    }

    var harmlessCount = 0;
    for (final entry in sim.newBalls.entries) {
      final pos = entry.key;
      final color = entry.value;
      if (wazaSeeds.containsKey(pos)) {
        final colorNeeds = wazaSeeds[pos]!;
        if (colorNeeds.containsKey(color)) {
          final info = colorNeeds[color]!;
          final needed = info.needed;
          final mult = info.type.multiplier;
          if (needed == 1) {
            score += weights.hintBonus * 2.0 * mult;
          } else if (needed == 2) {
            score += weights.reachBonus * 5.0 * mult;
          } else if (needed == 3) {
            score += weights.reachBonus * 2.0 * mult;
          } else if (needed == 4) {
            score += weights.reachBonus * 0.55 * mult;
          }

          var minOtherNeeded = 99;
          for (final otherColor in colorNeeds.keys) {
            if (otherColor != color &&
                colorNeeds[otherColor]!.needed < minOtherNeeded) {
              minOtherNeeded = colorNeeds[otherColor]!.needed;
            }
          }
          if (minOtherNeeded < needed) {
            if (minOtherNeeded == 1) {
              score -= 5000000000.0;
            } else if (minOtherNeeded == 2) {
              score -= 50000000.0;
            } else {
              score -= 5000000.0;
            }
          }
        } else {
          final minNeeded = colorNeeds.values
              .map((info) => info.needed)
              .reduce((a, b) => a < b ? a : b);
          if (minNeeded == 1) {
            score -= 5000000000.0;
          } else if (minNeeded == 2) {
            score -= 50000000.0;
          } else {
            score -= 5000000.0;
          }
        }
      } else {
        harmlessCount++;
      }
    }

    for (final seedPos in wazaSeeds.keys) {
      final colorNeeds = wazaSeeds[seedPos]!;
      final minNeeded = colorNeeds.values
          .map((info) => info.needed)
          .reduce((a, b) => a < b ? a : b);
      if (minNeeded > 2) continue;
      if (sim.simGrid.isOccupied(seedPos) || sim.allMatched.contains(seedPos)) {
        continue;
      }

      var columnTop = 12;
      for (int row = 0; row < 12; row++) {
        if (sim.simGrid.isOccupied(HexCoordinate(seedPos.col, row))) {
          columnTop = row;
          break;
        }
      }
      var isOpen = columnTop > seedPos.row - 1;
      if (!isOpen) {
        final upL = sim.simGrid.getNeighbor(seedPos, 'f');
        final upR = sim.simGrid.getNeighbor(seedPos, 'g');
        isOpen = (upL != null && !sim.simGrid.isOccupied(upL)) ||
            (upR != null && !sim.simGrid.isOccupied(upR));
      }
      if (!isOpen) {
        if (minNeeded == 1) {
          score -= 5000000000.0;
        } else if (minNeeded == 2) {
          score -= 50000000.0;
        }
      }
    }

    final hasCriticalSeed = wazaSeeds.values
        .any((map) => map.values.any((info) => info.needed <= 2));
    if (hasCriticalSeed && harmlessCount > 0) {
      score += harmlessCount * weights.dumpBonus;
    }
    return score;
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
    return _demonSimScore(option.simResult, option.score);
  }

  double _demonSimScore(ExtendedSimDropResult sim, double baseScore) {
    final attackBonus =
        sim.wazaCompleted ? 1000000000000000.0 * sim.highestWazaMult : 0.0;
    final clearBonus = sim.allMatched.length * 25000000.0;
    return attackBonus +
        clearBonus +
        baseScore +
        (_boardControlScore(sim.simGrid) * 0.05);
  }

  double _boardControlScore(SimGrid simGrid) {
    final metrics = _measureBoard(simGrid);
    final dangerHeight = max(0, metrics.maxHeight - 7);
    final criticalHeight = max(0, metrics.maxHeight - 9);
    return -(metrics.holes * 50000000.0) -
        (metrics.maxHeight * 3000000.0) -
        (metrics.totalHeight * 500000.0) -
        (metrics.roughness * 350000.0) -
        (dangerHeight * dangerHeight * 25000000.0) -
        (criticalHeight * 200000000.0);
  }

  double _wazaBuildScore(
    SimGrid simGrid,
    Map<HexCoordinate, BallColor> newBalls,
  ) {
    if (newBalls.isEmpty) return 0.0;

    var score = 0.0;
    for (final def in WazaPatterns.detailedPatterns) {
      BallColor? patternColor;
      var colorCount = 0;
      var newCount = 0;
      var isDead = false;
      final emptySpots = <HexCoordinate>[];

      for (final hex in def.hexes) {
        final color = simGrid.board[hex];
        if (color == null) {
          emptySpots.add(hex);
          continue;
        }
        if (patternColor == null) {
          patternColor = color;
        } else if (patternColor != color) {
          isDead = true;
          break;
        }
        colorCount++;
        if (newBalls.containsKey(hex)) {
          newCount++;
        }
      }

      if (isDead || newCount == 0 || colorCount < 2 || colorCount >= 6) {
        continue;
      }
      if (!_areWazaEmptiesOpen(simGrid, emptySpots)) {
        continue;
      }

      final mult = def.type.multiplier;
      if (colorCount == 5) {
        score += 120000000.0 * mult;
      } else if (colorCount == 4) {
        score += 24000000.0 * mult;
      } else if (colorCount == 3) {
        score += 6000000.0 * mult;
      } else {
        score += 1200000.0 * mult;
      }
    }
    return score;
  }

  double _wazaFoundationScore(
    SimGrid simGrid,
    Map<HexCoordinate, BallColor> newBalls,
  ) {
    if (newBalls.isEmpty) return 0.0;

    var score = 0.0;
    for (final def in WazaPatterns.detailedPatterns) {
      BallColor? patternColor;
      var colorCount = 0;
      var newCount = 0;
      var isDead = false;
      final occupied = <HexCoordinate>[];
      final emptySpots = <HexCoordinate>[];

      for (final hex in def.hexes) {
        final color = simGrid.board[hex];
        if (color == null) {
          emptySpots.add(hex);
          continue;
        }
        if (patternColor == null) {
          patternColor = color;
        } else if (patternColor != color) {
          isDead = true;
          break;
        }
        colorCount++;
        occupied.add(hex);
        if (newBalls.containsKey(hex)) {
          newCount++;
        }
      }

      if (isDead || newCount == 0 || colorCount < 2 || colorCount >= 6) {
        continue;
      }
      if (!_areWazaEmptiesOpen(simGrid, emptySpots)) {
        continue;
      }

      var supportedCount = 0;
      for (final hex in occupied) {
        if (_isFoundationSupported(simGrid, hex)) {
          supportedCount++;
        }
      }
      final supportRatio = supportedCount / max(1, occupied.length);
      if (supportRatio < 0.55) {
        continue;
      }

      final averageRow =
          occupied.fold<double>(0.0, (sum, hex) => sum + hex.row) /
              occupied.length;
      final lowBoardBonus = 1.0 + (averageRow / 12.0).clamp(0.0, 1.0) * 0.8;
      final typeBonus = switch (def.type) {
        WazaType.hexagon => 2.2,
        WazaType.pyramid => 1.7,
        WazaType.straight => 1.25,
        WazaType.none => 1.0,
      };
      final progressBonus = switch (colorCount) {
        5 => 900000000.0,
        4 => 220000000.0,
        3 => 52000000.0,
        _ => 12000000.0,
      };

      score += progressBonus *
          typeBonus *
          lowBoardBonus *
          (0.55 + supportRatio * 0.45);
    }
    return score;
  }

  bool _isFoundationSupported(SimGrid simGrid, HexCoordinate hex) {
    if (hex.row >= simGrid.numRows - 1) {
      return true;
    }
    final downLeft = simGrid.getNeighbor(hex, 'b');
    final downRight = simGrid.getNeighbor(hex, 'c');
    final straightDown = simGrid.getNeighbor(hex, 'e');
    return (downLeft != null && simGrid.isOccupied(downLeft)) ||
        (downRight != null && simGrid.isOccupied(downRight)) ||
        (straightDown != null && simGrid.isOccupied(straightDown));
  }

  bool _areWazaEmptiesOpen(
    SimGrid simGrid,
    List<HexCoordinate> emptySpots,
  ) {
    for (final empty in emptySpots) {
      final columnTop = _columnTopRow(simGrid, empty.col);
      if (columnTop > empty.row - 1) {
        continue;
      }

      final upL = simGrid.getNeighbor(empty, 'f');
      final upR = simGrid.getNeighbor(empty, 'g');
      final isOpen = (upL != null && !simGrid.isOccupied(upL)) ||
          (upR != null && !simGrid.isOccupied(upR));
      if (!isOpen) {
        return false;
      }
    }
    return true;
  }

  _BoardMetrics _measureBoard(SimGrid simGrid) {
    const columnCount = 10;
    final heights = <int>[];
    var holes = 0;

    for (int col = 0; col < columnCount; col++) {
      int? topRow;
      for (int row = 0; row < simGrid.numRows; row++) {
        if (col >= simGrid.getColumnsForRow(row)) continue;
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

    var roughness = 0;
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

  Map<int, Set<double>> _oniDepth2TargetsByRotation(
    _BoardAnalysis analysis,
    Map<int, Set<double>> validTargetXsByRotation,
  ) {
    return {
      for (final entry in validTargetXsByRotation.entries)
        entry.key: _selectOniDepth2TargetXs(analysis, entry.value),
    };
  }

  Set<double> _selectOniDepth2TargetXs(
    _BoardAnalysis analysis,
    Set<double> validTargetXs,
  ) {
    if (validTargetXs.length <= _oniDepth2TargetsPerRotation) {
      return validTargetXs;
    }
    final sortedXs = validTargetXs.toList()..sort();
    final selected = <double>{};
    final seedEntries = analysis.wazaSeeds.entries.toList()
      ..sort((a, b) {
        final needOrder =
            _minimumSeedNeed(a.value).compareTo(_minimumSeedNeed(b.value));
        if (needOrder != 0) return needOrder;
        return _bestSeedMultiplier(b.value)
            .compareTo(_bestSeedMultiplier(a.value));
      });

    for (final entry in seedEntries) {
      if (selected.length >= _oniDepth2TargetsPerRotation) break;
      _addNearestLookaheadXs(
        sortedXs,
        _hexToPixel(entry.key).x,
        selected,
      );
    }
    if (selected.length < _oniDepth2TargetsPerRotation) {
      _addEvenlySpacedLookaheadXs(sortedXs, selected);
    }
    return selected;
  }

  int _minimumSeedNeed(Map<BallColor, _SeedInfo> colorNeeds) {
    return colorNeeds.values.map((info) => info.needed).reduce(min);
  }

  double _bestSeedMultiplier(Map<BallColor, _SeedInfo> colorNeeds) {
    return colorNeeds.values
        .map((info) => info.type.multiplier)
        .reduce((a, b) => a > b ? a : b);
  }

  void _addNearestLookaheadXs(
    List<double> sortedXs,
    double targetPixelX,
    Set<double> selected,
  ) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (int i = 0; i < sortedXs.length; i++) {
      final distance = (sortedXs[i] - targetPixelX).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    for (final index in [bestIndex, bestIndex - 1, bestIndex + 1]) {
      if (selected.length >= _oniDepth2TargetsPerRotation) return;
      if (index >= 0 && index < sortedXs.length) selected.add(sortedXs[index]);
    }
  }

  void _addEvenlySpacedLookaheadXs(
    List<double> sortedXs,
    Set<double> selected,
  ) {
    final remaining = _oniDepth2TargetsPerRotation - selected.length;
    if (remaining <= 0) return;
    for (int i = 0; i < remaining; i++) {
      if (selected.length >= _oniDepth2TargetsPerRotation) return;
      final t = remaining == 1 ? 0.5 : i / (remaining - 1);
      final index = (t * (sortedXs.length - 1)).round();
      selected.add(sortedXs[index]);
    }
  }

  Set<double> _candidateCenterXs() {
    return {
      for (int col = 0; col < 9; col++) _hexToPixel(HexCoordinate(col, 0)).x,
      for (int col = 1; col <= 8; col++) _hexToPixel(HexCoordinate(col, 1)).x,
    };
  }

  Iterable<double> _candidateOffsetsFromCenter(double centerX) sync* {
    const offset = 3.0;
    yield centerX;
    yield centerX - offset;
    yield centerX + offset;
  }

  Iterable<double> _immediateWazaTargetXs(
    int rot,
    double validMinX,
    double validMaxX,
  ) sync* {
    final rad = rot * pi / 3;
    final baseOffsets = _pieceBaseOffsets();
    final rotatedXs = [
      for (final offset in baseOffsets)
        offset.x * cos(rad) - offset.y * sin(rad),
    ];
    final yielded = <String>{};
    const fineOffsets = [0.0, -1.5, 1.5, -3.0, 3.0];

    for (final hex in _allBoardHexes()) {
      final hexX = _hexToPixel(hex).x;
      for (final rotatedX in rotatedXs) {
        for (final fineOffset in fineOffsets) {
          final targetX = hexX - rotatedX + fineOffset;
          if (targetX < validMinX || targetX > validMaxX) {
            continue;
          }
          final key = targetX.toStringAsFixed(3);
          if (yielded.add(key)) {
            yield targetX;
          }
        }
      }
    }
  }

  Iterable<HexCoordinate> _allBoardHexes() sync* {
    for (var row = 0; row < 12; row++) {
      final columns = row.isOdd ? 10 : 9;
      for (var col = 0; col < columns; col++) {
        yield HexCoordinate(col, row);
      }
    }
  }

  _BoardAnalysis _analyzeBoard(Map<HexCoordinate, BallColor> board) {
    return _BoardAnalysis(
      wazaSeeds: _analyzeWazaSeeds(board),
      protectedWazaBalls: _analyzeProtectedWazaBalls(board),
    );
  }

  Map<HexCoordinate, Map<BallColor, _SeedInfo>> _analyzeWazaSeeds(
    Map<HexCoordinate, BallColor> board,
  ) {
    final seeds = <HexCoordinate, Map<BallColor, _SeedInfo>>{};
    final sim = SimGrid(12, board);
    WazaPatterns.init(12);

    for (final def in WazaPatterns.detailedPatterns) {
      final pattern = def.hexes;
      BallColor? patternColor;
      var colorCount = 0;
      var isDead = false;
      final emptySpots = <HexCoordinate>[];

      for (final hex in pattern) {
        if (sim.isOccupied(hex)) {
          if (patternColor == null) {
            patternColor = sim.board[hex];
          } else if (patternColor != sim.board[hex]) {
            isDead = true;
            break;
          }
          colorCount++;
        } else {
          emptySpots.add(hex);
        }
      }

      if (!isDead && colorCount >= 2 && colorCount <= 5) {
        final needed = 6 - colorCount;
        for (final empty in emptySpots) {
          seeds.putIfAbsent(empty, () => {});
          final color = patternColor!;
          final existing = seeds[empty]![color];
          if (existing == null ||
              existing.needed > needed ||
              (existing.needed == needed &&
                  def.type.multiplier > existing.type.multiplier)) {
            seeds[empty]![color] = _SeedInfo(needed, def.type);
          }
        }
      }
    }
    return seeds;
  }

  Map<HexCoordinate, _ProtectedWazaBallInfo> _analyzeProtectedWazaBalls(
    Map<HexCoordinate, BallColor> board,
  ) {
    final protected = <HexCoordinate, _ProtectedWazaBallInfo>{};
    final sim = SimGrid(12, board);
    WazaPatterns.init(12);

    for (final def in WazaPatterns.detailedPatterns) {
      final pattern = def.hexes;
      BallColor? color;
      var colorCount = 0;
      var isDead = false;
      final occupied = <HexCoordinate>[];
      final emptySpots = <HexCoordinate>[];

      for (final hex in pattern) {
        if (sim.isOccupied(hex)) {
          final currentColor = sim.board[hex]!;
          if (color == null) {
            color = currentColor;
          } else if (color != currentColor) {
            isDead = true;
            break;
          }
          colorCount++;
          occupied.add(hex);
        } else {
          emptySpots.add(hex);
        }
      }

      if (isDead || colorCount < 3 || colorCount > 5) continue;
      var allOpen = true;
      for (final empty in emptySpots) {
        final columnTop = _columnTopRow(sim, empty.col);
        if (columnTop > empty.row - 1) continue;
        final upL = sim.getNeighbor(empty, 'f');
        final upR = sim.getNeighbor(empty, 'g');
        final isOpen = (upL != null && !sim.isOccupied(upL)) ||
            (upR != null && !sim.isOccupied(upR));
        if (!isOpen) {
          allOpen = false;
          break;
        }
      }
      if (!allOpen) continue;

      final needed = 6 - colorCount;
      for (final hex in occupied) {
        final existing = protected[hex];
        if (existing == null ||
            needed < existing.needed ||
            (needed == existing.needed &&
                def.type.multiplier > existing.type.multiplier)) {
          protected[hex] = _ProtectedWazaBallInfo(needed, def.type);
        }
      }
    }
    return protected;
  }

  int _columnTopRow(SimGrid sim, int col) {
    for (int row = 0; row < sim.numRows; row++) {
      if (col >= sim.getColumnsForRow(row)) continue;
      if (sim.isOccupied(HexCoordinate(col, row))) return row;
    }
    return sim.numRows;
  }

  String _boardKey(Map<HexCoordinate, BallColor> board) {
    final entries = board.entries.toList()
      ..sort((a, b) {
        final rowDiff = a.key.row.compareTo(b.key.row);
        if (rowDiff != 0) return rowDiff;
        return a.key.col.compareTo(b.key.col);
      });
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer
        ..write(entry.key.row)
        ..write(',')
        ..write(entry.key.col)
        ..write(':')
        ..write(entry.value.index)
        ..write(';');
    }
    return buffer.toString();
  }

  ExtendedSimDropResult _simulateDrop(
    Map<HexCoordinate, BallColor> board,
    double x,
    List<BallColor> colors,
    int rot,
  ) {
    final rad = rot * pi / 3;
    final baseOffsets = _pieceBaseOffsets();
    final sim = SimGrid(12, board);
    final newBalls = <HexCoordinate, BallColor>{};
    final drops = <_BallDrop>[];
    final orderedTargetHexes =
        List<HexCoordinate?>.filled(colors.length, null, growable: false);

    for (int i = 0; i < 3; i++) {
      final nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
      final ny = baseOffsets[i].x * sin(rad) + baseOffsets[i].y * cos(rad);
      drops.add(_BallDrop(i, colors[i], nx, ny));
    }

    var minGy = request.floorY + 1000.0;
    for (final drop in drops) {
      final hitY = request.floorY - 15.0 - drop.ny;
      if (hitY < minGy) minGy = hitY;
      final ballAx = x + drop.nx;
      for (final lockedHex in board.keys) {
        final lockedPx = _hexToPixel(lockedHex);
        final dx = ballAx - lockedPx.x;
        if (dx.abs() <= 30.0) {
          final dy = sqrt(900.0 - dx * dx);
          final hitLockedY = lockedPx.y - dy - drop.ny;
          if (hitLockedY < minGy) minGy = hitLockedY;
        }
      }
    }

    drops.sort((a, b) => b.ny.compareTo(a.ny));
    var shapeCollapsed = false;
    final initialStartHexes = <HexCoordinate>{};

    for (final drop in drops) {
      final finalPx =
          Vector2(x + drop.nx, minGy + CPUAgent._hardDropLockYOffset + drop.ny);
      var start = _pixelToHex(finalPx);
      if (initialStartHexes.contains(start) || sim.isOccupied(start)) {
        shapeCollapsed = true;
      }
      initialStartHexes.add(start);

      start = sim.findNearestEmpty(start);
      final localOffset = finalPx.x - _hexToPixel(start).x;
      final finalHex = sim.dropBall(start, localOffset, color: drop.color);
      sim.board[finalHex] = drop.color;
      newBalls[finalHex] = drop.color;
      if (drop.index >= 0 && drop.index < orderedTargetHexes.length) {
        orderedTargetHexes[drop.index] = finalHex;
      }
    }

    var wazaCompleted = false;
    var highestWazaMult = 0.0;
    final wazaColors = <BallColor>{};
    WazaPatterns.init(sim.numRows);
    for (final def in WazaPatterns.detailedPatterns) {
      final pattern = def.hexes;
      BallColor? patternColor;
      var colorCount = 0;
      var isDead = false;
      for (final hex in pattern) {
        if (sim.isOccupied(hex)) {
          if (patternColor == null) {
            patternColor = sim.board[hex];
          } else if (patternColor != sim.board[hex]) {
            isDead = true;
            break;
          }
          colorCount++;
        }
      }
      if (!isDead && colorCount == 6) {
        final involvesNew = pattern.any(newBalls.containsKey);
        if (involvesNew) {
          wazaCompleted = true;
          wazaColors.add(patternColor!);
          if (def.type.multiplier > highestWazaMult) {
            highestWazaMult = def.type.multiplier;
          }
        }
      }
    }

    final allMatched = <HexCoordinate>{};
    for (final entry in newBalls.entries) {
      if (allMatched.contains(entry.key)) continue;
      final match = sim.checkMatchesFrom(entry.key, entry.value);
      if (match != null && match.matched.length >= 6) {
        allMatched.addAll(match.matched);
      }
    }
    for (final hex in sim.board.keys.toList()) {
      if (wazaColors.contains(sim.board[hex])) {
        allMatched.add(hex);
      }
    }
    for (final hex in allMatched) {
      sim.board.remove(hex);
    }

    return ExtendedSimDropResult(
      sim,
      newBalls,
      allMatched,
      wazaCompleted: wazaCompleted,
      highestWazaMult: highestWazaMult,
      shapeCollapsed: shapeCollapsed,
      orderedTargetHexes:
          orderedTargetHexes.whereType<HexCoordinate>().toList(),
    );
  }

  Vector2 _hexToPixel(HexCoordinate hex) {
    const ballRadius = 15.0;
    final xOffset = hex.row.isEven ? ballRadius : 0.0;
    final x = request.gridOffsetX + xOffset + hex.col * (ballRadius * 2);
    final rowHeight = ballRadius * sqrt(3);
    final y = request.gridOffsetY + hex.row * rowHeight;
    return Vector2(x, y);
  }

  HexCoordinate _pixelToHex(Vector2 point) {
    const ballRadius = 15.0;
    final rowHeight = ballRadius * sqrt(3);
    var closestRow = ((point.y - request.gridOffsetY) / rowHeight).round();
    closestRow = min(closestRow, 11);
    final xOffset = closestRow.isEven ? ballRadius : 0.0;
    var closestCol =
        ((point.x - request.gridOffsetX - xOffset) / (ballRadius * 2)).round();
    final maxCols = closestRow.isOdd ? 10 : 9;
    closestCol = max(0, min(closestCol, maxCols - 1));
    return HexCoordinate(closestCol, closestRow);
  }
}

List<Vector2> _pieceBaseOffsets() {
  const ballRadius = 15.0;
  const d = ballRadius * 2;
  final rCenter = d * sqrt(3) / 3;
  final hSub = d * sqrt(3) / 6;
  return [
    Vector2(0, -rCenter),
    Vector2(-d / 2, hSub),
    Vector2(d / 2, hSub),
  ];
}

class _BallDrop {
  final int index;
  final BallColor color;
  final double nx;
  final double ny;
  _BallDrop(this.index, this.color, this.nx, this.ny);
}
