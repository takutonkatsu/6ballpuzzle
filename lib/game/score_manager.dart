import 'package:flutter/foundation.dart';
import 'game_models.dart';

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
  final ValueNotifier<ScoreState> state = ValueNotifier(ScoreState(
    score: 0,
    level: 1,
    totalClearedBalls: 0,
  ));

  int _chain = 0;

  void reset() {
    _chain = 0;
    state.value = ScoreState(
      score: 0,
      level: 1,
      totalClearedBalls: 0,
    );
  }

  void endChain() {
    _chain = 0;
  }

  void addMatch(int ballsDestroyed, WazaType highestWaza) {
    if (ballsDestroyed == 0) return;

    _chain++; // 今回の消去で連鎖を加算

    int baseScore = ballsDestroyed * 100;
    double shapeMultiplier = highestWaza.multiplier;
    double chainMultiplier = 1.0 + (_chain - 1) * 0.5;
    double levelMultiplier = 1.0 + (state.value.level * 0.1);

    int earnedScore = (baseScore * shapeMultiplier * chainMultiplier * levelMultiplier).toInt();
    
    int newTotalCleared = state.value.totalClearedBalls + ballsDestroyed;
    // 60個ごとに1レベルアップ
    int newLevel = 1 + (newTotalCleared ~/ 60);

    state.value = ScoreState(
      score: state.value.score + earnedScore,
      level: newLevel,
      totalClearedBalls: newTotalCleared,
    );
  }

  double get currentFallSpeed {
    return 15.0 + (state.value.level - 1) * 10.0;
  }
}
