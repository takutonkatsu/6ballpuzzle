enum ItemType {
  stamp,
  skin,
  vfx,
}

enum ItemRarity {
  common,
  rare,
  epic,
  legendary,
}

class GameItem {
  const GameItem({
    required this.id,
    required this.name,
    required this.type,
    required this.rarity,
    this.level = 1,
  });

  static const int maxStampLevel = 5;

  final String id;
  final String name;
  final ItemType type;
  final ItemRarity rarity;
  final int level;

  bool get isStamp => type == ItemType.stamp;
  bool get isMaxLevel => isStamp && level >= maxStampLevel;

  GameItem copyWith({
    String? id,
    String? name,
    ItemType? type,
    ItemRarity? rarity,
    int? level,
  }) {
    return GameItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      rarity: rarity ?? this.rarity,
      level: level ?? this.level,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'rarity': rarity.name,
      'level': level,
    };
  }

  factory GameItem.fromJson(Map<String, dynamic> json) {
    return GameItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Data',
      type: _enumByName(
        ItemType.values,
        json['type'] as String?,
        ItemType.stamp,
      ),
      rarity: _enumByName(
        ItemRarity.values,
        json['rarity'] as String?,
        ItemRarity.common,
      ),
      level: _intValue(json['level']) ?? 1,
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return fallback;
  }

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }
}

class GameItemCatalog {
  GameItemCatalog._();

  static const List<GameItem> commonStamps = [
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

  static const List<GameItem> rareData = [
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

  static const List<GameItem> epicSkins = [
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

  static const List<GameItem> legendaryVfx = [
    GameItem(
      id: 'vfx_overdrive_hex',
      name: 'OVERDRIVE HEX',
      type: ItemType.vfx,
      rarity: ItemRarity.legendary,
    ),
  ];

  static const List<GameItem> allItems = [
    ...commonStamps,
    ...rareData,
    ...epicSkins,
    ...legendaryVfx,
  ];

  static const List<GameItem> dailyShopPool = allItems;

  static GameItem? byId(String id) {
    for (final item in allItems) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}
