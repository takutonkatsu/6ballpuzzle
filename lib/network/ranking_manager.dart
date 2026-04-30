import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../auth/auth_manager.dart';
import 'multiplayer_manager.dart';

class RankingEntry {
  const RankingEntry({
    required this.uid,
    required this.displayName,
    required this.rating,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final int rating;
  final int? updatedAt;

  factory RankingEntry.fromMap(String uid, Map<dynamic, dynamic> data) {
    return RankingEntry(
      uid: uid,
      displayName: _normalizeName(data['displayName'] as String?) ??
          _normalizeName(data['name'] as String?) ??
          'Player',
      rating: _intValue(data['rating']) ?? MultiplayerManager.initialRating,
      updatedAt: _intValue(data['updatedAt']),
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

    await _db.child('rankings/global/$resolvedUid').update({
      'uid': resolvedUid,
      'displayName': resolvedName.isEmpty ? 'Player' : resolvedName,
      'rating': rating,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<List<RankingEntry>> fetchTopRankings() async {
    final snapshot = await _db
        .child('rankings/global')
        .orderByChild('rating')
        .limitToLast(50)
        .get();

    final raw = snapshot.value;
    if (raw is! Map) {
      return const [];
    }

    final entries = raw.entries
        .where((entry) => entry.value is Map<dynamic, dynamic>)
        .map(
          (entry) => RankingEntry.fromMap(
            '${entry.key}',
            entry.value as Map<dynamic, dynamic>,
          ),
        )
        .toList()
      ..sort((a, b) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) {
          return ratingDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });

    return entries.take(50).toList();
  }
}
