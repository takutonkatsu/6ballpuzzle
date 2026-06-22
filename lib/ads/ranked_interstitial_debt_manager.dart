import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';

class RankedInterstitialDebtManager {
  RankedInterstitialDebtManager._internal();

  static final RankedInterstitialDebtManager instance =
      RankedInterstitialDebtManager._internal();

  static const int forcedAdInterval = 3;

  static const String _pendingKey = 'ranked_interstitial_pending';
  static const String _completedCountKey =
      'ranked_interstitial_completed_count';

  Future<bool> hasPending() async {
    if (AppSettings.instance.adsRemoved.value) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pendingKey) ?? false;
  }

  Future<void> recordRankedMatchCompleted({
    required bool isHumanOpponent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (AppSettings.instance.adsRemoved.value) {
      await prefs.remove(_pendingKey);
      await prefs.remove(_completedCountKey);
      return;
    }

    final completedCount = (prefs.getInt(_completedCountKey) ?? 0) + 1;
    if (isHumanOpponent || completedCount >= forcedAdInterval) {
      await prefs.setBool(_pendingKey, true);
      await prefs.setInt(_completedCountKey, 0);
      return;
    }

    await prefs.setInt(_completedCountKey, completedCount);
  }

  Future<void> clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }
}
