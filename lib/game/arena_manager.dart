import 'package:shared_preferences/shared_preferences.dart';

import '../data/player_data_manager.dart';

class ArenaReward {
  const ArenaReward({
    required this.coins,
    required this.exp,
    required this.gachaTickets,
    required this.cyberScrap,
    this.title,
  });

  final int coins;
  final int exp;
  final int gachaTickets;
  final int cyberScrap;
  final String? title;

  bool get hasAnyReward =>
      coins > 0 ||
      exp > 0 ||
      gachaTickets > 0 ||
      cyberScrap > 0 ||
      title != null;
}

class ArenaMatchResult {
  const ArenaMatchResult({
    required this.isCompleted,
    required this.wins,
    required this.losses,
    this.reward = const ArenaReward(
      coins: 0,
      exp: 0,
      gachaTickets: 0,
      cyberScrap: 0,
      title: null,
    ),
  });

  final bool isCompleted;
  final int wins;
  final int losses;
  final ArenaReward reward;
}

class ArenaManager {
  ArenaManager._internal();

  static final ArenaManager instance = ArenaManager._internal();
  static const int entryCost = 5000;
  static const int maxWins = 12;
  static const int maxLosses = 3;
  static const String _activeKey = 'arena_is_active';
  static const String _winsKey = 'arena_current_wins';
  static const String _lossesKey = 'arena_current_losses';

  final PlayerDataManager _playerData = PlayerDataManager.instance;

  bool _loaded = false;
  bool isArenaActive = false;
  int currentWins = 0;
  int currentLosses = 0;

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    isArenaActive = prefs.getBool(_activeKey) ?? false;
    currentWins = prefs.getInt(_winsKey) ?? 0;
    currentLosses = prefs.getInt(_lossesKey) ?? 0;
    _loaded = true;
  }

  Future<void> enterArena() async {
    await load();
    if (isArenaActive) {
      return;
    }

    await _playerData.spendCoins(entryCost);
    await _playerData.recordArenaChallengeStarted();
    currentWins = 0;
    currentLosses = 0;
    isArenaActive = true;
    await _save();
  }

  Future<ArenaMatchResult> recordArenaMatch(bool isWin) async {
    await load();
    if (!isArenaActive) {
      return ArenaMatchResult(
        isCompleted: false,
        wins: currentWins,
        losses: currentLosses,
      );
    }

    if (isWin) {
      currentWins = (currentWins + 1).clamp(0, maxWins);
      await _playerData.updateMaxArenaWins(currentWins);
    } else {
      currentLosses = (currentLosses + 1).clamp(0, maxLosses);
    }

    final completed = currentWins >= maxWins || currentLosses >= maxLosses;
    if (!completed) {
      await _save();
      return ArenaMatchResult(
        isCompleted: false,
        wins: currentWins,
        losses: currentLosses,
      );
    }

    final reward = _calculateReward(currentWins);
    isArenaActive = false;
    await _grantReward(reward);
    await _save();

    return ArenaMatchResult(
      isCompleted: true,
      wins: currentWins,
      losses: currentLosses,
      reward: reward,
    );
  }

  ArenaReward _calculateReward(int wins) {
    const rewardTable = [
      500,
      1500,
      2600,
      3800,
      5000,
      6900,
      9000,
      11300,
      13800,
      16500,
      19400,
      22500,
      30000,
    ];
    final coins = rewardTable[wins.clamp(0, maxWins)];

    return ArenaReward(
      coins: coins,
      exp: 0,
      gachaTickets: 0,
      cyberScrap: 0,
      title: null,
    );
  }

  ArenaReward previewRewardForWins(int wins) {
    return _calculateReward(wins.clamp(0, maxWins));
  }

  Future<void> _grantReward(ArenaReward reward) async {
    if (reward.coins > 0) {
      await _playerData.addCoins(reward.coins);
    }
    if (reward.exp > 0) {
      await _playerData.addExp(reward.exp);
    }
    if (reward.gachaTickets > 0) {
      await _playerData.addGachaTickets(reward.gachaTickets);
    }
    if (reward.cyberScrap > 0) {
      await _playerData.addCyberScrap(reward.cyberScrap);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_activeKey, isArenaActive);
    await prefs.setInt(_winsKey, currentWins);
    await prefs.setInt(_lossesKey, currentLosses);
  }

  Future<void> setArenaStateForDebug({
    required bool isActive,
    required int wins,
    required int losses,
  }) async {
    await load();
    isArenaActive = isActive;
    currentWins = wins.clamp(0, maxWins);
    currentLosses = losses.clamp(0, maxLosses);
    await _save();
  }
}
