import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../data/player_data_manager.dart';
import '../firebase_database_provider.dart';
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
  static const int _minimumListedRating = 1001;
  static const int _finalTop100SchemaVersion = 6;
  static const Duration _rankingCacheTtl = Duration(seconds: 45);
  static const Duration _summaryCacheTtl = Duration(seconds: 30);
  static const Duration _sameRatingPushInterval = Duration(minutes: 10);
  static const String _lastPushPrefix = 'ranking_last_push_v2_';

  List<RankingEntry>? _topRatingCache;
  DateTime? _topRatingCacheAt;
  String? _topRatingCacheSeasonId;
  List<RankingEntry>? _topDailyCache;
  DateTime? _topDailyCacheAt;
  String? _topDailyCacheKey;
  List<RankingEntry>? _topEndlessCache;
  DateTime? _topEndlessCacheAt;
  RankingSummary? _summaryCache;
  DateTime? _summaryCacheAt;
  String? _summaryCacheSeasonId;

  DatabaseReference get _db {
    return AppFirebaseDatabase.ref();
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
    return '残り${value.inSeconds}秒';
  }

  static String todayKeyJst({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      throw StateError('todayKeyJst requires server based JST time.');
    }
    return _dateKey(now);
  }

  Future<void> updateMyRating({
    String? uid,
    String? displayName,
    required int rating,
    bool incrementDailyWin = false,
    bool incrementSeasonLoss = false,
  }) async {
    final multiplayerManager = MultiplayerManager.instance;
    final resolvedUid = uid ??
        multiplayerManager.myUid ??
        await AuthManager.instance.ensureSignedIn();
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
    final publicId = PlayerDataManager.instance.playerId;
    final highestEndlessScore = PlayerDataManager.instance.highestEndlessScore
        .clamp(0, PlayerDataManager.maxEndlessScore)
        .toInt();
    final clock = await _rankingClock();
    final today = _dateKey(clock.nowJst);
    final seasonId = clock.currentSeasonId;
    final seasonEntryRef = _seasonRankingRef(seasonId).child(resolvedUid);
    final legacyEntryRef = _legacyRankingRef().child(resolvedUid);
    final prefs = await SharedPreferences.getInstance();
    final pushKey = '$_lastPushPrefix${seasonId}_$resolvedUid';
    if (!incrementDailyWin &&
        !incrementSeasonLoss &&
        _canSkipSameRatingPush(
          prefs: prefs,
          key: pushKey,
          displayName: resolvedName,
          publicId: publicId,
          rating: rating,
          highestEndlessScore: highestEndlessScore,
        )) {
      final snapshots = await Future.wait([
        seasonEntryRef.get(),
        legacyEntryRef.get(),
      ]);
      if (snapshots.every((snapshot) => snapshot.exists)) {
        await _syncProfileRatingFields(
          uid: resolvedUid,
          displayName: resolvedName,
          publicId: publicId,
          rating: rating,
        );
        return;
      }
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
    );
    final legacyPayload = await _buildRankingUpdatePayload(
      entryRef: legacyEntryRef,
      uid: resolvedUid,
      publicId: publicId,
      displayName: resolvedName,
      rating: rating,
      highestEndlessScore: highestEndlessScore,
      today: today,
      incrementDailyWin: incrementDailyWin,
      incrementSeasonLoss: incrementSeasonLoss,
    );

    await Future.wait([
      seasonEntryRef.update(seasonPayload),
      legacyEntryRef.update(legacyPayload),
      _syncProfileRatingFields(
        uid: resolvedUid,
        displayName: resolvedName,
        publicId: publicId,
        rating: rating,
      ),
    ]);
    await _saveLastPush(
      prefs: prefs,
      key: pushKey,
      displayName: resolvedName,
      publicId: publicId,
      rating: rating,
      highestEndlessScore: highestEndlessScore,
    );
    _invalidateCaches();
  }

  Future<void> _syncProfileRatingFields({
    required String uid,
    required String displayName,
    required String publicId,
    required int rating,
  }) async {
    final lookupKey = _nameLookupKey(displayName);
    final payload = <String, Object?>{
      'playerRecordSummaries/$uid/displayName': displayName,
      'playerRecordSummaries/$uid/publicId': publicId,
      'playerRecordSummaries/$uid/ranked/currentRating': rating,
      'playerRecordSummaries/$uid/updatedAt': ServerValue.timestamp,
      'playerNameLookup/$lookupKey/$uid/uid': uid,
      'playerNameLookup/$lookupKey/$uid/publicId': publicId,
      'playerNameLookup/$lookupKey/$uid/displayName': displayName,
      'playerNameLookup/$lookupKey/$uid/currentRating': rating,
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
    if (highestEndlessScore <= 0) {
      return;
    }

    final publicId = PlayerDataManager.instance.playerId;
    await _legacyRankingRef().child(resolvedUid).update({
      'uid': resolvedUid,
      'publicId': publicId,
      'displayName': resolvedName,
      'rating': PlayerDataManager.instance.currentRating,
      'highestEndlessScore': highestEndlessScore,
      'updatedAt': ServerValue.timestamp,
    });
    _topEndlessCache = null;
    _topEndlessCacheAt = null;
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
    final clock = await _rankingClock(forceRefresh: true);
    final entries = _rankableEntries(
        await _fetchTopRatingEntries(seasonId: clock.currentSeasonId))
      ..sort((a, b) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) {
          return ratingDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
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
    final ratingEntries =
        _rankableEntries(await _fetchTopRatingEntries(seasonId: seasonId))
          ..sort((a, b) {
            final ratingDiff = b.rating.compareTo(a.rating);
            if (ratingDiff != 0) {
              return ratingDiff;
            }
            return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
          });
    final dailyEntries = _rankableEntries(await _fetchDailyEntriesForDate(
      today,
      currentSeasonId: currentSeasonId,
    ))
      ..sort((a, b) {
        final winDiff = b.dailyWins.compareTo(a.dailyWins);
        if (winDiff != 0) {
          return winDiff;
        }
        return b.rating.compareTo(a.rating);
      });
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
    if (dailyRank != null &&
        dailyRank <= _rankingLimit &&
        resolvedDailyWins > 0) {
      await PlayerDataManager.instance.recordDailyWinRankingPlacement(
        rank: dailyRank,
        wins: resolvedDailyWins,
      );
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
    final entries = _rankableEntries(await _fetchDailyEntriesForDate(
      today,
      currentSeasonId: clock.currentSeasonId,
    ))
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
    final entries = _rankableEntries(await _fetchDailyEntriesForDate(
      yesterday,
      currentSeasonId: clock.currentSeasonId,
    ))
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
    if (!forceRefresh && _isCacheFresh(_topEndlessCacheAt)) {
      return List<RankingEntry>.from(_topEndlessCache!);
    }
    await AuthManager.instance.ensureSignedIn();
    final entries = (await _fetchTopEndlessEntries())
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
    return List<RankingEntry>.from(_topEndlessCache!);
  }

  Future<List<String>> fetchArchivedSeasonIds() async {
    final snapshot = await _db.child('rankedSeasons/seasons').get();
    final raw = snapshot.value;
    if (raw is! Map) {
      return const [];
    }
    final clock = await _rankingClock();
    final current = clock.currentSeasonId;
    final seasonIds = raw.entries
        .where((entry) {
          final seasonId = '${entry.key}';
          final data = entry.value is Map
              ? entry.value as Map<dynamic, dynamic>
              : const <dynamic, dynamic>{};
          return seasonId != current &&
              RankedSeasonManager.seasonNumber(seasonId) >
                  RankedSeasonManager.baseSeasonNumber &&
              data['finalized'] == true;
        })
        .map((entry) => '${entry.key}')
        .toList();
    return seasonIds.toList()..sort((a, b) => b.compareTo(a));
  }

  Future<List<RankingEntry>> fetchSeasonRankings(
    String seasonId, {
    bool finalizedOnly = true,
  }) async {
    final clock = await _rankingClock();
    if (seasonId == clock.currentSeasonId) {
      return fetchTopRankings(forceRefresh: true);
    }
    final ref = finalizedOnly
        ? _db.child('rankedSeasons/seasons/$seasonId/finalTop100')
        : _seasonRankingRef(seasonId);
    return _fetchRankingsFromRef(ref, applyRatingFilter: !finalizedOnly);
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
    final publicId = PlayerDataManager.instance.playerId;
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
      previousSeasonName: RankedSeasonManager.seasonName(previousSeasonId),
      previousFinalRank: previousRank,
      previousFinalRating: previousEntry?.rating,
      previousSeasonWins:
          _hasSeasonRecord(previousEntry) ? previousEntry!.seasonWins : null,
      previousSeasonLosses:
          _hasSeasonRecord(previousEntry) ? previousEntry!.seasonLosses : null,
    );
    await syncSeasonRankBadgesForCurrentPlayer();
  }

  Future<void> syncSeasonRankBadgesForCurrentPlayer() async {
    await PlayerDataManager.instance.setSeasonRankBadges(const []);
  }

  Future<void> finalizeSeasonIfNeeded(String seasonId) async {
    final clock = await _rankingClock();
    if (seasonId == clock.currentSeasonId) {
      return;
    }
    final seasonRef = _db.child('rankedSeasons/seasons/$seasonId');
    final finalizedSnapshot = await seasonRef.child('finalized').get();
    if (finalizedSnapshot.value == true) {
      final snapshot = await seasonRef.get();
      final rawSeason = snapshot.value is Map
          ? snapshot.value as Map<dynamic, dynamic>
          : null;
      final rawFinalTop = rawSeason?['finalTop100'];
      final schemaVersion =
          RankingEntry._intValue(rawSeason?['finalTop100SchemaVersion']);
      if (rawFinalTop != null && schemaVersion == _finalTop100SchemaVersion) {
        await _ensureSeasonBadgesFromFinalTop(seasonId, rawFinalTop);
        return;
      }
    }
    final entries = await _fetchSeasonSourceRankings(seasonId);
    final topEntries = entries.take(_rankingLimit).toList();
    final finalTop100 = <String, Object?>{};
    final payload = <String, Object?>{};
    for (var i = 0; i < topEntries.length; i++) {
      final rank = i + 1;
      final entry = topEntries[i];
      finalTop100['rank_${rank.toString().padLeft(3, '0')}'] = {
        'uid': entry.uid,
        'publicId': entry.publicId,
        'displayName': entry.displayName,
        'rating': entry.rating,
        'rank': rank,
        'updatedAt': entry.updatedAt,
        'seasonWins': entry.seasonWins,
        'seasonLosses': entry.seasonLosses,
      };
    }
    payload['rankedSeasons/seasons/$seasonId/finalTop100'] = finalTop100;
    payload['rankedSeasons/seasons/$seasonId/finalTop100SchemaVersion'] =
        _finalTop100SchemaVersion;
    payload['rankedSeasons/seasons/$seasonId/finalized'] = true;
    payload['rankedSeasons/seasons/$seasonId/finalizedAt'] =
        ServerValue.timestamp;
    await _db.update(payload);
  }

  Future<void> _ensureSeasonBadgesFromFinalTop(
    String seasonId,
    Object rawFinalTop,
  ) async {
    return;
  }

  Future<List<RankingEntry>> _fetchSeasonSourceRankings(String seasonId) async {
    final snapshot = await _seasonRankingRef(seasonId).get();
    final entries = _entriesFromSnapshot(snapshot);
    final fallback = seasonId == RankedSeasonManager.baseSeasonId
        ? _entriesFromSnapshot(await _legacyRankingRef().get())
        : const <RankingEntry>[];
    return _rankableEntries(
      _mergeRankingEntries(primary: entries, fallback: fallback),
    )..sort((a, b) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) return ratingDiff;
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
  }

  Future<List<RankingEntry>> _fetchTopRatingEntries({
    required String seasonId,
  }) async {
    final seasonSnapshot = await _seasonRankingRef(seasonId)
        .orderByChild('rating')
        .limitToLast(_rankingLimit)
        .get();
    if (seasonId != RankedSeasonManager.baseSeasonId) {
      return _entriesFromSnapshot(seasonSnapshot);
    }
    final legacySnapshot = await _legacyRankingRef()
        .orderByChild('rating')
        .limitToLast(_rankingLimit)
        .get();
    return _mergeRankingEntries(
      primary: _entriesFromSnapshot(seasonSnapshot),
      fallback: _entriesFromSnapshot(legacySnapshot),
    );
  }

  Future<List<RankingEntry>> _fetchTopEndlessEntries() async {
    final snapshot = await _legacyRankingRef().get();
    return _entriesFromSnapshot(snapshot);
  }

  Future<List<RankingEntry>> _fetchDailyEntriesForDate(
    String dateKey, {
    required String currentSeasonId,
  }) async {
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
    if (seasonIds.contains(RankedSeasonManager.baseSeasonId)) {
      final legacySnapshot = await _legacyRankingRef()
          .orderByChild('dailyWinDate')
          .equalTo(dateKey)
          .get();
      final previousLegacySnapshot = await _legacyRankingRef()
          .orderByChild('previousDailyWinDate')
          .equalTo(dateKey)
          .get();
      return _mergeDailyFallbackEntries(
        primary: mergedSeasonEntries,
        fallback: [
          ..._entriesFromSnapshot(legacySnapshot),
          ..._previousDailyEntriesFromSnapshot(previousLegacySnapshot),
        ],
        dateKey: dateKey,
      ).where((entry) => entry.dailyWins > 0).toList();
    }
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
  }) async {
    final updatePayload = <String, Object?>{
      'uid': uid,
      'publicId': publicId,
      'displayName': displayName,
      'rating': rating,
      'highestEndlessScore': highestEndlessScore,
      'updatedAt': ServerValue.timestamp,
    };

    if (incrementDailyWin || incrementSeasonLoss) {
      final currentSnapshot = await entryRef.get();
      final currentData = currentSnapshot.value is Map
          ? currentSnapshot.value as Map<dynamic, dynamic>
          : null;
      final currentSeasonWins =
          RankingEntry._intValue(currentData?['seasonWins']) ?? 0;
      final currentSeasonLosses =
          RankingEntry._intValue(currentData?['seasonLosses']) ?? 0;
      updatePayload['seasonWins'] =
          currentSeasonWins + (incrementDailyWin ? 1 : 0);
      updatePayload['seasonLosses'] =
          currentSeasonLosses + (incrementSeasonLoss ? 1 : 0);
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
        updatePayload['dailyWins'] = currentWins + 1;
        updatePayload['dailyWinDate'] = today;
      }
    }

    return updatePayload;
  }

  List<RankingEntry> _mergeRankingEntries({
    required List<RankingEntry> primary,
    required List<RankingEntry> fallback,
  }) {
    final merged = <RankingEntry>[];
    final seenKeys = <String>{};
    for (final entry in [...primary, ...fallback]) {
      final key =
          entry.publicId.isNotEmpty ? 'public:${entry.publicId}' : entry.uid;
      if (seenKeys.add(key)) {
        merged.add(entry);
      }
    }
    return merged;
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

  List<RankingEntry> _mergeDailyFallbackEntries({
    required List<RankingEntry> primary,
    required List<RankingEntry> fallback,
    required String dateKey,
  }) {
    final merged = <String, RankingEntry>{
      for (final entry in primary) _entryKey(entry): entry,
    };
    for (final entry in fallback) {
      if (entry.dailyWinDate != dateKey || entry.dailyWins <= 0) {
        continue;
      }
      final key = _entryKey(entry);
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
        dailyWins: previous.dailyWins >= entry.dailyWins
            ? previous.dailyWins
            : entry.dailyWins,
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
        .toList();
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

  DatabaseReference _legacyRankingRef() {
    return _db.child('rankings/global');
  }

  bool _canSkipSameRatingPush({
    required SharedPreferences prefs,
    required String key,
    required String displayName,
    required String publicId,
    required int rating,
    required int highestEndlessScore,
  }) {
    final pushedAt = prefs.getInt('${key}_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - pushedAt >= _sameRatingPushInterval.inMilliseconds) {
      return false;
    }
    return prefs.getInt('${key}_rating') == rating &&
        prefs.getInt('${key}_highestEndlessScore') == highestEndlessScore &&
        prefs.getString('${key}_displayName') == displayName &&
        prefs.getString('${key}_publicId') == publicId;
  }

  Future<void> _saveLastPush({
    required SharedPreferences prefs,
    required String key,
    required String displayName,
    required String publicId,
    required int rating,
    required int highestEndlessScore,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await Future.wait([
      prefs.setInt('${key}_at', now),
      prefs.setInt('${key}_rating', rating),
      prefs.setInt('${key}_highestEndlessScore', highestEndlessScore),
      prefs.setString('${key}_displayName', displayName),
      prefs.setString('${key}_publicId', publicId),
    ]);
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
    return entry != null && entry.seasonWins + entry.seasonLosses > 0;
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
  });

  final DateTime nowJst;
  final String currentSeasonId;
}
