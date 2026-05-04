import 'dart:async';

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../audio/sfx.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../game/gacha_manager.dart';
import '../game/mission_manager.dart';
import 'components/gacha_animation_screen.dart';
import 'components/hexagon_grid_background.dart';
import 'components/hexagon_currency_icons.dart';
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
  int _premiumFreeRollsUsed = 0;

  int get _remainingAdRolls =>
      (GachaManager.dailyAdRollLimit - _adRollsUsed).clamp(0, 999);
  int get _remainingPremiumFreeRolls =>
      (GachaManager.dailyPremiumFreeRollLimit - _premiumFreeRollsUsed)
          .clamp(0, 999);

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
    final premiumFreeRollsUsed =
        await _gachaManager.premiumFreeRollsUsedToday();
    if (!mounted) {
      return;
    }
    setState(() {
      _coins = _playerData.coins;
      _ownedItems = ownedItems;
      _items = items;
      _adRollsUsed = adRollsUsed;
      _premiumFreeRollsUsed = premiumFreeRollsUsed;
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
              '購入完了',
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
                child: const Text('閉じる'),
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
              '購入失敗',
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
                child: const Text('閉じる'),
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
                child: const Text('閉じる'),
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

  Future<void> _rollPremiumDailyFreeGacha() async {
    if (_isBuying ||
        _premiumFreeRollsUsed >= GachaManager.dailyPremiumFreeRollLimit) {
      return;
    }

    setState(() {
      _isBuying = true;
    });
    try {
      final result = await _gachaManager.rollPremiumDailyFreeGacha();
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
                child: const Text('閉じる'),
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
              'ガチャ失敗',
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
                child: const Text('閉じる'),
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
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: GachaAnimationScreen(result: result),
          );
        },
      ),
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
        return 8000;
      case ItemRarity.rare:
        return 15000;
      case ItemRarity.epic:
        return 40000;
      case ItemRarity.legendary:
        return 100000;
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
    final adsRemoved = AppSettings.instance.adsRemoved.value;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            _playUiTap();
            Navigator.of(context).pop();
          },
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.purpleAccent.withValues(alpha: 0.2),
                Colors.transparent,
              ],
            ),
          ),
        ),
        title: const Text(
          'ショップ',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
            shadows: [
              Shadow(color: Colors.purpleAccent, blurRadius: 10),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const HexagonGridBackground(
            color: Colors.cyanAccent,
            opacity: 0.04,
            hexRadius: 30,
          ),
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.cyanAccent),
                )
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    children: [
                      // Coins Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1C29),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amberAccent.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amberAccent.withValues(alpha: 0.15),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const HexagonCoinIcon(size: 28),
                            const SizedBox(width: 12),
                            Text(
                              '$_coins',
                              style: const TextStyle(
                                color: Color(0xFFEAF6FF),
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                letterSpacing: 0.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.white24,
                                    blurRadius: 8,
                                  )
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Gacha Section
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 12),
                        child: Text(
                          'ガチャ',
                          style: TextStyle(
                            color: Colors.purpleAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1,
                            shadows: [
                              Shadow(color: Colors.purpleAccent, blurRadius: 8)
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151723),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.purpleAccent.withValues(alpha: 0.5),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purpleAccent.withValues(alpha: 0.1),
                              blurRadius: 20,
                              spreadRadius: -5,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.hub, color: Colors.purpleAccent),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'スタンプ / スキン / アイコンを抽出します',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _isBuying
                                  ? null
                                  : () {
                                      _playUiTap();
                                      unawaited(_rollGacha());
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.purpleAccent.withValues(alpha: 0.2),
                                foregroundColor: Colors.white,
                                shadowColor:
                                    Colors.purpleAccent.withValues(alpha: 0.5),
                                elevation: 8,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(
                                      color: Colors.purpleAccent, width: 1.5),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              icon: const Icon(Icons.auto_awesome,
                                  color: Colors.white),
                              label: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'ガチャを引く（',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                      fontSize: 16,
                                    ),
                                  ),
                                  HexagonCoinIcon(size: 18),
                                  Text(
                                    '${GachaManager.rollCost}）',
                                    style: TextStyle(
                                      color: Color(0xFFEAF6FF),
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: adsRemoved
                                  ? (_isBuying ||
                                          _premiumFreeRollsUsed >=
                                              GachaManager
                                                  .dailyPremiumFreeRollLimit)
                                      ? null
                                      : () {
                                          _playUiTap();
                                          unawaited(
                                            _rollPremiumDailyFreeGacha(),
                                          );
                                        }
                                  : (_isBuying ||
                                          _adRollsUsed >=
                                              GachaManager.dailyAdRollLimit)
                                      ? null
                                      : () {
                                          _playUiTap();
                                          unawaited(_rollFreeAdGacha());
                                        },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amberAccent,
                                side: BorderSide(
                                  color:
                                      Colors.amberAccent.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              icon: Icon(
                                adsRemoved
                                    ? Icons.auto_awesome
                                    : Icons.ondemand_video,
                              ),
                              label: Text(
                                adsRemoved
                                    ? '1日1回無料 残り$_remainingPremiumFreeRolls回'
                                    : '動画で無料 残り$_remainingAdRolls回',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Direct Buy Shop
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 12),
                        child: Text(
                          '本日のショップ',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1,
                            shadows: [
                              Shadow(color: Colors.cyanAccent, blurRadius: 8)
                            ],
                          ),
                        ),
                      ),
                      for (final item in _items) ...[
                        _buildItemCard(item),
                        const SizedBox(height: 16),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildItemCard(GameItem item) {
    final accent = _colorFor(item);
    final canBuy = _canBuy(item);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11131F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.3),
                  accent.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Icon(
                _iconForItem(item),
                color: accent,
                size: 32,
                shadows: [Shadow(color: accent, blurRadius: 10)],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.2,
                    shadows: [Shadow(color: accent, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitleFor(item),
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _rarityLabel(item.rarity),
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            height: 44,
            child: ElevatedButton(
              onPressed: !_isBuying && canBuy
                  ? () {
                      _playUiTap();
                      unawaited(_buyItem(item));
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    canBuy ? accent.withValues(alpha: 0.15) : Colors.white10,
                foregroundColor: canBuy ? accent : Colors.white30,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color:
                        canBuy ? accent.withValues(alpha: 0.8) : Colors.white24,
                  ),
                ),
                padding: EdgeInsets.zero,
              ),
              child: canBuy
                  ? HexagonCoinAmount(
                      _priceFor(item),
                      color: const Color(0xFFEAF6FF),
                      iconSize: 16,
                      fontSize: 14,
                    )
                  : const Text(
                      '購入済み',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        fontSize: 14,
                      ),
                    ),
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

  String _rarityLabel(ItemRarity rarity) {
    switch (rarity) {
      case ItemRarity.common:
        return 'ノーマル';
      case ItemRarity.rare:
        return 'レア';
      case ItemRarity.epic:
        return 'エピック';
      case ItemRarity.legendary:
        return 'レジェンド';
    }
  }
}
