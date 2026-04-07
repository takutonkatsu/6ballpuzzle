import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'headless_game.dart';
import '../game/game_models.dart';
import '../game/game_logic.dart';

class Individual {
  Map<String, double> weightsMap;
  double fitness;

  Individual({required this.weightsMap, this.fitness = 0.0});

  CPUWeights get toCPUWeights {
    return CPUWeights(
      safety: weightsMap['safety'] ?? 1.0,
      shape: weightsMap['shape'] ?? 1.0,
      flatness: weightsMap['flatness'] ?? 1.0,
      connection: weightsMap['connection'] ?? 1.0,
    );
  }
}

class GeneticEvolver {
  final int popSize = 8;
  final int generations = 10; 
  final double mutationRate = 0.2;
  final Random rng = Random();

  List<Individual> population = [];

  void initializePopulation() {
    for (int i = 0; i < popSize; i++) {
        population.add(Individual(weightsMap: {
          'safety': 0.5 + rng.nextDouble() * 1.5, 
          'shape': 0.5 + rng.nextDouble() * 1.5,
          'flatness': 0.5 + rng.nextDouble() * 1.5,
          'connection': 0.5 + rng.nextDouble() * 1.5,
        }));
    }
  }

  Future<void> runEvolution() async {
    initializePopulation();

    for (int g = 1; g <= generations; g++) {
      for (var ind in population) {
        ind.fitness = evaluate(ind);
      }

      population.sort((a, b) => b.fitness.compareTo(a.fitness));

      Individual best = population.first;
      print('第$g世代: 最高スコア ${best.fitness.toInt()}, 重み [Saf: ${best.weightsMap['safety']!.toStringAsFixed(2)}, Sha: ${best.weightsMap['shape']!.toStringAsFixed(2)}, Flat: ${best.weightsMap['flatness']!.toStringAsFixed(2)}, Conn: ${best.weightsMap['connection']!.toStringAsFixed(2)}]');

      if (g == generations) {
        _saveBestWeights(best);
        break;
      }

      List<Individual> newPop = [];
      newPop.add(Individual(weightsMap: Map.from(population[0].weightsMap), fitness: population[0].fitness));
      newPop.add(Individual(weightsMap: Map.from(population[1].weightsMap), fitness: population[1].fitness));

      while (newPop.length < popSize) {
        Individual p1 = _selectParent();
        Individual p2 = _selectParent();
        Individual child = crossover(p1, p2);
        mutate(child);
        newPop.add(child);
      }

      population = newPop;
    }
  }

  double evaluate(Individual ind) {
    double totalScore = 0;
    const int trials = 1;
    for (int i = 0; i < trials; i++) {
       HeadlessGame game = HeadlessGame(ind.toCPUWeights);
       totalScore += game.run();
    }
    return totalScore / trials;
  }

  Individual _selectParent() {
    Individual best = population[rng.nextInt(population.length)];
    for (int i = 0; i < 3; i++) {
       Individual contender = population[rng.nextInt(population.length)];
       if (contender.fitness > best.fitness) {
          best = contender;
       }
    }
    return best;
  }

  Individual crossover(Individual p1, Individual p2) {
    Map<String, double> childWeights = {};
    for (var key in p1.weightsMap.keys) {
      childWeights[key] = rng.nextBool() ? p1.weightsMap[key]! : p2.weightsMap[key]!;
    }
    return Individual(weightsMap: childWeights);
  }

  void mutate(Individual ind) {
    for (var key in ind.weightsMap.keys) {
      if (rng.nextDouble() < mutationRate) {
        double change = (rng.nextDouble() - 0.5) * 0.5; 
        ind.weightsMap[key] = max(0.01, ind.weightsMap[key]! + change);
      }
    }
  }

  void _saveBestWeights(Individual best) {
    final file = File('best_weights.json');
    file.writeAsStringSync(jsonEncode(best.weightsMap));
    print('最適化された重みを best_weights.json に保存しました！');
  }
}

void main() async {
  print('=== 6-Ball Puzzle GA Tuner (Pure Dart) ===');
  await GeneticEvolver().runEvolution();
}
