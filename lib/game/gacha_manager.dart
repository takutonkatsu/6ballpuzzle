import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';

class GachaRollResult {
  const GachaRollResult({
    required this.item,
    required this.grantResult,
  });

  final GameItem item;
  final ItemGrantResult grantResult;
}

class GachaManager {
  GachaManager._internal();

  static final GachaManager instance = GachaManager._internal();
  static const int rollCost = 5000;
  static const int dailyAdRollLimit = 3;
  static const int dailyPremiumFreeRollLimit = 1;
  static const String _adRollDateKey = 'gacha_ad_roll_date';
  static const String _adRollCountKey = 'gacha_ad_roll_count';
  static const String _premiumFreeRollDateKey = 'gacha_premium_free_roll_date';
  static const String _premiumFreeRollCountKey =
      'gacha_premium_free_roll_count';

  final Random _random = Random();
  final PlayerDataManager _playerData = PlayerDataManager.instance;

  Future<GachaRollResult> rollGacha() async {
    await _playerData.spendCoins(rollCost);
    return _grantDrawnItem();
  }

  Future<GachaRollResult> rollFreeAdGacha() async {
    final used = await adRollsUsedToday();
    if (used >= dailyAdRollLimit) {
      throw StateError('本日の無料ガチャは上限に達しました。');
    }
    final result = await _grantDrawnItem();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adRollDateKey, _todayKey());
    await prefs.setInt(_adRollCountKey, used + 1);
    return result;
  }

  Future<GachaRollResult> rollPremiumDailyFreeGacha() async {
    if (!AppSettings.instance.adsRemoved.value) {
      throw StateError('広告削除が有効ではありません。');
    }
    final used = await premiumFreeRollsUsedToday();
    if (used >= dailyPremiumFreeRollLimit) {
      throw StateError('本日の無料ガチャは受取済みです。');
    }
    final result = await _grantDrawnItem();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_premiumFreeRollDateKey, _todayKey());
    await prefs.setInt(_premiumFreeRollCountKey, used + 1);
    return result;
  }

  Future<int> adRollsUsedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_adRollDateKey);
    if (savedDate != _todayKey()) {
      return 0;
    }
    return prefs.getInt(_adRollCountKey) ?? 0;
  }

  Future<int> premiumFreeRollsUsedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_premiumFreeRollDateKey);
    if (savedDate != _todayKey()) {
      return 0;
    }
    return prefs.getInt(_premiumFreeRollCountKey) ?? 0;
  }

  Future<GachaRollResult> _grantDrawnItem() async {
    final item = _drawItem();
    final grantResult = await _playerData.addOrUpgradeItem(item);
    return GachaRollResult(item: item, grantResult: grantResult);
  }

  GameItem _drawItem() {
    final roll = _random.nextDouble();
    if (roll < 0.60) {
      return _randomFrom(GameItemCatalog.gachaCommonPool);
    }
    if (roll < 0.92) {
      return _randomFrom(GameItemCatalog.gachaRarePool);
    }
    return _randomFrom(GameItemCatalog.gachaEpicPool);
  }

  GameItem _randomFrom(List<GameItem> items) {
    return items[_random.nextInt(items.length)];
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
