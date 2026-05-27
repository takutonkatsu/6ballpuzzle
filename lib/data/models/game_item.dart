enum ItemType { stamp, skin, icon, vfx }

enum ItemRarity { common, rare, epic, legendary }

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
      name: 'よろしく！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Cyan',
      text: 'よろしく！',
    ),
    GameItem(
      id: 'stamp_react_01',
      name: 'ありがとう！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Blue',
      text: 'ありがとう！',
    ),
    GameItem(
      id: 'stamp_praise_01',
      name: 'グッドゲーム！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Yellow',
      text: 'グッドゲーム！',
    ),
    GameItem(
      id: 'stamp_react_02',
      name: 'やるな！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Red',
      text: 'やるな！',
    ),
    GameItem(
      id: 'stamp_taunt_01',
      name: 'おっと！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Magenta',
      text: 'おっと！',
    ),
    GameItem(
      id: 'stamp_taunt_02',
      name: 'まさか！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Purple',
      text: 'まさか！',
    ),
  ];

  static const List<GameItem> commonStamps = [
    ...defaultStamps,
    GameItem(
      id: 'stamp_after_01',
      name: 'おつかれ！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Cyan',
      text: 'おつかれ！',
    ),
    GameItem(
      id: 'stamp_after_02',
      name: 'もう一戦？',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Blue',
      text: 'もう一戦？',
    ),
    GameItem(
      id: 'stamp_praise_02',
      name: 'すごいね！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Yellow',
      text: 'すごいね！',
    ),
    GameItem(
      id: 'stamp_surprise_01',
      name: 'うそでしょ！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Purple',
      text: 'うそでしょ！',
    ),
    GameItem(
      id: 'stamp_surprise_02',
      name: 'えっ！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Magenta',
      text: 'えっ！',
    ),
    GameItem(
      id: 'stamp_surprise_03',
      name: 'えぐい！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Red',
      text: 'えぐい！',
    ),
    GameItem(
      id: 'stamp_pinch_01',
      name: 'やばい！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Red',
      text: 'やばい！',
    ),
    GameItem(
      id: 'stamp_pinch_02',
      name: '間に合え！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Yellow',
      text: '間に合え！',
    ),
    GameItem(
      id: 'stamp_attack_01',
      name: 'チャンス！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Cyan',
      text: 'チャンス！',
    ),
    GameItem(
      id: 'stamp_waza_01',
      name: 'ヘキサゴン！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Purple',
      text: 'ヘキサゴン！',
    ),
    GameItem(
      id: 'stamp_waza_02',
      name: 'ピラミッド！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Yellow',
      text: 'ピラミッド！',
    ),
    GameItem(
      id: 'stamp_waza_03',
      name: 'ストレート！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Blue',
      text: 'ストレート！',
    ),
    GameItem(
      id: 'stamp_defense_01',
      name: '落ち着け！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Blue',
      text: '落ち着け！',
    ),
    GameItem(
      id: 'stamp_defense_02',
      name: 'まだ大丈夫！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Cyan',
      text: 'まだ大丈夫！',
    ),
    GameItem(
      id: 'stamp_defense_03',
      name: '耐えた！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Yellow',
      text: '耐えた！',
    ),
    GameItem(
      id: 'stamp_defense_04',
      name: '盤面整理！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Blue',
      text: '盤面整理！',
    ),
    GameItem(
      id: 'stamp_attack_02',
      name: 'おじゃま行くよ？',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Red',
      text: 'おじゃま行くよ？',
    ),
    GameItem(
      id: 'stamp_attack_03',
      name: '返せる？',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Magenta',
      text: '返せる？',
    ),
    GameItem(
      id: 'stamp_taunt_03',
      name: 'どうする？',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Purple',
      text: 'どうする？',
    ),
    GameItem(
      id: 'stamp_taunt_04',
      name: '余裕？',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Magenta',
      text: '余裕？',
    ),
    GameItem(
      id: 'stamp_taunt_05',
      name: 'そこ置く？',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Red',
      text: 'そこ置く？',
    ),
    GameItem(
      id: 'stamp_taunt_06',
      name: '油断した？',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Purple',
      text: '油断した？',
    ),
    GameItem(
      id: 'stamp_calm_01',
      name: 'ふぅ…',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Blue',
      text: 'ふぅ…',
    ),
    GameItem(
      id: 'stamp_calm_02',
      name: 'なるほど',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Cyan',
      text: 'なるほど',
    ),
    GameItem(
      id: 'stamp_pray_01',
      name: '奇跡こい！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Yellow',
      text: '奇跡こい！',
    ),
    GameItem(
      id: 'stamp_pray_02',
      name: '祈る！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Purple',
      text: '祈る！',
    ),
    GameItem(
      id: 'stamp_wait_01',
      name: 'ちょっと待って！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Magenta',
      text: 'ちょっと待って！',
    ),
    GameItem(
      id: 'stamp_after_03',
      name: '参りました！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Blue',
      text: '参りました！',
    ),
    GameItem(
      id: 'stamp_after_04',
      name: '次は勝つ！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Red',
      text: '次は勝つ！',
    ),
    GameItem(
      id: 'stamp_taunt_07',
      name: '甘いかも！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Red',
      text: '甘いかも！',
    ),
    GameItem(
      id: 'stamp_praise_03',
      name: 'これは強い！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Yellow',
      text: 'これは強い！',
    ),
    GameItem(
      id: 'stamp_taunt_08',
      name: 'まだまだ！',
      type: ItemType.stamp,
      rarity: ItemRarity.common,
      colorName: 'Purple',
      text: 'まだまだ！',
    ),
  ];

  static const List<GameItem> rareStamps = [];

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
      rarity: ItemRarity.common,
      iconName: 'star',
    ),
    GameItem(
      id: 'icon_gamepad',
      name: 'ゲームパッド',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'gamepad',
    ),
    GameItem(
      id: 'icon_sword',
      name: '剣',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'sword',
    ),
    GameItem(
      id: 'icon_shield',
      name: '盾',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'shield',
    ),
    GameItem(
      id: 'icon_crown',
      name: '王冠',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'crown',
    ),
    GameItem(
      id: 'icon_trophy',
      name: 'トロフィー',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'trophy',
    ),
    GameItem(
      id: 'icon_medal',
      name: 'メダル',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'medal',
    ),
    GameItem(
      id: 'icon_hexagon',
      name: 'ヘキサゴン',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'hexagon',
    ),
    GameItem(
      id: 'icon_diamond',
      name: 'ダイヤ',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'diamond',
    ),
    GameItem(
      id: 'icon_fire',
      name: '炎',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'fire',
    ),
    GameItem(
      id: 'icon_water',
      name: '水滴',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'water',
    ),
    GameItem(
      id: 'icon_moon',
      name: '月',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'moon',
    ),
    GameItem(
      id: 'icon_rocket',
      name: 'ロケット',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'rocket',
    ),
    GameItem(
      id: 'icon_terminal',
      name: '端末',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'terminal',
    ),
    GameItem(
      id: 'icon_smile',
      name: 'スマイル',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'smile',
    ),
    GameItem(
      id: 'icon_ribbon',
      name: 'リボン',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'ribbon',
    ),
    GameItem(
      id: 'icon_heart',
      name: 'ハート',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'heart',
    ),
    GameItem(
      id: 'icon_music',
      name: '音符',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'music',
    ),
    GameItem(
      id: 'icon_cafe',
      name: 'カフェ',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'cafe',
    ),
    GameItem(
      id: 'icon_flower',
      name: '花',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'flower',
    ),
    GameItem(
      id: 'icon_bell',
      name: 'ベル',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'bell',
    ),
    GameItem(
      id: 'icon_visibility',
      name: '目',
      type: ItemType.icon,
      rarity: ItemRarity.common,
      iconName: 'visibility',
    ),
  ];

  static const List<GameItem> ballSkins = [];

  static const List<GameItem> legacyVfxItems = [];

  static const List<GameItem> gachaCommonPool = [
    ...commonStamps,
    ...playerIcons,
  ];

  static const List<GameItem> gachaRarePool = [];

  static const List<GameItem> gachaEpicPool = [];

  static const List<GameItem> unlockableItems = [
    ...commonStamps,
    ...rareStamps,
    ...playerIcons,
    ...ballSkins,
  ];

  static const List<GameItem> allItems = [
    ...unlockableItems,
    ...legacyVfxItems,
  ];

  static const List<GameItem> shopDirectPurchasePool = [
    ...commonStamps,
    ...playerIcons,
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
