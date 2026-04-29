import 'dart:math';

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
  static const int rollCost = 1000;

  final Random _random = Random();
  final PlayerDataManager _playerData = PlayerDataManager.instance;

  Future<GachaRollResult> rollGacha() async {
    await _playerData.spendCoins(rollCost);
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
}
