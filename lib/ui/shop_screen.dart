import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../game/gacha_manager.dart';
import '../game/mission_manager.dart';
import 'components/rewarded_ad_manager.dart';

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
  int _adRollsUsed = 0;

  void _playUiTap() {
    AppSfx.playUiTap();
  }

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
        .take(3)
        .toList();
    final adRollsUsed = await _gachaManager.adRollsUsedToday();
    if (!mounted) {
      return;
    }
    setState(() {
      _coins = _playerData.coins;
      _ownedItems = ownedItems;
      _items = items;
      _adRollsUsed = adRollsUsed;
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
      final grantResult = await _playerData.addOrUpgradeItem(item);
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
              _grantResultMessage(grantResult),
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _playUiTap();
                  Navigator.of(dialogContext).pop();
                },
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
                onPressed: () {
                  _playUiTap();
                  Navigator.of(dialogContext).pop();
                },
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

  Future<void> _rollFreeAdGacha() async {
    if (_isBuying || _adRollsUsed >= GachaManager.dailyAdRollLimit) {
      return;
    }

    setState(() {
      _isBuying = true;
    });
    try {
      final rewarded = await RewardedAdManager.instance.showDoubleRewardAd();
      if (!rewarded) {
        throw StateError('動画の視聴が完了しませんでした。');
      }
      final result = await _gachaManager.rollFreeAdGacha();
      await _missionManager.recordEvent('roll_gacha');
      await _loadShop();
      if (!mounted) {
        return;
      }
      await _showGachaResultDialog(result);
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
              '無料ガチャ失敗',
              style: TextStyle(color: Colors.redAccent),
            ),
            content:
                Text('$error', style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () {
                  _playUiTap();
                  Navigator.of(dialogContext).pop();
                },
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
      await _showGachaResultDialog(result);
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
                onPressed: () {
                  _playUiTap();
                  Navigator.of(dialogContext).pop();
                },
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

  Future<void> _showGachaResultDialog(GachaRollResult result) {
    final item = result.grantResult.item;
    final accent = _colorFor(item);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF11131F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: accent.withValues(alpha: 0.85), width: 2),
          ),
          title: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.92 + value * 0.08,
                child: Text(
                  'アイテム解放！',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    shadows: [
                      Shadow(color: accent, blurRadius: 8 + value * 16),
                    ],
                  ),
                ),
              );
            },
          ),
          content: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  Colors.purpleAccent.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.36)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  builder: (context, value, child) {
                    return Transform.rotate(
                      angle: (1 - value) * 0.35,
                      child: Transform.scale(
                        scale: 0.72 + value * 0.28,
                        child: Icon(
                          _iconForItem(item),
                          color: accent,
                          size: 62,
                          shadows: [Shadow(color: accent, blurRadius: 20)],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  item.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _grantResultMessage(result.grantResult),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () {
                _playUiTap();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
        return 9000;
      case ItemRarity.rare:
        return 18000;
      case ItemRarity.epic:
        return 32000;
      case ItemRarity.legendary:
        return 50000;
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
      case ItemType.icon:
        return 'プレイヤーアイコン';
      case ItemType.vfx:
        return '演出データ';
    }
  }

  String _grantResultMessage(ItemGrantResult grantResult) {
    final item = grantResult.item;
    if (!grantResult.isDuplicate) {
      return '${item.name} を獲得しました。';
    }
    if (grantResult.leveledUp) {
      return '${item.name} が Lv.${item.level} になりました。';
    }
    return '${item.name} はすでに所持しています。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121520),
        title: const Text(
          'ITEM SHOP',
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151723),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.purpleAccent.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'アイテムガチャ',
                          style: TextStyle(
                            color: Colors.purpleAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'スタンプ / ボールスキン / アイコンが排出されます',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isBuying
                              ? null
                              : () {
                                  _playUiTap();
                                  unawaited(_rollGacha());
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.purpleAccent,
                            side: BorderSide(
                              color: Colors.purpleAccent.withValues(alpha: 0.6),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('1回 1000C'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _isBuying ||
                                  _adRollsUsed >= GachaManager.dailyAdRollLimit
                              ? null
                              : () {
                                  _playUiTap();
                                  unawaited(_rollFreeAdGacha());
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.amberAccent,
                            side: BorderSide(
                              color: Colors.amberAccent.withValues(alpha: 0.7),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.ondemand_video),
                          label: Text(
                            '動画で無料 $_adRollsUsed/${GachaManager.dailyAdRollLimit}',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '直買いショップ',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '本日の品揃えはランダムで3点です。',
                    style: TextStyle(color: Colors.white60),
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
              _iconForItem(item),
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
            onPressed: !_isBuying && canBuy
                ? () {
                    _playUiTap();
                    unawaited(_buyItem(item));
                  }
                : null,
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

  IconData _iconForItem(GameItem item) {
    switch (item.type) {
      case ItemType.skin:
        return Icons.palette;
      case ItemType.icon:
        return switch (item.iconName) {
          'bolt' => Icons.bolt,
          'star' => Icons.star,
          'gamepad' => Icons.sports_esports,
          _ => Icons.person,
        };
      case ItemType.vfx:
        return Icons.auto_awesome;
      case ItemType.stamp:
        return switch (item.iconName) {
          'handshake' => Icons.handshake,
          'water_drop' => Icons.water_drop,
          'local_fire_department' => Icons.local_fire_department,
          'thumb_up' => Icons.thumb_up,
          'coffee' => Icons.coffee,
          'visibility' => Icons.visibility,
          'memory' => Icons.memory,
          _ => Icons.chat_bubble,
        };
    }
  }
}
