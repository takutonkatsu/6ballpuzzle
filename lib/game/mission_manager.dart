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

  bool get allMissionsComplete {
    if (currentMissions.isEmpty) return false;
    for (final mission in currentMissions) {
      if (!_isComplete(mission)) return false;
    }
    return true;
  }

  Future<int> claimAllMissionsBoosted() async {
    await load();
    if (!allMissionsComplete) {
      throw StateError('すべてのミッションがクリアされていません。');
    }

    final missions = currentMissions;
    int totalBaseReward = 0;
    
    for (final mission in missions) {
      if (!(mission['claimed'] as bool? ?? false)) {
        totalBaseReward += _intValue(mission['rewardCoins']) ?? 0;
        mission['claimed'] = true;
      }
    }

    if (totalBaseReward == 0) return 0; // Already claimed

    final totalReward = totalBaseReward * 3;
    await _playerData.addCoins(totalReward);
    await _playerData.saveCurrentMissions(missions);

    return totalReward;
  }

  bool _isComplete(Map<String, dynamic> mission) {
    final progress = _intValue(mission['progress']) ?? 0;
    final target = _intValue(mission['target']) ?? 0;
    return progress >= target;
  }

  bool _isClaimable(Map<String, dynamic> mission) {
    final claimed = mission['claimed'] as bool? ?? false;
    return !claimed && _isComplete(mission);
  }

  int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }
}
