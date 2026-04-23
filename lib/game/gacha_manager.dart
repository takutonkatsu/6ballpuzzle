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
      return _randomFrom(_commonStamps);
    }
    if (roll < 0.90) {
      return _randomFrom(_rareData);
    }
    if (roll < 0.99) {
      return _randomFrom(_epicSkins);
    }
    return _randomFrom(_legendaryVfx);
  }

  GameItem _randomFrom(List<GameItem> items) {
    return items[_random.nextInt(items.length)];
  }

  static const List<GameItem> _commonStamps = [
    GameItem(
      id: 'stamp_good_game',
      name: 'GOOD GAME',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
    ),
    GameItem(
      id: 'stamp_nice_chain',
      name: 'NICE CHAIN',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
    ),
    GameItem(
      id: 'stamp_too_fast',
      name: 'TOO FAST',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
    ),
  ];

  static const List<GameItem> _rareData = [
    GameItem(
      id: 'stamp_data_burst',
      name: 'DATA BURST',
      type: ItemType.stamp,
      rarity: ItemRarity.rare,
    ),
    GameItem(
      id: 'vfx_low_bit_glitch',
      name: 'LOW BIT GLITCH',
      type: ItemType.vfx,
      rarity: ItemRarity.rare,
    ),
  ];

  static const List<GameItem> _epicSkins = [
    GameItem(
      id: 'skin_neon_chrome',
      name: 'NEON CHROME',
      type: ItemType.skin,
      rarity: ItemRarity.epic,
    ),
    GameItem(
      id: 'skin_black_ice',
      name: 'BLACK ICE',
      type: ItemType.skin,
      rarity: ItemRarity.epic,
    ),
  ];

  static const List<GameItem> _legendaryVfx = [
    GameItem(
      id: 'vfx_overdrive_hex',
      name: 'OVERDRIVE HEX',
      type: ItemType.vfx,
      rarity: ItemRarity.legendary,
    ),
  ];
}
