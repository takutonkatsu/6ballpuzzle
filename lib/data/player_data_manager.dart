import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../app_settings.dart';
import '../audio/audio_selection_manager.dart';
import '../game/effect_skin.dart';
import '../game/mission_catalog.dart';
import '../moderation/moderation_manager.dart';
import '../network/ranked_season_manager.dart';
import 'models/badge_item.dart';
import 'models/game_item.dart';
import '../app_review_config.dart';
import '../firebase_database_provider.dart';
import '../invite/invite_manager.dart';

class ItemGrantResult {
  const ItemGrantResult({
    required this.item,
    required this.isDuplicate,
    required this.leveledUp,
    required this.convertedToScrap,
    required this.cyberScrapAdded,
    required this.collectionMedalsAdded,
  });

  final GameItem item;
  final bool isDuplicate;
  final bool leveledUp;
  final bool convertedToScrap;
  final int cyberScrapAdded;
  final int collectionMedalsAdded;
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
  static const int maxEquippedStampCount = 12;
  static const String emptyStampSlotId = '__empty_stamp_slot__';
  static const String retiredPrismSkinId = 'skin_luxury_prism';
  static const String _coinsKey = 'player_coins';
  static const String _expKey = 'player_exp';
  static const String _gachaTicketsKey = 'player_gacha_tickets';
  static const String _cyberScrapKey = 'player_cyber_scrap';
  static const String _collectionMedalsKey = 'player_collection_medals';
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
  static const String playerIdPrefsKey = _playerIdKey;
  static const String _equippedBadgeIdsKey = 'player_equipped_badge_ids_json';
  static const String _equippedStampIdsKey = 'player_equipped_stamp_ids_json';
  static const String _seasonRankBadgesKey = 'player_season_rank_badges_json';
  static const String _rankedSeasonIdKey = 'player_ranked_season_id';
  static const String _seasonRankedWinsKey = 'player_season_ranked_wins';
  static const String _seasonRankedLossesKey = 'player_season_ranked_losses';
  static const String _seasonRankedMaxWinStreakKey =
      'player_season_ranked_max_win_streak';
  static const String _pendingRankedSeasonResultLogKey =
      'player_pending_ranked_season_result_log';
  static const String _currentRatingKey = 'player_current_rating';
  static const String _equippedBallSkinIdKey = 'player_equipped_ball_skin_id';
  static const String _equippedFormationEffectIdKey =
      'player_equipped_formation_effect_id';
  static const String _equippedOjamaEffectIdKey =
      'player_equipped_ojama_effect_id';
  static const String _equippedPlayerIconIdKey =
      'player_equipped_player_icon_id';
  static const String _equippedIconFrameIdKey = 'player_equipped_icon_frame_id';
  static const String _equippedProfileBannerIdKey =
      'player_equipped_profile_banner_id';
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
  static const String _endlessSeasonIdKey = 'player_endless_season_id';
  static const String _seasonEndlessHighScoreKey =
      'player_season_endless_high_score';
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
  static const String _cpuDifficultyRecordsKey =
      'player_cpu_difficulty_records_json';
  static const String _inventoryRevisionKey = 'player_inventory_revision';
  static const String _pendingLevelUpRewardLogKey =
      'player_pending_level_up_reward_log';
  static const String _pendingLoginBonusLogKey =
      'player_pending_login_bonus_log';
  static const String _pendingAdminGrantLogsKey =
      'player_pending_admin_grant_logs_json';
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

  final Random _random = Random();
  bool _loaded = false;
  bool _debugMissionsResetApplied = false;
  int _coins = initialCoins;
  int _exp = 0;
  int _gachaTickets = 0;
  int _cyberScrap = 0;
  int _collectionMedals = 0;
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
  int _seasonRankedMaxWinStreak = 0;
  int _currentRating = 1000;
  String _equippedBallSkinId = 'default';
  String _equippedFormationEffectId = EffectSkinCatalog.defaultFormationId;
  String _equippedOjamaEffectId = EffectSkinCatalog.defaultOjamaId;
  String _equippedPlayerIconId = 'default';
  String _equippedIconFrameId = 'default';
  String _equippedProfileBannerId = 'default';
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
  String _endlessSeasonId = '';
  int _seasonEndlessHighScore = 0;
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
  Map<String, int> _cpuDifficultyRecords = {
    'weak_matches': 0,
    'weak_wins': 0,
    'normal_matches': 0,
    'normal_wins': 0,
    'strong_matches': 0,
    'strong_wins': 0,
    'oni_matches': 0,
    'oni_wins': 0,
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
  int get seasonRankedMaxWinStreak => _seasonRankedMaxWinStreak;
  int get currentRating => _currentRating;
  String get equippedBallSkinId => _equippedBallSkinId;
  String get equippedFormationEffectId => _equippedFormationEffectId;
  String get equippedOjamaEffectId => _equippedOjamaEffectId;
  String get equippedPlayerIconId => _equippedPlayerIconId;
  String get equippedIconFrameId => _equippedIconFrameId;
  String get equippedProfileBannerId => _equippedProfileBannerId;
  int get collectionMedals => _collectionMedals;
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
  String get endlessSeasonId => _endlessSeasonId;
  int get seasonEndlessHighScore => _seasonEndlessHighScore;
  int get rankedWins => _rankedWins;
  int get rankedCurrentWinStreak => _rankedCurrentWinStreak;
  int get rankedMaxWinStreak => _rankedMaxWinStreak;
  int get todayRankedWins => _todayRankedWins;
  int get bestRankedRank => _bestRankedRank;
  Map<String, int> get dailyWinRankPlacements =>
      Map.unmodifiable(_dailyWinRankPlacements);
  int get arenaPerfectClearCount => _arenaPerfectClearCount;
  Map<String, int> get wazaCounts => Map.unmodifiable(_wazaCounts);
  List<MatchHistoryEntry> get matchHistory => List.unmodifiable(_matchHistory);
  Map<String, int> get modePlayCounts => Map.unmodifiable(_modePlayCounts);
  Map<String, int> get cpuDifficultyRecords =>
      Map.unmodifiable(_cpuDifficultyRecords);
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
    _collectionMedals = max(0, prefs.getInt(_collectionMedalsKey) ?? 0);
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
    ).take(3).toList();
    _equippedStampIds = _stringListFromJson(
      prefs.getString(_equippedStampIdsKey),
    ).take(6).toList();
    _seasonRankBadges = _seasonRankBadgesFromJson(
      prefs.getString(_seasonRankBadgesKey),
    );
    _rankedSeasonId = prefs.getString(_rankedSeasonIdKey) ?? '';
    _seasonRankedWins = prefs.getInt(_seasonRankedWinsKey) ?? 0;
    _seasonRankedLosses = prefs.getInt(_seasonRankedLossesKey) ?? 0;
    _seasonRankedMaxWinStreak = prefs.getInt(_seasonRankedMaxWinStreakKey) ?? 0;
    _currentRating = prefs.getInt(_currentRatingKey) ?? 1000;
    _highestRating = max(
      prefs.getInt(_highestRatingKey) ?? _currentRating,
      _currentRating,
    );
    _equippedBallSkinId = prefs.getString(_equippedBallSkinIdKey) ?? 'default';
    _equippedFormationEffectId =
        prefs.getString(_equippedFormationEffectIdKey) ??
            EffectSkinCatalog.defaultFormationId;
    _equippedOjamaEffectId = prefs.getString(_equippedOjamaEffectIdKey) ??
        EffectSkinCatalog.defaultOjamaId;
    _equippedPlayerIconId =
        prefs.getString(_equippedPlayerIconIdKey) ?? 'default';
    _equippedIconFrameId =
        prefs.getString(_equippedIconFrameIdKey) ?? 'default';
    _equippedProfileBannerId =
        prefs.getString(_equippedProfileBannerIdKey) ?? 'default';

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
    _endlessSeasonId = prefs.getString(_endlessSeasonIdKey) ?? '';
    _seasonEndlessHighScore = (prefs.getInt(_seasonEndlessHighScoreKey) ?? 0)
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
    _cpuDifficultyRecords = {
      'weak_matches': 0,
      'weak_wins': 0,
      'normal_matches': 0,
      'normal_wins': 0,
      'strong_matches': 0,
      'strong_wins': 0,
      'oni_matches': 0,
      'oni_wins': 0,
      ..._intMapFromJson(prefs.getString(_cpuDifficultyRecordsKey)),
    };
    if (_cpuDifficultyRecords.values.every((value) => value == 0) &&
        _matchHistory.any((entry) => entry.mode == 'CPU')) {
      for (final entry in _matchHistory.where((entry) => entry.mode == 'CPU')) {
        _recordCpuDifficultyResult(
          opponentName: entry.opponentName,
          isWin: entry.isWin,
        );
      }
      await prefs.setString(
        _cpuDifficultyRecordsKey,
        jsonEncode(_cpuDifficultyRecords),
      );
    }
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
    await AudioSelectionManager.setOwnedAudioItemIds(
      _ownedItems.where((item) => item.isAudio).map((item) => item.id),
    );
    await AudioSelectionManager.restrictSelectionsForPlayer(displayPlayerName);

    if (await _claimAdminGrants(uid)) {
      shouldSaveProfile = true;
    }

    final loadedEquippedBadgeIds = List<String>.from(_equippedBadgeIds);
    final ownedSeasonBadgeIds =
        _seasonRankBadges.map((badge) => badge.id).toSet();
    _equippedBadgeIds = _equippedBadgeIds
        .map((id) => _normalizeEquippedBadgeId(
              id,
              ownedSeasonBadgeIds: ownedSeasonBadgeIds,
            ))
        .where((id) =>
            unlockedBadgeIds.contains(id) || ownedSeasonBadgeIds.contains(id))
        .fold<List<String>>(<String>[], (items, id) {
      if (!items.contains(id) && items.length < 3) {
        items.add(id);
      }
      return items;
    });
    if (!_stringListsEqual(loadedEquippedBadgeIds, _equippedBadgeIds)) {
      shouldSaveProfile = true;
    }
    var shouldSaveItems = false;
    if (inventoryRevision < _currentInventoryRevision) {
      shouldSaveItems = _applyInventoryMigration(inventoryRevision);
      shouldSaveProfile = true;
    }
    if (_removeRetiredCollectionItems()) {
      shouldSaveItems = true;
      shouldSaveProfile = true;
    }
    var shouldSaveEquippedStamps = false;
    final loadedEquippedStampIds = List<String>.from(_equippedStampIds);
    final ownedStampIds = _ownedItems
        .where((item) => item.isStamp)
        .map((item) => item.id)
        .toSet();
    _equippedStampIds =
        _normalizeEquippedStampSlots(_equippedStampIds, ownedStampIds);
    if (!_stringListsEqual(loadedEquippedStampIds, _equippedStampIds)) {
      shouldSaveEquippedStamps = true;
    }
    if (!_ownsEquippableItem(_equippedBallSkinId, ItemType.skin)) {
      _equippedBallSkinId = 'default';
      shouldSaveProfile = true;
    }
    if (!EffectSkinCatalog.isFormation(_equippedFormationEffectId)) {
      _equippedFormationEffectId = EffectSkinCatalog.defaultFormationId;
      shouldSaveProfile = true;
    }
    if (!EffectSkinCatalog.isOjama(_equippedOjamaEffectId)) {
      _equippedOjamaEffectId = EffectSkinCatalog.defaultOjamaId;
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
    if (!_ownsEquippableItem(_equippedProfileBannerId, ItemType.banner)) {
      _equippedProfileBannerId = 'default';
      shouldSaveProfile = true;
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
      final rewardLogs = <String>[];
      final processedGrantIds = <String>[];
      final claimedGrantLogs = <Map<String, Object?>>[];
      var completedOwnInvite = false;
      var grantedAdRemoval = false;
      var grantedItem = false;
      for (final entry in raw.entries) {
        final grantId = '${entry.key}';
        final grant = entry.value;
        if (grant is! Map) {
          continue;
        }
        final grantType = grant['type']?.toString().trim() ?? '';
        if (grantType == 'ad_removal') {
          processedGrantIds.add(grantId);
          grantedAdRemoval = true;
          final title = grant['title']?.toString().trim() ?? '広告削除';
          final message =
              grant['message']?.toString().trim() ?? '広告削除を有効にしました。';
          rewardLogs.add('$title\n$message');
          claimedGrantLogs.add(_claimedAdminGrantLog(
            grantId: grantId,
            grantType: grantType,
            title: title,
            message: message,
            coins: 0,
          ));
          continue;
        }
        if (grantType == 'item') {
          final itemId = grant['itemId']?.toString().trim() ?? '';
          final item = GameItemCatalog.byId(itemId);
          if (item == null) {
            continue;
          }
          processedGrantIds.add(grantId);
          final level = _grantItemLevel(grant['level']);
          if (_applyGrantedItem(item, level: level)) {
            grantedItem = true;
          }
          final title = grant['title']?.toString().trim() ?? 'アイテム付与';
          final message =
              grant['message']?.toString().trim() ?? '${item.name}を受け取りました。';
          rewardLogs.add('$title\n$message');
          claimedGrantLogs.add(_claimedAdminGrantLog(
            grantId: grantId,
            grantType: grantType,
            title: title,
            message: message,
            coins: 0,
          ));
          continue;
        }
        if (grantType == 'items') {
          final rawItems = grant['items'];
          if (rawItems is! List) {
            continue;
          }
          var appliedAny = false;
          for (final rawItem in rawItems) {
            if (rawItem is! Map) {
              continue;
            }
            final itemId = rawItem['itemId']?.toString().trim() ?? '';
            final item = GameItemCatalog.byId(itemId);
            if (item == null) {
              continue;
            }
            if (_applyGrantedItem(
              item,
              level: _grantItemLevel(rawItem['level']),
            )) {
              appliedAny = true;
            }
          }
          if (!appliedAny) {
            continue;
          }
          processedGrantIds.add(grantId);
          grantedItem = true;
          final title = grant['title']?.toString().trim() ?? 'アイテム付与';
          final message =
              grant['message']?.toString().trim() ?? 'アイテムを受け取りました。';
          rewardLogs.add('$title\n$message');
          claimedGrantLogs.add(_claimedAdminGrantLog(
            grantId: grantId,
            grantType: grantType,
            title: title,
            message: message,
            coins: 0,
          ));
          continue;
        }
        final coins = _intValue(grant['coins']);
        if (coins == null || coins <= 0) {
          continue;
        }
        totalCoins += coins;
        processedGrantIds.add(grantId);
        if (grantType == 'invite_reward' && grant['role'] == 'invitee') {
          completedOwnInvite = true;
        }
        final title = grant['title']?.toString().trim() ?? '';
        final rawMessage = grant['message']?.toString().trim() ?? '';
        final message = _claimedAdminGrantDisplayMessage(rawMessage);
        if (title.isNotEmpty || message.isNotEmpty) {
          rewardLogs.add([
            if (title.isNotEmpty) title,
            if (message.isNotEmpty) message,
            if (message.isEmpty) '$coinsコインを受け取りました。',
          ].join('\n'));
        } else {
          rewardLogs.add('$coinsコインを受け取りました。');
        }
        claimedGrantLogs.add(_claimedAdminGrantLog(
          grantId: grantId,
          grantType: grantType,
          title: title,
          message: message,
          coins: coins,
        ));
      }

      if ((totalCoins <= 0 && !grantedAdRemoval && !grantedItem) ||
          processedGrantIds.isEmpty) {
        return false;
      }

      if (totalCoins > 0) {
        _coins += totalCoins;
      }
      if (grantedAdRemoval) {
        await AppSettings.instance.setAdsRemoved(true);
      }
      if (grantedItem) {
        await _saveItems();
      }
      await _saveEconomy();
      await grantsRef.update({
        for (final grantId in processedGrantIds) grantId: null,
      });
      unawaited(_writeClaimedAdminGrantLogs(
        uid: uid,
        claimedGrantLogs: claimedGrantLogs,
      ));
      await _storePendingAdminGrantLogs(rewardLogs);
      if (completedOwnInvite) {
        await InviteManager.instance.markCompletedLocally();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  String _claimedAdminGrantDisplayMessage(String message) {
    if (message.isEmpty) {
      return message;
    }
    return message
        .replaceAll('コインを受け取れます。', 'コインを受け取りました。')
        .replaceAll('コインを受け取れます', 'コインを受け取りました');
  }

  Map<String, Object?> _claimedAdminGrantLog({
    required String grantId,
    required String grantType,
    required String title,
    required String message,
    required int coins,
  }) {
    return {
      'grantId': grantId,
      'type': grantType.isEmpty ? 'coin' : grantType,
      if (title.isNotEmpty) 'title': title,
      if (message.isNotEmpty) 'message': message,
      if (coins > 0) 'coins': coins,
      'claimedAt': ServerValue.timestamp,
      'claimedAtText': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _writeClaimedAdminGrantLogs({
    required String uid,
    required List<Map<String, Object?>> claimedGrantLogs,
  }) async {
    if (claimedGrantLogs.isEmpty) {
      return;
    }
    try {
      final updates = <String, Object?>{};
      for (final log in claimedGrantLogs) {
        final grantId = log['grantId']?.toString().trim() ?? '';
        if (grantId.isEmpty) {
          continue;
        }
        updates['claimedAdminGrants/$uid/$grantId'] = log;
      }
      if (updates.isNotEmpty) {
        await AppFirebaseDatabase.ref()
            .update(updates)
            .timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      // 受取済みログの保存失敗で報酬付与自体は巻き戻さない。
    }
  }

  int _grantItemLevel(Object? value) {
    return (_intValue(value) ?? 1).clamp(1, GameItem.maxStampLevel);
  }

  bool _applyGrantedItem(GameItem item, {required int level}) {
    final existingIndex =
        _ownedItems.indexWhere((ownedItem) => ownedItem.id == item.id);
    final storedItem = item.isStamp ? item.copyWith(level: level) : item;
    if (existingIndex < 0) {
      _ownedItems.add(storedItem);
      unawaited(_markCollectionItemUnseen(storedItem.id));
      return true;
    }
    final existing = _ownedItems[existingIndex];
    if (existing.isStamp && level > existing.level) {
      _ownedItems[existingIndex] = existing.copyWith(level: level);
      return true;
    }
    return false;
  }

  Future<void> checkDailyReset() async {
    await load();
    final today = _todayKey();
    final previousStatsDate = _todayStatsDate;
    final shouldSnapshotPreviousToday =
        previousStatsDate.isNotEmpty && previousStatsDate != today;
    var changed = false;
    var statsChanged = false;

    if (shouldSnapshotPreviousToday) {
      await syncRecordSummary(force: true);
    }

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
    final hasRequiredDailyMission =
        missionIds.contains(MissionCatalog.requiredDailyMissionId);
    final hasTemporarilyDisabledMissions =
        missionIds.any(MissionCatalog.isTemporarilyDisabledMissionId);

    if (_lastDailyReset != today ||
        _currentMissions.length != 4 ||
        !hasSpecialDailyMission ||
        !hasRequiredDailyMission ||
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
    unawaited(_incrementDailyEconomy(coinsSpent: amount));
  }

  Future<void> addCoins(int amount) async {
    await load();
    if (amount <= 0) {
      return;
    }
    _coins += amount;
    await _saveEconomy();
    unawaited(_incrementDailyEconomy(coinsEarned: amount));
  }

  Future<void> setCoinsForDebug(int amount) async {
    if (!_debugControlsEnabled) {
      return;
    }
    await load();
    _coins = max(0, amount);
    await _saveEconomy();
  }

  Future<bool> claimPendingServerGrants() async {
    await load();
    final uid = await AuthManager.instance.ensureSignedIn();
    if (uid.isEmpty) {
      return false;
    }
    return _claimAdminGrants(uid);
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
    unawaited(_incrementDailyEconomy(expEarned: amount));

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

  Future<void> addCollectionMedals(int amount) async {
    await load();
    if (amount <= 0) {
      return;
    }
    _collectionMedals += amount;
    await _saveEconomy();
  }

  Future<void> spendCollectionMedals(int amount) async {
    await load();
    if (amount <= 0) {
      return;
    }
    if (_collectionMedals < amount) {
      throw StateError('コレクションメダルが不足しています。');
    }
    _collectionMedals -= amount;
    await _saveEconomy();
  }

  Future<ItemGrantResult> addOrUpgradeItem(GameItem item) async {
    await load();

    final existingIndex = _ownedItems.indexWhere(
      (ownedItem) => ownedItem.id == item.id,
    );

    if (existingIndex == -1) {
      if (_isImplicitlyUnlockedCollectionItem(item)) {
        final storedItem = item.isStamp ? item.copyWith(level: 1) : item;
        _ownedItems.add(storedItem);
        final medalReward = _collectionMedalsForDuplicate(storedItem);
        _collectionMedals += medalReward;
        await _saveEconomy();
        await _saveItems();
        if (storedItem.isAudio) {
          await AudioSelectionManager.setOwnedAudioItemIds(
            _ownedItems.where((ownedItem) => ownedItem.isAudio).map(
                  (ownedItem) => ownedItem.id,
                ),
          );
        }
        return ItemGrantResult(
          item: storedItem,
          isDuplicate: true,
          leveledUp: false,
          convertedToScrap: false,
          cyberScrapAdded: 0,
          collectionMedalsAdded: medalReward,
        );
      }
      final storedItem = item.isStamp ? item.copyWith(level: 1) : item;
      _ownedItems.add(storedItem);
      await _saveItems();
      if (storedItem.isAudio) {
        await AudioSelectionManager.setOwnedAudioItemIds(
          _ownedItems.where((ownedItem) => ownedItem.isAudio).map(
                (ownedItem) => ownedItem.id,
              ),
        );
      }
      await _markCollectionItemUnseen(storedItem.id);
      return ItemGrantResult(
        item: storedItem,
        isDuplicate: false,
        leveledUp: false,
        convertedToScrap: false,
        cyberScrapAdded: 0,
        collectionMedalsAdded: 0,
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
        collectionMedalsAdded: 0,
      );
    }

    final medalReward = _collectionMedalsForDuplicate(existing);
    _collectionMedals += medalReward;
    await _saveEconomy();
    await _saveItems();
    return ItemGrantResult(
      item: existing,
      isDuplicate: true,
      leveledUp: false,
      convertedToScrap: false,
      cyberScrapAdded: 0,
      collectionMedalsAdded: medalReward,
    );
  }

  bool _isImplicitlyUnlockedCollectionItem(GameItem item) {
    if (item.isAudio) {
      return AudioSelectionManager.isAudioUnlocked(
        playerName: displayPlayerName,
        itemId: item.id,
      );
    }
    if (item.isEffect) {
      return _ownsEffectSkin(item.id);
    }
    if (item.isIcon || item.isFrame || item.isBanner || item.isSkin) {
      return _ownsEquippableItem(item.id, item.type);
    }
    return false;
  }

  int _collectionMedalsForDuplicate(GameItem item) {
    if (item.rarity == ItemRarity.legendary || item.colorName == 'rainbow') {
      return 100;
    }
    switch (item.type) {
      case ItemType.stamp:
        return 5;
      case ItemType.icon:
      case ItemType.frame:
      case ItemType.banner:
        return 10;
      case ItemType.vfx:
      case ItemType.audio:
        return 50;
      case ItemType.skin:
        return 100;
    }
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
    await _syncRecordSummarySafely(force: previousName != _playerName);
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
    await _syncRecordSummarySafely(force: true);
  }

  Future<void> setEquippedBadgeIds(List<String> badgeIds) async {
    await load();
    final ownedSeasonBadgeIds =
        _seasonRankBadges.map((badge) => badge.id).toSet();
    final unlocked = {...unlockedBadgeIds, ...ownedSeasonBadgeIds};
    _equippedBadgeIds = badgeIds
        .map((id) => _normalizeEquippedBadgeId(
              id,
              ownedSeasonBadgeIds: ownedSeasonBadgeIds,
            ))
        .where((id) => unlocked.contains(id))
        .fold<List<String>>(<String>[], (items, id) {
      if (!items.contains(id) && items.length < 3) {
        items.add(id);
      }
      return items;
    });
    await _savePublicProfile();
    await _syncRecordSummarySafely(force: true);
  }

  Future<void> setEquippedStampIds(List<String> stampIds) async {
    await load();
    final ownedStampIds = _ownedItems
        .where((item) => item.isStamp)
        .map((item) => item.id)
        .toSet();
    _equippedStampIds = _normalizeEquippedStampSlots(stampIds, ownedStampIds);
    await _saveEquippedStamps();
    await _syncRecordSummarySafely(force: true);
  }

  List<String> _normalizeEquippedStampSlots(
    List<String> stampIds,
    Set<String> ownedStampIds,
  ) {
    final normalized = <String>[];
    final actualStampIds = <String>{};
    for (final id in stampIds) {
      if (normalized.length >= maxEquippedStampCount) {
        break;
      }
      if (id == emptyStampSlotId) {
        normalized.add(id);
        continue;
      }
      if (ownedStampIds.contains(id) && actualStampIds.add(id)) {
        normalized.add(id);
      }
    }
    if (actualStampIds.isNotEmpty || ownedStampIds.isEmpty) {
      return normalized;
    }
    final defaultOwnedStampIds = GameItemCatalog.defaultStamps
        .map((stamp) => stamp.id)
        .where(ownedStampIds.contains)
        .take(maxEquippedStampCount)
        .toList();
    return defaultOwnedStampIds.isNotEmpty
        ? defaultOwnedStampIds
        : ownedStampIds.take(maxEquippedStampCount).toList();
  }

  Future<void> setSeasonRankBadges(List<SeasonRankBadge> badges) async {
    await load();
    _seasonRankBadges = badges
        .where((badge) => badge.seasonId.isNotEmpty && badge.rank > 0)
        .toList()
      ..sort((a, b) {
        final kindDiff = a.kind.index.compareTo(b.kind.index);
        if (kindDiff != 0) {
          return kindDiff;
        }
        return b.seasonId.compareTo(a.seasonId);
      });
    for (final badge in _seasonRankBadges) {
      if (badge.kind == SeasonRankBadgeKind.ranked &&
          (_bestRankedRank <= 0 || badge.rank < _bestRankedRank)) {
        _bestRankedRank = badge.rank;
      }
    }
    final ownedSeasonBadgeIds =
        _seasonRankBadges.map((badge) => badge.id).toSet();
    _equippedBadgeIds = _equippedBadgeIds
        .map((id) => _normalizeEquippedBadgeId(
              id,
              ownedSeasonBadgeIds: ownedSeasonBadgeIds,
            ))
        .where((id) =>
            unlockedBadgeIds.contains(id) || ownedSeasonBadgeIds.contains(id))
        .fold<List<String>>(<String>[], (items, id) {
      if (!items.contains(id) && items.length < 3) {
        items.add(id);
      }
      return items;
    });
    await _saveSeasonRankBadges();
    await _savePublicProfile();
    await _syncRecordSummarySafely(force: true);
  }

  String _normalizeEquippedBadgeId(
    String id, {
    required Set<String> ownedSeasonBadgeIds,
  }) {
    final seasonBadge = SeasonRankBadge.fromId(id);
    if (seasonBadge != null) {
      if (ownedSeasonBadgeIds.contains(id)) {
        return id;
      }
      for (final ownedBadge in _seasonRankBadges) {
        if (ownedBadge.seasonId == seasonBadge.seasonId &&
            ownedBadge.rank == seasonBadge.rank &&
            ownedSeasonBadgeIds.contains(ownedBadge.id)) {
          return ownedBadge.id;
        }
      }
      return id;
    }
    return BadgeCatalog.evolvedBadgeIdFor(
      id,
      {
        ...unlockedBadgeIds,
        ...ownedSeasonBadgeIds,
      },
    );
  }

  Future<void> setEquippedBallSkinId(String skinId) async {
    await load();
    final normalized = _normalizeBallSkinId(skinId);
    if (!_ownsEquippableItem(normalized, ItemType.skin)) {
      return;
    }
    _equippedBallSkinId = normalized;
    await _savePublicProfile();
    await _syncRecordSummarySafely(force: true);
  }

  Future<void> setEquippedFormationEffectId(String effectId) async {
    await load();
    final normalized = effectId.trim().isEmpty
        ? EffectSkinCatalog.defaultFormationId
        : effectId.trim();
    if (!EffectSkinCatalog.isFormation(normalized)) {
      return;
    }
    if (!_ownsEffectSkin(normalized)) {
      return;
    }
    _equippedFormationEffectId = normalized;
    await _savePublicProfile();
    await _syncRecordSummarySafely(force: true);
  }

  Future<void> setEquippedOjamaEffectId(String effectId) async {
    await load();
    final normalized = effectId.trim().isEmpty
        ? EffectSkinCatalog.defaultOjamaId
        : effectId.trim();
    if (!EffectSkinCatalog.isOjama(normalized)) {
      return;
    }
    if (!_ownsEffectSkin(normalized)) {
      return;
    }
    _equippedOjamaEffectId = normalized;
    await _savePublicProfile();
    await _syncRecordSummarySafely(force: true);
  }

  Future<void> setEquippedPlayerIconId(String iconId) async {
    await load();
    final normalized = iconId.trim().isEmpty ? 'default' : iconId.trim();
    if (!_ownsEquippableItem(normalized, ItemType.icon)) {
      return;
    }
    _equippedPlayerIconId = normalized;
    await _savePublicProfile();
    await _syncRecordSummarySafely(force: true);
  }

  Future<void> setEquippedIconFrameId(String frameId) async {
    await load();
    final normalized = frameId.trim().isEmpty ? 'default' : frameId.trim();
    if (!_ownsEquippableItem(normalized, ItemType.frame)) {
      return;
    }
    _equippedIconFrameId = normalized;
    await _savePublicProfile();
    await _syncRecordSummarySafely(force: true);
  }

  Future<void> setEquippedProfileBannerId(String bannerId) async {
    await load();
    final normalized = bannerId.trim().isEmpty ? 'default' : bannerId.trim();
    if (!_ownsEquippableItem(normalized, ItemType.banner)) {
      return;
    }
    _equippedProfileBannerId = normalized;
    await _savePublicProfile();
    await _syncRecordSummarySafely(force: true);
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
    _rankedSeasonId = '';
    _seasonRankedWins = 0;
    _seasonRankedLosses = 0;
    _seasonRankedMaxWinStreak = 0;
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
    _endlessSeasonId = '';
    _seasonEndlessHighScore = 0;
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
    _cpuDifficultyRecords = {
      'weak_matches': 0,
      'weak_wins': 0,
      'normal_matches': 0,
      'normal_wins': 0,
      'strong_matches': 0,
      'strong_wins': 0,
      'oni_matches': 0,
      'oni_wins': 0,
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
    bool isPvp = false,
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
      final safeScore = score.clamp(0, maxEndlessScore).toInt();
      _highestEndlessScore = max(_highestEndlessScore, safeScore);
      _seasonEndlessHighScore = max(_seasonEndlessHighScore, safeScore);
    }
    if (mode == 'RANKED') {
      if (isWin) {
        _rankedWins++;
        _rankedCurrentWinStreak++;
        _rankedMaxWinStreak = max(_rankedMaxWinStreak, _rankedCurrentWinStreak);
        _seasonRankedMaxWinStreak =
            max(_seasonRankedMaxWinStreak, _rankedCurrentWinStreak);
        _seasonRankedWins++;
      } else {
        _rankedCurrentWinStreak = 0;
        _seasonRankedLosses++;
      }
    }
    _modePlayCounts[mode] = (_modePlayCounts[mode] ?? 0) + 1;
    if (mode == 'CPU') {
      _recordCpuDifficultyResult(opponentName: opponentName, isWin: isWin);
    }
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
    unawaited(_syncGlobalDailyStatsIncrement(
      isWin: isWin,
      mode: mode,
      wazaCounts: wazaCounts,
      clearedBalls: clearedBalls,
      normalClearedBalls: normalClearedBalls,
      maxChain: maxChain,
      score: score,
      ratingDelta: ratingDelta,
      isPvp: isPvp,
    ));
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
    await _syncRecordSummarySafely(force: true);
    unawaited(_requestInviteCompletionIfNeeded(mode: mode));
  }

  Future<void> ensureEndlessSeason({
    required String currentSeasonId,
    int? currentSeasonScore,
    bool hasCurrentSeasonRecord = false,
  }) async {
    await load();
    final resolvedSeasonId = currentSeasonId.trim();
    if (resolvedSeasonId.isEmpty) {
      return;
    }
    final safeCurrentScore =
        (currentSeasonScore ?? 0).clamp(0, maxEndlessScore).toInt();
    if (_endlessSeasonId == resolvedSeasonId) {
      if (hasCurrentSeasonRecord &&
          safeCurrentScore > _seasonEndlessHighScore) {
        _seasonEndlessHighScore = safeCurrentScore;
        await _saveStats();
        await _syncRecordSummarySafely(force: true);
      }
      return;
    }

    _endlessSeasonId = resolvedSeasonId;
    _seasonEndlessHighScore = hasCurrentSeasonRecord ? safeCurrentScore : 0;
    await _saveStats();
    await _syncRecordSummarySafely(force: true);
  }

  Future<void> _requestInviteCompletionIfNeeded({required String mode}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(InviteManager.localStatusKey) != 'pending') {
        return;
      }
      final uid = await AuthManager.instance.ensureSignedIn();
      if (uid.isEmpty) {
        return;
      }
      await AppFirebaseDatabase.ref().child('inviteCompletions/$uid').set({
        'uid': uid,
        'mode': mode,
        'totalMatches': _totalMatches,
        'requestedAt': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 3));
    } catch (_) {
      // 招待報酬の成立通知に失敗してもゲーム結果保存は止めない。
    }
  }

  Future<void> _syncGlobalDailyStatsIncrement({
    required bool isWin,
    required String mode,
    required Map<String, int> wazaCounts,
    required int clearedBalls,
    required int normalClearedBalls,
    required int maxChain,
    int? score,
    int? ratingDelta,
    bool isPvp = false,
  }) async {
    try {
      final uid = await AuthManager.instance.ensureSignedIn();
      if (uid.isEmpty) {
        return;
      }
      final date = _todayStatsDate.isEmpty ? _todayKey() : _todayStatsDate;
      final safeMode = _sanitizeDatabaseKey(mode);
      final statsMode = safeMode == 'SOLO' ? 'ENDLESS' : safeMode;
      final isRankedPvp = mode == 'RANKED' && isPvp;
      final isFriendPvp = mode == 'FRIEND';
      final updates = <String, Object?>{
        'date': date,
        'updatedAt': ServerValue.timestamp,
        'activePlayers/$uid/uid': uid,
        'activePlayers/$uid/publicId': _playerId,
        'activePlayers/$uid/displayName': displayPlayerName,
        'activePlayers/$uid/updatedAt': ServerValue.timestamp,
        'totals/matches': ServerValue.increment(1),
        'totals/wins': ServerValue.increment(isWin ? 1 : 0),
        'totals/losses': ServerValue.increment(isWin ? 0 : 1),
        'totals/clearedBalls': ServerValue.increment(max(0, clearedBalls)),
        'totals/normalClearedBalls':
            ServerValue.increment(max(0, normalClearedBalls)),
        'modePlayCounts/$statsMode': ServerValue.increment(1),
      };
      if (isRankedPvp) {
        updates['modePlayCounts/RANKED_PVP'] = ServerValue.increment(1);
      }
      if (isFriendPvp || isRankedPvp) {
        updates['modePlayCounts/VERSUS'] = ServerValue.increment(1);
      }
      if (mode == 'RANKED') {
        updates['ranked/matches'] = ServerValue.increment(1);
        updates['ranked/wins'] = ServerValue.increment(isWin ? 1 : 0);
        updates['ranked/losses'] = ServerValue.increment(isWin ? 0 : 1);
        updates['ranked/ratingDelta'] = ServerValue.increment(ratingDelta ?? 0);
      }
      for (final entry in wazaCounts.entries) {
        updates['formationCounts/${_sanitizeDatabaseKey(entry.key)}'] =
            ServerValue.increment(max(0, entry.value));
      }
      await AppFirebaseDatabase.ref()
          .child('adminStats/dailyRawStats/$date')
          .update(updates);
    } catch (_) {
      // 全体統計の加算失敗でゲーム結果保存を止めない。
    }
  }

  String _sanitizeDatabaseKey(String value) {
    final key = value.trim().replaceAll(RegExp(r'[\.\#\$\[\]/]'), '_');
    return key.isEmpty ? 'UNKNOWN' : key;
  }

  void _recordCpuDifficultyResult({
    required String opponentName,
    required bool isWin,
  }) {
    final key = _cpuDifficultyKeyForName(opponentName);
    _cpuDifficultyRecords['${key}_matches'] =
        (_cpuDifficultyRecords['${key}_matches'] ?? 0) + 1;
    if (isWin) {
      _cpuDifficultyRecords['${key}_wins'] =
          (_cpuDifficultyRecords['${key}_wins'] ?? 0) + 1;
    }
  }

  String _cpuDifficultyKeyForName(String opponentName) {
    final name = opponentName.trim();
    if (name.contains('鬼') || name.toLowerCase().contains('oni')) {
      return 'oni';
    }
    if (name.contains('強') ||
        name.contains('つよ') ||
        name.toLowerCase().contains('hard')) {
      return 'strong';
    }
    if (name.contains('普通') ||
        name.contains('ふつう') ||
        name.toLowerCase().contains('normal')) {
      return 'normal';
    }
    return 'weak';
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
    await _syncRecordSummarySafely(force: true);
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
    int? currentSeasonRating,
    bool hasCurrentSeasonRecord = false,
    int? currentSeasonWins,
    int? currentSeasonLosses,
    required String previousSeasonName,
    int? previousFinalRank,
    int? previousFinalRating,
    int? previousSeasonWins,
    int? previousSeasonLosses,
  }) async {
    await load();
    if (_rankedSeasonId == currentSeasonId) {
      final resolvedSeasonRating = currentSeasonRating;
      final hasLocalSeasonRecord = _seasonRankedWins + _seasonRankedLosses > 0;
      if (!_isPlausibleRankedSeasonRating(
        rating: _currentRating,
        wins: _seasonRankedWins,
        losses: _seasonRankedLosses,
      )) {
        _currentRating = 1000;
        _seasonRankedWins = 0;
        _seasonRankedLosses = 0;
        _seasonRankedMaxWinStreak = 0;
        _rankedCurrentWinStreak = 0;
        await _savePublicProfile();
        await _saveStats();
        await _syncRecordSummarySafely(force: true);
        return;
      }
      if (hasCurrentSeasonRecord &&
          resolvedSeasonRating != null &&
          _currentRating != resolvedSeasonRating) {
        _currentRating = resolvedSeasonRating;
        _highestRating = max(_highestRating, resolvedSeasonRating);
        await _savePublicProfile();
        await _saveStats();
        await _syncRecordSummarySafely(force: true);
      } else if (!hasCurrentSeasonRecord &&
          !hasLocalSeasonRecord &&
          _currentRating != 1000) {
        _currentRating = 1000;
        await _savePublicProfile();
        await _saveStats();
        await _syncRecordSummarySafely(force: true);
      }
      return;
    }

    final hadRankedSeason = _rankedSeasonId.isNotEmpty;
    final shouldTreatLegacyRatingAsPreviousSeason = _rankedSeasonId.isEmpty &&
        currentSeasonId != RankedSeasonManager.baseSeasonId &&
        _currentRating != 1000;
    final shouldResetFromPreviousSeason =
        hadRankedSeason || shouldTreatLegacyRatingAsPreviousSeason;
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
      if (previousFinalRank != null &&
          previousFinalRank > 0 &&
          (_bestRankedRank <= 0 || previousFinalRank < _bestRankedRank)) {
        _bestRankedRank = previousFinalRank;
      }
    }

    final remoteSeasonWins = currentSeasonWins ?? 0;
    final remoteSeasonLosses = currentSeasonLosses ?? 0;
    final remoteSeasonRating = currentSeasonRating ?? 1000;
    final canUseCurrentSeasonRecord = hasCurrentSeasonRecord &&
        _isPlausibleRankedSeasonRating(
          rating: remoteSeasonRating,
          wins: remoteSeasonWins,
          losses: remoteSeasonLosses,
        );

    _rankedSeasonId = currentSeasonId;
    _seasonRankedWins = canUseCurrentSeasonRecord ? remoteSeasonWins : 0;
    _seasonRankedLosses = canUseCurrentSeasonRecord ? remoteSeasonLosses : 0;
    _seasonRankedMaxWinStreak = 0;
    _rankedCurrentWinStreak =
        shouldResetFromPreviousSeason || !canUseCurrentSeasonRecord
            ? 0
            : _rankedCurrentWinStreak;
    _currentRating = canUseCurrentSeasonRecord ? remoteSeasonRating : 1000;
    _highestRating = max(_highestRating, _currentRating);
    await _savePublicProfile();
    await _saveStats();
    await _syncRecordSummarySafely(force: true);
  }

  bool _isPlausibleRankedSeasonRating({
    required int rating,
    required int wins,
    required int losses,
  }) {
    final safeWins = max(0, wins);
    final safeLosses = max(0, losses);
    final maxReachable = 1000 + safeWins * 95 - safeLosses * 5;
    final minReachable = 1000 + safeWins * 5 - safeLosses * 95;
    return rating >= minReachable && rating <= maxReachable;
  }

  Future<void> syncRecordSummary({
    bool force = false,
    bool rethrowErrors = false,
  }) async {
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

    final database = AppFirebaseDatabase.ref();
    final syncedAt = DateTime.now();
    final nextLookupKey = _nameLookupKey(displayPlayerName);
    final previousLookupKey = _nameLookupKey(previousName);
    Object? syncError;
    StackTrace? syncStackTrace;

    Future<void> runSyncStep(Future<void> Function() step) async {
      try {
        await step();
      } catch (error, stackTrace) {
        syncError ??= error;
        syncStackTrace ??= stackTrace;
      }
    }

    var recordSynced = false;

    await runSyncStep(() async {
      final recordPayload = await _recordSummaryPayloadForDatabase(
        database: database,
        uid: uid,
        summary: summary,
        syncedAt: syncedAt,
      );
      await Future.wait([
        database.child('playerRecordSummaries/$uid').set(recordPayload),
        database
            .child('publicProfiles/$uid')
            .set(_publicProfilePayload(recordPayload)),
        if (nameChanged &&
            previousName.trim().isNotEmpty &&
            previousLookupKey != nextLookupKey)
          database.child('playerNameLookup/$previousLookupKey/$uid').remove(),
        database.child('playerNameLookup/$nextLookupKey/$uid').set({
          'uid': uid,
          'publicId': _playerId,
          'displayName': displayPlayerName,
          'updatedAt': ServerValue.timestamp,
        }),
      ]);
      await _syncGlobalDailyLogin(database: database, uid: uid);
      recordSynced = true;
    });

    if (recordSynced) {
      await prefs.setString(_recordSummaryLastHashKey, hash);
      await prefs.setInt(_recordSummaryLastSyncAtKey, now);
      await prefs.setString(_recordSummaryLastNameKey, displayPlayerName);
      await prefs.setInt(
        _recordSummarySchemaVersionKey,
        _recordSummarySchemaVersion,
      );
      return;
    }

    if (rethrowErrors && syncError != null) {
      Error.throwWithStackTrace(
        syncError!,
        syncStackTrace ?? StackTrace.current,
      );
    }
    if (syncError != null) {
      // 管理用サマリーの同期失敗で、プレイ中の保存処理は止めない。
    }
  }

  void _syncRecordSummaryInBackground({bool force = false}) {
    unawaited(_syncRecordSummarySafely(force: force));
  }

  String _nameLookupKey(String name) {
    final normalized = name.trim().toLowerCase();
    final key = normalized
        .replaceAll(RegExp(r'[\.\#\$\[\]/]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return key.isEmpty ? 'player' : key;
  }

  Future<Map<String, Object?>> _recordSummaryPayloadForDatabase({
    required DatabaseReference database,
    required String uid,
    required Map<String, dynamic> summary,
    required DateTime syncedAt,
  }) async {
    final payload = Map<String, dynamic>.from(summary);
    final ranked = Map<String, dynamic>.from(
      (payload['ranked'] as Map?) ?? const <String, dynamic>{},
    );
    final remotePlacements = await _remoteDailyWinRankPlacements(
      database: database,
      uid: uid,
    );
    final placements = <String, int>{...remotePlacements};
    for (final entry in _dailyWinRankPlacements.entries) {
      placements[entry.key] = max(placements[entry.key] ?? 0, entry.value);
    }
    if (placements.isNotEmpty) {
      ranked['dailyWinRankPlacements'] = placements;
    }
    payload['ranked'] = ranked;
    payload['updatedAt'] = ServerValue.timestamp;
    payload['updatedAtText'] = _formatDateTimeForDatabase(syncedAt);
    payload['lastSeenAtText'] = _formatDateTimeForDatabase(syncedAt);
    return Map<String, Object?>.from(_sanitizeDatabaseValue(payload) as Map);
  }

  Map<String, Object?> _publicProfilePayload(Map<String, Object?> summary) {
    final overall =
        Map<String, Object?>.from((summary['overall'] as Map?) ?? const {});
    final economy =
        Map<String, Object?>.from((summary['economy'] as Map?) ?? const {});
    final collection =
        Map<String, Object?>.from((summary['collection'] as Map?) ?? const {});
    final ranked =
        Map<String, Object?>.from((summary['ranked'] as Map?) ?? const {});
    final endless =
        Map<String, Object?>.from((summary['endless'] as Map?) ?? const {});
    final payload = <String, Object?>{
      'uid': summary['uid'],
      'publicId': summary['publicId'],
      'displayName': summary['displayName'],
      'updatedAt': summary['updatedAt'],
      'overall': {
        'totalWins': overall['totalWins'],
        'totalClearedBalls': overall['totalClearedBalls'],
      },
      'economy': {
        'level': economy['level'],
      },
      'collection': {
        'equippedPlayerIconId': collection['equippedPlayerIconId'],
        'equippedIconFrameId': collection['equippedIconFrameId'],
        'equippedProfileBannerId': collection['equippedProfileBannerId'],
        'equippedBadgeIds': collection['equippedBadgeIds'],
        'unlockedBadgeIds': collection['unlockedBadgeIds'],
        'seasonRankBadges': collection['seasonRankBadges'],
      },
      'ranked': {
        'currentRating': ranked['currentRating'],
        'highestRating': ranked['highestRating'],
        'maxWinStreak': ranked['maxWinStreak'],
        'bestRankedRank': ranked['bestRankedRank'],
      },
      'endless': {
        'highestScore': endless['highestScore'],
      },
      'wazaCounts': summary['wazaCounts'],
    };
    return Map<String, Object?>.from(_sanitizeDatabaseValue(payload) as Map);
  }

  Future<Map<String, int>> _remoteDailyWinRankPlacements({
    required DatabaseReference database,
    required String uid,
  }) async {
    try {
      final snapshot = await database
          .child('playerRecordSummaries/$uid/ranked/dailyWinRankPlacements')
          .get()
          .timeout(const Duration(seconds: 2));
      return _intMapFromDynamic(snapshot.value);
    } catch (_) {
      return const {};
    }
  }

  Future<void> _syncGlobalDailyLogin({
    required DatabaseReference database,
    required String uid,
  }) async {
    final date = _todayStatsDate.isEmpty ? _todayKey() : _todayStatsDate;
    await database.child('adminStats/dailyRawStats/$date').update({
      'date': date,
      'updatedAt': ServerValue.timestamp,
      'activePlayers/$uid/uid': uid,
      'activePlayers/$uid/publicId': _playerId,
      'activePlayers/$uid/displayName': displayPlayerName,
      'activePlayers/$uid/updatedAt': ServerValue.timestamp,
    });
  }

  Future<void> _incrementDailyEconomy({
    int coinsEarned = 0,
    int coinsSpent = 0,
    int expEarned = 0,
  }) async {
    final earned = max(0, coinsEarned);
    final spent = max(0, coinsSpent);
    final exp = max(0, expEarned);
    if (earned == 0 && spent == 0 && exp == 0) {
      return;
    }
    try {
      await load();
      final date = _todayStatsDate.isEmpty ? _todayKey() : _todayStatsDate;
      final updates = <String, Object?>{
        'date': date,
        'updatedAt': ServerValue.timestamp,
        if (earned > 0) 'economy/coinsEarned': ServerValue.increment(earned),
        if (spent > 0) 'economy/coinsSpent': ServerValue.increment(spent),
        if (earned != spent)
          'economy/netCoins': ServerValue.increment(earned - spent),
        if (exp > 0) 'economy/expEarned': ServerValue.increment(exp),
      };
      await AppFirebaseDatabase.ref()
          .child('adminStats/dailyRawStats/$date')
          .update(updates);
    } catch (_) {
      // 日別経済統計の加算失敗でプレイヤーの報酬処理は止めない。
    }
  }

  Object? _sanitizeDatabaseValue(Object? value) {
    if (value is Map) {
      if (value.keys.any((key) => key.toString().startsWith('.'))) {
        return value;
      }
      return {
        for (final entry in value.entries)
          _databasePathKey(entry.key): _sanitizeDatabaseValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_sanitizeDatabaseValue).toList();
    }
    return value;
  }

  String _databasePathKey(Object? key) {
    final sanitized =
        key.toString().trim().replaceAll(RegExp(r'[\.\#\$\[\]/]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
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
    await prefs.setInt(_collectionMedalsKey, _collectionMedals);
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
    await prefs.setString(
      _equippedFormationEffectIdKey,
      _equippedFormationEffectId,
    );
    await prefs.setString(_equippedOjamaEffectIdKey, _equippedOjamaEffectId);
    await prefs.setString(_equippedPlayerIconIdKey, _equippedPlayerIconId);
    await prefs.setString(_equippedIconFrameIdKey, _equippedIconFrameId);
    await prefs.setString(
      _equippedProfileBannerIdKey,
      _equippedProfileBannerId,
    );
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
    await prefs.setString(_endlessSeasonIdKey, _endlessSeasonId);
    await prefs.setInt(
      _seasonEndlessHighScoreKey,
      _seasonEndlessHighScore.clamp(0, maxEndlessScore).toInt(),
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
    await prefs.setInt(_seasonRankedMaxWinStreakKey, _seasonRankedMaxWinStreak);
    await prefs.setInt(_arenaPerfectClearCountKey, _arenaPerfectClearCount);
    await prefs.setString(_wazaCountsKey, jsonEncode(_wazaCounts));
    await prefs.setString(_modePlayCountsKey, jsonEncode(_modePlayCounts));
    await prefs.setString(
      _cpuDifficultyRecordsKey,
      jsonEncode(_cpuDifficultyRecords),
    );
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

  Future<List<String>> consumePendingAdminGrantLogs() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingAdminGrantLogsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    await prefs.remove(_pendingAdminGrantLogsKey);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((entry) => entry.toString().trim())
            .where((entry) => entry.isNotEmpty)
            .toList();
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  List<Map<String, dynamic>> _generateDailyMissions() {
    final activeDailyPool = MissionCatalog.activeDailyPool;
    final rewardedMission = activeDailyPool.firstWhere(
      (mission) => mission.id == MissionCatalog.rewardedAdMissionIds.first,
    );
    final dailyMission = activeDailyPool.firstWhere(
      (mission) => mission.id == MissionCatalog.requiredDailyMissionId,
    );
    final pool = activeDailyPool
        .where((mission) =>
            !MissionCatalog.isRewardedAdMissionId(mission.id) &&
            mission.id != MissionCatalog.requiredDailyMissionId)
        .toList()
      ..shuffle(_random);
    return [
      rewardedMission.toMissionMap(),
      dailyMission.toMissionMap(),
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

  bool _removeRetiredCollectionItems() {
    var changed = false;
    final allowAllCollections =
        displayPlayerName == AudioSelectionManager.allAudioUnlockedPlayerName;
    final filteredItems = _ownedItems
        .where((item) =>
            item.id != retiredPrismSkinId &&
            (allowAllCollections || !item.isSkin))
        .toList();
    if (filteredItems.length != _ownedItems.length) {
      _ownedItems = filteredItems;
      changed = true;
    }
    if (_equippedBallSkinId == retiredPrismSkinId ||
        (!allowAllCollections && _equippedBallSkinId != 'default')) {
      _equippedBallSkinId = 'default';
      changed = true;
    }
    final normalizedBallSkin = _normalizeBallSkinId(_equippedBallSkinId);
    if (normalizedBallSkin != _equippedBallSkinId) {
      _equippedBallSkinId = normalizedBallSkin;
      changed = true;
    }
    return changed;
  }

  GameItem _canonicalItem(GameItem item) {
    final catalogItem = GameItemCatalog.byId(_normalizeBallSkinId(item.id));
    if (catalogItem == null) {
      return item;
    }
    return catalogItem.copyWith(level: item.level);
  }

  String _normalizeBallSkinId(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return 'default';
    }
    if (normalized.startsWith('skin_hexa_orbit_')) {
      return 'skin_orbit';
    }
    return normalized;
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
        'adsRemoved': AppSettings.instance.adsRemoved.value,
      },
      'collection': {
        'ownedItemCount': ownedItems.length,
        'ownedItems': ownedItems,
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
        'ownedBannerIds': _ownedItems
            .where((item) => item.type == ItemType.banner)
            .map((item) => item.id)
            .toList(),
        'equippedBallSkinId': _equippedBallSkinId,
        'equippedFormationEffectId': _equippedFormationEffectId,
        'equippedOjamaEffectId': _equippedOjamaEffectId,
        'equippedPlayerIconId': _equippedPlayerIconId,
        'equippedIconFrameId': _equippedIconFrameId,
        'equippedProfileBannerId': _equippedProfileBannerId,
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
        'seasonMaxWinStreak': _seasonRankedMaxWinStreak,
        'currentRating': _currentRating,
        'highestRating': _highestRating,
        'currentWinStreak': _rankedCurrentWinStreak,
        'maxWinStreak': _rankedMaxWinStreak,
        'bestRankedRank': _bestRankedRank,
      },
      'endless': {
        'playCount': _modePlayCounts['SOLO'] ?? 0,
        'highestScore': _highestEndlessScore,
        'seasonId': _endlessSeasonId,
        'seasonHighestScore': _seasonEndlessHighScore,
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
    Map<String, int> record(String key) {
      final matches = _cpuDifficultyRecords['${key}_matches'] ?? 0;
      final wins = _cpuDifficultyRecords['${key}_wins'] ?? 0;
      return {
        'matches': matches,
        'wins': wins,
        'losses': max(0, matches - wins),
      };
    }

    return {
      'matches': _modePlayCounts['CPU'] ?? 0,
      'byDifficulty': {
        'weak': record('weak'),
        'normal': record('normal'),
        'strong': record('strong'),
        'oni': record('oni'),
      },
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
        ? 'Lv.$previousLevel → Lv.$currentLevel\nレベルアップ報酬として $rewardCoins コインを獲得しました。'
        : 'Lv.$previousLevel → Lv.$currentLevel\nレベルアップ報酬として合計 $rewardCoins コインを獲得しました。';
    await prefs.setString(_pendingLevelUpRewardLogKey, message);
  }

  Future<void> _storePendingAdminGrantLogs(List<String> logs) async {
    final normalized =
        logs.map((log) => log.trim()).where((log) => log.isNotEmpty).toList();
    if (normalized.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final current = <String>[];
    final raw = prefs.getString(_pendingAdminGrantLogsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          current.addAll(decoded.map((entry) => entry.toString()));
        }
      } catch (_) {
        // 壊れた古い通知ログは今回の通知で上書きする。
      }
    }
    await prefs.setString(
      _pendingAdminGrantLogsKey,
      jsonEncode([...current, ...normalized].take(8).toList()),
    );
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
    final result = <String, int>{};
    void addPlacement(Object? key, Object? value) {
      final keyText = key?.toString() ?? '';
      final intValue = _intValue(value);
      if (intValue != null) {
        result[keyText] = (result[keyText] ?? 0) + intValue;
        return;
      }
      if (value is Map) {
        for (final nested in value.entries) {
          addPlacement(nested.key, nested.value);
        }
      }
    }

    for (final entry in raw.entries) {
      addPlacement(entry.key, entry.value);
    }
    return result;
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
    final normalized = type == ItemType.skin ? _normalizeBallSkinId(id) : id;
    if (normalized == 'default') {
      return true;
    }
    if (displayPlayerName == AudioSelectionManager.allAudioUnlockedPlayerName) {
      return true;
    }
    return _ownedItems
        .any((item) => item.id == normalized && item.type == type);
  }

  bool _ownsEffectSkin(String id) {
    if (id == EffectSkinCatalog.defaultFormationId ||
        id == EffectSkinCatalog.defaultOjamaId) {
      return true;
    }
    if (displayPlayerName == AudioSelectionManager.allAudioUnlockedPlayerName) {
      return true;
    }
    return _ownedItems.any((item) => item.id == id && item.isEffect);
  }
}
