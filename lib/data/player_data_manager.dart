import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../game/mission_catalog.dart';
import '../moderation/moderation_manager.dart';
import 'models/badge_item.dart';
import 'models/game_item.dart';
import '../app_review_config.dart';

class ItemGrantResult {
  const ItemGrantResult({
    required this.item,
    required this.isDuplicate,
    required this.leveledUp,
    required this.convertedToScrap,
    required this.cyberScrapAdded,
  });

  final GameItem item;
  final bool isDuplicate;
  final bool leveledUp;
  final bool convertedToScrap;
  final int cyberScrapAdded;
}

class MatchHistoryEntry {
  const MatchHistoryEntry({
    required this.isWin,
    required this.opponentName,
    required this.mode,
    required this.playedAt,
    this.isForfeitWin = false,
    this.score,
    this.ratingAfter,
    this.ratingDelta,
  });

  final bool isWin;
  final String opponentName;
  final String mode;
  final DateTime playedAt;
  final bool isForfeitWin;
  final int? score;
  final int? ratingAfter;
  final int? ratingDelta;

  Map<String, dynamic> toJson() {
    return {
      'isWin': isWin,
      'opponentName': opponentName,
      'mode': mode,
      'playedAt': playedAt.toIso8601String(),
      if (isForfeitWin) 'isForfeitWin': true,
      if (score != null) 'score': score,
      if (ratingAfter != null) 'ratingAfter': ratingAfter,
      if (ratingDelta != null) 'ratingDelta': ratingDelta,
    };
  }

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MatchHistoryEntry(
      isWin: json['isWin'] == true,
      opponentName: json['opponentName']?.toString() ?? 'UNKNOWN',
      mode: json['mode']?.toString() ?? 'MATCH',
      playedAt: DateTime.tryParse(json['playedAt']?.toString() ?? '') ??
          DateTime.now(),
      isForfeitWin: json['isForfeitWin'] == true,
      score: _intValue(json['score']),
      ratingAfter: _intValue(json['ratingAfter']),
      ratingDelta: _intValue(json['ratingDelta']),
    );
  }

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }
}

class PlayerDataManager {
  PlayerDataManager._internal();

  static final PlayerDataManager instance = PlayerDataManager._internal();
  static const bool _debugControlsEnabled = AppReviewConfig.debugMenuEnabled;

  static const int initialCoins = 10000;
  static const String _coinsKey = 'player_coins';
  static const String _expKey = 'player_exp';
  static const String _gachaTicketsKey = 'player_gacha_tickets';
  static const String _cyberScrapKey = 'player_cyber_scrap';
  static const String _itemsKey = 'player_owned_items_json';
  static const String _lastDailyResetKey = 'player_last_daily_reset';
  static const String _currentMissionsKey = 'player_current_missions_json';
  static const String _dailyShopItemsKey = 'player_daily_shop_items_json';
  static const String _loginStreakKey = 'player_login_streak';
  static const String _lastLoginDateKey = 'player_last_login_date';
  static const String _playerNameKey = 'player_name';
  static const String _playerIdKey = 'player_public_id';
  static const String _equippedBadgeIdsKey = 'player_equipped_badge_ids_json';
  static const String _currentRatingKey = 'player_current_rating';
  static const String _equippedBallSkinIdKey = 'player_equipped_ball_skin_id';
  static const String _equippedPlayerIconIdKey =
      'player_equipped_player_icon_id';
  static const String _highestRatingKey = 'player_highest_rating';
  static const String _maxArenaWinsKey = 'player_max_arena_wins';
  static const String _arenaChallengeCountKey = 'player_arena_challenge_count';
  static const String _accountCreatedAtKey = 'player_account_created_at';
  static const String _totalMatchesKey = 'player_total_matches';
  static const String _totalWinsKey = 'player_total_wins';
  static const String _totalLossesKey = 'player_total_losses';
  static const String _totalClearedBallsKey = 'player_total_cleared_balls';
  static const String _totalNormalClearedBallsKey =
      'player_total_normal_cleared_balls';
  static const String _maxChainKey = 'player_max_chain';
  static const String _highestEndlessScoreKey = 'player_highest_endless_score';
  static const String _rankedWinsKey = 'player_ranked_wins';
  static const String _rankedCurrentWinStreakKey =
      'player_ranked_current_win_streak';
  static const String _rankedMaxWinStreakKey = 'player_ranked_max_win_streak';
  static const String _arenaPerfectClearCountKey =
      'player_arena_perfect_clear_count';
  static const String _recordResetVersionKey = 'player_record_reset_version';
  static const String _wazaCountsKey = 'player_waza_counts_json';
  static const String _matchHistoryKey = 'player_match_history_json';
  static const String _modePlayCountsKey = 'player_mode_play_counts_json';
  static const String _inventoryRevisionKey = 'player_inventory_revision';
  static const String _pendingLevelUpRewardLogKey =
      'player_pending_level_up_reward_log';
  static const String _pendingLoginBonusLogKey =
      'player_pending_login_bonus_log';
  static const int _currentInventoryRevision = 2;
  static const int _currentRecordResetVersion = 1;
  static const int _debugBuildCoins = 1000000;

  final Random _random = Random();
  bool _loaded = false;
  bool _debugMissionsResetApplied = false;
  int _coins = initialCoins;
  int _exp = 0;
  int _gachaTickets = 0;
  int _cyberScrap = 0;
  List<GameItem> _ownedItems = [];
  String _lastDailyReset = '';
  List<Map<String, dynamic>> _currentMissions = [];
  List<String> _dailyShopItems = [];
  int _loginStreak = 0;
  String _lastLoginDate = '';
  String _playerName = '';
  String _playerId = '';
  List<String> _equippedBadgeIds = [];
  int _currentRating = 1000;
  String _equippedBallSkinId = 'default';
  String _equippedPlayerIconId = 'default';
  int _highestRating = 1000;
  int _maxArenaWins = 0;
  int _arenaChallengeCount = 0;
  DateTime _accountCreatedAt = DateTime.now();
  int _totalMatches = 0;
  int _totalWins = 0;
  int _totalLosses = 0;
  int _totalClearedBalls = 0;
  int _totalNormalClearedBalls = 0;
  int _maxChain = 0;
  int _highestEndlessScore = 0;
  int _rankedWins = 0;
  int _rankedCurrentWinStreak = 0;
  int _rankedMaxWinStreak = 0;
  int _arenaPerfectClearCount = 0;
  Map<String, int> _wazaCounts = {
    'straight': 0,
    'pyramid': 0,
    'hexagon': 0,
  };
  List<MatchHistoryEntry> _matchHistory = [];
  Map<String, int> _modePlayCounts = {
    'RANKED': 0,
    'ARENA': 0,
    'CPU': 0,
    'SOLO': 0,
    'FRIEND': 0,
  };

  int get coins => _coins;
  int get exp => _exp;
  int get level => _levelFromExp(_exp);
  int get currentLevelExp => _expIntoCurrentLevel(_exp);
  int get nextLevelRequiredExp => getRequiredExp(level);
  int get remainingExpToNextLevel =>
      max(0, nextLevelRequiredExp - currentLevelExp);
  int get gachaTickets => _gachaTickets;
  int get cyberScrap => _cyberScrap;
  List<GameItem> get ownedItems => List.unmodifiable(_ownedItems);
  String get lastDailyReset => _lastDailyReset;
  List<Map<String, dynamic>> get currentMissions => _currentMissions
      .map((mission) => Map<String, dynamic>.from(mission))
      .toList();
  List<String> get dailyShopItems => List.unmodifiable(_dailyShopItems);
  int get loginStreak => _loginStreak;
  String get playerName => _playerName;
  String get displayPlayerName =>
      _playerName.trim().isEmpty ? 'プレイヤー' : _playerName.trim();
  String get playerId => _playerId;
  List<String> get equippedBadgeIds => List.unmodifiable(_equippedBadgeIds);
  int get currentRating => _currentRating;
  String get equippedBallSkinId => _equippedBallSkinId;
  String get equippedPlayerIconId => _equippedPlayerIconId;
  int get highestRating => _highestRating;
  int get maxArenaWins => _maxArenaWins;
  int get arenaChallengeCount => _arenaChallengeCount;
  DateTime get accountCreatedAt => _accountCreatedAt;
  Duration get accountAge => DateTime.now().difference(_accountCreatedAt);
  int get totalMatches => _totalMatches;
  int get totalWins => _totalWins;
  int get totalLosses => _totalLosses;
  int get totalClearedBalls => _totalClearedBalls;
  int get totalNormalClearedBalls => _totalNormalClearedBalls;
  int get maxChain => _maxChain;
  int get highestEndlessScore => _highestEndlessScore;
  int get rankedWins => _rankedWins;
  int get rankedCurrentWinStreak => _rankedCurrentWinStreak;
  int get rankedMaxWinStreak => _rankedMaxWinStreak;
  int get arenaPerfectClearCount => _arenaPerfectClearCount;
  Map<String, int> get wazaCounts => Map.unmodifiable(_wazaCounts);
  List<MatchHistoryEntry> get matchHistory => List.unmodifiable(_matchHistory);
  Map<String, int> get modePlayCounts => Map.unmodifiable(_modePlayCounts);
  List<String> get unlockedBadgeIds => BadgeCatalog.allBadges
      .where(
        (badge) => badge.unlockedCondition.isUnlocked(
          highestRating: _highestRating,
          maxArenaWins: _maxArenaWins,
          accountAge: accountAge,
          totalWins: _totalWins,
          wazaCounts: _wazaCounts,
        ),
      )
      .map((badge) => badge.id)
      .toList();

  Future<List<GameItem>> getOwnedItems() async {
    await load();
    return ownedItems;
  }

  Future<void> saveOwnedItems(List<GameItem> items) async {
    await load();
    _ownedItems = List<GameItem>.from(items);
    await _saveItems();
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    await AuthManager.instance.ensureSignedIn();
    final prefs = await SharedPreferences.getInstance();
    final inventoryRevision = prefs.getInt(_inventoryRevisionKey) ?? 0;
    _coins = prefs.getInt(_coinsKey) ?? initialCoins;
    _exp = prefs.getInt(_expKey) ?? 0;
    _gachaTickets = prefs.getInt(_gachaTicketsKey) ?? 0;
    _cyberScrap = prefs.getInt(_cyberScrapKey) ?? 0;
    _lastDailyReset = prefs.getString(_lastDailyResetKey) ?? '';

    final rawItems = prefs.getString(_itemsKey);
    if (rawItems != null && rawItems.isNotEmpty) {
      final decoded = jsonDecode(rawItems);
      if (decoded is List) {
        _ownedItems = decoded
            .whereType<Map>()
            .map((item) => GameItem.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.id.isNotEmpty)
            .toList();
      }
    }
    _ownedItems = _ownedItems.map(_canonicalItem).toList();

    final rawMissions = prefs.getString(_currentMissionsKey);
    if (rawMissions != null && rawMissions.isNotEmpty) {
      final decoded = jsonDecode(rawMissions);
      if (decoded is List) {
        _currentMissions = decoded
            .whereType<Map>()
            .map((mission) => Map<String, dynamic>.from(mission))
            .toList();
      }
    }

    final rawDailyShopItems = prefs.getString(_dailyShopItemsKey);
    if (rawDailyShopItems != null && rawDailyShopItems.isNotEmpty) {
      final decoded = jsonDecode(rawDailyShopItems);
      if (decoded is List) {
        _dailyShopItems = decoded.map((item) => '$item').toList();
      }
    }
    _loginStreak = max(0, prefs.getInt(_loginStreakKey) ?? 0);
    _lastLoginDate = prefs.getString(_lastLoginDateKey) ?? '';

    var shouldSaveProfile = false;
    var shouldSaveStats = false;
    _playerName = prefs.getString(_playerNameKey) ?? '';
    final savedPlayerId = prefs.getString(_playerIdKey) ?? '';
    if (savedPlayerId.trim().isEmpty || savedPlayerId.length > 10) {
      _playerId = _generatePublicPlayerId();
      shouldSaveProfile = true;
    } else {
      _playerId = savedPlayerId;
    }
    if (savedPlayerId != _playerId) {
      shouldSaveProfile = true;
    }
    _equippedBadgeIds = _stringListFromJson(
      prefs.getString(_equippedBadgeIdsKey),
    ).take(2).toList();
    _currentRating = prefs.getInt(_currentRatingKey) ?? 1000;
    _highestRating = max(
      prefs.getInt(_highestRatingKey) ?? _currentRating,
      _currentRating,
    );
    _equippedBallSkinId = prefs.getString(_equippedBallSkinIdKey) ?? 'default';
    _equippedPlayerIconId =
        prefs.getString(_equippedPlayerIconIdKey) ?? 'default';

    final createdAtRaw = prefs.getString(_accountCreatedAtKey);
    final parsedCreatedAt = DateTime.tryParse(createdAtRaw ?? '');
    if (parsedCreatedAt == null) {
      _accountCreatedAt = DateTime.now();
      shouldSaveStats = true;
    } else {
      _accountCreatedAt = parsedCreatedAt;
    }
    _maxArenaWins = prefs.getInt(_maxArenaWinsKey) ?? 0;
    _arenaChallengeCount = prefs.getInt(_arenaChallengeCountKey) ?? 0;
    _totalMatches = prefs.getInt(_totalMatchesKey) ?? 0;
    _totalWins = prefs.getInt(_totalWinsKey) ?? 0;
    _totalLosses = prefs.getInt(_totalLossesKey) ?? 0;
    _totalClearedBalls = prefs.getInt(_totalClearedBallsKey) ?? 0;
    _totalNormalClearedBalls = prefs.getInt(_totalNormalClearedBallsKey) ?? 0;
    _maxChain = prefs.getInt(_maxChainKey) ?? 0;
    _highestEndlessScore = prefs.getInt(_highestEndlessScoreKey) ?? 0;
    _rankedWins = prefs.getInt(_rankedWinsKey) ?? 0;
    _rankedCurrentWinStreak = prefs.getInt(_rankedCurrentWinStreakKey) ?? 0;
    _rankedMaxWinStreak = prefs.getInt(_rankedMaxWinStreakKey) ?? 0;
    _arenaPerfectClearCount = prefs.getInt(_arenaPerfectClearCountKey) ?? 0;
    _wazaCounts = {
      'straight': 0,
      'pyramid': 0,
      'hexagon': 0,
      ..._intMapFromJson(prefs.getString(_wazaCountsKey)),
    };
    _matchHistory = _historyFromJson(prefs.getString(_matchHistoryKey));
    _modePlayCounts = {
      'RANKED': 0,
      'ARENA': 0,
      'CPU': 0,
      'SOLO': 0,
      'FRIEND': 0,
      ..._intMapFromJson(prefs.getString(_modePlayCountsKey)),
    };

    if ((prefs.getInt(_recordResetVersionKey) ?? 0) <
        _currentRecordResetVersion) {
      _resetRecordsForRebuild();
      await prefs.setInt(_recordResetVersionKey, _currentRecordResetVersion);
      shouldSaveProfile = true;
      shouldSaveStats = true;
    }

    _loaded = true;

    _equippedBadgeIds = _equippedBadgeIds
        .where((id) => unlockedBadgeIds.contains(id))
        .take(2)
        .toList();
    var shouldSaveItems = false;
    if (inventoryRevision < _currentInventoryRevision) {
      shouldSaveItems = _applyInventoryMigration(inventoryRevision);
      shouldSaveProfile = true;
    }
    if (!_ownsEquippableItem(_equippedBallSkinId, ItemType.skin)) {
      _equippedBallSkinId = 'default';
      shouldSaveProfile = true;
    }
    if (!_ownsEquippableItem(_equippedPlayerIconId, ItemType.icon)) {
      _equippedPlayerIconId = 'default';
      shouldSaveProfile = true;
    }

    if (_debugControlsEnabled && _coins != _debugBuildCoins) {
      _coins = _debugBuildCoins;
      await _saveEconomy();
    }
    if (shouldSaveItems || inventoryRevision < _currentInventoryRevision) {
      await _saveItems();
      await prefs.setInt(_inventoryRevisionKey, _currentInventoryRevision);
    }
    if (shouldSaveProfile) {
      await _savePublicProfile();
    }
    if (shouldSaveStats) {
      await _saveStats();
    }
  }

  Future<void> checkDailyReset() async {
    await load();
    final today = _todayKey();
    var changed = false;

    if (await _updateLoginStreak(today)) {
      changed = true;
    }

    final missionIds = _currentMissions
        .map((mission) => mission['id']?.toString() ?? '')
        .toSet();
    final hasRequiredRewardedMissions =
        MissionCatalog.rewardedAdMissionIds.every(missionIds.contains);

    if (_lastDailyReset != today ||
        _currentMissions.length != 4 ||
        !hasRequiredRewardedMissions ||
        _dailyShopItems.length != 3) {
      _lastDailyReset = today;
      _currentMissions = _generateDailyMissions();
      _dailyShopItems = _generateDailyShopItems();
      changed = true;
    }

    if (_applyDebugBuildMissionReset()) {
      changed = true;
    }

    if (changed) {
      await _saveDailyData();
    }
  }

  Future<void> spendCoins(int amount) async {
    await load();
    if (_coins < amount) {
      throw StateError('不足しています。必要: $amount / 所持: $_coins');
    }
    _coins -= amount;
    await _saveEconomy();
  }

  Future<void> addCoins(int amount) async {
    await load();
    _coins += amount;
    await _saveEconomy();
  }

  Future<void> setCoinsForDebug(int amount) async {
    if (!_debugControlsEnabled) {
      return;
    }
    await load();
    _coins = max(0, amount);
    await _saveEconomy();
  }

  int getRequiredExp(int currentLevel) {
    final normalizedLevel = max(1, currentLevel);
    return 1000 + (pow(normalizedLevel - 1, 1.5) * 1000).toInt();
  }

  Future<void> addExp(int amount) async {
    await load();
    if (amount <= 0) {
      return;
    }

    final previousLevel = level;
    _exp += amount;
    final currentLevel = level;
    await _saveEconomy();

    if (currentLevel <= previousLevel) {
      return;
    }

    var totalRewardCoins = 0;
    for (var reachedLevel = previousLevel + 1;
        reachedLevel <= currentLevel;
        reachedLevel++) {
      totalRewardCoins += reachedLevel * 500;
    }
    await addCoins(totalRewardCoins);
    await _storePendingLevelUpRewardLog(
      previousLevel: previousLevel,
      currentLevel: currentLevel,
      rewardCoins: totalRewardCoins,
    );
  }

  Future<void> adjustExpForDebug(int delta) async {
    if (!_debugControlsEnabled) {
      return;
    }
    await load();
    _exp = max(0, _exp + delta);
    await _saveEconomy();
  }

  Future<int> levelUpReward() async {
    await load();
    final reward = level * 500;
    _coins += reward;
    await _saveEconomy();
    return reward;
  }

  Future<void> addGachaTickets(int amount) async {
    await load();
    _gachaTickets += amount;
    await _saveEconomy();
  }

  Future<void> addCyberScrap(int amount) async {
    await load();
    _cyberScrap += amount;
    await _saveEconomy();
  }

  Future<ItemGrantResult> addOrUpgradeItem(GameItem item) async {
    await load();

    final existingIndex = _ownedItems.indexWhere(
      (ownedItem) => ownedItem.id == item.id,
    );

    if (existingIndex == -1) {
      final storedItem = item.isStamp ? item.copyWith(level: 1) : item;
      _ownedItems.add(storedItem);
      await _saveItems();
      return ItemGrantResult(
        item: storedItem,
        isDuplicate: false,
        leveledUp: false,
        convertedToScrap: false,
        cyberScrapAdded: 0,
      );
    }

    final existing = _ownedItems[existingIndex];
    if (existing.isStamp && !existing.isMaxLevel) {
      final upgraded = existing.copyWith(level: existing.level + 1);
      _ownedItems[existingIndex] = upgraded;
      await _saveItems();
      return ItemGrantResult(
        item: upgraded,
        isDuplicate: true,
        leveledUp: true,
        convertedToScrap: false,
        cyberScrapAdded: 0,
      );
    }

    await _saveItems();
    return ItemGrantResult(
      item: existing,
      isDuplicate: true,
      leveledUp: false,
      convertedToScrap: false,
      cyberScrapAdded: 0,
    );
  }

  Future<void> saveCurrentMissions(List<Map<String, dynamic>> missions) async {
    await load();
    _currentMissions =
        missions.map((mission) => Map<String, dynamic>.from(mission)).toList();
    await _saveDailyData();
  }

  Future<void> saveDailyShopItems(List<String> itemIds) async {
    await load();
    _dailyShopItems = List<String>.from(itemIds);
    await _saveDailyData();
  }

  Future<void> setPlayerName(String name) async {
    await load();
    _playerName = ModerationManager.instance.sanitizePlayerName(name);
    await _savePublicProfile();
  }

  Future<void> setCurrentRating(int rating) async {
    await load();
    _currentRating = rating;
    _highestRating = max(_highestRating, rating);
    await _savePublicProfile();
    await _saveStats();
  }

  Future<void> setEquippedBadgeIds(List<String> badgeIds) async {
    await load();
    final unlocked = unlockedBadgeIds.toSet();
    _equippedBadgeIds =
        badgeIds.where((id) => unlocked.contains(id)).toSet().take(2).toList();
    await _savePublicProfile();
  }

  Future<void> setEquippedBallSkinId(String skinId) async {
    await load();
    final normalized = skinId.trim().isEmpty ? 'default' : skinId.trim();
    if (!_ownsEquippableItem(normalized, ItemType.skin)) {
      return;
    }
    _equippedBallSkinId = normalized;
    await _savePublicProfile();
  }

  Future<void> setEquippedPlayerIconId(String iconId) async {
    await load();
    final normalized = iconId.trim().isEmpty ? 'default' : iconId.trim();
    if (!_ownsEquippableItem(normalized, ItemType.icon)) {
      return;
    }
    _equippedPlayerIconId = normalized;
    await _savePublicProfile();
  }

  Future<void> recordArenaChallengeStarted() async {
    await load();
    _arenaChallengeCount++;
    await _saveStats();
  }

  Future<void> updateMaxArenaWins(int wins) async {
    await load();
    _maxArenaWins = max(_maxArenaWins, wins);
    await _saveStats();
  }

  Future<void> recordArenaPerfectClear() async {
    await load();
    _arenaPerfectClearCount++;
    await _saveStats();
  }

  Future<void> resetRecordsForRebuild() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    _resetRecordsForRebuild();
    await prefs.setInt(_recordResetVersionKey, _currentRecordResetVersion);
    await _savePublicProfile();
    await _saveStats();
  }

  void _resetRecordsForRebuild() {
    _currentRating = 1000;
    _highestRating = 1000;
    _maxArenaWins = 0;
    _arenaChallengeCount = 0;
    _totalMatches = 0;
    _totalWins = 0;
    _totalLosses = 0;
    _totalClearedBalls = 0;
    _totalNormalClearedBalls = 0;
    _maxChain = 0;
    _highestEndlessScore = 0;
    _rankedWins = 0;
    _rankedCurrentWinStreak = 0;
    _rankedMaxWinStreak = 0;
    _arenaPerfectClearCount = 0;
    _wazaCounts = {
      'straight': 0,
      'pyramid': 0,
      'hexagon': 0,
    };
    _matchHistory = [];
    _modePlayCounts = {
      'RANKED': 0,
      'ARENA': 0,
      'CPU': 0,
      'SOLO': 0,
      'FRIEND': 0,
    };
  }

  Future<void> recordMatchResult({
    required bool isWin,
    required String mode,
    required String opponentName,
    required Map<String, int> wazaCounts,
    int clearedBalls = 0,
    int normalClearedBalls = 0,
    int maxChain = 0,
    bool isForfeitWin = false,
    int? score,
    int? ratingAfter,
    int? ratingDelta,
  }) async {
    await load();
    _totalMatches++;
    if (isWin) {
      _totalWins++;
    } else {
      _totalLosses++;
    }
    _totalClearedBalls += max(0, clearedBalls);
    _totalNormalClearedBalls += max(0, normalClearedBalls);
    _maxChain = max(_maxChain, maxChain);
    if (mode == 'SOLO' && score != null) {
      _highestEndlessScore = max(_highestEndlessScore, score);
    }
    if (mode == 'RANKED') {
      if (isWin) {
        _rankedWins++;
        _rankedCurrentWinStreak++;
        _rankedMaxWinStreak = max(_rankedMaxWinStreak, _rankedCurrentWinStreak);
      } else {
        _rankedCurrentWinStreak = 0;
      }
    }
    _modePlayCounts[mode] = (_modePlayCounts[mode] ?? 0) + 1;
    for (final entry in wazaCounts.entries) {
      _wazaCounts[entry.key] = (_wazaCounts[entry.key] ?? 0) + entry.value;
    }
    if (ratingAfter != null) {
      _currentRating = ratingAfter;
      _highestRating = max(_highestRating, ratingAfter);
    }
    _matchHistory = [
      MatchHistoryEntry(
        isWin: isWin,
        opponentName: opponentName.trim().isEmpty ? 'UNKNOWN' : opponentName,
        mode: mode,
        playedAt: DateTime.now(),
        isForfeitWin: isForfeitWin,
        score: score,
        ratingAfter: ratingAfter,
        ratingDelta: ratingDelta,
      ),
      ..._matchHistory,
    ].take(30).toList();
    await _savePublicProfile();
    await _saveStats();
  }

  Future<void> updateLatestRankedHistory({
    required int ratingAfter,
    required int ratingDelta,
  }) async {
    await load();
    final index = _matchHistory.indexWhere((entry) => entry.mode == 'RANKED');
    if (index == -1) {
      return;
    }
    final target = _matchHistory[index];
    _matchHistory[index] = MatchHistoryEntry(
      isWin: target.isWin,
      opponentName: target.opponentName,
      mode: target.mode,
      playedAt: target.playedAt,
      isForfeitWin: target.isForfeitWin,
      score: target.score,
      ratingAfter: ratingAfter,
      ratingDelta: ratingDelta,
    );
    _currentRating = ratingAfter;
    _highestRating = max(_highestRating, ratingAfter);
    await _savePublicProfile();
    await _saveStats();
  }

  Future<void> _saveEconomy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_coinsKey, _coins);
    await prefs.setInt(_expKey, _exp);
    await prefs.setInt(_gachaTicketsKey, _gachaTickets);
    await prefs.setInt(_cyberScrapKey, _cyberScrap);
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _itemsKey,
      jsonEncode(_ownedItems.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _savePublicProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playerNameKey, _playerName);
    await prefs.setString(_playerIdKey, _playerId);
    await prefs.setString(_equippedBadgeIdsKey, jsonEncode(_equippedBadgeIds));
    await prefs.setInt(_currentRatingKey, _currentRating);
    await prefs.setString(_equippedBallSkinIdKey, _equippedBallSkinId);
    await prefs.setString(_equippedPlayerIconIdKey, _equippedPlayerIconId);
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_highestRatingKey, _highestRating);
    await prefs.setInt(_maxArenaWinsKey, _maxArenaWins);
    await prefs.setInt(_arenaChallengeCountKey, _arenaChallengeCount);
    await prefs.setString(
      _accountCreatedAtKey,
      _accountCreatedAt.toIso8601String(),
    );
    await prefs.setInt(_totalMatchesKey, _totalMatches);
    await prefs.setInt(_totalWinsKey, _totalWins);
    await prefs.setInt(_totalLossesKey, _totalLosses);
    await prefs.setInt(_totalClearedBallsKey, _totalClearedBalls);
    await prefs.setInt(_totalNormalClearedBallsKey, _totalNormalClearedBalls);
    await prefs.setInt(_maxChainKey, _maxChain);
    await prefs.setInt(_highestEndlessScoreKey, _highestEndlessScore);
    await prefs.setInt(_rankedWinsKey, _rankedWins);
    await prefs.setInt(_rankedCurrentWinStreakKey, _rankedCurrentWinStreak);
    await prefs.setInt(_rankedMaxWinStreakKey, _rankedMaxWinStreak);
    await prefs.setInt(_arenaPerfectClearCountKey, _arenaPerfectClearCount);
    await prefs.setString(_wazaCountsKey, jsonEncode(_wazaCounts));
    await prefs.setString(_modePlayCountsKey, jsonEncode(_modePlayCounts));
    await prefs.setString(
      _matchHistoryKey,
      jsonEncode(_matchHistory.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> _saveDailyData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDailyResetKey, _lastDailyReset);
    await prefs.setString(
      _currentMissionsKey,
      jsonEncode(_currentMissions),
    );
    await prefs.setString(
      _dailyShopItemsKey,
      jsonEncode(_dailyShopItems),
    );
    await prefs.setInt(_loginStreakKey, _loginStreak);
    await prefs.setString(_lastLoginDateKey, _lastLoginDate);
  }

  Future<String?> consumePendingLevelUpRewardLog() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    final message = prefs.getString(_pendingLevelUpRewardLogKey);
    if (message == null || message.isEmpty) {
      return null;
    }
    await prefs.remove(_pendingLevelUpRewardLogKey);
    return message;
  }

  Future<String?> consumePendingLoginBonusLog() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    final message = prefs.getString(_pendingLoginBonusLogKey);
    if (message == null || message.isEmpty) {
      return null;
    }
    await prefs.remove(_pendingLoginBonusLogKey);
    return message;
  }

  List<Map<String, dynamic>> _generateDailyMissions() {
    final rewardedMission = MissionCatalog.dailyPool.firstWhere(
      (mission) => mission.id == MissionCatalog.rewardedAdMissionIds.first,
    );
    final pool = MissionCatalog.dailyPool
        .where((mission) => !MissionCatalog.isRewardedAdMissionId(mission.id))
        .toList()
      ..shuffle(_random);
    return [
      rewardedMission.toMissionMap(),
      ...pool.take(3).map((mission) => mission.toMissionMap()),
    ];
  }

  List<String> _generateDailyShopItems() {
    final pool = List<GameItem>.from(GameItemCatalog.shopDirectPurchasePool)
      ..shuffle(_random);
    return pool.take(3).map((item) => item.id).toList();
  }

  bool _applyInventoryMigration(int revision) {
    var changed = false;
    if (revision < 1) {
      final filteredItems =
          _ownedItems.where((item) => !item.isStamp && !item.isIcon).toList();
      if (filteredItems.length != _ownedItems.length) {
        _ownedItems = filteredItems;
        changed = true;
      }
      if (_equippedPlayerIconId != 'default') {
        _equippedPlayerIconId = 'default';
      }
    }
    if (revision < 2) {
      for (final stamp in GameItemCatalog.defaultStamps) {
        if (_ownedItems.every((item) => item.id != stamp.id)) {
          _ownedItems.add(stamp.copyWith(level: 1));
          changed = true;
        }
      }
    }
    return changed;
  }

  GameItem _canonicalItem(GameItem item) {
    final catalogItem = GameItemCatalog.byId(item.id);
    if (catalogItem == null) {
      return item;
    }
    return catalogItem.copyWith(level: item.level);
  }

  String _generatePublicPlayerId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  bool _applyDebugBuildMissionReset() {
    if (!_debugControlsEnabled ||
        _debugMissionsResetApplied ||
        _currentMissions.isEmpty) {
      return false;
    }

    _debugMissionsResetApplied = true;
    for (final mission in _currentMissions) {
      mission['progress'] = 0;
      mission['claimed'] = false;
      mission['allClearBonusClaimed'] = false;
    }
    return true;
  }

  Future<void> _storePendingLevelUpRewardLog({
    required int previousLevel,
    required int currentLevel,
    required int rewardCoins,
  }) async {
    if (currentLevel <= previousLevel || rewardCoins <= 0) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final message = currentLevel == previousLevel + 1
        ? 'Lv.$previousLevel → Lv.$currentLevel\nレベルアップ報酬として $rewardCoins を獲得しました。'
        : 'Lv.$previousLevel → Lv.$currentLevel\nレベルアップ報酬として合計 $rewardCoins を獲得しました。';
    await prefs.setString(_pendingLevelUpRewardLogKey, message);
  }

  Future<bool> _updateLoginStreak(String today) async {
    if (_lastLoginDate == today) {
      return false;
    }

    final previousDate = _parseDateKey(_lastLoginDate);
    final currentDate = _parseDateKey(today);
    if (currentDate == null) {
      return false;
    }

    if (previousDate == null) {
      _loginStreak = 1;
    } else {
      final difference = currentDate.difference(previousDate).inDays;
      if (difference == 1) {
        _loginStreak += 1;
      } else {
        _loginStreak = 1;
      }
    }
    _lastLoginDate = today;

    if (_loginStreak > 0 && _loginStreak % 7 == 0) {
      await addCoins(5000);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pendingLoginBonusLogKey,
        '連続ログイン$_loginStreak日達成！\n5000を獲得しました。',
      );
    }
    return true;
  }

  int _levelFromExp(int value) {
    var currentLevel = 1;
    var remainingExp = max(0, value);

    while (remainingExp >= getRequiredExp(currentLevel)) {
      remainingExp -= getRequiredExp(currentLevel);
      currentLevel++;
    }

    return currentLevel;
  }

  int _expIntoCurrentLevel(int value) {
    var currentLevel = 1;
    var remainingExp = max(0, value);

    while (remainingExp >= getRequiredExp(currentLevel)) {
      remainingExp -= getRequiredExp(currentLevel);
      currentLevel++;
    }

    return remainingExp;
  }

  String _todayKey() {
    return DateTime.now().toLocal().toIso8601String().split('T').first;
  }

  DateTime? _parseDateKey(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  List<String> _stringListFromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => '$item').toList();
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  Map<String, int> _intMapFromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            entry.key.toString(): _intValue(entry.value) ?? 0,
        };
      }
    } catch (_) {
      return {};
    }
    return {};
  }

  List<MatchHistoryEntry> _historyFromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (entry) => MatchHistoryEntry.fromJson(
                Map<String, dynamic>.from(entry),
              ),
            )
            .take(30)
            .toList();
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  bool _ownsEquippableItem(String id, ItemType type) {
    if (id == 'default') {
      return true;
    }
    return _ownedItems.any((item) => item.id == id && item.type == type);
  }
}
