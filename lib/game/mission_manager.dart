import 'dart:math';

import '../data/player_data_manager.dart';
import 'mission_catalog.dart';

class MissionManager {
  MissionManager._internal();

  static final MissionManager instance = MissionManager._internal();
  static const int rerollCost = 500;

  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final Random _random = Random();

  List<Map<String, dynamic>> get currentMissions => _playerData.currentMissions;

  int get claimableCount => currentMissions.where(_isClaimable).length;

  Future<void> load() async {
    await _playerData.checkDailyReset();
  }

  Future<void> recordEvent(String eventKey, {int amount = 1}) async {
    await load();
    final missions = currentMissions;
    var changed = false;

    for (final mission in missions) {
      if (mission['eventKey'] != eventKey ||
          (mission['claimed'] as bool? ?? false)) {
        continue;
      }

      final target = _intValue(mission['target']) ?? 0;
      final progress = _intValue(mission['progress']) ?? 0;
      final nextProgress = (progress + amount).clamp(0, target);
      if (nextProgress != progress) {
        mission['progress'] = nextProgress;
        changed = true;
      }
    }

    if (changed) {
      await _playerData.saveCurrentMissions(missions);
    }
  }

  Future<void> rerollMission(int index) async {
    await load();
    final missions = currentMissions;
    if (index < 0 || index >= missions.length) {
      throw RangeError.index(index, missions, 'index');
    }

    await _playerData.spendCoins(rerollCost);
    final currentIds =
        missions.map((mission) => mission['id']?.toString() ?? '').toSet();
    currentIds.remove(missions[index]['id']?.toString() ?? '');

    final candidates = MissionCatalog.dailyPool
        .where((mission) => !currentIds.contains(mission.id))
        .toList();
    if (candidates.isEmpty) {
      throw StateError('差し替え可能なミッションがありません。');
    }

    final nextMission =
        candidates[_random.nextInt(candidates.length)].toMissionMap();
    missions[index] = nextMission;
    await _playerData.saveCurrentMissions(missions);
  }

  Future<int> claimMission(int index, {bool boosted = false}) async {
    await load();
    final missions = currentMissions;
    if (index < 0 || index >= missions.length) {
      throw RangeError.index(index, missions, 'index');
    }

    final mission = missions[index];
    if (!_isClaimable(mission)) {
      throw StateError('まだ報酬を受け取れません。');
    }

    final baseReward = _intValue(mission['rewardCoins']) ?? 0;
    final reward = boosted ? baseReward * 2 : baseReward;
    mission['claimed'] = true;
    await _playerData.addCoins(reward);
    await _playerData.saveCurrentMissions(missions);
    return reward;
  }

  bool _isClaimable(Map<String, dynamic> mission) {
    final claimed = mission['claimed'] as bool? ?? false;
    final progress = _intValue(mission['progress']) ?? 0;
    final target = _intValue(mission['target']) ?? 0;
    return !claimed && progress >= target;
  }

  int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }
}
