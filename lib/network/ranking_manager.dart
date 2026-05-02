import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

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
    final currentSnapshot =
        await _db.child('rankings/global/$resolvedUid').get();
    final currentData = currentSnapshot.value is Map
        ? currentSnapshot.value as Map<dynamic, dynamic>
        : null;
    final currentWinDate = currentData?['dailyWinDate']?.toString();
    final currentWins = currentWinDate == today
        ? RankingEntry._intValue(currentData?['dailyWins']) ?? 0
        : 0;
    final nextDailyWins = currentWins + (incrementDailyWin ? 1 : 0);

    await _db.child('rankings/global/$resolvedUid').update({
      'uid': resolvedUid,
      'publicId': publicId,
      'displayName': resolvedName.isEmpty ? 'Player' : resolvedName,
      'rating': rating,
      'dailyWins': nextDailyWins,
      'dailyWinDate': today,
      'updatedAt': ServerValue.timestamp,
    });
    await _deleteDuplicateEntries(
      resolvedUid: resolvedUid,
      publicId: publicId,
    );
  }

  Future<List<RankingEntry>> fetchTopRankings() async {
    final entries = await _fetchAllEntries()
      ..sort((a, b) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) {
          return ratingDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
    return entries.take(100).toList();
  }

  Future<RankingSummary> fetchMySummary() async {
    final entries = await _fetchAllEntries()
      ..sort((a, b) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) {
          return ratingDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
    final uid = MultiplayerManager.instance.myUid ??
        await AuthManager.instance.ensureSignedIn();
    await PlayerDataManager.instance.load();
    final publicId = PlayerDataManager.instance.playerId;
    final today = _todayKey();
    final myIndex = entries.indexWhere(
      (entry) => _matchesCurrentPlayer(
        entry: entry,
        uid: uid,
        publicId: publicId,
      ),
    );
    final myEntry = myIndex == -1 ? null : entries[myIndex];
    final dailyEntries = entries
        .where((entry) => entry.dailyWinDate == today && entry.dailyWins > 0)
        .toList()
      ..sort((a, b) {
        final winDiff = b.dailyWins.compareTo(a.dailyWins);
        if (winDiff != 0) {
          return winDiff;
        }
        return b.rating.compareTo(a.rating);
      });
    final dailyIndex = dailyEntries.indexWhere(
      (entry) => _matchesCurrentPlayer(
        entry: entry,
        uid: uid,
        publicId: publicId,
      ),
    );
    final ratingRank = myIndex == -1 ? null : _displayRankAt(entries, myIndex);
    final dailyRank =
        dailyIndex == -1 ? null : _displayDailyRankAt(dailyEntries, dailyIndex);
    return RankingSummary(
      ratingRankLabel:
          ratingRank == null || ratingRank > 100 ? '圏外' : '$ratingRank位',
      dailyWinRankLabel:
          dailyRank == null || dailyRank > 100 ? '圏外' : '$dailyRank位',
      dailyWins: dailyIndex == -1
          ? (myEntry?.dailyWinDate == today ? myEntry!.dailyWins : 0)
          : dailyEntries[dailyIndex].dailyWins,
    );
  }

  Future<void> clearAllRankings() async {
    await _db.child('rankings').remove();
  }

  Future<List<RankingEntry>> fetchTopDailyWinRankings() async {
    final rawEntries = await _fetchAllEntries();
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
    return entries.take(100).toList();
  }

  Future<List<RankingEntry>> _fetchAllEntries() async {
    final snapshot = await _db.child('rankings/global').get();
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

  Future<void> _deleteDuplicateEntries({
    required String resolvedUid,
    required String publicId,
  }) async {
    if (publicId.isEmpty) {
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
