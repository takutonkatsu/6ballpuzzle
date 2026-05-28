import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../app_settings.dart';
import '../game/mission_catalog.dart';
import '../moderation/moderation_manager.dart';
import 'models/badge_item.dart';
import 'models/game_item.dart';
import '../app_review_config.dart';
import '../firebase_database_provider.dart';

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
    this.opponentUid = '',
    this.opponentPublicId = '',
    this.isForfeitWin = false,
    this.wazaCounts = const {},
    this.clearedBalls = 0,
    this.normalClearedBalls = 0,
    this.maxChain = 0,
    this.hasStyleMetrics = false,
    this.score,
    this.ratingAfter,
    this.ratingDelta,
  });

  final bool isWin;
  final String opponentName;
  final String mode;
  final DateTime playedAt;
  final String opponentUid;
  final String opponentPublicId;
  final bool isForfeitWin;
  final Map<String, int> wazaCounts;
  final int clearedBalls;
  final int normalClearedBalls;
  final int maxChain;
  final bool hasStyleMetrics;
  final int? score;
  final int? ratingAfter;
  final int? ratingDelta;

  Map<String, dynamic> toJson() {
    return {
      'isWin': isWin,
      'opponentName': opponentName,
      'mode': mode,
      'playedAt': playedAt.toIso8601String(),
      if (opponentUid.isNotEmpty) 'opponentUid': opponentUid,
      if (opponentPublicId.isNotEmpty) 'opponentPublicId': opponentPublicId,
      if (isForfeitWin) 'isForfeitWin': true,
      if (hasStyleMetrics) ...{
        'wazaCounts': wazaCounts,
        'clearedBalls': clearedBalls,
        'normalClearedBalls': normalClearedBalls,
        'maxChain': maxChain,
      },
      if (score != null) 'score': score,
      if (ratingAfter != null) 'ratingAfter': ratingAfter,
      if (ratingDelta != null) 'ratingDelta': ratingDelta,
    };
  }

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    final wazaCounts = _intMapValue(json['wazaCounts']);
    final hasStyleMetrics = json.containsKey('wazaCounts') ||
        json.containsKey('clearedBalls') ||
        json.containsKey('normalClearedBalls') ||
        json.containsKey('maxChain');
    return MatchHistoryEntry(
      isWin: json['isWin'] == true,
      opponentName: json['opponentName']?.toString() ?? 'UNKNOWN',
      mode: json['mode']?.toString() ?? 'MATCH',
      playedAt: DateTime.tryParse(json['playedAt']?.toString() ?? '') ??
          DateTime.now(),
      opponentUid: json['opponentUid']?.toString() ?? '',
      opponentPublicId: json['opponentPublicId']?.toString() ?? '',
      isForfeitWin: json['isForfeitWin'] == true,
      wazaCounts: wazaCounts,
      clearedBalls: _intValue(json['clearedBalls']) ?? 0,
      normalClearedBalls: _intValue(json['normalClearedBalls']) ?? 0,
      maxChain: _intValue(json['maxChain']) ?? 0,
      hasStyleMetrics: hasStyleMetrics,
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

  static Map<String, int> _intMapValue(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        entry.key.toString(): _intValue(entry.value) ?? 0,
    };
  }
}

class PlayerDataManager {
  PlayerDataManager._internal();

  static final PlayerDataManager instance = PlayerDataManager._internal();
  static const bool _debugControlsEnabled = AppReviewConfig.debugMenuEnabled;

  static const int initialCoins = 10000;
  static const int maxEndlessScore = 99999999;
  static const String _coinsKey = 'player_coins';
  static const String _expKey = 'player_exp';
  static const String _gachaTicketsKey = 'player_gacha_tickets';
  static const String _cyberScrapKey = 'player_cyber_scrap';
  static const String _itemsKey = 'player_owned_items_json';
  static const String _lastDailyResetKey = 'player_last_daily_reset';
  static const String _currentMissionsKey = 'player_current_missions_json';
  static const String _dailyShopItemsKey = 'player_daily_shop_items_json';
  static const String _unseenCollectionItemIdsKey =
      'player_unseen_collection_item_ids_json';
  static const String _loginStreakKey = 'player_login_streak';
  static const String _totalLoginDaysKey = 'player_total_login_days';
  static const String _lastLoginDateKey = 'player_last_login_date';
  static const String _lastLoginBonusStreakKey =
      'player_last_login_bonus_streak';
  static const String _playerNameKey = 'player_name';
  static const String _playerIdKey = 'player_public_id';
  static const String _equippedBadgeIdsKey = 'player_equipped_badge_ids_json';
  static const String _equippedStampIdsKey = 'player_equipped_stamp_ids_json';
  static const String _seasonRankBadgesKey = 'player_season_rank_badges_json';
  static const String _rankedSeasonIdKey = 'player_ranked_season_id';
  static const String _seasonRankedWinsKey = 'player_season_ranked_wins';
  static const String _seasonRankedLossesKey = 'player_season_ranked_losses';
  static const String _pendingRankedSeasonResultLogKey =
      'player_pending_ranked_season_result_log';
  static const String _currentRatingKey = 'player_current_rating';
  static const String _equippedBallSkinIdKey = 'player_equipped_ball_skin_id';
  static const String _equippedPlayerIconIdKey =
      'player_equipped_player_icon_id';
  static const String _equippedIconFrameIdKey = 'player_equipped_icon_frame_id';
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
  static const String _totalChainKey = 'player_total_chain';
  static const String _highestEndlessScoreKey = 'player_highest_endless_score';
  static const String _rankedWinsKey = 'player_ranked_wins';
  static const String _rankedCurrentWinStreakKey =
      'player_ranked_current_win_streak';
  static const String _rankedMaxWinStreakKey = 'player_ranked_max_win_streak';
  static const String _bestRankedRankKey = 'player_best_ranked_rank';
  static const String _dailyWinRankPlacementsKey =
      'player_daily_win_rank_placements_json';
  static const String _dailyWinRankPlacementLastKey =
      'player_daily_win_rank_placement_last';
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
  static const String _todayStatsDateKey = 'player_today_stats_date';
  static const String _todayTotalMatchesKey = 'player_today_total_matches';
  static const String _todayTotalWinsKey = 'player_today_total_wins';
  static const String _todayTotalLossesKey = 'player_today_total_losses';
  static const String _todayClearedBallsKey = 'player_today_cleared_balls';
  static const String _todayNormalClearedBallsKey =
      'player_today_normal_cleared_balls';
  static const String _todayMaxChainKey = 'player_today_max_chain';
  static const String _todayHighestEndlessScoreKey =
      'player_today_highest_endless_score';
  static const String _todayRankedMatchesKey = 'player_today_ranked_matches';
  static const String _todayRankedWinsKey = 'player_today_ranked_wins';
  static const String _todayRankedLossesKey = 'player_today_ranked_losses';
  static const String _todayRankedRatingStartKey =
      'player_today_ranked_rating_start';
  static const String _todayRankedRatingCurrentKey =
      'player_today_ranked_rating_current';
  static const String _todayWazaCountsKey = 'player_today_waza_counts_json';
  static const String _todayModePlayCountsKey =
      'player_today_mode_play_counts_json';
  static const String _recordSummaryLastSyncAtKey =
      'player_record_summary_last_sync_at';
  static const String _recordSummaryLastHashKey =
      'player_record_summary_last_hash';
  static const String _recordSummaryLastNameKey =
      'player_record_summary_last_name';
  static const String _recordSummarySchemaVersionKey =
      'player_record_summary_schema_version';
  static const Duration _matchHistoryRetention = Duration(days: 8);
  static const Duration _recordSummarySyncInterval = Duration(minutes: 1);
  static const Duration _playerNameSyncTimeout = Duration(seconds: 3);
  static const int _recordSummarySchemaVersion = 4;
  static const int _currentInventoryRevision = 4;
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
  List<String> _unseenCollectionItemIds = [];
  int _loginStreak = 0;
  int _totalLoginDays = 0;
  int _lastLoginBonusStreak = 0;
  String _lastLoginDate = '';
  String _playerName = '';
  String _playerId = '';
  List<String> _equippedBadgeIds = [];
  List<String> _equippedStampIds = [];
  List<SeasonRankBadge> _seasonRankBadges = [];
  String _rankedSeasonId = '';
  int _seasonRankedWins = 0;
  int _seasonRankedLosses = 0;
  int _currentRating = 1000;
  String _equippedBallSkinId = 'default';
  String _equippedPlayerIconId = 'default';
  String _equippedIconFrameId = 'default';
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
  int _totalChain = 0;
  int _highestEndlessScore = 0;
  int _rankedWins = 0;
  int _rankedCurrentWinStreak = 0;
  int _rankedMaxWinStreak = 0;
  int _bestRankedRank = 0;
  Map<String, int> _dailyWinRankPlacements = {};
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
  String _todayStatsDate = '';
  int _todayTotalMatches = 0;
  int _todayTotalWins = 0;
  int _todayTotalLosses = 0;
  int _todayClearedBalls = 0;
  int _todayNormalClearedBalls = 0;
  int _todayMaxChain = 0;
  int _todayHighestEndlessScore = 0;
  int _todayRankedMatches = 0;
  int _todayRankedWins = 0;
  int _todayRankedLosses = 0;
  int? _todayRankedRatingStart;
  int? _todayRankedRatingCurrent;
  Map<String, int> _todayWazaCounts = {
    'straight': 0,
    'pyramid': 0,
    'hexagon': 0,
  };
  Map<String, int> _todayModePlayCounts = {
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
  String get lastLoginDate => _lastLoginDate;
  List<Map<String, dynamic>> get currentMissions => _currentMissions
      .map((mission) => Map<String, dynamic>.from(mission))
      .toList();
  List<String> get dailyShopItems => List.unmodifiable(_dailyShopItems);
  bool get hasUnseenCollectionItems => _unseenCollectionItemIds.isNotEmpty;
  int get loginStreak => _loginStreak;
  int get totalLoginDays => _totalLoginDays;
  String get playerName => _playerName;
  String get displayPlayerName =>
      _playerName.trim().isEmpty ? 'プレイヤー' : _playerName.trim();
  String get playerId => _playerId;
  List<String> get equippedBadgeIds => List.unmodifiable(_equippedBadgeIds);
  List<String> get equippedStampIds => List.unmodifiable(_equippedStampIds);
  List<SeasonRankBadge> get seasonRankBadges =>
      List.unmodifiable(_seasonRankBadges);
  String get rankedSeasonId => _rankedSeasonId;
  int get seasonRankedWins => _seasonRankedWins;
  int get seasonRankedLosses => _seasonRankedLosses;
  int get currentRating => _currentRating;
  String get equippedBallSkinId => _equippedBallSkinId;
  String get equippedPlayerIconId => _equippedPlayerIconId;
  String get equippedIconFrameId => _equippedIconFrameId;
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
  double get averageChain =>
      _totalMatches <= 0 ? 0 : _totalChain / _totalMatches;
  int get highestEndlessScore => _highestEndlessScore;
  int get rankedWins => _rankedWins;
  int get rankedCurrentWinStreak => _rankedCurrentWinStreak;
  int get rankedMaxWinStreak => _rankedMaxWinStreak;
  int get bestRankedRank => _bestRankedRank;
  Map<String, int> get dailyWinRankPlacements =>
      Map.unmodifiable(_dailyWinRankPlacements);
  int get arenaPerfectClearCount => _arenaPerfectClearCount;
  Map<String, int> get wazaCounts => Map.unmodifiable(_wazaCounts);
  List<MatchHistoryEntry> get matchHistory => List.unmodifiable(_matchHistory);
  Map<String, int> get modePlayCounts => Map.unmodifiable(_modePlayCounts);
  List<String> get unlockedBadgeIds => BadgeCatalog.allBadges
      .where(
        (badge) => badge.unlockedCondition.isUnlocked(
          highestRating: _highestRating,
          totalMatches: _totalMatches,
          arenaPerfectClearCount: _arenaPerfectClearCount,
          accountAge: accountAge,
          wazaCounts: _wazaCounts,
          highestEndlessScore: _highestEndlessScore,
          bestRankedRank: _bestRankedRank,
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

    final uid = await AuthManager.instance.ensureSignedIn();
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
    _unseenCollectionItemIds = _stringListFromJson(
      prefs.getString(_unseenCollectionItemIdsKey),
    );
    _loginStreak = max(0, prefs.getInt(_loginStreakKey) ?? 0);
    _lastLoginDate = prefs.getString(_lastLoginDateKey) ?? '';
    _lastLoginBonusStreak = max(0, prefs.getInt(_lastLoginBonusStreakKey) ?? 0);
    _totalLoginDays = max(0,
        prefs.getInt(_totalLoginDaysKey) ?? (_lastLoginDate.isEmpty ? 0 : 1));

    var shouldSaveProfile = false;
    var shouldSaveStats = false;
    _playerName = prefs.getString(_playerNameKey) ?? 'プレイヤー';
    if (_playerName.trim().isEmpty) {
      _playerName = 'プレイヤー';
      shouldSaveProfile = true;
    }
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
    _equippedStampIds = _stringListFromJson(
      prefs.getString(_equippedStampIdsKey),
    ).take(6).toList();
    _seasonRankBadges = _seasonRankBadgesFromJson(
      prefs.getString(_seasonRankBadgesKey),
    );
    _rankedSeasonId = prefs.getString(_rankedSeasonIdKey) ?? '';
    _seasonRankedWins = prefs.getInt(_seasonRankedWinsKey) ?? 0;
    _seasonRankedLosses = prefs.getInt(_seasonRankedLossesKey) ?? 0;
    _currentRating = prefs.getInt(_currentRatingKey) ?? 1000;
    _highestRating = max(
      prefs.getInt(_highestRatingKey) ?? _currentRating,
      _currentRating,
    );
    _equippedBallSkinId = prefs.getString(_equippedBallSkinIdKey) ?? 'default';
    _equippedPlayerIconId =
        prefs.getString(_equippedPlayerIconIdKey) ?? 'default';
    _equippedIconFrameId =
        prefs.getString(_equippedIconFrameIdKey) ?? 'default';

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
    _totalChain = prefs.getInt(_totalChainKey) ?? _maxChain;
    _highestEndlessScore = (prefs.getInt(_highestEndlessScoreKey) ?? 0)
        .clamp(0, maxEndlessScore)
        .toInt();
    _rankedWins = prefs.getInt(_rankedWinsKey) ?? 0;
    _rankedCurrentWinStreak = prefs.getInt(_rankedCurrentWinStreakKey) ?? 0;
    _rankedMaxWinStreak = prefs.getInt(_rankedMaxWinStreakKey) ?? 0;
    _bestRankedRank = prefs.getInt(_bestRankedRankKey) ?? 0;
    _dailyWinRankPlacements = _intMapFromJson(
      prefs.getString(_dailyWinRankPlacementsKey),
    );
    _arenaPerfectClearCount = prefs.getInt(_arenaPerfectClearCountKey) ?? 0;
    _wazaCounts = {
      'straight': 0,
      'pyramid': 0,
      'hexagon': 0,
      ..._intMapFromJson(prefs.getString(_wazaCountsKey)),
    };
    _matchHistory = _historyFromJson(prefs.getString(_matchHistoryKey));
    _trimMatchHistory();
    _modePlayCounts = {
      'RANKED': 0,
      'ARENA': 0,
      'CPU': 0,
      'SOLO': 0,
      'FRIEND': 0,
      ..._intMapFromJson(prefs.getString(_modePlayCountsKey)),
    };
    _todayStatsDate = prefs.getString(_todayStatsDateKey) ?? '';
    _todayTotalMatches = prefs.getInt(_todayTotalMatchesKey) ?? 0;
    _todayTotalWins = prefs.getInt(_todayTotalWinsKey) ?? 0;
    _todayTotalLosses = prefs.getInt(_todayTotalLossesKey) ?? 0;
    _todayClearedBalls = prefs.getInt(_todayClearedBallsKey) ?? 0;
    _todayNormalClearedBalls = prefs.getInt(_todayNormalClearedBallsKey) ?? 0;
    _todayMaxChain = prefs.getInt(_todayMaxChainKey) ?? 0;
    _todayHighestEndlessScore = prefs.getInt(_todayHighestEndlessScoreKey) ?? 0;
    _todayRankedMatches = prefs.getInt(_todayRankedMatchesKey) ?? 0;
    _todayRankedWins = prefs.getInt(_todayRankedWinsKey) ?? 0;
    _todayRankedLosses = prefs.getInt(_todayRankedLossesKey) ?? 0;
    _todayRankedRatingStart = prefs.getInt(_todayRankedRatingStartKey);
    _todayRankedRatingCurrent = prefs.getInt(_todayRankedRatingCurrentKey);
    _todayWazaCounts = {
      'straight': 0,
      'pyramid': 0,
      'hexagon': 0,
      ..._intMapFromJson(prefs.getString(_todayWazaCountsKey)),
    };
    _todayModePlayCounts = {
      'RANKED': 0,
      'ARENA': 0,
      'CPU': 0,
      'SOLO': 0,
      'FRIEND': 0,
      ..._intMapFromJson(prefs.getString(_todayModePlayCountsKey)),
    };
    if (_ensureTodayStatsDate(_todayKey())) {
      shouldSaveStats = true;
    }

    if ((prefs.getInt(_recordResetVersionKey) ?? 0) <
        _currentRecordResetVersion) {
      _resetRecordsForRebuild();
      await prefs.setInt(_recordResetVersionKey, _currentRecordResetVersion);
      shouldSaveProfile = true;
      shouldSaveStats = true;
    }

    _loaded = true;

    if (await _claimAdminGrants(uid)) {
      shouldSaveProfile = true;
    }

    final loadedEquippedBadgeIds = List<String>.from(_equippedBadgeIds);
    _equippedBadgeIds = _equippedBadgeIds
        .where((id) => !SeasonRankBadge.isSeasonRankBadgeId(id))
        .map((id) => BadgeCatalog.evolvedBadgeIdFor(
              id,
              unlockedBadgeIds.toSet(),
            ))
        .where((id) => unlockedBadgeIds.contains(id))
        .toSet()
        .take(2)
        .toList();
    if (!_stringListsEqual(loadedEquippedBadgeIds, _equippedBadgeIds)) {
      shouldSaveProfile = true;
    }
    var shouldSaveItems = false;
    if (inventoryRevision < _currentInventoryRevision) {
      shouldSaveItems = _applyInventoryMigration(inventoryRevision);
      shouldSaveProfile = true;
    }
    var shouldSaveEquippedStamps = false;
    final loadedEquippedStampIds = List<String>.from(_equippedStampIds);
    final ownedStampIds = _ownedItems
        .where((item) => item.isStamp)
        .map((item) => item.id)
        .toSet();
    _equippedStampIds = _equippedStampIds
        .where(ownedStampIds.contains)
        .toSet()
        .take(6)
        .toList();
    if (_equippedStampIds.isEmpty && ownedStampIds.isNotEmpty) {
      final defaultOwnedStampIds = GameItemCatalog.defaultStamps
          .map((stamp) => stamp.id)
          .where(ownedStampIds.contains)
          .take(6)
          .toList();
      _equippedStampIds = defaultOwnedStampIds.isNotEmpty
          ? defaultOwnedStampIds
          : ownedStampIds.take(6).toList();
    }
    if (!_stringListsEqual(loadedEquippedStampIds, _equippedStampIds)) {
      shouldSaveEquippedStamps = true;
    }
    if (!_ownsEquippableItem(_equippedBallSkinId, ItemType.skin)) {
      _equippedBallSkinId = 'default';
      shouldSaveProfile = true;
    }
    if (!_ownsEquippableItem(_equippedPlayerIconId, ItemType.icon)) {
      _equippedPlayerIconId = 'default';
      shouldSaveProfile = true;
    }
    if (!_ownsEquippableItem(_equippedIconFrameId, ItemType.frame)) {
      _equippedIconFrameId = 'default';
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
    if (shouldSaveEquippedStamps) {
      await _saveEquippedStamps();
    }
    if (shouldSaveStats) {
      await _saveStats();
    }
  }

  Future<bool> _claimAdminGrants(String uid) async {
    try {
      final grantsRef = AppFirebaseDatabase.ref().child('adminGrants/$uid');
      final snapshot =
          await grantsRef.get().timeout(const Duration(seconds: 3));
      final raw = snapshot.value;
      if (raw is! Map) {
        return false;
      }

      var totalCoins = 0;
      final processedGrantIds = <String>[];
      for (final entry in raw.entries) {
        final grantId = '${entry.key}';
        final grant = entry.value;
        if (grant is! Map) {
          continue;
        }
        final coins = _intValue(grant['coins']);
        if (coins == null || coins <= 0) {
          continue;
        }
        totalCoins += coins;
        processedGrantIds.add(grantId);
      }

      if (totalCoins <= 0 || processedGrantIds.isEmpty) {
        return false;
      }

      _coins += totalCoins;
      await _saveEconomy();
      await grantsRef.update({
        for (final grantId in processedGrantIds) grantId: null,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> checkDailyReset() async {
    await load();
    final today = _todayKey();
    var changed = false;
    var statsChanged = false;

    if (_ensureTodayStatsDate(today)) {
      statsChanged = true;
    }

    if (await _updateLoginStreak(today)) {
      changed = true;
      statsChanged = true;
    }
    final missionIds = _currentMissions
        .map((mission) => mission['id']?.toString() ?? '')
        .toSet();
    final hasSpecialDailyMission =
        missionIds.any(MissionCatalog.isRewardedAdMissionId);
    final hasRetiredLoginMission =
        missionIds.any(MissionCatalog.isLoginRewardMissionId);
    final hasRequiredEndlessMission =
        missionIds.contains(MissionCatalog.requiredEndlessMissionId);
    final hasTemporarilyDisabledMissions =
        missionIds.any(MissionCatalog.isTemporarilyDisabledMissionId);

    if (_lastDailyReset != today ||
        _currentMissions.length != 4 ||
        !hasSpecialDailyMission ||
        !hasRequiredEndlessMission ||
        hasRetiredLoginMission ||
        hasTemporarilyDisabledMissions ||
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
    if (statsChanged) {
      await _saveStats();
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
      await _markCollectionItemUnseen(storedItem.id);
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

  Future<void> clearUnseenCollectionItems() async {
    await load();
    if (_unseenCollectionItemIds.isEmpty) {
      return;
    }
    _unseenCollectionItemIds = [];
    await _saveUnseenCollectionItems();
  }

  Future<void> setPlayerName(String name) async {
    await load();
    final previousName = _playerName;
    _playerName = ModerationManager.instance.sanitizePlayerName(name);
    await _savePublicProfile();
    _syncRecordSummaryInBackground(force: previousName != _playerName);
  }

  Future<void> setCurrentRating(int rating) async {
    await load();
    _ensureTodayStatsDate(_todayKey());
    _currentRating = rating;
    _highestRating = max(_highestRating, rating);
    if (_todayRankedRatingStart != null) {
      _todayRankedRatingCurrent = rating;
    }
    await _savePublicProfile();
    await _saveStats();
    _syncRecordSummaryInBackground(force: true);
  }

  Future<void> setEquippedBadgeIds(List<String> badgeIds) async {
    await load();
    final unlocked = unlockedBadgeIds.toSet();
    _equippedBadgeIds = badgeIds
        .where((id) => !SeasonRankBadge.isSeasonRankBadgeId(id))
        .map((id) => BadgeCatalog.evolvedBadgeIdFor(id, unlocked))
        .where((id) => unlocked.contains(id))
        .toSet()
        .take(2)
        .toList();
    await _savePublicProfile();
  }

  Future<void> setEquippedStampIds(List<String> stampIds) async {
    await load();
    final ownedStampIds = _ownedItems
        .where((item) => item.isStamp)
        .map((item) => item.id)
        .toSet();
    _equippedStampIds =
        stampIds.where(ownedStampIds.contains).toSet().take(6).toList();
    await _saveEquippedStamps();
  }

  Future<void> setSeasonRankBadges(List<SeasonRankBadge> badges) async {
    await load();
    _seasonRankBadges = badges
        .where((badge) => badge.seasonId.isNotEmpty && badge.rank > 0)
        .toList()
      ..sort((a, b) => b.seasonId.compareTo(a.seasonId));
    _equippedBadgeIds = _equippedBadgeIds
        .where((id) => !SeasonRankBadge.isSeasonRankBadgeId(id))
        .map((id) => BadgeCatalog.evolvedBadgeIdFor(
              id,
              unlockedBadgeIds.toSet(),
            ))
        .where((id) => unlockedBadgeIds.contains(id))
        .toSet()
        .take(2)
        .toList();
    await _saveSeasonRankBadges();
    await _savePublicProfile();
    _syncRecordSummaryInBackground(force: true);
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

  Future<void> setEquippedIconFrameId(String frameId) async {
    await load();
    final normalized = frameId.trim().isEmpty ? 'default' : frameId.trim();
    if (!_ownsEquippableItem(normalized, ItemType.frame)) {
      return;
    }
    _equippedIconFrameId = normalized;
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
    _totalChain = 0;
    _highestEndlessScore = 0;
    _rankedWins = 0;
    _rankedCurrentWinStreak = 0;
    _rankedMaxWinStreak = 0;
    _bestRankedRank = 0;
    _dailyWinRankPlacements = {};
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
    String opponentUid = '',
    String opponentPublicId = '',
    int clearedBalls = 0,
    int normalClearedBalls = 0,
    int maxChain = 0,
    bool isForfeitWin = false,
    int? score,
    int? ratingAfter,
    int? ratingDelta,
  }) async {
    await load();
    _ensureTodayStatsDate(_todayKey());
    _totalMatches++;
    if (isWin) {
      _totalWins++;
    } else {
      _totalLosses++;
    }
    _totalClearedBalls += max(0, clearedBalls);
    _totalNormalClearedBalls += max(0, normalClearedBalls);
    _maxChain = max(_maxChain, maxChain);
    _totalChain += max(0, maxChain);
    if (mode == 'SOLO' && score != null) {
      _highestEndlessScore =
          max(_highestEndlessScore, score.clamp(0, maxEndlessScore).toInt());
    }
    if (mode == 'RANKED') {
      if (isWin) {
        _rankedWins++;
        _rankedCurrentWinStreak++;
        _rankedMaxWinStreak = max(_rankedMaxWinStreak, _rankedCurrentWinStreak);
        _seasonRankedWins++;
      } else {
        _rankedCurrentWinStreak = 0;
        _seasonRankedLosses++;
      }
    }
    _modePlayCounts[mode] = (_modePlayCounts[mode] ?? 0) + 1;
    for (final entry in wazaCounts.entries) {
      _wazaCounts[entry.key] = (_wazaCounts[entry.key] ?? 0) + entry.value;
    }
    _recordTodayMatchResult(
      isWin: isWin,
      mode: mode,
      wazaCounts: wazaCounts,
      clearedBalls: clearedBalls,
      normalClearedBalls: normalClearedBalls,
      maxChain: maxChain,
      score: score,
      ratingAfter: ratingAfter,
      ratingDelta: ratingDelta,
    );
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
        opponentUid: opponentUid.trim(),
        opponentPublicId: opponentPublicId.trim(),
        isForfeitWin: isForfeitWin,
        wazaCounts: Map<String, int>.from(wazaCounts),
        clearedBalls: max(0, clearedBalls),
        normalClearedBalls: max(0, normalClearedBalls),
        maxChain: max(0, maxChain),
        hasStyleMetrics: !isForfeitWin,
        score: score,
        ratingAfter: ratingAfter,
        ratingDelta: ratingDelta,
      ),
      ..._matchHistory,
    ];
    _trimMatchHistory();
    await _savePublicProfile();
    await _saveStats();
    if (ratingAfter != null) {
      _syncRecordSummaryInBackground(force: true);
    }
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
      opponentUid: target.opponentUid,
      opponentPublicId: target.opponentPublicId,
      isForfeitWin: target.isForfeitWin,
      wazaCounts: target.wazaCounts,
      clearedBalls: target.clearedBalls,
      normalClearedBalls: target.normalClearedBalls,
      maxChain: target.maxChain,
      hasStyleMetrics: target.hasStyleMetrics,
      score: target.score,
      ratingAfter: ratingAfter,
      ratingDelta: ratingDelta,
    );
    _currentRating = ratingAfter;
    _highestRating = max(_highestRating, ratingAfter);
    if (_todayRankedRatingStart != null) {
      _todayRankedRatingCurrent = ratingAfter;
    }
    await _savePublicProfile();
    await _saveStats();
    _syncRecordSummaryInBackground(force: true);
  }

  void _trimMatchHistory() {
    final cutoff = DateTime.now().subtract(_matchHistoryRetention);
    final recent = _matchHistory
        .where((entry) => !entry.playedAt.isBefore(cutoff))
        .toList();
    final latestDisplayEntries = _matchHistory.take(30);
    _matchHistory = {
      for (final entry in [...recent, ...latestDisplayEntries]) entry: entry,
    }.keys.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  }

  Future<void> recordBestRankedRank(int rank) async {
    await load();
    if (rank <= 0 || (_bestRankedRank > 0 && _bestRankedRank <= rank)) {
      return;
    }
    _bestRankedRank = rank;
    await _saveStats();
  }

  Future<void> recordDailyWinRankingPlacement({
    required int rank,
    required int wins,
  }) async {
    await load();
    if (rank <= 0 || wins <= 0) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final placementKey = '${_todayKey()}|$rank|$wins';
    if (prefs.getString(_dailyWinRankPlacementLastKey) == placementKey) {
      return;
    }
    final key = '$rank位';
    _dailyWinRankPlacements[key] = (_dailyWinRankPlacements[key] ?? 0) + 1;
    await prefs.setString(_dailyWinRankPlacementLastKey, placementKey);
    await _saveStats();
  }

  Future<void> syncDailyWinRankPlacementsFromRecordSummary() async {
    await load();
    try {
      final uid = await AuthManager.instance.ensureSignedIn();
      if (uid.isEmpty) {
        return;
      }
      final snapshot = await AppFirebaseDatabase.ref()
          .child('playerRecordSummaries/$uid/ranked/dailyWinRankPlacements')
          .get();
      final remote = _intMapFromDynamic(snapshot.value);
      if (_mapsEqual(_dailyWinRankPlacements, remote)) {
        return;
      }
      _dailyWinRankPlacements = remote;
      await _saveStats();
    } catch (_) {
      // 集計値の同期失敗はミッション表示を止めない。
    }
  }

  Future<String?> consumePendingRankedSeasonResultLog() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getString(_pendingRankedSeasonResultLogKey);
    if (log == null || log.isEmpty) {
      return null;
    }
    await prefs.remove(_pendingRankedSeasonResultLogKey);
    return log;
  }

  Future<void> ensureRankedSeason({
    required String currentSeasonId,
    required String previousSeasonName,
    int? previousFinalRank,
    int? previousFinalRating,
    int? previousSeasonWins,
    int? previousSeasonLosses,
  }) async {
    await load();
    if (_rankedSeasonId == currentSeasonId) {
      return;
    }

    final hadRankedSeason = _rankedSeasonId.isNotEmpty;
    if (hadRankedSeason) {
      final wins = previousSeasonWins ?? _seasonRankedWins;
      final losses = previousSeasonLosses ?? _seasonRankedLosses;
      final total = wins + losses;
      final winRate =
          total <= 0 ? '未参加' : '${((wins / total) * 100).toStringAsFixed(1)}%';
      final rankText = previousFinalRank == null ? '圏外' : '$previousFinalRank位';
      final ratingText = previousFinalRating ?? _currentRating;
      final log = StringBuffer()
        ..writeln('$previousSeasonName 結果')
        ..writeln('最終レート: $ratingText')
        ..writeln('最終順位: $rankText')
        ..writeln('勝敗: $wins勝 $losses敗')
        ..write('勝率: $winRate');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingRankedSeasonResultLogKey, log.toString());
    }

    _rankedSeasonId = currentSeasonId;
    if (hadRankedSeason) {
      _seasonRankedWins = 0;
      _seasonRankedLosses = 0;
      _rankedCurrentWinStreak = 0;
      _currentRating = 1000;
    }
    await _savePublicProfile();
    await _saveStats();
  }

  Future<void> syncRecordSummary({bool force = false}) async {
    await load();
    await AppSettings.instance.load();
    final uid = await AuthManager.instance.ensureSignedIn();
    final prefs = await SharedPreferences.getInstance();
    final summary = _recordSummaryPayload(uid);
    final hash = jsonEncode(summary);
    final previousHash = prefs.getString(_recordSummaryLastHashKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastSyncedAt = prefs.getInt(_recordSummaryLastSyncAtKey) ?? 0;
    final previousName = prefs.getString(_recordSummaryLastNameKey) ?? '';
    final nameChanged = previousName != displayPlayerName;
    final schemaChanged = (prefs.getInt(_recordSummarySchemaVersionKey) ?? 0) <
        _recordSummarySchemaVersion;

    if (!force &&
        !schemaChanged &&
        previousHash == hash &&
        !nameChanged &&
        now - lastSyncedAt < _recordSummarySyncInterval.inMilliseconds) {
      return;
    }
    if (!force &&
        !schemaChanged &&
        previousHash != null &&
        previousHash != hash &&
        now - lastSyncedAt < _recordSummarySyncInterval.inMilliseconds) {
      return;
    }

    try {
      final database = AppFirebaseDatabase.ref();
      if (nameChanged && previousName.trim().isNotEmpty) {
        final previousKey = _nameLookupKey(previousName);
        final nextKey = _nameLookupKey(displayPlayerName);
        if (previousKey != nextKey) {
          await database.child('playerNameLookup/$previousKey/$uid').remove();
        }
      }
      final syncedAt = DateTime.now();
      await database.child('playerRecordSummaries/$uid').set({
        ...summary,
        'updatedAt': ServerValue.timestamp,
        'updatedAtText': _formatDateTimeForDatabase(syncedAt),
        'lastSeenAtText': _formatDateTimeForDatabase(syncedAt),
      });
      await database
          .child('playerNameLookup/${_nameLookupKey(displayPlayerName)}/$uid')
          .set({
        'uid': uid,
        'publicId': _playerId,
        'displayName': displayPlayerName,
        'currentRating': _currentRating,
        'totalMatches': _totalMatches,
        'updatedAt': ServerValue.timestamp,
      });
      await prefs.setString(_recordSummaryLastHashKey, hash);
      await prefs.setInt(_recordSummaryLastSyncAtKey, now);
      await prefs.setString(_recordSummaryLastNameKey, displayPlayerName);
      await prefs.setInt(
        _recordSummarySchemaVersionKey,
        _recordSummarySchemaVersion,
      );
    } catch (_) {
      // 管理用サマリーの同期失敗で、プレイ中の保存処理は止めない。
    }
  }

  void _syncRecordSummaryInBackground({bool force = false}) {
    unawaited(_syncRecordSummarySafely(force: force));
  }

  Future<void> _syncRecordSummarySafely({bool force = false}) async {
    try {
      await syncRecordSummary(force: force).timeout(
        _playerNameSyncTimeout,
        onTimeout: () {},
      );
    } catch (_) {
      // 管理用サマリーのバックグラウンド同期失敗で保存処理は止めない。
    }
  }

  Future<void> _saveEconomy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_coinsKey, _coins);
    await prefs.setInt(_expKey, _exp);
    await prefs.setInt(_gachaTicketsKey, _gachaTickets);
    await prefs.setInt(_cyberScrapKey, _cyberScrap);
    _syncRecordSummaryInBackground();
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _itemsKey,
      jsonEncode(_ownedItems.map((item) => item.toJson()).toList()),
    );
    _syncRecordSummaryInBackground();
  }

  Future<void> _saveEquippedStamps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedStampIdsKey, jsonEncode(_equippedStampIds));
  }

  Future<void> _saveSeasonRankBadges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _seasonRankBadgesKey,
      jsonEncode(_seasonRankBadges.map((badge) => badge.toJson()).toList()),
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
    await prefs.setString(_equippedIconFrameIdKey, _equippedIconFrameId);
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
    await prefs.setInt(_totalChainKey, _totalChain);
    await prefs.setInt(
      _highestEndlessScoreKey,
      _highestEndlessScore.clamp(0, maxEndlessScore).toInt(),
    );
    await prefs.setInt(_rankedWinsKey, _rankedWins);
    await prefs.setInt(_rankedCurrentWinStreakKey, _rankedCurrentWinStreak);
    await prefs.setInt(_rankedMaxWinStreakKey, _rankedMaxWinStreak);
    await prefs.setInt(_bestRankedRankKey, _bestRankedRank);
    await prefs.setString(
      _dailyWinRankPlacementsKey,
      jsonEncode(_dailyWinRankPlacements),
    );
    await prefs.setString(_rankedSeasonIdKey, _rankedSeasonId);
    await prefs.setInt(_seasonRankedWinsKey, _seasonRankedWins);
    await prefs.setInt(_seasonRankedLossesKey, _seasonRankedLosses);
    await prefs.setInt(_arenaPerfectClearCountKey, _arenaPerfectClearCount);
    await prefs.setString(_wazaCountsKey, jsonEncode(_wazaCounts));
    await prefs.setString(_modePlayCountsKey, jsonEncode(_modePlayCounts));
    await prefs.setString(
      _matchHistoryKey,
      jsonEncode(_matchHistory.map((entry) => entry.toJson()).toList()),
    );
    await _saveTodayStats(prefs);
    await _saveSeasonRankBadges();
    await syncRecordSummary();
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
    await prefs.setInt(_totalLoginDaysKey, _totalLoginDays);
    await prefs.setInt(_lastLoginBonusStreakKey, _lastLoginBonusStreak);
    await prefs.setString(_lastLoginDateKey, _lastLoginDate);
  }

  Future<void> _saveUnseenCollectionItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _unseenCollectionItemIdsKey,
      jsonEncode(_unseenCollectionItemIds),
    );
  }

  Future<void> _markCollectionItemUnseen(String itemId) async {
    if (itemId.isEmpty || _unseenCollectionItemIds.contains(itemId)) {
      return;
    }
    _unseenCollectionItemIds = [
      ..._unseenCollectionItemIds,
      itemId,
    ];
    await _saveUnseenCollectionItems();
  }

  Future<void> _saveTodayStats(SharedPreferences prefs) async {
    await prefs.setString(_todayStatsDateKey, _todayStatsDate);
    await prefs.setInt(_todayTotalMatchesKey, _todayTotalMatches);
    await prefs.setInt(_todayTotalWinsKey, _todayTotalWins);
    await prefs.setInt(_todayTotalLossesKey, _todayTotalLosses);
    await prefs.setInt(_todayClearedBallsKey, _todayClearedBalls);
    await prefs.setInt(
      _todayNormalClearedBallsKey,
      _todayNormalClearedBalls,
    );
    await prefs.setInt(_todayMaxChainKey, _todayMaxChain);
    await prefs.setInt(
      _todayHighestEndlessScoreKey,
      _todayHighestEndlessScore,
    );
    await prefs.setInt(_todayRankedMatchesKey, _todayRankedMatches);
    await prefs.setInt(_todayRankedWinsKey, _todayRankedWins);
    await prefs.setInt(_todayRankedLossesKey, _todayRankedLosses);
    final ratingStart = _todayRankedRatingStart;
    final ratingCurrent = _todayRankedRatingCurrent;
    if (ratingStart == null) {
      await prefs.remove(_todayRankedRatingStartKey);
    } else {
      await prefs.setInt(_todayRankedRatingStartKey, ratingStart);
    }
    if (ratingCurrent == null) {
      await prefs.remove(_todayRankedRatingCurrentKey);
    } else {
      await prefs.setInt(_todayRankedRatingCurrentKey, ratingCurrent);
    }
    await prefs.setString(_todayWazaCountsKey, jsonEncode(_todayWazaCounts));
    await prefs.setString(
      _todayModePlayCountsKey,
      jsonEncode(_todayModePlayCounts),
    );
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
    final activeDailyPool = MissionCatalog.activeDailyPool;
    final rewardedMission = activeDailyPool.firstWhere(
      (mission) => mission.id == MissionCatalog.rewardedAdMissionIds.first,
    );
    final endlessMission = activeDailyPool.firstWhere(
      (mission) => mission.id == MissionCatalog.requiredEndlessMissionId,
    );
    final pool = activeDailyPool
        .where((mission) =>
            !MissionCatalog.isRewardedAdMissionId(mission.id) &&
            mission.id != MissionCatalog.requiredEndlessMissionId)
        .toList()
      ..shuffle(_random);
    return [
      rewardedMission.toMissionMap(),
      endlessMission.toMissionMap(),
      ...pool.take(2).map((mission) => mission.toMissionMap()),
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
    if (revision < 3) {
      final allowedStampIds =
          GameItemCatalog.commonStamps.map((stamp) => stamp.id).toSet();
      final filteredItems = _ownedItems
          .where((item) => !item.isStamp || allowedStampIds.contains(item.id))
          .toList();
      if (filteredItems.length != _ownedItems.length) {
        _ownedItems = filteredItems;
        changed = true;
      }
    }
    if (revision < 4) {
      for (final stamp in GameItemCatalog.defaultStamps) {
        if (_ownedItems.every((item) => item.id != stamp.id)) {
          _ownedItems.add(stamp.copyWith(level: 1));
          changed = true;
        }
      }
    }
    final allowedItemIds =
        GameItemCatalog.allItems.map((item) => item.id).toSet();
    final filteredItems =
        _ownedItems.where((item) => allowedItemIds.contains(item.id)).toList();
    if (filteredItems.length != _ownedItems.length) {
      _ownedItems = filteredItems;
      changed = true;
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

  bool _ensureTodayStatsDate(String today) {
    if (_todayStatsDate == today) {
      return false;
    }
    _todayStatsDate = today;
    _todayTotalMatches = 0;
    _todayTotalWins = 0;
    _todayTotalLosses = 0;
    _todayClearedBalls = 0;
    _todayNormalClearedBalls = 0;
    _todayMaxChain = 0;
    _todayHighestEndlessScore = 0;
    _todayRankedMatches = 0;
    _todayRankedWins = 0;
    _todayRankedLosses = 0;
    _todayRankedRatingStart = null;
    _todayRankedRatingCurrent = null;
    _todayWazaCounts = {
      'straight': 0,
      'pyramid': 0,
      'hexagon': 0,
    };
    _todayModePlayCounts = {
      'RANKED': 0,
      'ARENA': 0,
      'CPU': 0,
      'SOLO': 0,
      'FRIEND': 0,
    };
    return true;
  }

  void _recordTodayMatchResult({
    required bool isWin,
    required String mode,
    required Map<String, int> wazaCounts,
    required int clearedBalls,
    required int normalClearedBalls,
    required int maxChain,
    int? score,
    int? ratingAfter,
    int? ratingDelta,
  }) {
    _todayTotalMatches++;
    if (isWin) {
      _todayTotalWins++;
    } else {
      _todayTotalLosses++;
    }
    _todayClearedBalls += max(0, clearedBalls);
    _todayNormalClearedBalls += max(0, normalClearedBalls);
    _todayMaxChain = max(_todayMaxChain, maxChain);
    if (mode == 'SOLO' && score != null) {
      _todayHighestEndlessScore = max(
          _todayHighestEndlessScore, score.clamp(0, maxEndlessScore).toInt());
    }
    _todayModePlayCounts[mode] = (_todayModePlayCounts[mode] ?? 0) + 1;
    for (final entry in wazaCounts.entries) {
      _todayWazaCounts[entry.key] =
          (_todayWazaCounts[entry.key] ?? 0) + entry.value;
    }
    if (mode == 'RANKED') {
      _todayRankedMatches++;
      if (isWin) {
        _todayRankedWins++;
      } else {
        _todayRankedLosses++;
      }
      if (ratingAfter != null) {
        _todayRankedRatingCurrent = ratingAfter;
        _todayRankedRatingStart ??=
            ratingDelta == null ? _currentRating : ratingAfter - ratingDelta;
      } else {
        _todayRankedRatingStart ??= _currentRating;
        _todayRankedRatingCurrent = _currentRating;
      }
    }
  }

  Map<String, dynamic> _recordSummaryPayload(String uid) {
    final ratingStart = _todayRankedRatingStart;
    final ratingCurrent = _todayRankedRatingCurrent;
    final ownedItems = _ownedItems.map((item) => item.toJson()).toList();
    return {
      'schemaVersion': _recordSummarySchemaVersion,
      'uid': uid,
      'publicId': _playerId,
      'displayName': displayPlayerName,
      'recordDate': _todayStatsDate.isEmpty ? _todayKey() : _todayStatsDate,
      'overall': {
        'totalMatches': _totalMatches,
        'totalWins': _totalWins,
        'totalLosses': _totalLosses,
        'totalClearedBalls': _totalClearedBalls,
        'totalNormalClearedBalls': _totalNormalClearedBalls,
        'maxChain': _maxChain,
        'averageChain': double.parse(averageChain.toStringAsFixed(2)),
        'totalLoginDays': _totalLoginDays,
        'accountCreatedAt': _accountCreatedAt.toIso8601String(),
        'accountCreatedAtText': _formatDateTimeForDatabase(_accountCreatedAt),
        'lastLoginDate': _lastLoginDate,
        'lastLoginDateText': _lastLoginDate.isEmpty
            ? ''
            : _formatDateKeyForDatabase(_lastLoginDate),
      },
      'economy': {
        'coins': _coins,
        'level': level,
        'exp': _exp,
        'currentLevelExp': currentLevelExp,
        'nextLevelRequiredExp': nextLevelRequiredExp,
        'gachaTickets': _gachaTickets,
        'cyberScrap': _cyberScrap,
        'adsRemoved': AppSettings.instance.adsRemoved.value,
      },
      'collection': {
        'ownedItemCount': ownedItems.length,
        'ownedItems': ownedItems,
        'ownedItemIds': _ownedItems.map((item) => item.id).toList(),
        'ownedStampIds': _ownedItems
            .where((item) => item.type == ItemType.stamp)
            .map((item) => item.id)
            .toList(),
        'ownedSkinIds': _ownedItems
            .where((item) => item.type == ItemType.skin)
            .map((item) => item.id)
            .toList(),
        'ownedIconIds': _ownedItems
            .where((item) => item.type == ItemType.icon)
            .map((item) => item.id)
            .toList(),
        'ownedFrameIds': _ownedItems
            .where((item) => item.type == ItemType.frame)
            .map((item) => item.id)
            .toList(),
        'equippedBallSkinId': _equippedBallSkinId,
        'equippedPlayerIconId': _equippedPlayerIconId,
        'equippedIconFrameId': _equippedIconFrameId,
        'equippedBadgeIds': List<String>.from(_equippedBadgeIds),
        'unlockedBadgeIds': unlockedBadgeIds,
        'seasonRankBadges':
            _seasonRankBadges.map((badge) => badge.toJson()).toList(),
      },
      'ranked': {
        'wins': _rankedWins,
        'losses': max(0, (_modePlayCounts['RANKED'] ?? 0) - _rankedWins),
        'matches': _modePlayCounts['RANKED'] ?? 0,
        'seasonId': _rankedSeasonId,
        'seasonWins': _seasonRankedWins,
        'seasonLosses': _seasonRankedLosses,
        'seasonMatches': _seasonRankedWins + _seasonRankedLosses,
        'currentRating': _currentRating,
        'highestRating': _highestRating,
        'currentWinStreak': _rankedCurrentWinStreak,
        'maxWinStreak': _rankedMaxWinStreak,
        'bestRankedRank': _bestRankedRank,
      },
      'arena': {
        'maxWins': _maxArenaWins,
        'challengeCount': _arenaChallengeCount,
        'perfectClearCount': _arenaPerfectClearCount,
      },
      'endless': {
        'playCount': _modePlayCounts['SOLO'] ?? 0,
        'highestScore': _highestEndlessScore,
      },
      'cpu': _cpuStatsPayload(),
      'friend': {
        'matches': _modePlayCounts['FRIEND'] ?? 0,
      },
      'wazaCounts': Map<String, int>.from(_wazaCounts),
      'modePlayCounts': Map<String, int>.from(_modePlayCounts),
      'matchHistory':
          _matchHistory.take(30).map((entry) => entry.toJson()).toList(),
      'today': {
        'date': _todayStatsDate.isEmpty ? _todayKey() : _todayStatsDate,
        'totalMatches': _todayTotalMatches,
        'totalWins': _todayTotalWins,
        'totalLosses': _todayTotalLosses,
        'totalClearedBalls': _todayClearedBalls,
        'totalNormalClearedBalls': _todayNormalClearedBalls,
        'maxChain': _todayMaxChain,
        'highestEndlessScore': _todayHighestEndlessScore,
        'modePlayCounts': Map<String, int>.from(_todayModePlayCounts),
        'ranked': {
          'matches': _todayRankedMatches,
          'wins': _todayRankedWins,
          'losses': _todayRankedLosses,
          'ratingStart': ratingStart ?? _currentRating,
          'ratingCurrent': ratingCurrent ?? _currentRating,
          'ratingDelta': ratingStart != null && ratingCurrent != null
              ? ratingCurrent - ratingStart
              : 0,
        },
        'wazaCounts': Map<String, int>.from(_todayWazaCounts),
      },
    };
  }

  Map<String, dynamic> _cpuStatsPayload() {
    final buckets = <String, Map<String, int>>{};
    for (final entry in _matchHistory.where((entry) => entry.mode == 'CPU')) {
      final key = entry.opponentName.trim().isEmpty
          ? 'UNKNOWN'
          : entry.opponentName.trim();
      final bucket = buckets.putIfAbsent(
        key,
        () => {'matches': 0, 'wins': 0, 'losses': 0},
      );
      bucket['matches'] = (bucket['matches'] ?? 0) + 1;
      if (entry.isWin) {
        bucket['wins'] = (bucket['wins'] ?? 0) + 1;
      } else {
        bucket['losses'] = (bucket['losses'] ?? 0) + 1;
      }
    }
    return {
      'matches': _modePlayCounts['CPU'] ?? 0,
      'byDifficulty': buckets,
    };
  }

  String _formatDateTimeForDatabase(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  String _formatDateKeyForDatabase(String dateKey) {
    final parsed = _parseDateKey(dateKey);
    if (parsed == null) {
      return dateKey.replaceAll('-', '/');
    }
    return '${parsed.year.toString().padLeft(4, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.day.toString().padLeft(2, '0')}';
  }

  String _nameLookupKey(String name) {
    final normalized = name.trim().toLowerCase();
    final key = normalized
        .replaceAll(RegExp(r'[\.\#\$\[\]/]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return key.isEmpty ? 'player' : key;
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
    _totalLoginDays++;

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

  List<SeasonRankBadge> _seasonRankBadgesFromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (entry) => SeasonRankBadge.fromJson(
                Map<String, dynamic>.from(entry),
              ),
            )
            .where((badge) => badge.seasonId.isNotEmpty && badge.rank > 0)
            .toList();
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

  Map<String, int> _intMapFromDynamic(Object? raw) {
    if (raw is! Map) {
      return {};
    }
    return {
      for (final entry in raw.entries)
        entry.key.toString(): _intValue(entry.value) ?? 0,
    };
  }

  bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
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

  bool _stringListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  bool _ownsEquippableItem(String id, ItemType type) {
    if (id == 'default') {
      return true;
    }
    return _ownedItems.any((item) => item.id == id && item.type == type);
  }
}
