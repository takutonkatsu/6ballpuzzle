import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../data/player_data_manager.dart';
import '../firebase_database_provider.dart';
import '../network/server_time_manager.dart';

class DailyChallengeEntry {
  const DailyChallengeEntry({
    required this.uid,
    required this.displayName,
    required this.publicId,
    required this.score,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String publicId;
  final int score;
  final int? updatedAt;

  factory DailyChallengeEntry.fromMap(String uid, Map<dynamic, dynamic> data) {
    return DailyChallengeEntry(
      uid: uid,
      displayName: data['displayName']?.toString().trim().isNotEmpty == true
          ? data['displayName'].toString().trim()
          : 'Player',
      publicId: data['publicId']?.toString() ?? '',
      score: _intValue(data['score']) ?? 0,
      updatedAt: _intValue(data['updatedAt']),
    );
  }

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }
}

class DailyChallengeStatus {
  const DailyChallengeStatus({
    required this.dateKey,
    required this.seed,
    required this.attemptsUsed,
    required this.bestScore,
  });

  final String dateKey;
  final int seed;
  final int attemptsUsed;
  final int bestScore;

  bool get hasFreeAttempt => attemptsUsed <= 0;
  bool get canAttempt => attemptsUsed < DailyChallengeManager.maxAttemptsPerDay;
  bool get needsRewardAd => attemptsUsed > 0;
}

class DailyChallengeManager {
  DailyChallengeManager._();

  static final DailyChallengeManager instance = DailyChallengeManager._();

  static const int durationSeconds = 60;
  static const int maxAttemptsPerDay = 5;
  static const int freeAttemptsPerDay = 1;
  static const String _attemptDateKey = 'daily_challenge_attempt_date';
  static const String _attemptCountKey = 'daily_challenge_attempt_count';
  static const String _bestDateKey = 'daily_challenge_best_date';
  static const String _bestScoreKey = 'daily_challenge_best_score';

  DatabaseReference get _db => AppFirebaseDatabase.ref();

  Future<DailyChallengeStatus> loadStatus() async {
    final dateKey = await currentDateKey();
    final prefs = await SharedPreferences.getInstance();
    final attempts = prefs.getString(_attemptDateKey) == dateKey
        ? prefs.getInt(_attemptCountKey) ?? 0
        : 0;
    final bestScore = prefs.getString(_bestDateKey) == dateKey
        ? prefs.getInt(_bestScoreKey) ?? 0
        : 0;
    return DailyChallengeStatus(
      dateKey: dateKey,
      seed: seedForDateKey(dateKey),
      attemptsUsed: attempts.clamp(0, maxAttemptsPerDay).toInt(),
      bestScore: max(0, bestScore),
    );
  }

  Future<DailyChallengeStatus> recordAttemptStart() async {
    final status = await loadStatus();
    if (!status.canAttempt) {
      throw StateError('本日の挑戦回数は上限に達しました。');
    }
    final prefs = await SharedPreferences.getInstance();
    final nextAttempts = status.attemptsUsed + 1;
    await prefs.setString(_attemptDateKey, status.dateKey);
    await prefs.setInt(_attemptCountKey, nextAttempts);
    return DailyChallengeStatus(
      dateKey: status.dateKey,
      seed: status.seed,
      attemptsUsed: nextAttempts,
      bestScore: status.bestScore,
    );
  }

  Future<void> submitScore({
    required String dateKey,
    required int score,
  }) async {
    final safeScore = max(0, score);
    final prefs = await SharedPreferences.getInstance();
    final previousBest = prefs.getString(_bestDateKey) == dateKey
        ? prefs.getInt(_bestScoreKey) ?? 0
        : 0;
    if (safeScore > previousBest) {
      await prefs.setString(_bestDateKey, dateKey);
      await prefs.setInt(_bestScoreKey, safeScore);
    }
    final uid = await AuthManager.instance.ensureSignedIn();
    await PlayerDataManager.instance.load();
    final playerData = PlayerDataManager.instance;
    final displayName = playerData.displayPlayerName;
    final publicId = playerData.playerId;
    final entryRef = _db.child('dailyChallengeRankings/$dateKey/$uid');
    final current = await entryRef.get();
    final currentScore = current.value is Map
        ? DailyChallengeEntry.fromMap(
            uid,
            current.value as Map<dynamic, dynamic>,
          ).score
        : 0;
    if (safeScore < currentScore) {
      return;
    }
    await entryRef.update({
      'uid': uid,
      'publicId': publicId,
      'displayName': displayName,
      'score': safeScore,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<List<DailyChallengeEntry>> fetchTopRankings({
    String? dateKey,
  }) async {
    final key = dateKey ?? await currentDateKey();
    final snapshot = await _db
        .child('dailyChallengeRankings/$key')
        .orderByChild('score')
        .limitToLast(100)
        .get();
    final raw = snapshot.value;
    if (raw is! Map) {
      return const [];
    }
    final entries = raw.entries
        .where((entry) => entry.value is Map<dynamic, dynamic>)
        .map(
          (entry) => DailyChallengeEntry.fromMap(
            entry.key.toString(),
            entry.value as Map<dynamic, dynamic>,
          ),
        )
        .where((entry) => entry.score > 0)
        .toList()
      ..sort((a, b) {
        final scoreDiff = b.score.compareTo(a.score);
        if (scoreDiff != 0) {
          return scoreDiff;
        }
        return (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0);
      });
    return entries;
  }

  Future<String> currentDateKey() async {
    final now = await ServerTimeManager.instance.nowJst();
    return dateKeyFor(now);
  }

  static String dateKeyFor(DateTime jst) {
    return '${jst.year.toString().padLeft(4, '0')}-'
        '${jst.month.toString().padLeft(2, '0')}-'
        '${jst.day.toString().padLeft(2, '0')}';
  }

  static int seedForDateKey(String dateKey) {
    var hash = 0x6D2B79F5;
    for (final unit in dateKey.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash <= 0 ? 1 : hash;
  }
}
