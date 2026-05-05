import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';
import '../data/player_data_manager.dart';
import 'mission_catalog.dart';

class MissionManager {
  MissionManager._internal();

  static final MissionManager instance = MissionManager._internal();
  static const int allClearBonusCoins = 2000;
  static const int _adsRemovedRewardMultiplier = 2;
  static const int _adsRemovedDailyRerollLimit = 1;
  static const String _dailyRerollDateKey = 'mission_daily_reroll_date';
  static const String _dailyRerollCountKey = 'mission_daily_reroll_count';

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
      total += rewardCoinsFor(mission);
    }
    return total;
  }

  int get allClearClaimAmount {
    return allClearBonusCoins;
  }

  bool get adsRemovedBenefitsEnabled => AppSettings.instance.adsRemoved.value;

  Future<int> remainingDailyRerolls() async {
    if (!adsRemovedBenefitsEnabled) {
      return 999;
    }
    final prefs = await _prefs();
    return (_adsRemovedDailyRerollLimit - _dailyRerollCountToday(prefs))
        .clamp(0, _adsRemovedDailyRerollLimit);
  }

  Future<void> load() async {
    await _playerData.checkDailyReset();
    await _syncSpecialMissionVariant();
    await _applyLoginRewardMissionProgressIfNeeded();
    await _sortAndPersistIfNeeded();
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
      await _persistMissionChanges(missions);
    }
  }

  Future<void> rerollMission(int index) async {
    await load();
    final missions = currentMissions;
    if (index < 0 || index >= missions.length) {
      throw RangeError.index(index, missions, 'index');
    }
    final missionId = missions[index]['id']?.toString() ?? '';
    if (MissionCatalog.isRewardedAdMissionId(missionId) ||
        MissionCatalog.isLoginRewardMissionId(missionId)) {
      throw StateError('このミッションはチェンジできません。');
    }

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

    if (adsRemovedBenefitsEnabled) {
      final prefs = await _prefs();
      final rerollCount = _dailyRerollCountToday(prefs);
      if (rerollCount >= _adsRemovedDailyRerollLimit) {
        throw StateError('チェンジは1日1回までです。');
      }
      await prefs.setString(_dailyRerollDateKey, _todayKey());
      await prefs.setInt(_dailyRerollCountKey, rerollCount + 1);
    }

    final nextMission =
        candidates[_random.nextInt(candidates.length)].toMissionMap();
    missions[index] = nextMission;
    await _persistMissionChanges(missions);
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

    final reward = rewardCoinsFor(mission);
    mission['claimed'] = true;
    await _playerData.addCoins(reward);
    await _persistMissionChanges(missions);
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

    const claimAmount = allClearBonusCoins;
    if (claimAmount == 0) return 0;

    await _playerData.addCoins(claimAmount);
    await _persistMissionChanges(missions);
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
    await _persistMissionChanges(missions);
    return claimMissionReward(index);
  }

  Future<void> markRewardedAdMissionWatched(int index) async {
    final missions = currentMissions;
    if (index < 0 || index >= missions.length) {
      throw StateError('ミッションが見つかりません。');
    }
    final mission = missions[index];
    final missionId = mission['id']?.toString() ?? '';
    if (!MissionCatalog.isRewardedAdMissionId(missionId)) {
      throw StateError('動画広告ミッションではありません。');
    }
    if (mission['claimed'] as bool? ?? false) {
      return;
    }
    mission['progress'] = mission['target'] ?? 1;
    await _persistMissionChanges(missions);
  }

  int rewardCoinsFor(Map<String, dynamic> mission) {
    final baseReward = _intValue(mission['rewardCoins']) ?? 0;
    if (!adsRemovedBenefitsEnabled) {
      return baseReward;
    }
    return baseReward * _adsRemovedRewardMultiplier;
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int _dailyRerollCountToday(SharedPreferences prefs) {
    final savedDate = prefs.getString(_dailyRerollDateKey);
    if (savedDate != _todayKey()) {
      return 0;
    }
    return prefs.getInt(_dailyRerollCountKey) ?? 0;
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<void> _persistMissionChanges(List<Map<String, dynamic>> missions) async {
    _sortMissionsInPlace(missions);
    await _playerData.saveCurrentMissions(missions);
  }

  Future<void> _sortAndPersistIfNeeded() async {
    final missions = currentMissions;
    final sorted = List<Map<String, dynamic>>.from(missions);
    _sortMissionsInPlace(sorted);
    if (!_missionListsEqual(missions, sorted)) {
      await _playerData.saveCurrentMissions(sorted);
    }
  }

  void _sortMissionsInPlace(List<Map<String, dynamic>> missions) {
    final indexed = missions.asMap().entries.toList()
      ..sort((a, b) {
        final aDone = _isComplete(a.value);
        final bDone = _isComplete(b.value);
        if (aDone != bDone) {
          return aDone ? 1 : -1;
        }
        return a.key.compareTo(b.key);
      });
    final reordered = indexed.map((entry) => entry.value).toList();
    missions
      ..clear()
      ..addAll(reordered);
  }

  bool _missionListsEqual(
    List<Map<String, dynamic>> left,
    List<Map<String, dynamic>> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i]['id'] != right[i]['id']) {
        return false;
      }
    }
    return true;
  }

  Future<void> _applyLoginRewardMissionProgressIfNeeded() async {
    final missions = currentMissions;
    if (missions.isEmpty || _playerData.lastLoginDate != _todayKey()) {
      return;
    }

    var changed = false;
    for (final mission in missions) {
      final missionId = mission['id']?.toString() ?? '';
      if (!MissionCatalog.isLoginRewardMissionId(missionId)) {
        continue;
      }
      final target = _intValue(mission['target']) ?? 1;
      final progress = _intValue(mission['progress']) ?? 0;
      if (progress < target) {
        mission['progress'] = target;
        changed = true;
      }
    }

    if (changed) {
      await _persistMissionChanges(missions);
    }
  }

  Future<void> _syncSpecialMissionVariant() async {
    final missions = currentMissions;
    if (missions.isEmpty) {
      return;
    }

    final shouldUseLoginReward = adsRemovedBenefitsEnabled;
    var changed = false;
    for (var i = 0; i < missions.length; i++) {
      final mission = missions[i];
      final missionId = mission['id']?.toString() ?? '';
      if (!MissionCatalog.isRewardedAdMissionId(missionId) &&
          !MissionCatalog.isLoginRewardMissionId(missionId)) {
        continue;
      }

      final replacement = shouldUseLoginReward
          ? const MissionDefinition(
              id: 'login_bonus_1',
              title: 'ログイン報酬を受け取る',
              description: 'ログイン報酬を受け取る',
              eventKey: 'login_bonus',
              target: 1,
              rewardCoins: 500,
            ).toMissionMap()
          : const MissionDefinition(
              id: 'watch_rewarded_ad_1',
              title: '動画広告を見る',
              description: '動画広告を1回見る',
              eventKey: 'watch_rewarded_ad',
              target: 1,
              rewardCoins: 500,
            ).toMissionMap();

      replacement['claimed'] = mission['claimed'] as bool? ?? false;
      replacement['allClearBonusClaimed'] =
          mission['allClearBonusClaimed'] as bool? ?? false;
      replacement['progress'] = shouldUseLoginReward
          ? (replacement['target'] as int)
          : ((mission['claimed'] as bool? ?? false) ? 1 : 0);
      if (missionId != replacement['id'] ||
          mission['progress'] != replacement['progress']) {
        missions[i] = replacement;
        changed = true;
      }
      break;
    }

    if (changed) {
      await _playerData.saveCurrentMissions(missions);
    }
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
