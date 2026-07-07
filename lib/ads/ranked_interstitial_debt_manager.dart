import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';

enum InterstitialDebtKind {
  rankedHuman,
  rankedBot,
  endless,
  computer,
}

class RankedInterstitialDebtManager {
  RankedInterstitialDebtManager._internal();

  static final RankedInterstitialDebtManager instance =
      RankedInterstitialDebtManager._internal();

  static const int forcedAdInterval = 3;

  static const String _pendingKey = 'ranked_interstitial_pending';
  static const String _completedCountKey =
      'ranked_interstitial_completed_count';

  Future<bool> hasPending({
    InterstitialDebtKind kind = InterstitialDebtKind.rankedHuman,
  }) async {
    if (AppSettings.instance.adsRemoved.value ||
        AppSettings.instance.isInterstitialSkipActive) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pendingKeyFor(kind)) ?? false;
  }

  Future<void> recordRankedMatchCompleted({
    required bool isHumanOpponent,
  }) async {
    await recordMatchCompleted(
      isHumanOpponent
          ? InterstitialDebtKind.rankedHuman
          : InterstitialDebtKind.rankedBot,
    );
  }

  Future<void> recordMatchCompleted(InterstitialDebtKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    if (AppSettings.instance.adsRemoved.value) {
      await clearPending(kind: kind);
      await prefs.remove(_completedCountKeyFor(kind));
      return;
    }

    final completedCount = (prefs.getInt(_completedCountKeyFor(kind)) ?? 0) + 1;
    if (_requiresEveryMatch(kind) || completedCount >= forcedAdInterval) {
      await prefs.setBool(_pendingKeyFor(kind), true);
      await prefs.setInt(_completedCountKeyFor(kind), 0);
      return;
    }

    await prefs.setInt(_completedCountKeyFor(kind), completedCount);
  }

  Future<void> clearPending({
    InterstitialDebtKind kind = InterstitialDebtKind.rankedHuman,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKeyFor(kind));
  }

  Future<void> clearAllPending() async {
    final prefs = await SharedPreferences.getInstance();
    for (final kind in InterstitialDebtKind.values) {
      await prefs.remove(_pendingKeyFor(kind));
    }
  }

  bool _requiresEveryMatch(InterstitialDebtKind kind) {
    return kind == InterstitialDebtKind.rankedHuman;
  }

  String _pendingKeyFor(InterstitialDebtKind kind) {
    return switch (kind) {
      InterstitialDebtKind.rankedHuman => _pendingKey,
      InterstitialDebtKind.rankedBot => 'ranked_bot_interstitial_pending',
      InterstitialDebtKind.endless => 'endless_interstitial_pending',
      InterstitialDebtKind.computer => 'computer_interstitial_pending',
    };
  }

  String _completedCountKeyFor(InterstitialDebtKind kind) {
    return switch (kind) {
      InterstitialDebtKind.rankedHuman => _completedCountKey,
      InterstitialDebtKind.rankedBot =>
        'ranked_bot_interstitial_completed_count',
      InterstitialDebtKind.endless => 'endless_interstitial_completed_count',
      InterstitialDebtKind.computer => 'computer_interstitial_completed_count',
    };
  }
}
