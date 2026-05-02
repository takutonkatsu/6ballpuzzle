import 'dart:math';

import '../data/player_data_manager.dart';
import 'mission_catalog.dart';

class MissionManager {
  MissionManager._internal();

  static final MissionManager instance = MissionManager._internal();
  static const int rerollCost = 500;
  static const int allClearBonusCoins = 2000;

  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final Random _random = Random();

  List<Map<String, dynamic>> get currentMissions => _playerData.currentMissions;

  int get claimableCount => currentMissions.where(_isClaimable).length;

  bool get isAllClearBonusClaimed {
    final missions = currentMissions;
    if (missions.isEmpty) return false;
    return missions.every(
      (mission) => mission['allClearBonusClaimed'] as bool? ?? false,
    );
  }

  int get totalMissionRewardCoins {
    var total = 0;
    for (final mission in currentMissions) {
      total += _intValue(mission['rewardCoins']) ?? 0;
    }
    return total;
  }

  int get allClearClaimAmount {
    if (isAllClearBonusClaimed) return 0;
    for (final mission in currentMissions) {
      if (!_isComplete(mission)) {
        return 0;
      }
    }
    return allClearBonusCoins;
  }

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
    final missionId = missions[index]['id']?.toString() ?? '';
    if (MissionCatalog.isRewardedAdMissionId(missionId)) {
      throw StateError('動画広告ミッションは固定です。');
    }

    await _playerData.spendCoins(rerollCost);
    final currentIds =
        missions.map((mission) => mission['id']?.toString() ?? '').toSet();
    currentIds.remove(missions[index]['id']?.toString() ?? '');

    final candidates = MissionCatalog.dailyPool
        .where(
          (mission) =>
              !MissionCatalog.isRewardedAdMissionId(mission.id) &&
              !currentIds.contains(mission.id),
        )
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

  Future<int> claimMissionReward(int index) async {
    await load();
    final missions = currentMissions;
    if (index < 0 || index >= missions.length) {
      throw RangeError.index(index, missions, 'index');
    }

    final mission = missions[index];
    if (!_isComplete(mission)) {
      throw StateError('ミッションがまだクリアされていません。');
    }
    if (mission['claimed'] as bool? ?? false) {
      return 0;
    }

    final reward = _intValue(mission['rewardCoins']) ?? 0;
    mission['claimed'] = true;
    await _playerData.addCoins(reward);
    await _playerData.saveCurrentMissions(missions);
    return reward;
  }

  Future<int> claimAllClearBonus() async {
    await load();
    if (!allMissionsComplete) {
      throw StateError('すべてのミッションがクリアされていません。');
    }
    if (isAllClearBonusClaimed) {
      return 0;
    }

    final missions = currentMissions;
    for (final mission in missions) {
      if (!(mission['claimed'] as bool? ?? false)) {
        mission['claimed'] = true;
      }
      mission['allClearBonusClaimed'] = true;
    }

    final claimAmount = allClearBonusCoins;
    if (claimAmount == 0) return 0;

    await _playerData.addCoins(claimAmount);
    await _playerData.saveCurrentMissions(missions);
    return claimAmount;
  }

  Future<int> completeRewardedAdMission(int index) async {
    await load();
    final missions = currentMissions;
    if (index < 0 || index >= missions.length) {
      throw RangeError.index(index, missions, 'index');
    }

    final mission = missions[index];
    final missionId = mission['id']?.toString() ?? '';
    if (!MissionCatalog.isRewardedAdMissionId(missionId)) {
      throw StateError('動画広告ミッションではありません。');
    }
    if (mission['claimed'] as bool? ?? false) {
      return 0;
    }

    final target = _intValue(mission['target']) ?? 1;
    mission['progress'] = target;
    await _playerData.saveCurrentMissions(missions);
    return claimMissionReward(index);
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
