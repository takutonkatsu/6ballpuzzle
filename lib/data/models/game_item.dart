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
    this.emoji,
    this.text,
  });

  static const int maxStampLevel = 5;

  final String id;
  final String name;
  final ItemType type;
  final ItemRarity rarity;
  final int level;
  final String? emoji;
  final String? text;

  bool get isStamp => type == ItemType.stamp;
  bool get isMaxLevel => isStamp && level >= maxStampLevel;

  GameItem copyWith({
    String? id,
    String? name,
    ItemType? type,
    ItemRarity? rarity,
    int? level,
    String? emoji,
    String? text,
  }) {
    return GameItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      rarity: rarity ?? this.rarity,
      level: level ?? this.level,
      emoji: emoji ?? this.emoji,
      text: text ?? this.text,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'rarity': rarity.name,
      'level': level,
      if (emoji != null) 'emoji': emoji,
      if (text != null) 'text': text,
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
      emoji: json['emoji'] as String?,
      text: json['text'] as String?,
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
      id: 'stamp_cyber_1',
      name: 'CONNECTING',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      emoji: '👽',
      text: 'CONNECTING...',
    ),
    GameItem(
      id: 'stamp_cyber_2',
      name: 'NICE HACK',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      emoji: '⚡️',
      text: 'NICE HACK!',
    ),
    GameItem(
      id: 'stamp_cyber_3',
      name: 'SYSTEM ERROR',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      emoji: '⚠️',
      text: 'SYSTEM ERROR',
    ),
    GameItem(
      id: 'stamp_cyber_4',
      name: 'TOO SLOW',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      emoji: '🥱',
      text: 'TOO SLOW',
    ),
    GameItem(
      id: 'stamp_cyber_5',
      name: 'ACCESS DENIED',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      emoji: '🛑',
      text: 'ACCESS DENIED',
    ),
    GameItem(
      id: 'stamp_cyber_6',
      name: 'U BORING',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      emoji: '😈',
      text: 'U BORING?',
    ),
    GameItem(
      id: 'stamp_cyber_7',
      name: 'SESSION CLOSED',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      emoji: '🔌',
      text: 'SESSION CLOSED',
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
