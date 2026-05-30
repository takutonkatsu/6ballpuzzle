import 'dart:convert';
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
  static const String _regularClaimCountsKey =
      'mission_regular_claim_counts_json';
  static const String _rewardedAdViewCountKey =
      'mission_rewarded_ad_view_count';

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

  Future<List<Map<String, dynamic>>> regularMissions() async {
    await load();
    await _playerData.syncDailyWinRankPlacementsFromRecordSummary();
    final prefs = await _prefs();
    final claimedCounts = _regularClaimCounts(prefs);
    final missions = <Map<String, dynamic>>[];
    for (final definition in MissionCatalog.regularMissions) {
      if (_isHiddenRegularMission(definition)) {
        continue;
      }
      final claimedCount = claimedCounts[definition.id] ?? 0;
      final target = definition.targetForClaimedCount(claimedCount);
      final progress = _regularProgressFor(definition, prefs);
      missions.add({
        'id': definition.id,
        'title': definition.title,
        'progressKey': definition.progressKey,
        'progress': progress,
        'target': target,
        'rewardCoins': definition.rewardCoins,
        'claimedCount': claimedCount,
        'claimable': progress >= target,
      });
    }
    missions.sort((a, b) {
      final aClaimable = a['claimable'] as bool? ?? false;
      final bClaimable = b['claimable'] as bool? ?? false;
      if (aClaimable != bClaimable) {
        return aClaimable ? -1 : 1;
      }
      return MissionCatalog.regularMissions
          .indexWhere((definition) => definition.id == a['id'])
          .compareTo(MissionCatalog.regularMissions
              .indexWhere((definition) => definition.id == b['id']));
    });
    return missions;
  }

  Future<int> regularClaimableCount() async {
    final missions = await regularMissions();
    return missions.where((mission) => mission['claimable'] == true).length;
  }

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

  Future<void> recordRewardedAdView() async {
    final prefs = await _prefs();
    final current = max(0, prefs.getInt(_rewardedAdViewCountKey) ?? 0);
    await prefs.setInt(_rewardedAdViewCountKey, current + 1);
  }

  Future<void> rerollMission(int index) async {
    await load();
    final missions = currentMissions;
    if (index < 0 || index >= missions.length) {
      throw RangeError.index(index, missions, 'index');
    }
    final missionId = missions[index]['id']?.toString() ?? '';
    if (MissionCatalog.isRewardedAdMissionId(missionId) ||
        missionId == MissionCatalog.requiredEndlessMissionId ||
        MissionCatalog.isLoginRewardMissionId(missionId)) {
      throw StateError('このミッションはチェンジできません。');
    }

    final currentIds =
        missions.map((mission) => mission['id']?.toString() ?? '').toSet();
    currentIds.remove(missions[index]['id']?.toString() ?? '');

    final candidates = MissionCatalog.activeDailyPool
        .where(
          (mission) =>
              !MissionCatalog.isRewardedAdMissionId(mission.id) &&
              mission.id != MissionCatalog.requiredEndlessMissionId &&
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

  Future<int> claimMissionRewardById(String missionId) async {
    await load();
    final missions = currentMissions;
    final index = _indexOfMission(missions, missionId);
    if (index == -1) {
      throw StateError('ミッションが見つかりません。');
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
      mission['allClearBonusClaimed'] = true;
    }

    const claimAmount = allClearBonusCoins;
    if (claimAmount == 0) return 0;

    await _playerData.addCoins(claimAmount);
    await _persistMissionChanges(missions);
    return claimAmount;
  }

  Future<int> claimRegularMissionReward(String missionId) async {
    await load();
    final prefs = await _prefs();
    final definition = MissionCatalog.regularMissions.firstWhere(
      (mission) => mission.id == missionId,
      orElse: () => throw StateError('ミッションが見つかりません。'),
    );
    if (_isHiddenRegularMission(definition)) {
      throw StateError('このミッションは現在利用できません。');
    }
    final claimedCounts = _regularClaimCounts(prefs);
    final claimedCount = claimedCounts[missionId] ?? 0;
    final target = definition.targetForClaimedCount(claimedCount);
    final progress = _regularProgressFor(definition, prefs);
    if (progress < target) {
      throw StateError('ミッションがまだクリアされていません。');
    }

    claimedCounts[missionId] = claimedCount + 1;
    await prefs.setString(_regularClaimCountsKey, jsonEncode(claimedCounts));
    await _playerData.addCoins(definition.rewardCoins);
    return definition.rewardCoins;
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
    mission['claimed'] = true;
    final reward = rewardCoinsFor(mission);
    await _playerData.addCoins(reward);
    await _persistMissionChanges(missions);
    return reward;
  }

  Future<int> completeRewardedAdMissionById(String missionId) async {
    await load();
    final missions = currentMissions;
    final index = _indexOfMission(missions, missionId);
    if (index == -1) {
      throw StateError('ミッションが見つかりません。');
    }
    final mission = missions[index];
    if (!MissionCatalog.isRewardedAdMissionId(missionId)) {
      throw StateError('動画広告ミッションではありません。');
    }
    if (mission['claimed'] as bool? ?? false) {
      return 0;
    }

    final target = _intValue(mission['target']) ?? 1;
    mission['progress'] = target;
    mission['claimed'] = true;
    final reward = rewardCoinsFor(mission);
    await _playerData.addCoins(reward);
    await _persistMissionChanges(missions);
    return reward;
  }

  Future<void> markRewardedAdMissionWatched(int index) async {
    await load();
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

  Future<void> rerollMissionById(String missionId) async {
    await load();
    final missions = currentMissions;
    final index = _indexOfMission(missions, missionId);
    if (index == -1) {
      throw StateError('ミッションが見つかりません。');
    }
    if (MissionCatalog.isRewardedAdMissionId(missionId) ||
        missionId == MissionCatalog.requiredEndlessMissionId ||
        MissionCatalog.isLoginRewardMissionId(missionId)) {
      throw StateError('このミッションはチェンジできません。');
    }

    final currentIds =
        missions.map((mission) => mission['id']?.toString() ?? '').toSet();
    currentIds.remove(missionId);

    final candidates = MissionCatalog.activeDailyPool
        .where(
          (mission) =>
              !MissionCatalog.isRewardedAdMissionId(mission.id) &&
              mission.id != MissionCatalog.requiredEndlessMissionId &&
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

    missions[index] =
        candidates[_random.nextInt(candidates.length)].toMissionMap();
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

  Map<String, int> _regularClaimCounts(SharedPreferences prefs) {
    final raw = prefs.getString(_regularClaimCountsKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return {};
      }
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): _intValue(entry.value) ?? 0,
      };
    } catch (_) {
      return {};
    }
  }

  int _regularProgressFor(
    RegularMissionDefinition definition,
    SharedPreferences prefs,
  ) {
    return switch (definition.progressKey) {
      'ranked_wins' => _playerData.rankedWins,
      'highest_endless_score' => _playerData.highestEndlessScore,
      'rewarded_ad_views' => max(0, prefs.getInt(_rewardedAdViewCountKey) ?? 0),
      'total_login_days' => _playerData.totalLoginDays,
      'highest_rating' => _playerData.highestRating,
      'daily_win_rank_1' => _playerData.dailyWinRankPlacements['1位'] ?? 0,
      'waza_hexagon' => _playerData.wazaCounts['hexagon'] ?? 0,
      'waza_pyramid' => _playerData.wazaCounts['pyramid'] ?? 0,
      'waza_straight' => _playerData.wazaCounts['straight'] ?? 0,
      'total_cleared_balls' => _playerData.totalClearedBalls,
      _ => 0,
    };
  }

  bool _isHiddenRegularMission(RegularMissionDefinition definition) {
    return adsRemovedBenefitsEnabled &&
        definition.progressKey == 'rewarded_ad_views';
  }

  int _indexOfMission(List<Map<String, dynamic>> missions, String missionId) =>
      missions.indexWhere(
        (mission) => mission['id']?.toString() == missionId,
      );

  Future<void> _persistMissionChanges(
      List<Map<String, dynamic>> missions) async {
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
