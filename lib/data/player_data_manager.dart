import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/mission_catalog.dart';
import 'models/game_item.dart';

class ItemGrantResult {
  const ItemGrantResult({
    required this.item,
    required this.isDuplicate,
    required this.leveledUp,
    required this.convertedToScrap,
    required this.cyberScrapAdded,
  });

  final GameItem item;
  final bool isDuplicate;
  final bool leveledUp;
  final bool convertedToScrap;
  final int cyberScrapAdded;
}

class PlayerDataManager {
  PlayerDataManager._internal();

  static final PlayerDataManager instance = PlayerDataManager._internal();
  static const bool _debugControlsEnabled =
      bool.fromEnvironment('ENABLE_DEBUG_CONTROLS', defaultValue: true);

  static const int initialCoins = 10000;
  static const String _coinsKey = 'player_coins';
  static const String _expKey = 'player_exp';
  static const String _gachaTicketsKey = 'player_gacha_tickets';
  static const String _cyberScrapKey = 'player_cyber_scrap';
  static const String _itemsKey = 'player_owned_items_json';
  static const String _lastDailyResetKey = 'player_last_daily_reset';
  static const String _currentMissionsKey = 'player_current_missions_json';
  static const String _dailyShopItemsKey = 'player_daily_shop_items_json';
  static const int _debugBuildCoins = 1000000;

  final Random _random = Random();
  bool _loaded = false;
  bool _debugMissionsResetApplied = false;
  int _coins = initialCoins;
  int _exp = 0;
  int _gachaTickets = 0;
  int _cyberScrap = 0;
  List<GameItem> _ownedItems = [];
  String _lastDailyReset = '';
  List<Map<String, dynamic>> _currentMissions = [];
  List<String> _dailyShopItems = [];

  int get coins => _coins;
  int get exp => _exp;
  int get level => _levelFromExp(_exp);
  int get currentLevelExp => _expIntoCurrentLevel(_exp);
  int get nextLevelRequiredExp => getRequiredExp(level);
  int get remainingExpToNextLevel =>
      max(0, nextLevelRequiredExp - currentLevelExp);
  int get gachaTickets => _gachaTickets;
  int get cyberScrap => _cyberScrap;
  List<GameItem> get ownedItems => List.unmodifiable(_ownedItems);
  String get lastDailyReset => _lastDailyReset;
  List<Map<String, dynamic>> get currentMissions => _currentMissions
      .map((mission) => Map<String, dynamic>.from(mission))
      .toList();
  List<String> get dailyShopItems => List.unmodifiable(_dailyShopItems);

  Future<List<GameItem>> getOwnedItems() async {
    await load();
    return ownedItems;
  }

  Future<void> saveOwnedItems(List<GameItem> items) async {
    await load();
    _ownedItems = List<GameItem>.from(items);
    await _saveItems();
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _coins = prefs.getInt(_coinsKey) ?? initialCoins;
    _exp = prefs.getInt(_expKey) ?? 0;
    _gachaTickets = prefs.getInt(_gachaTicketsKey) ?? 0;
    _cyberScrap = prefs.getInt(_cyberScrapKey) ?? 0;
    _lastDailyReset = prefs.getString(_lastDailyResetKey) ?? '';

    final rawItems = prefs.getString(_itemsKey);
    if (rawItems != null && rawItems.isNotEmpty) {
      final decoded = jsonDecode(rawItems);
      if (decoded is List) {
        _ownedItems = decoded
            .whereType<Map>()
            .map((item) => GameItem.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.id.isNotEmpty)
            .toList();
      }
    }

    final rawMissions = prefs.getString(_currentMissionsKey);
    if (rawMissions != null && rawMissions.isNotEmpty) {
      final decoded = jsonDecode(rawMissions);
      if (decoded is List) {
        _currentMissions = decoded
            .whereType<Map>()
            .map((mission) => Map<String, dynamic>.from(mission))
            .toList();
      }
    }

    final rawDailyShopItems = prefs.getString(_dailyShopItemsKey);
    if (rawDailyShopItems != null && rawDailyShopItems.isNotEmpty) {
      final decoded = jsonDecode(rawDailyShopItems);
      if (decoded is List) {
        _dailyShopItems = decoded.map((item) => '$item').toList();
      }
    }

    _loaded = true;

    if (_debugControlsEnabled && _coins != _debugBuildCoins) {
      _coins = _debugBuildCoins;
      await _saveEconomy();
    }
  }

  Future<void> checkDailyReset() async {
    await load();
    final today = _todayKey();
    var changed = false;

    if (_lastDailyReset != today ||
        _currentMissions.length != 3 ||
        _dailyShopItems.length != 3) {
      _lastDailyReset = today;
      _currentMissions = _generateDailyMissions();
      _dailyShopItems = _generateDailyShopItems();
      changed = true;
    }

    if (_applyDebugBuildMissionReset()) {
      changed = true;
    }

    if (changed) {
      await _saveDailyData();
    }
  }

  Future<void> spendCoins(int amount) async {
    await load();
    if (_coins < amount) {
      throw StateError('コインが足りません。必要: $amount / 所持: $_coins');
    }
    _coins -= amount;
    await _saveEconomy();
  }

  Future<void> addCoins(int amount) async {
    await load();
    _coins += amount;
    await _saveEconomy();
  }

  Future<void> setCoinsForDebug(int amount) async {
    if (!_debugControlsEnabled) {
      return;
    }
    await load();
    _coins = max(0, amount);
    await _saveEconomy();
  }

  int getRequiredExp(int currentLevel) {
    final normalizedLevel = max(1, currentLevel);
    return 1000 + (pow(normalizedLevel - 1, 1.5) * 1000).toInt();
  }

  Future<void> addExp(int amount) async {
    await load();
    if (amount <= 0) {
      return;
    }

    final previousLevel = level;
    _exp += amount;
    final currentLevel = level;
    await _saveEconomy();

    if (currentLevel <= previousLevel) {
      return;
    }

    var totalRewardCoins = 0;
    for (var reachedLevel = previousLevel + 1;
        reachedLevel <= currentLevel;
        reachedLevel++) {
      totalRewardCoins += reachedLevel * 500;
    }
    await addCoins(totalRewardCoins);
  }

  Future<void> adjustExpForDebug(int delta) async {
    if (!_debugControlsEnabled) {
      return;
    }
    await load();
    _exp = max(0, _exp + delta);
    await _saveEconomy();
  }

  Future<int> levelUpReward() async {
    await load();
    final reward = level * 500;
    _coins += reward;
    await _saveEconomy();
    return reward;
  }

  Future<void> addGachaTickets(int amount) async {
    await load();
    _gachaTickets += amount;
    await _saveEconomy();
  }

  Future<void> addCyberScrap(int amount) async {
    await load();
    _cyberScrap += amount;
    await _saveEconomy();
  }

  Future<ItemGrantResult> addOrUpgradeItem(GameItem item) async {
    await load();

    final existingIndex = _ownedItems.indexWhere(
      (ownedItem) => ownedItem.id == item.id,
    );

    if (existingIndex == -1) {
      final storedItem = item.isStamp ? item.copyWith(level: 1) : item;
      _ownedItems.add(storedItem);
      await _saveItems();
      return ItemGrantResult(
        item: storedItem,
        isDuplicate: false,
        leveledUp: false,
        convertedToScrap: false,
        cyberScrapAdded: 0,
      );
    }

    final existing = _ownedItems[existingIndex];
    if (existing.isStamp && !existing.isMaxLevel) {
      final upgraded = existing.copyWith(level: existing.level + 1);
      _ownedItems[existingIndex] = upgraded;
      await _saveItems();
      return ItemGrantResult(
        item: upgraded,
        isDuplicate: true,
        leveledUp: true,
        convertedToScrap: false,
        cyberScrapAdded: 0,
      );
    }

    _cyberScrap += 10;
    await _saveAll();
    return ItemGrantResult(
      item: existing,
      isDuplicate: true,
      leveledUp: false,
      convertedToScrap: true,
      cyberScrapAdded: 10,
    );
  }

  Future<void> saveCurrentMissions(List<Map<String, dynamic>> missions) async {
    await load();
    _currentMissions =
        missions.map((mission) => Map<String, dynamic>.from(mission)).toList();
    await _saveDailyData();
  }

  Future<void> saveDailyShopItems(List<String> itemIds) async {
    await load();
    _dailyShopItems = List<String>.from(itemIds);
    await _saveDailyData();
  }

  Future<void> _saveEconomy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_coinsKey, _coins);
    await prefs.setInt(_expKey, _exp);
    await prefs.setInt(_gachaTicketsKey, _gachaTickets);
    await prefs.setInt(_cyberScrapKey, _cyberScrap);
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _itemsKey,
      jsonEncode(_ownedItems.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _saveAll() async {
    await _saveEconomy();
    await _saveItems();
  }

  Future<void> _saveDailyData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDailyResetKey, _lastDailyReset);
    await prefs.setString(
      _currentMissionsKey,
      jsonEncode(_currentMissions),
    );
    await prefs.setString(
      _dailyShopItemsKey,
      jsonEncode(_dailyShopItems),
    );
  }

  List<Map<String, dynamic>> _generateDailyMissions() {
    final pool = List<MissionDefinition>.from(MissionCatalog.dailyPool)
      ..shuffle(_random);
    return pool.take(3).map((mission) => mission.toMissionMap()).toList();
  }

  List<String> _generateDailyShopItems() {
    final pool = List<GameItem>.from(GameItemCatalog.dailyShopPool)
      ..shuffle(_random);
    return pool.take(3).map((item) => item.id).toList();
  }

  bool _applyDebugBuildMissionReset() {
    if (!_debugControlsEnabled ||
        _debugMissionsResetApplied ||
        _currentMissions.isEmpty) {
      return false;
    }

    _debugMissionsResetApplied = true;
    for (final mission in _currentMissions) {
      mission['progress'] = 0;
      mission['claimed'] = false;
      mission['allClearBonusClaimed'] = false;
    }
    return true;
  }

  int _levelFromExp(int value) {
    var currentLevel = 1;
    var remainingExp = max(0, value);

    while (remainingExp >= getRequiredExp(currentLevel)) {
      remainingExp -= getRequiredExp(currentLevel);
      currentLevel++;
    }

    return currentLevel;
  }

  int _expIntoCurrentLevel(int value) {
    var currentLevel = 1;
    var remainingExp = max(0, value);

    while (remainingExp >= getRequiredExp(currentLevel)) {
      remainingExp -= getRequiredExp(currentLevel);
      currentLevel++;
    }

    return remainingExp;
  }

  String _todayKey() {
    return DateTime.now().toLocal().toIso8601String().split('T').first;
  }
}
