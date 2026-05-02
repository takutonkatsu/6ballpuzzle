import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../data/player_data_manager.dart';
import 'multiplayer_manager.dart';

class RankingEntry {
  const RankingEntry({
    required this.uid,
    required this.displayName,
    required this.rating,
    this.publicId = '',
    this.updatedAt,
    this.dailyWins = 0,
    this.dailyWinDate = '',
  });

  final String uid;
  final String displayName;
  final int rating;
  final String publicId;
  final int? updatedAt;
  final int dailyWins;
  final String dailyWinDate;

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
  static const int _dailyQueryLimit = 160;
  static const Duration _rankingCacheTtl = Duration(seconds: 45);
  static const Duration _summaryCacheTtl = Duration(seconds: 30);
  static const Duration _sameRatingPushInterval = Duration(minutes: 10);
  static const Duration _duplicateCleanupInterval = Duration(hours: 24);
  static const String _lastPushPrefix = 'ranking_last_push_v2_';
  static const String _lastDuplicateCleanupPrefix =
      'ranking_last_duplicate_cleanup_v1_';

  List<RankingEntry>? _topRatingCache;
  DateTime? _topRatingCacheAt;
  List<RankingEntry>? _topDailyCache;
  DateTime? _topDailyCacheAt;
  RankingSummary? _summaryCache;
  DateTime? _summaryCacheAt;

  DatabaseReference get _db {
    final app = Firebase.app();
    final database = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: app.options.databaseURL,
    );
    return database.ref();
  }

  Future<void> updateMyRating({
    String? uid,
    String? displayName,
    required int rating,
    bool incrementDailyWin = false,
  }) async {
    final multiplayerManager = MultiplayerManager.instance;
    final resolvedUid = uid ??
        multiplayerManager.myUid ??
        await AuthManager.instance.ensureSignedIn();
    if (resolvedUid.isEmpty) {
      return;
    }

    final resolvedName =
        (displayName ?? multiplayerManager.displayPlayerName).trim();
    await PlayerDataManager.instance.load();
    final publicId = PlayerDataManager.instance.playerId;
    final today = _todayKey();
    final prefs = await SharedPreferences.getInstance();
    final pushKey = '$_lastPushPrefix$resolvedUid';
    if (!incrementDailyWin &&
        _canSkipSameRatingPush(
          prefs: prefs,
          key: pushKey,
          displayName: resolvedName,
          publicId: publicId,
          rating: rating,
        )) {
      return;
    }

    final updatePayload = <String, Object?>{
      'uid': resolvedUid,
      'publicId': publicId,
      'displayName': resolvedName.isEmpty ? 'Player' : resolvedName,
      'rating': rating,
      'updatedAt': ServerValue.timestamp,
    };

    if (incrementDailyWin) {
      final currentSnapshot =
          await _db.child('rankings/global/$resolvedUid').get();
      final currentData = currentSnapshot.value is Map
          ? currentSnapshot.value as Map<dynamic, dynamic>
          : null;
      final currentWinDate = currentData?['dailyWinDate']?.toString();
      final currentWins = currentWinDate == today
          ? RankingEntry._intValue(currentData?['dailyWins']) ?? 0
          : 0;
      updatePayload['dailyWins'] = currentWins + 1;
      updatePayload['dailyWinDate'] = today;
    }

    await _db.child('rankings/global/$resolvedUid').update(updatePayload);
    await _saveLastPush(
      prefs: prefs,
      key: pushKey,
      displayName: resolvedName,
      publicId: publicId,
      rating: rating,
    );
    _invalidateCaches();
    await _deleteDuplicateEntriesIfDue(
      prefs: prefs,
      resolvedUid: resolvedUid,
      publicId: publicId,
    );
  }

  Future<List<RankingEntry>> fetchTopRankings() async {
    if (_isCacheFresh(_topRatingCacheAt)) {
      return List<RankingEntry>.from(_topRatingCache!);
    }
    final entries = await _fetchTopRatingEntries()
      ..sort((a, b) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) {
          return ratingDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
    _topRatingCache = entries.take(_rankingLimit).toList();
    _topRatingCacheAt = DateTime.now();
    return List<RankingEntry>.from(_topRatingCache!);
  }

  Future<RankingSummary> fetchMySummary() async {
    if (_summaryCache != null &&
        _isCacheFresh(_summaryCacheAt, _summaryCacheTtl)) {
      return _summaryCache!;
    }
    final uid = MultiplayerManager.instance.myUid ??
        await AuthManager.instance.ensureSignedIn();
    await PlayerDataManager.instance.load();
    final publicId = PlayerDataManager.instance.playerId;
    final today = _todayKey();
    final ratingEntries = await fetchTopRankings();
    final dailyEntries = await fetchTopDailyWinRankings();
    final mySnapshot = await _db.child('rankings/global/$uid').get();
    final myEntry = mySnapshot.value is Map
        ? RankingEntry.fromMap(
            uid,
            mySnapshot.value as Map<dynamic, dynamic>,
          )
        : null;
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
    final ratingRank =
        myIndex == -1 ? null : _displayRankAt(ratingEntries, myIndex);
    final dailyRank =
        dailyIndex == -1 ? null : _displayDailyRankAt(dailyEntries, dailyIndex);
    final summary = RankingSummary(
      ratingRankLabel: ratingRank == null || ratingRank > _rankingLimit
          ? '圏外'
          : '$ratingRank位',
      dailyWinRankLabel:
          dailyRank == null || dailyRank > _rankingLimit ? '圏外' : '$dailyRank位',
      dailyWins: dailyIndex == -1
          ? (myEntry?.dailyWinDate == today ? myEntry!.dailyWins : 0)
          : dailyEntries[dailyIndex].dailyWins,
    );
    _summaryCache = summary;
    _summaryCacheAt = DateTime.now();
    return summary;
  }

  Future<void> clearAllRankings() async {
    await _db.child('rankings').remove();
  }

  Future<List<RankingEntry>> fetchTopDailyWinRankings() async {
    if (_isCacheFresh(_topDailyCacheAt)) {
      return List<RankingEntry>.from(_topDailyCache!);
    }
    final rawEntries = await _fetchTopDailyWinEntries();
    final today = _todayKey();
    final entries = rawEntries
        .where((entry) => entry.dailyWinDate == today && entry.dailyWins > 0)
        .toList()
      ..sort((a, b) {
        final winDiff = b.dailyWins.compareTo(a.dailyWins);
        if (winDiff != 0) {
          return winDiff;
        }
        return b.rating.compareTo(a.rating);
      });
    _topDailyCache = entries.take(_rankingLimit).toList();
    _topDailyCacheAt = DateTime.now();
    return List<RankingEntry>.from(_topDailyCache!);
  }

  Future<List<RankingEntry>> _fetchTopRatingEntries() async {
    final snapshot = await _db
        .child('rankings/global')
        .orderByChild('rating')
        .limitToLast(_rankingLimit)
        .get();
    return _entriesFromSnapshot(snapshot);
  }

  Future<List<RankingEntry>> _fetchTopDailyWinEntries() async {
    final snapshot = await _db
        .child('rankings/global')
        .orderByChild('dailyWins')
        .limitToLast(_dailyQueryLimit)
        .get();
    return _entriesFromSnapshot(snapshot);
  }

  List<RankingEntry> _entriesFromSnapshot(DataSnapshot snapshot) {
    final raw = snapshot.value;
    if (raw is! Map) {
      return const [];
    }
    return raw.entries
        .where((entry) => entry.value is Map<dynamic, dynamic>)
        .map(
          (entry) => RankingEntry.fromMap(
            '${entry.key}',
            entry.value as Map<dynamic, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> _deleteDuplicateEntriesIfDue({
    required SharedPreferences prefs,
    required String resolvedUid,
    required String publicId,
  }) async {
    if (publicId.isEmpty) {
      return;
    }
    final cleanupKey = '$_lastDuplicateCleanupPrefix$publicId';
    final lastCleanup = prefs.getInt(cleanupKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastCleanup < _duplicateCleanupInterval.inMilliseconds) {
      return;
    }
    final snapshot = await _db.child('rankings/global').get();
    final raw = snapshot.value;
    if (raw is! Map) {
      return;
    }
    final updates = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = '${entry.key}';
      final value = entry.value;
      if (key == resolvedUid || value is! Map<dynamic, dynamic>) {
        continue;
      }
      if (value['uid'] == resolvedUid || value['publicId'] == publicId) {
        updates[key] = null;
      }
    }
    if (updates.isNotEmpty) {
      await _db.child('rankings/global').update(updates);
    }
    await prefs.setInt(cleanupKey, now);
  }

  bool _canSkipSameRatingPush({
    required SharedPreferences prefs,
    required String key,
    required String displayName,
    required String publicId,
    required int rating,
  }) {
    final pushedAt = prefs.getInt('${key}_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - pushedAt >= _sameRatingPushInterval.inMilliseconds) {
      return false;
    }
    return prefs.getInt('${key}_rating') == rating &&
        prefs.getString('${key}_displayName') == displayName &&
        prefs.getString('${key}_publicId') == publicId;
  }

  Future<void> _saveLastPush({
    required SharedPreferences prefs,
    required String key,
    required String displayName,
    required String publicId,
    required int rating,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await Future.wait([
      prefs.setInt('${key}_at', now),
      prefs.setInt('${key}_rating', rating),
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
    _topDailyCache = null;
    _topDailyCacheAt = null;
    _summaryCache = null;
    _summaryCacheAt = null;
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

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
