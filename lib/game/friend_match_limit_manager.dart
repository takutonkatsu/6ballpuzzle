import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';

class FriendMatchLimitManager {
  FriendMatchLimitManager._internal();

  static final FriendMatchLimitManager instance =
      FriendMatchLimitManager._internal();

  static const int freeDailyMatches = 3;
  static const int rewardedAdRestoreMatches = 2;

  static const String _dateKey = 'friend_match_limit_date';
  static const String _usedKey = 'friend_match_limit_used';
  static const String _bonusKey = 'friend_match_limit_bonus';

  Future<FriendMatchLimitSnapshot> loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);

    final isUnlimited = AppSettings.instance.adsRemoved.value;
    final used = prefs.getInt(_usedKey) ?? 0;
    final bonus = prefs.getInt(_bonusKey) ?? 0;
    final allowance = freeDailyMatches + bonus;
    final remaining = isUnlimited ? 1 << 30 : math.max(0, allowance - used);

    return FriendMatchLimitSnapshot(
      isUnlimited: isUnlimited,
      used: used,
      bonus: bonus,
      allowance: allowance,
      remaining: remaining,
    );
  }

  Future<bool> canStartMatch() async {
    final snapshot = await loadSnapshot();
    return snapshot.isUnlimited || snapshot.remaining > 0;
  }

  Future<bool> consumeMatch() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);

    if (AppSettings.instance.adsRemoved.value) {
      return true;
    }

    final used = prefs.getInt(_usedKey) ?? 0;
    final bonus = prefs.getInt(_bonusKey) ?? 0;
    final allowance = freeDailyMatches + bonus;
    if (used >= allowance) {
      return false;
    }

    await prefs.setInt(_usedKey, used + 1);
    return true;
  }

  Future<void> restoreConsumedMatch() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);

    if (AppSettings.instance.adsRemoved.value) {
      return;
    }

    final used = prefs.getInt(_usedKey) ?? 0;
    if (used <= 0) {
      return;
    }

    await prefs.setInt(_usedKey, used - 1);
  }

  Future<void> addRewardedMatches([
    int amount = rewardedAdRestoreMatches,
  ]) async {
    if (amount <= 0) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);
    final bonus = prefs.getInt(_bonusKey) ?? 0;
    await prefs.setInt(_bonusKey, bonus + amount);
  }

  Future<void> _resetIfNeeded(SharedPreferences prefs) async {
    final today = _todayKey();
    if (prefs.getString(_dateKey) == today) {
      return;
    }

    await prefs.setString(_dateKey, today);
    await prefs.setInt(_usedKey, 0);
    await prefs.setInt(_bonusKey, 0);
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}

class FriendMatchLimitSnapshot {
  const FriendMatchLimitSnapshot({
    required this.isUnlimited,
    required this.used,
    required this.bonus,
    required this.allowance,
    required this.remaining,
  });

  final bool isUnlimited;
  final int used;
  final int bonus;
  final int allowance;
  final int remaining;
}
