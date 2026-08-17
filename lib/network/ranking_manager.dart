import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../data/models/badge_item.dart';
import '../data/player_data_manager.dart';
import '../firebase_database_provider.dart';
import 'endless_season_manager.dart';
import 'multiplayer_manager.dart';
import 'ranked_season_manager.dart';
import 'server_time_manager.dart';

class RankingEntry {
  const RankingEntry({
    required this.uid,
    required this.displayName,
    required this.rating,
    this.publicId = '',
    this.updatedAt,
    this.dailyWins = 0,
    this.dailyWinDate = '',
    this.seasonWins = 0,
    this.seasonLosses = 0,
    this.highestEndlessScore = 0,
    this.finalRank,
  });

  final String uid;
  final String displayName;
  final int rating;
  final String publicId;
  final int? updatedAt;
  final int dailyWins;
  final String dailyWinDate;
  final int seasonWins;
  final int seasonLosses;
  final int highestEndlessScore;
  final int? finalRank;

  factory RankingEntry.fromMap(String uid, Map<dynamic, dynamic> data) {
    return RankingEntry(
      uid: uid,
      displayName: _normalizeName(data['displayName'] as String?) ??
          _normalizeName(data['name'] as String?) ??
          'Player',
      rating: _intValue(data['rating']) ?? MultiplayerManager.initialRating,
      publicId: data['publicId']?.toString() ?? '',
      updatedAt: _intValue(data['updatedAt']),
      dailyWins: _intValue(data['dailyWins']) ?? 0,
      dailyWinDate: data['dailyWinDate']?.toString() ?? '',
      seasonWins: _intValue(data['seasonWins']) ?? 0,
      seasonLosses: _intValue(data['seasonLosses']) ?? 0,
      highestEndlessScore: ((_intValue(data['highestEndlessScore']) ?? 0)
              .clamp(0, PlayerDataManager.maxEndlessScore))
          .toInt(),
      finalRank: _intValue(data['rank']),
    );
  }

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  static String? _normalizeName(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

class RankingSummary {
  const RankingSummary({
    required this.ratingRankLabel,
    required this.dailyWinRankLabel,
    required this.dailyWins,
  });

  final String ratingRankLabel;
  final String dailyWinRankLabel;
  final int dailyWins;
}

class RankingManager {
  RankingManager._internal();

  static final RankingManager _instance = RankingManager._internal();

  factory RankingManager() => _instance;

  static RankingManager get instance => _instance;

  static const int _rankingLimit = 100;
  static const int _rankingFetchLimit = 300;
  static const int _minimumListedRating = 1001;
  static const int _finalTop100SchemaVersion = 6;
  static const Duration _rankingCacheTtl = Duration(minutes: 5);
  static const Duration _summaryCacheTtl = Duration(minutes: 5);
  static const Duration _unchangedPushTtl = Duration(minutes: 10);
  static const String _lastPushPrefix = 'ranking_last_push_v2_';
  static const String _pendingRankedResultSyncsKey =
      'ranking_pending_ranked_result_syncs_v1';
  static const int _pendingRankedResultSyncLimit = 12;

  List<RankingEntry>? _topRatingCache;
  DateTime? _topRatingCacheAt;
  String? _topRatingCacheSeasonId;
  List<RankingEntry>? _topDailyCache;
  DateTime? _topDailyCacheAt;
  String? _topDailyCacheKey;
  List<RankingEntry>? _topEndlessCache;
  DateTime? _topEndlessCacheAt;
  String? _topEndlessCacheSeasonId;
  List<RankingEntry>? _topAllTimeEndlessCache;
  DateTime? _topAllTimeEndlessCacheAt;
  List<String>? _archivedSeasonIdsCache;
  DateTime? _archivedSeasonIdsCacheAt;
  List<String>? _archivedEndlessSeasonIdsCache;
  DateTime? _archivedEndlessSeasonIdsCacheAt;
  final Map<String, List<RankingEntry>> _seasonRankingsCache = {};
  final Map<String, DateTime> _seasonRankingsCacheAt = {};
  final Map<String, List<RankingEntry>> _endlessSeasonRankingsCache = {};
  final Map<String, DateTime> _endlessSeasonRankingsCacheAt = {};
  final Map<String, List<SeasonRankBadge>> _seasonRankBadgesCache = {};
  final Map<String, DateTime> _seasonRankBadgesCacheAt = {};
  RankingSummary? _summaryCache;
  DateTime? _summaryCacheAt;
  String? _summaryCacheSeasonId;

  DatabaseReference get _db {
    return AppFirebaseDatabase.ref();
  }

  RankingSummary? cachedMySummary() {
    if (_summaryCache == null ||
        !_isCacheFresh(_summaryCacheAt, _summaryCacheTtl)) {
      return null;
    }
    return _summaryCache;
  }

  static String dailyRemainingLabel({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      return '残り--';
    }
    final wallClockNow = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    final nextDay = DateTime.utc(now.year, now.month, now.day + 1);
    final remaining = nextDay.difference(wallClockNow);
    final value = remaining.isNegative ? Duration.zero : remaining;
    if (value.inHours >= 1) {
      return '残り${value.inHours}時間';
    }
    if (value.inMinutes >= 1) {
      return '残り${value.inMinutes}分';
    }
    return '残り${value.inSeconds.toString().padLeft(2, '0')}秒';
  }

  static String todayKeyJst({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      throw StateError('todayKeyJst requires server based JST time.');
    }
    return _dateKey(now);
  }

  static String endlessRemainingLabel({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      return '残り--';
    }
    return EndlessSeasonManager.remainingLabel(nowJstOverride: now);
  }

  Future<void> updateMyRating({
    String? uid,
    String? displayName,
    required int rating,
    bool incrementDailyWin = false,
    bool incrementSeasonLoss = false,
    int? seasonWinsOverride,
    int? seasonLossesOverride,
    int? dailyWinsOverride,
    bool auditRankedResult = false,
    String auditReason = 'profile_sync',
  }) async {
    final clock = await _rankingClock(forceRefresh: true);
    final authUid = await AuthManager.instance.ensureSignedIn();
    MultiplayerManager.instance.myUid = authUid;
    final resolvedUid = (uid != null && uid == authUid) ? uid : authUid;
    if (resolvedUid.isEmpty) {
      return;
    }

    final seasonId = clock.currentSeasonId;
    final endlessSeasonId = clock.currentEndlessSeasonId;
    await PlayerDataManager.instance.load();
    if (PlayerDataManager.instance.rankedSeasonId != seasonId ||
        !_isPlausibleSeasonRating(
          rating: PlayerDataManager.instance.currentRating,
          wins: PlayerDataManager.instance.seasonRankedWins,
          losses: PlayerDataManager.instance.seasonRankedLosses,
        )) {
      await syncSeasonStateForCurrentPlayer();
      await PlayerDataManager.instance.load();
      if (PlayerDataManager.instance.rankedSeasonId != seasonId) {
        throw StateError('ランク戦のシーズン同期に失敗しました。');
      }
      if (!incrementDailyWin && !incrementSeasonLoss) {
        rating = PlayerDataManager.instance.currentRating;
      }
    }
    final savedPlayerName = PlayerDataManager.instance.playerName.trim();
    final resolvedName = (displayName ?? savedPlayerName).trim().isEmpty
        ? PlayerDataManager.instance.displayPlayerName
        : (displayName ?? savedPlayerName).trim();
    final publicId = PlayerDataManager.instance.playerId;
    final highestEndlessScore = PlayerDataManager.instance.highestEndlessScore
        .clamp(0, PlayerDataManager.maxEndlessScore)
        .toInt();
    await syncEndlessSeasonStateForCurrentPlayer(
      currentEndlessSeasonId: endlessSeasonId,
      uid: resolvedUid,
      publicId: publicId,
    );
    final seasonEndlessHighScore = PlayerDataManager
        .instance.seasonEndlessHighScore
        .clamp(0, PlayerDataManager.maxEndlessScore)
        .toInt();
    final today = _dateKey(clock.nowJst);
    final seasonEntryRef = _seasonRankingRef(seasonId).child(resolvedUid);
    final endlessSeasonEntryRef =
        _endlessSeasonRankingRef(endlessSeasonId).child(resolvedUid);
    final allTimeEndlessEntryRef =
        _allTimeEndlessRankingRef().child(resolvedUid);
    final prefs = await SharedPreferences.getInstance();
    final pushKey =
        '$_lastPushPrefix${seasonId}_${endlessSeasonId}_$resolvedUid';

    final hasAbsoluteSeasonOverrides =
        seasonWinsOverride != null || seasonLossesOverride != null;
    final hasAbsoluteDailyOverride = dailyWinsOverride != null;

    if (!incrementDailyWin &&
        !incrementSeasonLoss &&
        !hasAbsoluteSeasonOverrides &&
        !hasAbsoluteDailyOverride &&
        !auditRankedResult &&
        _isRecentUnchangedPush(
          prefs: prefs,
          key: pushKey,
          displayName: resolvedName,
          publicId: publicId,
          rating: rating,
          highestEndlessScore: highestEndlessScore,
          seasonEndlessHighScore: seasonEndlessHighScore,
        )) {
      return;
    }

    final seasonPayload = await _buildRankingUpdatePayload(
      entryRef: seasonEntryRef,
      uid: resolvedUid,
      publicId: publicId,
      displayName: resolvedName,
      rating: rating,
      highestEndlessScore: highestEndlessScore,
      today: today,
      incrementDailyWin: incrementDailyWin,
      incrementSeasonLoss: incrementSeasonLoss,
      seasonWinsOverride: seasonWinsOverride,
      seasonLossesOverride: seasonLossesOverride,
      dailyWinsOverride: dailyWinsOverride,
    );
    final endlessPayload = _buildEndlessRankingUpdatePayload(
      uid: resolvedUid,
      publicId: publicId,
      displayName: resolvedName,
      highestEndlessScore: seasonEndlessHighScore,
    );
    final dailyWinRankingPayload = seasonPayload.remove('dailyWinRanking');

    final futures = <Future<void>>[
      seasonEntryRef.update(seasonPayload),
      _syncProfileRatingFields(
        uid: resolvedUid,
        displayName: resolvedName,
        publicId: publicId,
        rating: rating,
      ),
    ];
    if (highestEndlessScore > 0) {
      futures.add(
        allTimeEndlessEntryRef.update(
          _buildAllTimeEndlessRankingUpdatePayload(
            uid: resolvedUid,
            publicId: publicId,
            displayName: resolvedName,
            highestEndlessScore: highestEndlessScore,
          ),
        ),
      );
    }
    if (seasonEndlessHighScore > 0) {
      futures.add(endlessSeasonEntryRef.update(endlessPayload));
    }
    if (dailyWinRankingPayload is Map<String, Object?>) {
      futures.add(
        _dailyWinRankingRef(today)
            .child(resolvedUid)
            .set(dailyWinRankingPayload),
      );
    }
    await Future.wait(futures);
    if (auditRankedResult) {
      await _writeRankedResultSyncAudit(
        uid: resolvedUid,
        publicId: publicId,
        displayName: resolvedName,
        seasonId: seasonId,
        rating: rating,
        seasonWins: seasonWinsOverride,
        seasonLosses: seasonLossesOverride,
        dailyWins: dailyWinsOverride,
        status: 'success',
        reason: auditReason,
      );
    }
    await _saveLastPush(
      prefs: prefs,
      key: pushKey,
      displayName: resolvedName,
      publicId: publicId,
      rating: rating,
      highestEndlessScore: highestEndlessScore,
      seasonEndlessHighScore: seasonEndlessHighScore,
    );
    _invalidateCaches();
  }

  Future<void> syncRankedResultAbsolute({
    required int rating,
    required bool isWin,
    String reason = 'ranked_result',
  }) async {
    await PlayerDataManager.instance.load();
    final clock = await _rankingClock(forceRefresh: true);
    final seasonWins = PlayerDataManager.instance.seasonRankedWins;
    final seasonLosses = PlayerDataManager.instance.seasonRankedLosses;
    final dailyWins = PlayerDataManager.instance.todayRankedWins;
    final seasonId = PlayerDataManager.instance.rankedSeasonId;
    if (seasonId.isEmpty || seasonId != clock.currentSeasonId) {
      await _writeRankedResultSyncAudit(
        uid: await AuthManager.instance.ensureSignedIn(),
        publicId: PlayerDataManager.instance.playerId,
        displayName: PlayerDataManager.instance.displayPlayerName,
        seasonId: seasonId.isEmpty ? clock.currentSeasonId : seasonId,
        rating: rating,
        seasonWins: seasonWins,
        seasonLosses: seasonLosses,
        dailyWins: dailyWins,
        status: 'skipped',
        reason: 'season_mismatch_$reason',
      );
      return;
    }
    try {
      await updateMyRating(
        rating: rating,
        displayName: PlayerDataManager.instance.displayPlayerName,
        seasonWinsOverride: seasonWins,
        seasonLossesOverride: seasonLosses,
        dailyWinsOverride: dailyWins,
        auditRankedResult: true,
        auditReason: reason,
      );
      await _removePendingRankedResultSync(seasonId: seasonId);
    } catch (error) {
      await _writeRankedResultSyncAudit(
        uid: await AuthManager.instance.ensureSignedIn(),
        publicId: PlayerDataManager.instance.playerId,
        displayName: PlayerDataManager.instance.displayPlayerName,
        seasonId: seasonId,
        rating: rating,
        seasonWins: seasonWins,
        seasonLosses: seasonLosses,
        dailyWins: dailyWins,
        status: 'failed',
        reason: reason,
        error: error.toString(),
      );
      await _storePendingRankedResultSync(
        seasonId: seasonId,
        rating: rating,
        seasonWins: seasonWins,
        seasonLosses: seasonLosses,
        dailyWins: dailyWins,
        isWin: isWin,
        reason: reason,
      );
      rethrow;
    }
  }

  Future<void> retryPendingRankedResultSyncs() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = _pendingRankedResultSyncs(prefs);
    if (pending.isEmpty) {
      return;
    }
    final remaining = <Map<String, Object?>>[];
    final clock = await _rankingClock(forceRefresh: true);
    for (final entry in pending) {
      final seasonId = entry['seasonId']?.toString() ?? '';
      final rating = RankingEntry._intValue(entry['rating']) ?? 0;
      if (seasonId.isEmpty || rating <= 0) {
        continue;
      }
      if (seasonId != clock.currentSeasonId) {
        continue;
      }
      try {
        await updateMyRating(
          rating: rating,
          displayName: PlayerDataManager.instance.displayPlayerName,
          seasonWinsOverride: RankingEntry._intValue(entry['seasonWins']) ?? 0,
          seasonLossesOverride:
              RankingEntry._intValue(entry['seasonLosses']) ?? 0,
          dailyWinsOverride: RankingEntry._intValue(entry['dailyWins']) ?? 0,
          auditRankedResult: true,
          auditReason: 'pending_retry',
        );
      } catch (_) {
        remaining.add(entry);
      }
    }
    await _savePendingRankedResultSyncs(prefs, remaining);
  }

  Future<void> _syncProfileRatingFields({
    required String uid,
    required String displayName,
    required String publicId,
    required int rating,
  }) async {
    final lookupKey = _nameLookupKey(displayName);
    final syncedAtText = DateTime.now().toIso8601String();
    final payload = <String, Object?>{
      'playerRecordSummaries/$uid/displayName': displayName,
      'playerRecordSummaries/$uid/publicId': publicId,
      'playerRecordSummaries/$uid/ranked/currentRating': rating,
      'playerRecordSummaries/$uid/updatedAt': ServerValue.timestamp,
      'playerRecordSummaries/$uid/updatedAtText': syncedAtText,
      'playerRecordSummaries/$uid/lastSeenAtText': syncedAtText,
      'users/$uid/rating': rating,
      'users/$uid/updatedAt': ServerValue.timestamp,
      'playerNameLookup/$lookupKey/$uid/uid': uid,
      'playerNameLookup/$lookupKey/$uid/publicId': publicId,
      'playerNameLookup/$lookupKey/$uid/displayName': displayName,
      'playerNameLookup/$lookupKey/$uid/updatedAt': ServerValue.timestamp,
    };
    await _db.update(payload);
  }

  String _nameLookupKey(String name) {
    final normalized = name.trim().toLowerCase();
    final key = normalized
        .replaceAll(RegExp(r'[\.\#\$\[\]/]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return key.isEmpty ? 'player' : key;
  }

  Future<void> syncEndlessScore({
    String? uid,
    String? displayName,
  }) async {
    final resolvedUid = uid ?? await AuthManager.instance.ensureSignedIn();
    if (resolvedUid.isEmpty) {
      return;
    }

    await PlayerDataManager.instance.load();
    final savedPlayerName = PlayerDataManager.instance.playerName.trim();
    if (savedPlayerName.isEmpty) {
      return;
    }
    final resolvedName = (displayName ?? savedPlayerName).trim();
    if (resolvedName.isEmpty) {
      return;
    }
    final highestEndlessScore = PlayerDataManager.instance.highestEndlessScore
        .clamp(0, PlayerDataManager.maxEndlessScore)
        .toInt();
    final publicId = PlayerDataManager.instance.playerId;
    final clock = await _rankingClock(forceRefresh: true);
    final endlessSeasonId = clock.currentEndlessSeasonId;
    await syncEndlessSeasonStateForCurrentPlayer(
      currentEndlessSeasonId: endlessSeasonId,
      uid: resolvedUid,
      publicId: publicId,
    );
    final seasonEndlessHighScore = PlayerDataManager
        .instance.seasonEndlessHighScore
        .clamp(0, PlayerDataManager.maxEndlessScore)
        .toInt();
    final allTimePayload = _buildAllTimeEndlessRankingUpdatePayload(
      uid: resolvedUid,
      publicId: publicId,
      displayName: resolvedName,
      highestEndlessScore: highestEndlessScore,
    );
    final futures = <Future<void>>[
      if (highestEndlessScore > 0)
        _allTimeEndlessRankingRef().child(resolvedUid).update(allTimePayload),
    ];
    if (seasonEndlessHighScore > 0) {
      final seasonPayload = _buildEndlessRankingUpdatePayload(
        uid: resolvedUid,
        publicId: publicId,
        displayName: resolvedName,
        highestEndlessScore: seasonEndlessHighScore,
      );
      futures.add(
        _endlessSeasonRankingRef(endlessSeasonId)
            .child(resolvedUid)
            .update(seasonPayload),
      );
    }
    await Future.wait(futures);
    await _syncProfileRatingFields(
      uid: resolvedUid,
      displayName: resolvedName,
      publicId: publicId,
      rating: PlayerDataManager.instance.currentRating,
    );
    _topEndlessCache = null;
    _topEndlessCacheAt = null;
    _topAllTimeEndlessCache = null;
    _topAllTimeEndlessCacheAt = null;
  }

  Future<RankingEntry?> fetchCurrentEntryForPlayer({
    required String uid,
    required String publicId,
  }) async {
    final clock = await _rankingClock(forceRefresh: true);
    final seasonId = clock.currentSeasonId;
    final seasonEntry = await _fetchEntryByUidOrPublicId(
      _seasonRankingRef(seasonId),
      uid: uid,
      publicId: publicId,
    );
    return seasonEntry;
  }

  Future<RankingEntry?> fetchCurrentSeasonEntryForPlayer({
    required String uid,
    required String publicId,
  }) async {
    final clock = await _rankingClock(forceRefresh: true);
    return _fetchEntryByUidOrPublicId(
      _seasonRankingRef(clock.currentSeasonId),
      uid: uid,
      publicId: publicId,
    );
  }

  Future<List<RankingEntry>> fetchTopRankings({
    bool forceRefresh = false,
  }) async {
    final clock = await _rankingClock();
    final seasonId = clock.currentSeasonId;
    if (!forceRefresh &&
        _topRatingCacheSeasonId == seasonId &&
        _isCacheFresh(_topRatingCacheAt)) {
      return List<RankingEntry>.from(_topRatingCache!);
    }
    final entries = await _fetchTopRatingEntries(seasonId: seasonId)
      ..sort((a, b) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) {
          return ratingDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
    _topRatingCache = _rankableEntries(entries).take(_rankingLimit).toList();
    _topRatingCacheAt = DateTime.now();
    _topRatingCacheSeasonId = seasonId;
    return List<RankingEntry>.from(_topRatingCache!);
  }

  Future<String> fetchRatingRankLabelForPlayer({
    required String uid,
    required String publicId,
  }) async {
    final entries = await fetchTopRankings();
    final index = entries.indexWhere(
      (entry) =>
          (uid.isNotEmpty && entry.uid == uid) ||
          (publicId.isNotEmpty && entry.publicId == publicId),
    );
    if (index == -1) {
      return '圏外';
    }
    final rank = _displayRankAt(entries, index);
    return rank > _rankingLimit ? '圏外' : '$rank位';
  }

  Future<RankingSummary> fetchMySummary({
    bool forceRefresh = false,
  }) async {
    final clock = await _rankingClock();
    final currentSeasonId = clock.currentSeasonId;
    if (!forceRefresh &&
        _summaryCache != null &&
        _summaryCacheSeasonId == currentSeasonId &&
        _isCacheFresh(_summaryCacheAt, _summaryCacheTtl)) {
      return _summaryCache!;
    }
    final uid = MultiplayerManager.instance.myUid ??
        await AuthManager.instance.ensureSignedIn();
    await PlayerDataManager.instance.load();
    final publicId = PlayerDataManager.instance.playerId;
    final today = _dateKey(clock.nowJst);
    final seasonId = currentSeasonId;
    final mySnapshot = await _seasonRankingRef(seasonId).child(uid).get();
    final myEntry = mySnapshot.value is Map
        ? RankingEntry.fromMap(
            uid,
            mySnapshot.value as Map<dynamic, dynamic>,
          )
        : null;
    final ratingEntries = await fetchTopRankings(forceRefresh: forceRefresh);
    final dailyEntries =
        await fetchTopDailyWinRankings(forceRefresh: forceRefresh);
    final myIndex = ratingEntries.indexWhere(
      (entry) => _matchesCurrentPlayer(
        entry: entry,
        uid: uid,
        publicId: publicId,
      ),
    );
    final dailyIndex = dailyEntries.indexWhere(
      (entry) => _matchesCurrentPlayer(
        entry: entry,
        uid: uid,
        publicId: publicId,
      ),
    );
    int? ratingRank =
        myIndex == -1 ? null : _displayRankAt(ratingEntries, myIndex);
    int? dailyRank =
        dailyIndex == -1 ? null : _displayDailyRankAt(dailyEntries, dailyIndex);
    int resolvedDailyWins = dailyIndex == -1
        ? (myEntry?.dailyWinDate == today ? myEntry!.dailyWins : 0)
        : dailyEntries[dailyIndex].dailyWins;

    if (ratingRank != null && ratingRank <= _rankingLimit) {
      await PlayerDataManager.instance.recordBestRankedRank(ratingRank);
    }
    final summary = RankingSummary(
      ratingRankLabel: ratingRank == null || ratingRank > _rankingLimit
          ? '圏外'
          : '$ratingRank位',
      dailyWinRankLabel:
          dailyRank == null || dailyRank > _rankingLimit ? '圏外' : '$dailyRank位',
      dailyWins: resolvedDailyWins,
    );
    _summaryCache = summary;
    _summaryCacheAt = DateTime.now();
    _summaryCacheSeasonId = seasonId;
    return summary;
  }

  Future<void> clearAllRankings() async {
    await _db.child('rankedSeasons').remove();
  }

  Future<List<RankingEntry>> fetchTopDailyWinRankings({
    bool forceRefresh = false,
  }) async {
    final clock = await _rankingClock();
    final today = _dateKey(clock.nowJst);
    final seasonIds = _dailyRankingSeasonIds(
      today,
      currentSeasonId: clock.currentSeasonId,
    );
    final cacheKey = '$today|${seasonIds.join(',')}';
    if (!forceRefresh &&
        _topDailyCacheKey == cacheKey &&
        _isCacheFresh(_topDailyCacheAt)) {
      return List<RankingEntry>.from(_topDailyCache!);
    }
    final entries = await _fetchDailyEntriesForDate(
      today,
      currentSeasonId: clock.currentSeasonId,
    )
      ..sort((a, b) {
        final winDiff = b.dailyWins.compareTo(a.dailyWins);
        if (winDiff != 0) {
          return winDiff;
        }
        return b.rating.compareTo(a.rating);
      });
    _topDailyCache = entries.take(_rankingLimit).toList();
    _topDailyCacheAt = DateTime.now();
    _topDailyCacheKey = cacheKey;
    return List<RankingEntry>.from(_topDailyCache!);
  }

  Future<List<RankingEntry>> fetchYesterdayDailyWinRankings() async {
    final clock = await _rankingClock(forceRefresh: true);
    final yesterday = _dateKey(clock.nowJst.subtract(const Duration(days: 1)));
    final entries = await _fetchDailyEntriesForDate(
      yesterday,
      currentSeasonId: clock.currentSeasonId,
    )
      ..sort((a, b) {
        final winDiff = b.dailyWins.compareTo(a.dailyWins);
        if (winDiff != 0) {
          return winDiff;
        }
        return b.rating.compareTo(a.rating);
      });
    return entries.take(_rankingLimit).toList();
  }

  Future<List<RankingEntry>> fetchTopEndlessScoreRankings({
    bool forceRefresh = false,
  }) async {
    final clock = await _rankingClock();
    final seasonId = clock.currentEndlessSeasonId;
    if (!forceRefresh &&
        _topEndlessCacheSeasonId == seasonId &&
        _isCacheFresh(_topEndlessCacheAt)) {
      return List<RankingEntry>.from(_topEndlessCache!);
    }
    await AuthManager.instance.ensureSignedIn();
    final entries = (await _fetchTopEndlessEntries(seasonId: seasonId))
        .where((entry) => entry.highestEndlessScore > 0)
        .toList()
      ..sort((a, b) {
        final scoreDiff =
            b.highestEndlessScore.compareTo(a.highestEndlessScore);
        if (scoreDiff != 0) {
          return scoreDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
    _topEndlessCache = entries.take(_rankingLimit).toList();
    _topEndlessCacheAt = DateTime.now();
    _topEndlessCacheSeasonId = seasonId;
    return List<RankingEntry>.from(_topEndlessCache!);
  }

  Future<List<RankingEntry>> fetchAllTimeEndlessScoreRankings({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _isCacheFresh(_topAllTimeEndlessCacheAt)) {
      return List<RankingEntry>.from(_topAllTimeEndlessCache!);
    }
    await AuthManager.instance.ensureSignedIn();
    final snapshot = await _allTimeEndlessRankingRef()
        .orderByChild('highestEndlessScore')
        .limitToLast(_rankingLimit)
        .get();
    final entries = _dedupeEndlessRankingEntries(_entriesFromSnapshot(snapshot))
        .where((entry) => entry.highestEndlessScore > 0)
        .toList()
      ..sort((a, b) {
        final scoreDiff =
            b.highestEndlessScore.compareTo(a.highestEndlessScore);
        if (scoreDiff != 0) {
          return scoreDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
    _topAllTimeEndlessCache = entries.take(_rankingLimit).toList();
    _topAllTimeEndlessCacheAt = DateTime.now();
    return List<RankingEntry>.from(_topAllTimeEndlessCache!);
  }

  Future<List<String>> fetchArchivedSeasonIds() async {
    if (_isCacheFresh(_archivedSeasonIdsCacheAt, const Duration(minutes: 5))) {
      return List<String>.from(_archivedSeasonIdsCache!);
    }
    final clock = await _rankingClock();
    final current = clock.currentSeasonId;
    final archivedSnapshot =
        await _db.child('rankedSeasons/archivedSeasonIds').get();
    final rawArchived = archivedSnapshot.value;
    if (rawArchived is Map) {
      final sorted = rawArchived.entries
          .where((entry) => entry.value == true && '${entry.key}' != current)
          .map((entry) => '${entry.key}')
          .where((seasonId) {
        return RankedSeasonManager.seasonNumber(seasonId) >=
            RankedSeasonManager.baseSeasonNumber;
      }).toList()
        ..sort((a, b) => b.compareTo(a));
      _archivedSeasonIdsCache = sorted;
      _archivedSeasonIdsCacheAt = DateTime.now();
      return List<String>.from(sorted);
    }
    final candidates = _rankedArchivedSeasonCandidates(current);
    final checks = await Future.wait(
      candidates.map((seasonId) async {
        final snapshot =
            await _db.child('rankedSeasons/seasons/$seasonId/finalized').get();
        return snapshot.value == true ? seasonId : null;
      }),
    );
    final sorted = checks.whereType<String>().toList()
      ..sort((a, b) => b.compareTo(a));
    _archivedSeasonIdsCache = sorted;
    _archivedSeasonIdsCacheAt = DateTime.now();
    return List<String>.from(sorted);
  }

  List<String> _rankedArchivedSeasonCandidates(String currentSeasonId) {
    final candidates = <String>[];
    var cursor = RankedSeasonManager.previousSeasonId(currentSeasonId);
    while (RankedSeasonManager.seasonNumber(cursor) >=
        RankedSeasonManager.baseSeasonNumber) {
      candidates.add(cursor);
      if (cursor == RankedSeasonManager.baseSeasonId) {
        break;
      }
      cursor = RankedSeasonManager.previousSeasonId(cursor);
    }
    return candidates;
  }

  Future<List<String>> fetchArchivedEndlessSeasonIds() async {
    if (_isCacheFresh(
        _archivedEndlessSeasonIdsCacheAt, const Duration(minutes: 5))) {
      return List<String>.from(_archivedEndlessSeasonIdsCache!);
    }
    final snapshot = await _db.child('endlessSeasons/archivedSeasonIds').get();
    final raw = snapshot.value;
    if (raw is! Map) {
      _archivedEndlessSeasonIdsCache = const [];
      _archivedEndlessSeasonIdsCacheAt = DateTime.now();
      return const [];
    }
    final clock = await _rankingClock();
    final current = clock.currentEndlessSeasonId;
    final seasonIds =
        raw.entries.where((entry) => '${entry.key}' != current).map((entry) {
      return '${entry.key}';
    }).toList()
          ..sort((a, b) => b.compareTo(a));
    _archivedEndlessSeasonIdsCache = seasonIds;
    _archivedEndlessSeasonIdsCacheAt = DateTime.now();
    return List<String>.from(seasonIds);
  }

  Future<List<RankingEntry>> fetchSeasonRankings(
    String seasonId, {
    bool finalizedOnly = true,
  }) async {
    final clock = await _rankingClock();
    if (seasonId == clock.currentSeasonId) {
      return fetchTopRankings();
    }
    final cacheKey = '$seasonId|$finalizedOnly';
    if (_isCacheFresh(
        _seasonRankingsCacheAt[cacheKey], const Duration(minutes: 5))) {
      return List<RankingEntry>.from(_seasonRankingsCache[cacheKey]!);
    }
    final ref = finalizedOnly
        ? _db.child('rankedSeasons/seasons/$seasonId/finalTop100')
        : _seasonRankingRef(seasonId);
    final entries =
        await _fetchRankingsFromRef(ref, applyRatingFilter: !finalizedOnly);
    _seasonRankingsCache[cacheKey] = entries;
    _seasonRankingsCacheAt[cacheKey] = DateTime.now();
    return List<RankingEntry>.from(entries);
  }

  Future<List<RankingEntry>> fetchEndlessSeasonRankings(String seasonId) async {
    final clock = await _rankingClock();
    if (seasonId == clock.currentEndlessSeasonId) {
      return fetchTopEndlessScoreRankings();
    }
    if (_isCacheFresh(
        _endlessSeasonRankingsCacheAt[seasonId], const Duration(minutes: 5))) {
      return List<RankingEntry>.from(_endlessSeasonRankingsCache[seasonId]!);
    }
    final entries = await _fetchRankingsFromRef(
      _db.child('endlessSeasons/seasons/$seasonId/finalTop100'),
      applyRatingFilter: false,
    );
    _endlessSeasonRankingsCache[seasonId] = entries;
    _endlessSeasonRankingsCacheAt[seasonId] = DateTime.now();
    return List<RankingEntry>.from(entries);
  }

  Future<List<RankingEntry>> _fetchRankingsFromRef(
    DatabaseReference ref, {
    bool applyRatingFilter = true,
  }) async {
    final snapshot = await ref.get();
    final raw = snapshot.value;
    final records = _rankingRecords(raw);
    if (records.isEmpty) {
      return const [];
    }
    final parsedEntries = records
        .where((record) => record.value is Map<dynamic, dynamic>)
        .map(
          (record) => RankingEntry.fromMap(
            '${(record.value as Map<dynamic, dynamic>)['uid'] ?? record.key}',
            record.value as Map<dynamic, dynamic>,
          ),
        )
        .where((entry) => entry.uid.isNotEmpty)
        .toList();
    final entries =
        (applyRatingFilter ? _rankableEntries(parsedEntries) : parsedEntries)
          ..sort((a, b) {
            if (a.finalRank != null && b.finalRank != null) {
              return a.finalRank!.compareTo(b.finalRank!);
            }
            final ratingDiff = b.rating.compareTo(a.rating);
            if (ratingDiff != 0) return ratingDiff;
            return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
          });
    return entries.take(_rankingLimit).toList();
  }

  Future<void> syncSeasonStateForCurrentPlayer() async {
    final clock = await _rankingClock();
    final currentSeasonId = clock.currentSeasonId;
    final previousSeasonId =
        RankedSeasonManager.previousSeasonId(currentSeasonId);
    await finalizeSeasonIfNeeded(previousSeasonId);

    final uid = MultiplayerManager.instance.myUid ??
        await AuthManager.instance.ensureSignedIn();
    await PlayerDataManager.instance.load();
    final playerData = PlayerDataManager.instance;
    final publicId = PlayerDataManager.instance.playerId;
    final currentEntry = await _fetchEntryByUidOrPublicId(
      _seasonRankingRef(currentSeasonId),
      uid: uid,
      publicId: publicId,
    );
    final shouldBootstrapBlankCurrentSeason =
        currentEntry == null &&
            playerData.rankedSeasonId.trim().isEmpty &&
            (playerData.seasonRankedWins + playerData.seasonRankedLosses) > 0 &&
            !playerData.accountCreatedAt.isBefore(
              RankedSeasonManager.seasonStartJst(currentSeasonId),
            ) &&
            _isPlausibleSeasonRating(
              rating: playerData.currentRating,
              wins: playerData.seasonRankedWins,
              losses: playerData.seasonRankedLosses,
            );
    final previousEntries = await fetchSeasonRankings(previousSeasonId);
    final previousIndex = previousEntries.indexWhere(
      (entry) => _matchesCurrentPlayer(
        entry: entry,
        uid: uid,
        publicId: publicId,
      ),
    );
    final previousEntry =
        previousIndex == -1 ? null : previousEntries[previousIndex];
    final previousRank = previousEntry?.finalRank ??
        (previousIndex == -1 ? null : previousIndex + 1);

    await PlayerDataManager.instance.ensureRankedSeason(
      currentSeasonId: currentSeasonId,
      currentSeasonRating: _hasSeasonRecord(currentEntry)
          ? currentEntry?.rating
          : (shouldBootstrapBlankCurrentSeason
              ? playerData.currentRating
              : MultiplayerManager.initialRating),
      hasCurrentSeasonRecord:
          _hasSeasonRecord(currentEntry) || shouldBootstrapBlankCurrentSeason,
      currentSeasonWins: currentEntry?.seasonWins ??
          (shouldBootstrapBlankCurrentSeason
              ? playerData.seasonRankedWins
              : null),
      currentSeasonLosses: currentEntry?.seasonLosses ??
          (shouldBootstrapBlankCurrentSeason
              ? playerData.seasonRankedLosses
              : null),
      previousSeasonName: RankedSeasonManager.seasonName(previousSeasonId),
      previousFinalRank: previousRank,
      previousFinalRating: previousEntry?.rating,
      previousSeasonWins:
          _hasSeasonRecord(previousEntry) ? previousEntry!.seasonWins : null,
      previousSeasonLosses:
          _hasSeasonRecord(previousEntry) ? previousEntry!.seasonLosses : null,
    );
    if (shouldBootstrapBlankCurrentSeason) {
      await PlayerDataManager.instance.load();
      await updateMyRating(
        uid: uid,
        displayName: PlayerDataManager.instance.displayPlayerName,
        rating: PlayerDataManager.instance.currentRating,
        seasonWinsOverride: PlayerDataManager.instance.seasonRankedWins,
        seasonLossesOverride: PlayerDataManager.instance.seasonRankedLosses,
        dailyWinsOverride: PlayerDataManager.instance.todayRankedWins,
        auditRankedResult: true,
        auditReason: 'bootstrap_blank_ranked_season_id',
      );
    }
    await syncSeasonRankBadgesForCurrentPlayer();
  }

  Future<void> syncEndlessSeasonStateForCurrentPlayer({
    String? currentEndlessSeasonId,
    String? uid,
    String? publicId,
  }) async {
    final seasonId = currentEndlessSeasonId ??
        (await _rankingClock()).currentEndlessSeasonId;
    final resolvedUid = uid ??
        MultiplayerManager.instance.myUid ??
        await AuthManager.instance.ensureSignedIn();
    await PlayerDataManager.instance.load();
    final resolvedPublicId = publicId ?? PlayerDataManager.instance.playerId;
    RankingEntry? currentEntry;
    try {
      currentEntry = await _fetchEntryByUidOrPublicId(
        _endlessSeasonRankingRef(seasonId),
        uid: resolvedUid,
        publicId: resolvedPublicId,
        ignoreSeededLegacy: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to fetch endless season entry for $seasonId: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    await PlayerDataManager.instance.ensureEndlessSeason(
      currentSeasonId: seasonId,
      currentSeasonScore: currentEntry?.highestEndlessScore,
      hasCurrentSeasonRecord: currentEntry != null,
    );
  }

  Future<void> syncSeasonRankBadgesForCurrentPlayer() async {
    final uid = MultiplayerManager.instance.myUid ??
        await AuthManager.instance.ensureSignedIn();
    await PlayerDataManager.instance.load();
    final publicId = PlayerDataManager.instance.playerId;
    final badges = [
      ...await fetchSeasonRankBadgesForPlayer(
        uid: uid,
        publicId: publicId,
      ),
      ...await fetchEndlessRankBadgesForPlayer(
        uid: uid,
        publicId: publicId,
      ),
    ];
    await PlayerDataManager.instance.setSeasonRankBadges(badges);
  }

  Future<List<SeasonRankBadge>> fetchEndlessRankBadgesForPlayer({
    required String uid,
    required String publicId,
  }) async {
    final cacheKey = 'endless|$uid|$publicId';
    if (_isCacheFresh(
      _seasonRankBadgesCacheAt[cacheKey],
      const Duration(minutes: 5),
    )) {
      return List<SeasonRankBadge>.from(_seasonRankBadgesCache[cacheKey]!);
    }
    if (uid.trim().isEmpty) {
      return const [];
    }
    final snapshot = await _db.child('endlessSeasonRankBadges/$uid').get();
    final raw = snapshot.value;
    if (raw is! Map) {
      _seasonRankBadgesCache[cacheKey] = const [];
      _seasonRankBadgesCacheAt[cacheKey] = DateTime.now();
      return const [];
    }
    final badges = <SeasonRankBadge>[];
    for (final entry in raw.entries) {
      final seasonId = '${entry.key}';
      final value = entry.value;
      if (value is! Map) {
        continue;
      }
      final rank = RankingEntry._intValue(value['rank']);
      if (rank == null || rank <= 0 || rank > 50) {
        continue;
      }
      badges.add(
        SeasonRankBadge(
          kind: SeasonRankBadgeKind.endless,
          seasonId: seasonId,
          rank: rank,
          score: RankingEntry._intValue(value['score']),
        ),
      );
    }
    badges.sort((a, b) {
      final seasonDiff = b.seasonId.compareTo(a.seasonId);
      if (seasonDiff != 0) {
        return seasonDiff;
      }
      return a.rank.compareTo(b.rank);
    });
    _seasonRankBadgesCache[cacheKey] = badges;
    _seasonRankBadgesCacheAt[cacheKey] = DateTime.now();
    return List<SeasonRankBadge>.from(badges);
  }

  Future<List<SeasonRankBadge>> fetchSeasonRankBadgesForPlayer({
    required String uid,
    required String publicId,
  }) async {
    final cacheKey = 'ranked|$uid|$publicId';
    if (_isCacheFresh(
      _seasonRankBadgesCacheAt[cacheKey],
      const Duration(minutes: 5),
    )) {
      return List<SeasonRankBadge>.from(_seasonRankBadgesCache[cacheKey]!);
    }
    if (uid.trim().isEmpty) {
      return const [];
    }
    final snapshot = await _db.child('rankedSeasonRankBadges/$uid').get();
    final raw = snapshot.value;
    if (raw is! Map) {
      _seasonRankBadgesCache[cacheKey] = const [];
      _seasonRankBadgesCacheAt[cacheKey] = DateTime.now();
      return const [];
    }
    final badges = <SeasonRankBadge>[];
    for (final entry in raw.entries) {
      final seasonId = '${entry.key}';
      final value = entry.value;
      if (value is! Map) {
        continue;
      }
      final rank = RankingEntry._intValue(value['rank']);
      if (rank == null) {
        continue;
      }
      if (rank <= 0 || rank > _rankingLimit) {
        continue;
      }
      badges.add(
        SeasonRankBadge(
          seasonId: seasonId,
          rank: rank,
          rating: RankingEntry._intValue(value['rating']),
        ),
      );
    }
    badges.sort((a, b) {
      final seasonDiff = b.seasonId.compareTo(a.seasonId);
      if (seasonDiff != 0) {
        return seasonDiff;
      }
      return a.rank.compareTo(b.rank);
    });
    _seasonRankBadgesCache[cacheKey] = badges;
    _seasonRankBadgesCacheAt[cacheKey] = DateTime.now();
    return List<SeasonRankBadge>.from(badges);
  }

  Future<void> finalizeSeasonIfNeeded(String seasonId) async {
    final clock = await _rankingClock();
    if (seasonId == clock.currentSeasonId) {
      return;
    }
    final seasonRef = _db.child('rankedSeasons/seasons/$seasonId');
    final snapshots = await Future.wait([
      seasonRef.child('finalized').get(),
      seasonRef.child('finalTop100').get(),
      seasonRef.child('finalTop100SchemaVersion').get(),
    ]);
    final isFinalized = snapshots[0].value == true;
    final rawFinalTop = snapshots[1].value;
    final schemaVersion = RankingEntry._intValue(snapshots[2].value);
    if (isFinalized &&
        rawFinalTop != null &&
        schemaVersion == _finalTop100SchemaVersion) {
      await _ensureSeasonBadgesFromFinalTop(seasonId, rawFinalTop);
      return;
    }
    debugPrint(
      'Ranked season $seasonId is not finalized on server; '
      'skipping client-side finalTop100 generation.',
    );
  }

  Future<void> _ensureSeasonBadgesFromFinalTop(
    String seasonId,
    Object rawFinalTop,
  ) async {
    final uid = MultiplayerManager.instance.myUid ??
        await AuthManager.instance.ensureSignedIn();
    await PlayerDataManager.instance.load();
    final publicId = PlayerDataManager.instance.playerId;
    final entry = _findFinalTopEntryForPlayer(
      rawFinalTop,
      uid: uid,
      publicId: publicId,
    );
    if (entry == null) {
      return;
    }
    final rank = RankingEntry._intValue(entry['rank']);
    if (rank == null || rank <= 0 || rank > _rankingLimit) {
      return;
    }
    final currentBadges = PlayerDataManager.instance.seasonRankBadges
        .where((badge) =>
            badge.kind != SeasonRankBadgeKind.ranked ||
            badge.seasonId != seasonId)
        .toList();
    currentBadges.add(
      SeasonRankBadge(
        kind: SeasonRankBadgeKind.ranked,
        seasonId: seasonId,
        rank: rank,
        rating: RankingEntry._intValue(entry['rating']),
      ),
    );
    await PlayerDataManager.instance.setSeasonRankBadges(currentBadges);
  }

  Map<dynamic, dynamic>? _findFinalTopEntryForPlayer(
    Object rawFinalTop, {
    required String uid,
    required String publicId,
  }) {
    final records = _rankingRecords(rawFinalTop);
    for (final record in records) {
      if (record.value is! Map<dynamic, dynamic>) {
        continue;
      }
      final data = record.value as Map<dynamic, dynamic>;
      final entryUid = data['uid']?.toString() ?? record.key;
      final entryPublicId = data['publicId']?.toString() ?? '';
      if (entryUid == uid ||
          (publicId.isNotEmpty && entryPublicId == publicId)) {
        return data;
      }
    }
    return null;
  }

  Future<List<RankingEntry>> _fetchTopRatingEntries({
    required String seasonId,
  }) async {
    final seasonSnapshot = await _seasonRankingRef(seasonId)
        .orderByChild('rating')
        .limitToLast(_rankingFetchLimit)
        .get();
    return _entriesFromSnapshot(seasonSnapshot);
  }

  Future<List<RankingEntry>> _fetchTopEndlessEntries({
    required String seasonId,
  }) async {
    final seasonSnapshot = await _endlessSeasonRankingRef(seasonId)
        .orderByChild('highestEndlessScore')
        .limitToLast(_rankingLimit)
        .get();
    return _endlessEntriesFromSnapshot(seasonSnapshot);
  }

  Future<RankingEntry?> _fetchEntryByUidOrPublicId(
    DatabaseReference ref, {
    required String uid,
    required String publicId,
    bool ignoreSeededLegacy = false,
  }) async {
    if (uid.isNotEmpty) {
      final snapshot = await ref.child(uid).get();
      if (snapshot.value is Map) {
        final raw = Map<dynamic, dynamic>.from(snapshot.value as Map);
        if (ignoreSeededLegacy && raw['seededFromLegacy'] == true) {
          return null;
        }
        return RankingEntry.fromMap(
          uid,
          raw,
        );
      }
    }
    if (publicId.isEmpty) {
      return null;
    }
    final snapshot = await ref
        .orderByChild('publicId')
        .equalTo(publicId)
        .limitToFirst(1)
        .get();
    final entries = ignoreSeededLegacy
        ? _endlessEntriesFromSnapshot(snapshot)
        : _entriesFromSnapshot(snapshot);
    return entries.isEmpty ? null : entries.first;
  }

  Future<List<RankingEntry>> _fetchDailyEntriesForDate(
    String dateKey, {
    required String currentSeasonId,
  }) async {
    final dailySnapshot = await _dailyWinRankingRef(dateKey)
        .orderByChild('dailyWins')
        .limitToLast(_rankingLimit)
        .get();
    final dailyEntries = _entriesFromSnapshot(dailySnapshot)
        .where((entry) => entry.dailyWins > 0)
        .toList();
    if (dailyEntries.isNotEmpty) {
      return dailyEntries;
    }
    final seasonIds = _dailyRankingSeasonIds(
      dateKey,
      currentSeasonId: currentSeasonId,
    );
    final seasonSnapshots = await Future.wait(
      seasonIds.map(
        (seasonId) => _seasonRankingRef(seasonId)
            .orderByChild('dailyWinDate')
            .equalTo(dateKey)
            .get(),
      ),
    );
    final previousDailySnapshots = await Future.wait(
      seasonIds.map(
        (seasonId) => _seasonRankingRef(seasonId)
            .orderByChild('previousDailyWinDate')
            .equalTo(dateKey)
            .get(),
      ),
    );
    final seasonEntries = <RankingEntry>[];
    for (final snapshot in seasonSnapshots) {
      seasonEntries.addAll(_entriesFromSnapshot(snapshot));
    }
    for (final snapshot in previousDailySnapshots) {
      seasonEntries.addAll(_previousDailyEntriesFromSnapshot(snapshot));
    }
    final mergedSeasonEntries =
        _mergeDailyRankingEntries(seasonEntries, dateKey);
    return mergedSeasonEntries.where((entry) => entry.dailyWins > 0).toList();
  }

  Future<Map<String, Object?>> _buildRankingUpdatePayload({
    required DatabaseReference entryRef,
    required String uid,
    required String publicId,
    required String displayName,
    required int rating,
    required int highestEndlessScore,
    required String today,
    required bool incrementDailyWin,
    required bool incrementSeasonLoss,
    int? seasonWinsOverride,
    int? seasonLossesOverride,
    int? dailyWinsOverride,
  }) async {
    final updatePayload = <String, Object?>{
      'uid': uid,
      'publicId': publicId,
      'displayName': displayName,
      'rating': rating,
      'highestEndlessScore': highestEndlessScore,
      'updatedAt': ServerValue.timestamp,
    };

    if (seasonWinsOverride != null || seasonLossesOverride != null) {
      updatePayload['seasonWins'] = (seasonWinsOverride ?? 0).clamp(0, 999999);
      updatePayload['seasonLosses'] =
          (seasonLossesOverride ?? 0).clamp(0, 999999);
    }

    if (dailyWinsOverride != null) {
      final safeDailyWins = dailyWinsOverride.clamp(0, 999999);
      updatePayload['dailyWins'] = safeDailyWins;
      updatePayload['dailyWinDate'] = today;
      if (safeDailyWins > 0) {
        updatePayload['dailyWinRanking'] = {
          'uid': uid,
          'publicId': publicId,
          'displayName': displayName,
          'rating': rating,
          'dailyWins': safeDailyWins,
          'updatedAt': ServerValue.timestamp,
        };
      }
    } else if (incrementDailyWin || incrementSeasonLoss) {
      final currentSnapshot = await entryRef.get();
      final currentData = currentSnapshot.value is Map
          ? currentSnapshot.value as Map<dynamic, dynamic>
          : null;
      final currentSeasonWins =
          RankingEntry._intValue(currentData?['seasonWins']) ?? 0;
      final currentSeasonLosses =
          RankingEntry._intValue(currentData?['seasonLosses']) ?? 0;
      if (seasonWinsOverride == null) {
        updatePayload['seasonWins'] =
            currentSeasonWins + (incrementDailyWin ? 1 : 0);
      }
      if (seasonLossesOverride == null) {
        updatePayload['seasonLosses'] =
            currentSeasonLosses + (incrementSeasonLoss ? 1 : 0);
      }
      final currentWinDate = currentData?['dailyWinDate']?.toString();
      final rawCurrentWins =
          RankingEntry._intValue(currentData?['dailyWins']) ?? 0;
      final currentWins = currentWinDate == today ? rawCurrentWins : 0;
      if (incrementDailyWin) {
        if (currentWinDate != null &&
            currentWinDate.isNotEmpty &&
            currentWinDate != today &&
            rawCurrentWins > 0) {
          updatePayload['previousDailyWinDate'] = currentWinDate;
          updatePayload['previousDailyWins'] = rawCurrentWins;
        }
        final nextDailyWins = currentWins + 1;
        updatePayload['dailyWins'] = nextDailyWins;
        updatePayload['dailyWinDate'] = today;
        updatePayload['dailyWinRanking'] = {
          'uid': uid,
          'publicId': publicId,
          'displayName': displayName,
          'rating': rating,
          'dailyWins': nextDailyWins,
          'updatedAt': ServerValue.timestamp,
        };
      }
    }

    return updatePayload;
  }

  Map<String, Object?> _buildAllTimeEndlessRankingUpdatePayload({
    required String uid,
    required String publicId,
    required String displayName,
    required int highestEndlessScore,
  }) {
    return {
      'uid': uid,
      'publicId': publicId,
      'displayName': displayName,
      'highestEndlessScore': highestEndlessScore,
      'updatedAt': ServerValue.timestamp,
    };
  }

  Map<String, Object?> _buildEndlessRankingUpdatePayload({
    required String uid,
    required String publicId,
    required String displayName,
    required int highestEndlessScore,
  }) {
    return {
      'uid': uid,
      'publicId': publicId,
      'displayName': displayName,
      'highestEndlessScore': highestEndlessScore,
      'updatedAt': ServerValue.timestamp,
      'seededFromLegacy': null,
    };
  }

  List<RankingEntry> _dedupeEndlessRankingEntries(
    Iterable<RankingEntry> entries,
  ) {
    final bestByPlayer = <String, RankingEntry>{};
    for (final entry in entries) {
      final key = _entryKey(entry);
      if (key.isEmpty) {
        continue;
      }
      final previous = bestByPlayer[key];
      if (previous == null ||
          entry.highestEndlessScore > previous.highestEndlessScore ||
          (entry.highestEndlessScore == previous.highestEndlessScore &&
              (entry.updatedAt ?? 0) > (previous.updatedAt ?? 0))) {
        bestByPlayer[key] = entry;
      }
    }
    return bestByPlayer.values.toList();
  }

  List<RankingEntry> _mergeDailyRankingEntries(
    List<RankingEntry> entries,
    String dateKey,
  ) {
    final merged = <String, RankingEntry>{};
    for (final entry in entries) {
      if (entry.dailyWinDate != dateKey || entry.dailyWins <= 0) {
        continue;
      }
      final key =
          entry.publicId.isNotEmpty ? 'public:${entry.publicId}' : entry.uid;
      final previous = merged[key];
      if (previous == null) {
        merged[key] = entry;
        continue;
      }
      final newerEntry = (entry.updatedAt ?? 0) >= (previous.updatedAt ?? 0)
          ? entry
          : previous;
      merged[key] = RankingEntry(
        uid: newerEntry.uid,
        displayName: newerEntry.displayName,
        rating:
            previous.rating >= entry.rating ? previous.rating : entry.rating,
        publicId: newerEntry.publicId,
        updatedAt: newerEntry.updatedAt,
        dailyWins: previous.dailyWins + entry.dailyWins,
        dailyWinDate: dateKey,
        seasonWins: newerEntry.seasonWins,
        seasonLosses: newerEntry.seasonLosses,
        highestEndlessScore: newerEntry.highestEndlessScore,
        finalRank: newerEntry.finalRank,
      );
    }
    return merged.values.toList();
  }

  List<String> _dailyRankingSeasonIds(
    String dateKey, {
    required String currentSeasonId,
  }) {
    final seasonIds = <String>[currentSeasonId];
    final parsedDate = DateTime.tryParse(dateKey);
    if (parsedDate != null) {
      for (final hour in const [0, 12, 22]) {
        final seasonId = RankedSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(
            parsedDate.year,
            parsedDate.month,
            parsedDate.day,
            hour,
          ),
        );
        if (!seasonIds.contains(seasonId)) {
          seasonIds.add(seasonId);
        }
      }
    }
    final previousSeasonId =
        RankedSeasonManager.previousSeasonId(currentSeasonId);
    if (!seasonIds.contains(previousSeasonId) &&
        _dateKey(RankedSeasonManager.seasonEndJst(previousSeasonId)) ==
            dateKey) {
      seasonIds.add(previousSeasonId);
    }
    return seasonIds;
  }

  List<RankingEntry> _rankableEntries(List<RankingEntry> entries) {
    return entries
        .where((entry) => entry.rating >= _minimumListedRating)
        .where(_isPlausibleSeasonEntry)
        .toList();
  }

  bool _isPlausibleSeasonEntry(RankingEntry entry) {
    return _isPlausibleSeasonRating(
      rating: entry.rating,
      wins: entry.seasonWins,
      losses: entry.seasonLosses,
    );
  }

  bool _isPlausibleSeasonRating({
    required int rating,
    required int wins,
    required int losses,
  }) {
    final maxReachable = MultiplayerManager.initialRating +
        wins.clamp(0, 1 << 30) * 95 -
        losses.clamp(0, 1 << 30) * 5;
    final minReachable = MultiplayerManager.initialRating +
        wins.clamp(0, 1 << 30) * 5 -
        losses.clamp(0, 1 << 30) * 95;
    return rating >= minReachable && rating <= maxReachable;
  }

  String _entryKey(RankingEntry entry) {
    return entry.publicId.isNotEmpty ? 'public:${entry.publicId}' : entry.uid;
  }

  List<RankingEntry> _entriesFromSnapshot(DataSnapshot snapshot) {
    final raw = snapshot.value;
    final records = _rankingRecords(raw);
    if (records.isEmpty) {
      return const [];
    }
    return records
        .where((record) => record.value is Map<dynamic, dynamic>)
        .map(
          (record) => RankingEntry.fromMap(
            '${(record.value as Map<dynamic, dynamic>)['uid'] ?? record.key}',
            record.value as Map<dynamic, dynamic>,
          ),
        )
        .where((entry) => entry.uid.isNotEmpty)
        .toList();
  }

  List<RankingEntry> _endlessEntriesFromSnapshot(DataSnapshot snapshot) {
    final raw = snapshot.value;
    final records = _rankingRecords(raw);
    if (records.isEmpty) {
      return const [];
    }
    return records
        .where((record) =>
            record.value is Map<dynamic, dynamic> &&
            (record.value as Map<dynamic, dynamic>)['seededFromLegacy'] != true)
        .map(
          (record) => RankingEntry.fromMap(
            '${(record.value as Map<dynamic, dynamic>)['uid'] ?? record.key}',
            record.value as Map<dynamic, dynamic>,
          ),
        )
        .where((entry) => entry.uid.isNotEmpty)
        .toList();
  }

  List<RankingEntry> _previousDailyEntriesFromSnapshot(DataSnapshot snapshot) {
    final raw = snapshot.value;
    final records = _rankingRecords(raw);
    if (records.isEmpty) {
      return const [];
    }
    return records
        .where((record) => record.value is Map<dynamic, dynamic>)
        .map((record) {
          final data = record.value as Map<dynamic, dynamic>;
          return RankingEntry.fromMap(
            '${data['uid'] ?? record.key}',
            {
              ...data,
              'dailyWins': data['previousDailyWins'],
              'dailyWinDate': data['previousDailyWinDate'],
            },
          );
        })
        .where((entry) => entry.uid.isNotEmpty)
        .toList();
  }

  Iterable<MapEntry<String, Object?>> _rankingRecords(Object? raw) {
    if (raw is Map) {
      return raw.entries.map(
        (entry) => MapEntry('${entry.key}', entry.value),
      );
    }
    if (raw is List) {
      return raw.indexed
          .where((entry) => entry.$2 != null)
          .map((entry) => MapEntry('${entry.$1}', entry.$2));
    }
    return const [];
  }

  DatabaseReference _seasonRankingRef(String seasonId) {
    return _db.child('rankedSeasons/seasons/$seasonId/rankings');
  }

  DatabaseReference _dailyWinRankingRef(String dateKey) {
    return _db.child('dailyWinRankings/$dateKey');
  }

  DatabaseReference _endlessSeasonRankingRef(String seasonId) {
    return _db.child('endlessSeasons/seasons/$seasonId/rankings');
  }

  DatabaseReference _allTimeEndlessRankingRef() {
    return _db.child('endlessAllTimeRankings');
  }

  Future<void> _saveLastPush({
    required SharedPreferences prefs,
    required String key,
    required String displayName,
    required String publicId,
    required int rating,
    required int highestEndlessScore,
    required int seasonEndlessHighScore,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await Future.wait([
      prefs.setInt('${key}_at', now),
      prefs.setInt('${key}_rating', rating),
      prefs.setInt('${key}_highestEndlessScore', highestEndlessScore),
      prefs.setInt('${key}_seasonEndlessHighScore', seasonEndlessHighScore),
      prefs.setString('${key}_displayName', displayName),
      prefs.setString('${key}_publicId', publicId),
    ]);
  }

  Future<void> _writeRankedResultSyncAudit({
    required String uid,
    required String publicId,
    required String displayName,
    required String seasonId,
    required int rating,
    required String status,
    required String reason,
    int? seasonWins,
    int? seasonLosses,
    int? dailyWins,
    String? error,
  }) async {
    if (uid.trim().isEmpty || seasonId.trim().isEmpty) {
      return;
    }
    final now = DateTime.now();
    final logKey = '${now.millisecondsSinceEpoch}_${status}_$reason'
        .replaceAll(RegExp(r'[\.\#\$\[\]/]'), '_');
    final log = <String, Object?>{
      'uid': uid,
      'publicId': publicId,
      'displayName': displayName,
      'seasonId': seasonId,
      'rating': rating,
      if (seasonWins != null) 'seasonWins': seasonWins,
      if (seasonLosses != null) 'seasonLosses': seasonLosses,
      if (dailyWins != null) 'dailyWins': dailyWins,
      'status': status,
      'reason': reason,
      if (error != null && error.isNotEmpty) 'error': error,
      'createdAt': ServerValue.timestamp,
      'createdAtText': now.toIso8601String(),
    };
    await _db.child('rankedResultSyncLogs/$uid/$logKey').set(log);
    await _db.child('rankedResultSyncLatest/$uid').set(log);
  }

  List<Map<String, Object?>> _pendingRankedResultSyncs(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_pendingRankedResultSyncsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, Object?>.from(entry))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _savePendingRankedResultSyncs(
    SharedPreferences prefs,
    List<Map<String, Object?>> pending,
  ) async {
    if (pending.isEmpty) {
      await prefs.remove(_pendingRankedResultSyncsKey);
      return;
    }
    await prefs.setString(_pendingRankedResultSyncsKey, jsonEncode(pending));
  }

  Future<void> _storePendingRankedResultSync({
    required String seasonId,
    required int rating,
    required int seasonWins,
    required int seasonLosses,
    required int dailyWins,
    required bool isWin,
    required String reason,
  }) async {
    if (seasonId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final pending = _pendingRankedResultSyncs(prefs)
        .where((entry) => entry['seasonId']?.toString() != seasonId)
        .toList();
    pending.add({
      'seasonId': seasonId,
      'rating': rating,
      'seasonWins': seasonWins,
      'seasonLosses': seasonLosses,
      'dailyWins': dailyWins,
      'isWin': isWin,
      'reason': reason,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    final trimmed = pending.length > _pendingRankedResultSyncLimit
        ? pending.sublist(pending.length - _pendingRankedResultSyncLimit)
        : pending;
    await _savePendingRankedResultSyncs(prefs, trimmed);
  }

  Future<void> _removePendingRankedResultSync({
    required String seasonId,
  }) async {
    if (seasonId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final remaining = _pendingRankedResultSyncs(prefs)
        .where((entry) => entry['seasonId']?.toString() != seasonId)
        .toList();
    await _savePendingRankedResultSyncs(prefs, remaining);
  }

  bool _isRecentUnchangedPush({
    required SharedPreferences prefs,
    required String key,
    required String displayName,
    required String publicId,
    required int rating,
    required int highestEndlessScore,
    required int seasonEndlessHighScore,
  }) {
    final lastSyncedAt = prefs.getInt('${key}_at') ?? 0;
    if (lastSyncedAt <= 0 ||
        DateTime.now().millisecondsSinceEpoch - lastSyncedAt >
            _unchangedPushTtl.inMilliseconds) {
      return false;
    }
    return prefs.getInt('${key}_rating') == rating &&
        prefs.getInt('${key}_highestEndlessScore') == highestEndlessScore &&
        prefs.getInt('${key}_seasonEndlessHighScore') ==
            seasonEndlessHighScore &&
        (prefs.getString('${key}_displayName') ?? '') == displayName &&
        (prefs.getString('${key}_publicId') ?? '') == publicId;
  }

  bool _isCacheFresh(DateTime? fetchedAt, [Duration ttl = _rankingCacheTtl]) {
    return fetchedAt != null && DateTime.now().difference(fetchedAt) < ttl;
  }

  void _invalidateCaches() {
    _topRatingCache = null;
    _topRatingCacheAt = null;
    _topRatingCacheSeasonId = null;
    _topDailyCache = null;
    _topDailyCacheAt = null;
    _topDailyCacheKey = null;
    _topEndlessCache = null;
    _topEndlessCacheAt = null;
    _topAllTimeEndlessCache = null;
    _topAllTimeEndlessCacheAt = null;
    _topEndlessCacheSeasonId = null;
    _archivedSeasonIdsCache = null;
    _archivedSeasonIdsCacheAt = null;
    _archivedEndlessSeasonIdsCache = null;
    _archivedEndlessSeasonIdsCacheAt = null;
    _seasonRankingsCache.clear();
    _seasonRankingsCacheAt.clear();
    _endlessSeasonRankingsCache.clear();
    _endlessSeasonRankingsCacheAt.clear();
    _seasonRankBadgesCache.clear();
    _seasonRankBadgesCacheAt.clear();
    _summaryCache = null;
    _summaryCacheAt = null;
    _summaryCacheSeasonId = null;
  }

  bool _matchesCurrentPlayer({
    required RankingEntry entry,
    required String uid,
    required String publicId,
  }) {
    if (entry.uid == uid) {
      return true;
    }
    return publicId.isNotEmpty && entry.publicId == publicId;
  }

  bool _hasSeasonRecord(RankingEntry? entry) {
    return entry != null &&
        entry.seasonWins + entry.seasonLosses > 0 &&
        _isPlausibleSeasonEntry(entry);
  }

  int _displayRankAt(List<RankingEntry> entries, int index) {
    if (index <= 0) {
      return 1;
    }
    final current = entries[index];
    final previous = entries[index - 1];
    if (current.rating == previous.rating) {
      return _displayRankAt(entries, index - 1);
    }
    return index + 1;
  }

  int _displayDailyRankAt(List<RankingEntry> entries, int index) {
    if (index <= 0) {
      return 1;
    }
    final current = entries[index];
    final previous = entries[index - 1];
    if (current.dailyWins == previous.dailyWins) {
      return _displayDailyRankAt(entries, index - 1);
    }
    return index + 1;
  }

  Future<_RankingClock> _rankingClock({bool forceRefresh = false}) async {
    final nowJst =
        await ServerTimeManager.instance.nowJst(forceRefresh: forceRefresh);
    return _RankingClock(
      nowJst: nowJst,
      currentSeasonId:
          RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst),
      currentEndlessSeasonId:
          EndlessSeasonManager.currentSeasonId(nowJstOverride: nowJst),
    );
  }

  static String _dateKey(DateTime dateTime) {
    final now = dateTime;
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

class _RankingClock {
  const _RankingClock({
    required this.nowJst,
    required this.currentSeasonId,
    required this.currentEndlessSeasonId,
  });

  final DateTime nowJst;
  final String currentSeasonId;
  final String currentEndlessSeasonId;
}
