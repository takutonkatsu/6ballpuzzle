import 'package:flutter/foundation.dart';
import 'game_models.dart';

enum ScoreMode {
  endless,
  daily,
}

class ScoreState {
  final int score;
  final int level;
  final int totalClearedBalls;

  ScoreState({
    required this.score,
    required this.level,
    required this.totalClearedBalls,
  });
}

class ScoreManager {
  static const int maxEndlessScore = 99999999;

  ScoreManager({
    this.mode = ScoreMode.endless,
  }) : state = ValueNotifier(ScoreState(
          score: 0,
          level: 1,
          totalClearedBalls: 0,
        ));

  final ScoreMode mode;
  final ValueNotifier<ScoreState> state;

  int _chain = 0;
  int _maxChain = 0;
  DateTime? _lastPlacementAt;
  Duration? _lastPlacementInterval;

  int get maxChainThisRun => _maxChain;

  Map<String, int> exportSnapshot() {
    return {
      'score': state.value.score,
      'level': state.value.level,
      'totalClearedBalls': state.value.totalClearedBalls,
      'chain': _chain,
      'maxChain': _maxChain,
    };
  }

  void restoreSnapshot(Map<String, dynamic>? snapshot) {
    if (snapshot == null) {
      reset();
      return;
    }

    final score = snapshot['score'];
    final level = snapshot['level'];
    final totalClearedBalls = snapshot['totalClearedBalls'];
    final chain = snapshot['chain'];
    final maxChain = snapshot['maxChain'];

    _chain = chain is num ? chain.toInt() : 0;
    _maxChain = maxChain is num ? maxChain.toInt() : 0;
    state.value = ScoreState(
      score: score is num ? score.toInt().clamp(0, maxEndlessScore).toInt() : 0,
      level: level is num ? level.toInt() : 1,
      totalClearedBalls:
          totalClearedBalls is num ? totalClearedBalls.toInt() : 0,
    );
  }

  void reset() {
    _chain = 0;
    _maxChain = 0;
    _lastPlacementAt = null;
    _lastPlacementInterval = null;
    state.value = ScoreState(
      score: 0,
      level: 1,
      totalClearedBalls: 0,
    );
  }

  void endChain() {
    _chain = 0;
  }

  void recordPlacement() {
    if (mode != ScoreMode.daily) {
      return;
    }
    final now = DateTime.now();
    final previous = _lastPlacementAt;
    _lastPlacementAt = now;
    if (previous != null) {
      _lastPlacementInterval = now.difference(previous);
    }
  }

  void addMatch(int ballsDestroyed, WazaType highestWaza) {
    if (ballsDestroyed == 0) return;

    _chain++; // 今回の消去で連鎖を加算
    if (_chain > _maxChain) {
      _maxChain = _chain;
    }

    final earnedScore = mode == ScoreMode.daily
        ? _dailyScoreForMatch(ballsDestroyed, highestWaza)
        : _endlessScoreForMatch(ballsDestroyed, highestWaza);

    int newTotalCleared = state.value.totalClearedBalls + ballsDestroyed;
    // 60個ごとに1レベルアップ
    int newLevel = 1 + (newTotalCleared ~/ 60);

    state.value = ScoreState(
      score:
          (state.value.score + earnedScore).clamp(0, maxEndlessScore).toInt(),
      level: newLevel,
      totalClearedBalls: newTotalCleared,
    );
  }

  int _endlessScoreForMatch(int ballsDestroyed, WazaType highestWaza) {
    final baseScore = ballsDestroyed * 100;
    final shapeMultiplier = highestWaza.multiplier;
    final chainMultiplier = 1.0 + (_chain - 1) * 0.5;
    final levelMultiplier = 1.0 + (state.value.level * 0.1);
    return (baseScore * shapeMultiplier * chainMultiplier * levelMultiplier)
        .toInt();
  }

  int _dailyScoreForMatch(int ballsDestroyed, WazaType highestWaza) {
    var score = ballsDestroyed * 100;
    if (highestWaza != WazaType.none) {
      score += switch (highestWaza) {
        WazaType.straight => 800,
        WazaType.pyramid => 1500,
        WazaType.hexagon => 3000,
        WazaType.none => 0,
      };
      score += ballsDestroyed * 180;
    }
    if (_chain >= 2) {
      score += 300 * (_chain - 1);
    }
    final interval = _lastPlacementInterval;
    if (interval != null) {
      if (interval.inMilliseconds <= 2000) {
        score += 250;
      } else if (interval.inMilliseconds <= 3000) {
        score += 120;
      }
    }
    return score;
  }

  void addDailyEndBonus({required bool noDanger}) {
    if (mode != ScoreMode.daily || !noDanger) {
      return;
    }
    state.value = ScoreState(
      score: (state.value.score + 1000).clamp(0, maxEndlessScore).toInt(),
      level: state.value.level,
      totalClearedBalls: state.value.totalClearedBalls,
    );
  }

  double get currentFallSpeed {
    return 15.0 + (state.value.level - 1) * 10.0;
  }

  void dispose() {
    state.dispose();
  }
}
