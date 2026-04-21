import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:vector_math/vector_math_64.dart'; // 🌟 この1行を追加してエラーを解消！
import '../game/game_models.dart';
import '../game/game_logic.dart';

const int populationSize = 50;
const int generations = 100;
const int gamesPerIndividual = 3;
const double mutationRate = 0.15;

final Random rng = Random();

class Individual {
  CPUWeights weights;
  double fitness = 0.0;
  int totalWazas = 0;
  int avgTurns = 0;

  Individual(this.weights);

  factory Individual.random() {
    return Individual(CPUWeights(
      safety: rng.nextDouble() * 50.0,
      shape: rng.nextDouble() * 10.0,
      flatness: rng.nextDouble() * 10.0,
      connection: rng.nextDouble() * 20.0,
      wazaBonus: rng.nextDouble() * 50000000.0,
      hintBonus: rng.nextDouble() * 50000000.0,
      hintPenalty: rng.nextDouble() * 500000000.0,
      reachBonus: rng.nextDouble() * 20000000.0,
      cavePenalty: rng.nextDouble() * 50000000.0,
      dumpBonus: rng.nextDouble() * 500000.0,
    ));
  }
}

void main() {
  print("🧬 ボーナス＆ペナルティ完全自動調整GAシミュレーション開始...");
  
  List<Individual> population = List.generate(populationSize, (_) => Individual.random());
  Individual globalBest = population.first;

  for (int gen = 1; gen <= generations; gen++) {
    print("--- 世代 $gen / $generations ---");
    
    for (var ind in population) {
      _evaluateIndividual(ind);
      if (ind.fitness > globalBest.fitness) globalBest = ind;
    }

    population.sort((a, b) => b.fitness.compareTo(a.fitness));

    print("🏆 スコア: ${population.first.fitness.toStringAsFixed(1)} | 生存: ${population.first.avgTurns}手 | ワザ: ${population.first.totalWazas}回");

    List<Individual> nextGen = [];
    int eliteCount = (populationSize * 0.1).toInt();
    for (int i = 0; i < eliteCount; i++) nextGen.add(population[i]);

    List<Individual> parents = population.sublist(0, (populationSize * 0.5).toInt());
    while (nextGen.length < populationSize) {
      var p1 = parents[rng.nextInt(parents.length)];
      var p2 = parents[rng.nextInt(parents.length)];
      nextGen.add(_crossoverAndMutate(p1, p2));
    }
    population = nextGen;
  }

  print("\n🎉 学習完了！最強の遺伝子を保存します...");
  final file = File('best_weights_full.json');
  file.writeAsStringSync(jsonEncode({
    'safety': globalBest.weights.safety,
    'shape': globalBest.weights.shape,
    'flatness': globalBest.weights.flatness,
    'connection': globalBest.weights.connection,
    'wazaBonus': globalBest.weights.wazaBonus,
    'hintBonus': globalBest.weights.hintBonus,
    'hintPenalty': globalBest.weights.hintPenalty,
    'reachBonus': globalBest.weights.reachBonus,
    'cavePenalty': globalBest.weights.cavePenalty,
    'dumpBonus': globalBest.weights.dumpBonus,
  }));
  print("💾 best_weights_full.json に保存しました！出力された値を game_logic.dart と cpu_agent.dart にコピペしてください。");
}

Individual _crossoverAndMutate(Individual p1, Individual p2) {
  double _mix(double a, double b) => rng.nextBool() ? a : b;
  double _mut(double val, double maxVal) => rng.nextDouble() < mutationRate ? (val + (rng.nextDouble() * maxVal * 0.2 - maxVal * 0.1)).clamp(0.0, maxVal) : val;

  return Individual(CPUWeights(
    safety: _mut(_mix(p1.weights.safety, p2.weights.safety), 100.0),
    shape: _mut(_mix(p1.weights.shape, p2.weights.shape), 20.0),
    flatness: _mut(_mix(p1.weights.flatness, p2.weights.flatness), 20.0),
    connection: _mut(_mix(p1.weights.connection, p2.weights.connection), 30.0),
    wazaBonus: _mut(_mix(p1.weights.wazaBonus, p2.weights.wazaBonus), 100000000.0),
    hintBonus: _mut(_mix(p1.weights.hintBonus, p2.weights.hintBonus), 100000000.0),
    hintPenalty: _mut(_mix(p1.weights.hintPenalty, p2.weights.hintPenalty), 1000000000.0),
    reachBonus: _mut(_mix(p1.weights.reachBonus, p2.weights.reachBonus), 50000000.0),
    cavePenalty: _mut(_mix(p1.weights.cavePenalty, p2.weights.cavePenalty), 100000000.0),
    dumpBonus: _mut(_mix(p1.weights.dumpBonus, p2.weights.dumpBonus), 1000000.0),
  ));
}

void _evaluateIndividual(Individual ind) {
  double totalScore = 0.0;
  int totalTurns = 0;
  int wazas = 0;

  for (int i = 0; i < gamesPerIndividual; i++) {
    SimGrid grid = SimGrid(12, {});
    bool gameOver = false;
    int turns = 0;

    while (!gameOver && turns < 200) {
      turns++;
      List<BallColor> nextColors = [
        BallColor.values[rng.nextInt(5)],
        BallColor.values[rng.nextInt(5)],
        BallColor.values[rng.nextInt(5)],
      ];

      double bestScore = -double.infinity;
      int bestCol = 0;
      double bestOffset = 0.0;
      int bestRot = 0;

      for (int c = 0; c < 10; c++) {
        for (double offset in [-8.0, 0.0, 8.0]) {
          for (int r = 0; r < 6; r++) {
            SimDropResult result = _simulateDropHeadless(grid, c, offset, r, nextColors);
            double score = evaluateBoardLogic(result.simGrid, result.newBalls, ind.weights);
            
            if (result.wazaCompleted) score += ind.weights.wazaBonus * 2.0;

            if (score > bestScore) {
              bestScore = score; bestCol = c; bestOffset = offset; bestRot = r;
            }
          }
        }
      }

      SimDropResult finalDrop = _simulateDropHeadless(grid, bestCol, bestOffset, bestRot, nextColors);
      grid = finalDrop.simGrid;
      if (finalDrop.wazaCompleted) wazas++;

      int highest = 12;
      for (var hex in grid.board.keys) if (hex.row < highest) highest = hex.row;
      if (highest <= 2) gameOver = true;
    }
    totalTurns += turns;
    totalScore += (turns * 10.0) + (wazas * 10000.0);
  }

  ind.fitness = totalScore / gamesPerIndividual;
  ind.avgTurns = totalTurns ~/ gamesPerIndividual;
  ind.totalWazas = wazas;
}

SimDropResult _simulateDropHeadless(SimGrid baseGrid, int targetCol, double offsetX, int targetRot, List<BallColor> colors) {
  SimGrid simGrid = SimGrid(12, Map.from(baseGrid.board));
  Map<HexCoordinate, BallColor> newBalls = {};
  
  double rad = targetRot * pi / 3;
  List<Vector2> baseOffsets = [Vector2(0, -17.32), Vector2(-15, 8.66), Vector2(15, 8.66)];
  
  List<_BallDrop> drops = [];
  for (int i = 0; i < 3; i++) {
    double nx = baseOffsets[i].x * cos(rad) - baseOffsets[i].y * sin(rad);
    double ny = baseOffsets[i].x * sin(rad) + baseOffsets[i].y * cos(rad);
    drops.add(_BallDrop(colors[i], nx, ny));
  }
  drops.sort((a, b) => b.ny.compareTo(a.ny));

  for (var drop in drops) {
     int c = (targetCol + (drop.nx > 0 ? 1 : drop.nx < 0 ? -1 : 0)).clamp(0, 9);
     HexCoordinate startHex = simGrid.findNearestEmpty(HexCoordinate(c, 0));
     HexCoordinate finalHex = simGrid.dropBall(startHex, offsetX);
     simGrid.board[finalHex] = drop.color;
     newBalls[finalHex] = drop.color;
  }

  bool wazaCompleted = false;
  Set<HexCoordinate> toRemove = {};
  for (var entry in newBalls.entries) {
     if (toRemove.contains(entry.key)) continue;
     var match = simGrid.checkMatchesFrom(entry.key, entry.value);
     if (match != null && match.matched.length >= 6) {
        if (match.waza != WazaType.none) wazaCompleted = true;
        toRemove.addAll(match.matched);
     }
  }

  for (var hex in toRemove) simGrid.board.remove(hex);
  return SimDropResult(simGrid, newBalls, toRemove, wazaCompleted: wazaCompleted);
}

class _BallDrop {
  final BallColor color;
  final double nx;
  final double ny;
  _BallDrop(this.color, this.nx, this.ny);
}