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
    this.iconName,
    this.colorName,
    this.text,
  });

  static const int maxStampLevel = 4;

  final String id;
  final String name;
  final ItemType type;
  final ItemRarity rarity;
  final int level;
  final String? iconName;
  final String? colorName;
  final String? text;

  bool get isStamp => type == ItemType.stamp;
  bool get isMaxLevel => isStamp && level >= maxStampLevel;

  GameItem copyWith({
    String? id,
    String? name,
    ItemType? type,
    ItemRarity? rarity,
    int? level,
    String? iconName,
    String? colorName,
    String? text,
  }) {
    return GameItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      rarity: rarity ?? this.rarity,
      level: level ?? this.level,
      iconName: iconName ?? this.iconName,
      colorName: colorName ?? this.colorName,
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
      if (iconName != null) 'iconName': iconName,
      if (colorName != null) 'colorName': colorName,
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
      iconName: json['iconName'] as String?,
      colorName: json['colorName'] as String?,
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
      id: 'stamp_greet_01',
      name: 'GREETING',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'handshake',
      colorName: 'Cyan',
      text: 'よろしく！',
    ),
    GameItem(
      id: 'stamp_react_01',
      name: 'SWEAT',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'water_drop',
      colorName: 'Blue',
      text: 'あせあせ',
    ),
    GameItem(
      id: 'stamp_react_02',
      name: 'FIRE',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'local_fire_department',
      colorName: 'Red',
      text: 'おこ！',
    ),
    GameItem(
      id: 'stamp_praise_01',
      name: 'NICE',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'thumb_up',
      colorName: 'Yellow',
      text: 'ナイス！',
    ),
    GameItem(
      id: 'stamp_taunt_01',
      name: 'EZ',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'coffee',
      colorName: 'Magenta',
      text: '余裕です',
    ),
    GameItem(
      id: 'stamp_taunt_02',
      name: 'SEE THROUGH',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'visibility',
      colorName: 'Purple',
      text: '見え見えだよ',
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
