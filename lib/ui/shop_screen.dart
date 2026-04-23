import 'package:flutter/material.dart';

import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../game/gacha_manager.dart';
import '../game/mission_manager.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final GachaManager _gachaManager = GachaManager.instance;
  final MissionManager _missionManager = MissionManager.instance;

  bool _isLoading = true;
  bool _isBuying = false;
  int _coins = 0;
  List<GameItem> _items = const [];
  List<GameItem> _ownedItems = const [];

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  Future<void> _loadShop() async {
    await _playerData.checkDailyReset();
    final ownedItems = await _playerData.getOwnedItems();
    final items = _playerData.dailyShopItems
        .map(GameItemCatalog.byId)
        .whereType<GameItem>()
        .toList();
    if (!mounted) {
      return;
    }
    setState(() {
      _coins = _playerData.coins;
      _ownedItems = ownedItems;
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _buyItem(GameItem item) async {
    if (_isBuying) {
      return;
    }

    setState(() {
      _isBuying = true;
    });
    try {
      await _playerData.spendCoins(_priceFor(item));
      await _playerData.addOrUpgradeItem(item);
      await _loadShop();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF151723),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _colorFor(item).withValues(alpha: 0.55),
              ),
            ),
            title: Text(
              'PURCHASE COMPLETE',
              style: TextStyle(
                color: _colorFor(item),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              '${item.name} を購入しました。',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF151723),
            title: const Text(
              'PURCHASE FAILED',
              style: TextStyle(color: Colors.redAccent),
            ),
            content:
                Text('$error', style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBuying = false;
        });
      }
    }
  }

  Future<void> _rollGacha() async {
    if (_isBuying) {
      return;
    }

    setState(() {
      _isBuying = true;
    });
    try {
      final result = await _gachaManager.rollGacha();
      await _missionManager.recordEvent('roll_gacha');
      await _loadShop();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF151723),
            title: const Text(
              'DATA DECODE',
              style: TextStyle(color: Colors.purpleAccent),
            ),
            content: Text(
              '${result.item.name} を獲得しました。',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF151723),
            title: const Text(
              'DATA DECODE FAILED',
              style: TextStyle(color: Colors.redAccent),
            ),
            content:
                Text('$error', style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBuying = false;
        });
      }
    }
  }

  bool _canBuy(GameItem item) {
    final owned = _ownedItems.where((ownedItem) => ownedItem.id == item.id);
    if (owned.isEmpty) {
      return true;
    }
    final ownedItem = owned.first;
    if (ownedItem.isStamp) {
      return !ownedItem.isMaxLevel;
    }
    return false;
  }

  int _priceFor(GameItem item) {
    switch (item.rarity) {
      case ItemRarity.common:
        return 5000;
      case ItemRarity.rare:
        return 9000;
      case ItemRarity.epic:
      case ItemRarity.legendary:
        return 15000;
    }
  }

  Color _colorFor(GameItem item) {
    switch (item.rarity) {
      case ItemRarity.common:
        return Colors.cyanAccent;
      case ItemRarity.rare:
        return Colors.greenAccent;
      case ItemRarity.epic:
        return Colors.orangeAccent;
      case ItemRarity.legendary:
        return Colors.pinkAccent;
    }
  }

  String _subtitleFor(GameItem item) {
    switch (item.type) {
      case ItemType.stamp:
        return '対戦スタンプ';
      case ItemType.skin:
        return 'ボールスキン';
      case ItemType.vfx:
        return '演出データ';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121520),
        title: const Text(
          'DAILY SHOP',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.amberAccent.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.monetization_on,
                            color: Colors.amberAccent),
                        const SizedBox(width: 8),
                        Text(
                          '$_coins COIN',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isBuying ? null : _rollGacha,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.purpleAccent,
                      side: BorderSide(
                        color: Colors.purpleAccent.withValues(alpha: 0.6),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('DATA DECODE 1000C'),
                  ),
                  const SizedBox(height: 16),
                  for (final item in _items) ...[
                    _buildItemCard(item),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildItemCard(GameItem item) {
    final accent = _colorFor(item);
    final canBuy = _canBuy(item);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151723),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              item.type == ItemType.skin
                  ? Icons.palette
                  : item.type == ItemType.vfx
                      ? Icons.auto_awesome
                      : Icons.chat_bubble,
              color: accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitleFor(item),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: !_isBuying && canBuy ? () => _buyItem(item) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent.withValues(alpha: canBuy ? 0.22 : 0.08),
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.7)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: Text(
              canBuy ? '${_priceFor(item)}C' : 'OWNED',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
