enum ItemType {
  stamp,
  skin,
  icon,
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
  bool get isIcon => type == ItemType.icon;
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

  static const List<GameItem> defaultStamps = [
    GameItem(
      id: 'stamp_greet_01',
      name: 'よろしく',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'handshake',
      colorName: 'Cyan',
      text: 'よろしく！',
    ),
    GameItem(
      id: 'stamp_react_01',
      name: 'ありがとう',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'water_drop',
      colorName: 'Blue',
      text: 'ありがとう！',
    ),
    GameItem(
      id: 'stamp_praise_01',
      name: 'グッドゲーム',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'thumb_up',
      colorName: 'Yellow',
      text: 'グッドゲーム！',
    ),
  ];

  static const List<GameItem> commonStamps = [
    ...defaultStamps,
    GameItem(
      id: 'stamp_react_02',
      name: 'すごい',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'local_fire_department',
      colorName: 'Red',
      text: 'やるな！',
    ),
    GameItem(
      id: 'stamp_taunt_01',
      name: 'おっと',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'coffee',
      colorName: 'Magenta',
      text: 'おっと！',
    ),
    GameItem(
      id: 'stamp_taunt_02',
      name: 'まさか',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      iconName: 'visibility',
      colorName: 'Purple',
      text: 'まさか！',
    ),
  ];

  static const List<GameItem> rareStamps = [
    GameItem(
      id: 'stamp_data_burst',
      name: '解析完了',
      type: ItemType.stamp,
      rarity: ItemRarity.rare,
      iconName: 'memory',
      colorName: 'Purple',
      text: '解析完了！',
    ),
  ];

  static const List<GameItem> playerIcons = [
    GameItem(
      id: 'icon_bolt',
      name: '稲妻',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'bolt',
    ),
    GameItem(
      id: 'icon_star',
      name: 'スター',
      type: ItemType.icon,
      rarity: ItemRarity.rare,
      iconName: 'star',
    ),
    GameItem(
      id: 'icon_gamepad',
      name: 'ゲームパッド',
      type: ItemType.icon,
      rarity: ItemRarity.epic,
      iconName: 'gamepad',
    ),
  ];

  static const List<GameItem> epicSkins = [
    GameItem(
      id: 'skin_neon_chrome',
      name: 'ネオンクローム',
      type: ItemType.skin,
      rarity: ItemRarity.rare,
    ),
    GameItem(
      id: 'skin_black_ice',
      name: 'ブラックアイス',
      type: ItemType.skin,
      rarity: ItemRarity.epic,
    ),
  ];

  static const List<GameItem> legacyVfxItems = [
    GameItem(
      id: 'vfx_low_bit_glitch',
      name: 'ロービットグリッチ',
      type: ItemType.vfx,
      rarity: ItemRarity.rare,
    ),
    GameItem(
      id: 'vfx_overdrive_hex',
      name: 'オーバードライブヘックス',
      type: ItemType.vfx,
      rarity: ItemRarity.legendary,
    ),
  ];

  static const List<GameItem> gachaCommonPool = [
    ...commonStamps,
    GameItem(
      id: 'icon_bolt',
      name: '稲妻',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'bolt',
    ),
  ];

  static const List<GameItem> gachaRarePool = [
    ...rareStamps,
    GameItem(
      id: 'icon_star',
      name: 'スター',
      type: ItemType.icon,
      rarity: ItemRarity.rare,
      iconName: 'star',
    ),
    GameItem(
      id: 'skin_neon_chrome',
      name: 'ネオンクローム',
      type: ItemType.skin,
      rarity: ItemRarity.rare,
    ),
  ];

  static const List<GameItem> gachaEpicPool = [
    GameItem(
      id: 'icon_gamepad',
      name: 'ゲームパッド',
      type: ItemType.icon,
      rarity: ItemRarity.epic,
      iconName: 'gamepad',
    ),
    GameItem(
      id: 'skin_black_ice',
      name: 'ブラックアイス',
      type: ItemType.skin,
      rarity: ItemRarity.epic,
    ),
  ];

  static const List<GameItem> unlockableItems = [
    ...commonStamps,
    ...rareStamps,
    ...playerIcons,
    ...epicSkins,
  ];

  static const List<GameItem> allItems = [
    ...unlockableItems,
    ...legacyVfxItems,
  ];

  static const List<GameItem> shopDirectPurchasePool = [
    ...rareStamps,
    ...playerIcons,
    ...epicSkins,
  ];

  static GameItem? byId(String id) {
    for (final item in allItems) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}
