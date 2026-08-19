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

enum GachaCategory { standard, stamp, profile, effect, audio, premium }

class GachaManager {
  GachaManager._internal();

  static final GachaManager instance = GachaManager._internal();
  static const int rollCost = 8000;
  static const int stampRollCost = 5000;
  static const int profileRollCost = 10000;
  static const int effectRollCost = 100000;
  static const int audioRollCost = 100000;
  static const int premiumRollCost = 30000;
  static const int dailyAdRollLimit = 1;
  static const int dailyPremiumFreeRollLimit = 1;
  static const int premiumAdRollAdViews = 3;
  static const int dailyPremiumAdRollLimit = 1;
  static const String _adRollDateKey = 'gacha_ad_roll_date';
  static const String _adRollCountKey = 'gacha_ad_roll_count';
  static const String _premiumFreeRollDateKey = 'gacha_premium_free_roll_date';
  static const String _premiumFreeRollCountKey =
      'gacha_premium_free_roll_count';
  static const String _premiumAdRollDateKey = 'gacha_premium_ad_roll_date';
  static const String _premiumAdRollCountKey = 'gacha_premium_ad_roll_count';
  static const String _categoryAdRollPrefix = 'gacha_category_ad_roll_';

  final Random _random = Random();
  final PlayerDataManager _playerData = PlayerDataManager.instance;

  static int categoryAdRollLimit(GachaCategory category) {
    return switch (category) {
      GachaCategory.stamp => 3,
      GachaCategory.profile => 1,
      GachaCategory.effect => 1,
      GachaCategory.audio => 1,
      GachaCategory.standard || GachaCategory.premium => 1,
    };
  }

  static int categoryAdRollAdViews(GachaCategory category) {
    return switch (category) {
      GachaCategory.stamp => 1,
      GachaCategory.profile => 2,
      GachaCategory.effect => 3,
      GachaCategory.audio => 3,
      GachaCategory.standard || GachaCategory.premium => 1,
    };
  }

  Future<GachaRollResult> rollGacha() async {
    await _playerData.spendCoins(rollCost);
    return _grantDrawnItemFromCategory(GachaCategory.standard);
  }

  Future<GachaRollResult> rollCategoryGacha(GachaCategory category) async {
    await _playerData.spendCoins(_costForCategory(category));
    return _grantDrawnItemFromCategory(category);
  }

  Future<GachaRollResult> rollFreeAdGacha() async {
    final used = await adRollsUsedToday();
    if (used >= dailyAdRollLimit) {
      throw StateError('本日の無料ガチャは上限に達しました。');
    }
    final result = await _grantDrawnItemFromCategory(GachaCategory.standard);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adRollDateKey, _todayKey());
    await prefs.setInt(_adRollCountKey, used + 1);
    return result;
  }

  Future<GachaRollResult> rollPremiumDailyFreeGacha() async {
    if (!AppSettings.instance.adRemovalBenefitsEnabled) {
      throw StateError('広告削除が有効ではありません。');
    }
    final used = await premiumFreeRollsUsedToday();
    if (used >= dailyPremiumFreeRollLimit) {
      throw StateError('本日の無料ガチャは受取済みです。');
    }
    final result = await _grantDrawnItemFromCategory(GachaCategory.standard);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_premiumFreeRollDateKey, _todayKey());
    await prefs.setInt(_premiumFreeRollCountKey, used + 1);
    return result;
  }

  Future<GachaRollResult> rollPremiumAdGacha() async {
    final used = await premiumAdRollsUsedToday();
    if (used >= dailyPremiumAdRollLimit) {
      throw StateError('本日のプレミアム広告ガチャは上限に達しました。');
    }
    final result = await _grantDrawnItemFromCategory(GachaCategory.premium);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_premiumAdRollDateKey, _todayKey());
    await prefs.setInt(_premiumAdRollCountKey, used + 1);
    return result;
  }

  Future<GachaRollResult> rollCategoryAdGacha(GachaCategory category) async {
    final used = await categoryAdRollsUsedToday(category);
    if (used >= categoryAdRollLimit(category)) {
      throw StateError('本日の広告ガチャは上限に達しました。');
    }
    final result = await _grantDrawnItemFromCategory(category);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_categoryAdRollDateKey(category), _todayKey());
    await prefs.setInt(_categoryAdRollCountKey(category), used + 1);
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

  Future<int> premiumAdRollsUsedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_premiumAdRollDateKey);
    if (savedDate != _todayKey()) {
      return 0;
    }
    return prefs.getInt(_premiumAdRollCountKey) ?? 0;
  }

  Future<int> categoryAdRollsUsedToday(GachaCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_categoryAdRollDateKey(category));
    if (savedDate != _todayKey()) {
      return 0;
    }
    return prefs.getInt(_categoryAdRollCountKey(category)) ?? 0;
  }

  Future<GachaRollResult> _grantDrawnItemFromCategory(
    GachaCategory category,
  ) async {
    final item = _drawItemForCategory(category);
    final grantResult = await _playerData.addOrUpgradeItem(item);
    return GachaRollResult(item: item, grantResult: grantResult);
  }

  GameItem _drawItemForCategory(GachaCategory category) {
    final profileItems = [
      ...GameItemCatalog.playerIcons,
      ...GameItemCatalog.standardIconFrames,
      ...GameItemCatalog.profileBanners,
      if (category == GachaCategory.premium)
        ...GameItemCatalog.premiumIconFrames,
    ];
    final formationEffects = GameItemCatalog.effectItems
        .where((item) => item.id.contains('formation'))
        .toList();
    final ojamaEffects = GameItemCatalog.effectItems
        .where((item) => item.id.contains('ojama'))
        .toList();
    final bgmItems = GameItemCatalog.audioItems
        .where((item) => item.id.contains('bgm'))
        .toList();
    final seItems = GameItemCatalog.audioItems
        .where((item) => !item.id.contains('bgm'))
        .toList();
    final weightedPools = switch (category) {
      GachaCategory.standard => [
          const _WeightedItemPool(GameItemCatalog.commonStamps, 70),
          _WeightedItemPool(profileItems, 25),
          const _WeightedItemPool([
            ...GameItemCatalog.effectItems,
            ...GameItemCatalog.audioItems,
            ...GameItemCatalog.ballSkins,
          ], 5),
        ],
      GachaCategory.stamp => [
          const _WeightedItemPool(GameItemCatalog.commonStamps, 100),
        ],
      GachaCategory.profile => [
          const _WeightedItemPool(GameItemCatalog.playerIcons, 50),
          const _WeightedItemPool(GameItemCatalog.standardIconFrames, 25),
          const _WeightedItemPool(GameItemCatalog.profileBanners, 25),
        ],
      GachaCategory.effect => [
          _WeightedItemPool(formationEffects, 40),
          _WeightedItemPool(ojamaEffects, 40),
          const _WeightedItemPool(GameItemCatalog.ballSkins, 20),
        ],
      GachaCategory.audio => [
          _WeightedItemPool(bgmItems, 35),
          _WeightedItemPool(seItems, 65),
        ],
      GachaCategory.premium => [
          const _WeightedItemPool(GameItemCatalog.commonStamps, 20),
          _WeightedItemPool(profileItems, 40),
          const _WeightedItemPool([
            ...GameItemCatalog.effectItems,
            ...GameItemCatalog.audioItems,
            ...GameItemCatalog.ballSkins,
          ], 40),
        ],
    };
    return _randomFromWeightedPools(weightedPools);
  }

  int _costForCategory(GachaCategory category) {
    return switch (category) {
      GachaCategory.standard => rollCost,
      GachaCategory.stamp => stampRollCost,
      GachaCategory.profile => profileRollCost,
      GachaCategory.effect => effectRollCost,
      GachaCategory.audio => audioRollCost,
      GachaCategory.premium => premiumRollCost,
    };
  }

  String _categoryAdRollDateKey(GachaCategory category) =>
      '$_categoryAdRollPrefix${category.name}_date';

  String _categoryAdRollCountKey(GachaCategory category) =>
      '$_categoryAdRollPrefix${category.name}_count';

  GameItem _randomFrom(List<GameItem> items) {
    return items[_random.nextInt(items.length)];
  }

  GameItem _randomFromWeightedPools(List<_WeightedItemPool> pools) {
    final availablePools = pools
        .where((pool) => pool.items.isNotEmpty && pool.weight > 0)
        .toList();
    final totalWeight =
        availablePools.fold<int>(0, (sum, pool) => sum + pool.weight);
    if (totalWeight <= 0) {
      return _randomFrom(GameItemCatalog.gachaCommonPool);
    }
    var ticket = _random.nextInt(totalWeight);
    for (final pool in availablePools) {
      if (ticket < pool.weight) {
        return _randomFrom(pool.items);
      }
      ticket -= pool.weight;
    }
    return _randomFrom(availablePools.last.items);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

class _WeightedItemPool {
  const _WeightedItemPool(this.items, this.weight);

  final List<GameItem> items;
  final int weight;
}
