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
import 'theme/game_theme_colors.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const Color _shopPanelColor = GameThemeColors.surface;
  static const Color _shopPanelAccent = GameThemeColors.cyan;
  static const Color _shopPanelAccentStrong = Color(0xFFEAF6FF);

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
    unawaited(RewardedAdManager.instance.warmUp());
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
      await _showShopErrorDialog(title: '購入失敗', error: error);
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
      await _showShopErrorDialog(title: '無料ガチャ失敗', error: error);
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
      await _showShopErrorDialog(title: '無料ガチャ失敗', error: error);
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
      await _showShopErrorDialog(title: 'ガチャ失敗', error: error);
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
    return 15000;
  }

  Color _colorFor(GameItem item) {
    if (item.type == ItemType.frame) {
      return _colorFromFrameName(item.colorName);
    }
    return GameThemeColors.cyan;
  }

  String _subtitleFor(GameItem item) {
    switch (item.type) {
      case ItemType.stamp:
        return '対戦スタンプ';
      case ItemType.skin:
        return 'ボールスキン';
      case ItemType.icon:
        return 'プレイヤーアイコン';
      case ItemType.frame:
        return 'アイコンフレーム';
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

  Future<void> _showShopErrorDialog({
    required String title,
    required Object error,
  }) async {
    final rawMessage = '$error';
    final message =
        rawMessage.contains('不足しています') ? 'コインが不足しています。' : rawMessage;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151723),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Colors.redAccent.withValues(alpha: 0.55),
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white70,
              height: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _playUiTap();
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                '閉じる',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final adsRemoved = AppSettings.instance.adsRemoved.value;
    return Scaffold(
      backgroundColor: GameThemeColors.background,
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x3325F4FF),
                Color(0x00000000),
              ],
            ),
          ),
        ),
        title: const _ShopPageTitle(
          title: 'ショップ',
          subtitle: 'HEXAGON STORE',
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _coinBadge()),
          ),
        ],
      ),
      body: Stack(
        children: [
          const HexagonGridBackground(
            color: GameThemeColors.cyan,
            opacity: 0.04,
            hexRadius: 30,
          ),
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: GameThemeColors.cyan),
                )
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    children: [
                      _buildGachaPanel(adsRemoved: adsRemoved),
                      const SizedBox(height: 32),

                      // Direct Buy Shop
                      const Padding(
                        padding: EdgeInsets.only(left: 8, bottom: 12),
                        child: Text(
                          '本日のショップ',
                          style: TextStyle(
                            color: GameThemeColors.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1,
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
        color: _shopPanelColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: 0.54),
          width: 1.3,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Icon(
                _iconForItem(item),
                color: accent,
                size: 32,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.2,
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
                  item.isStamp ? '重複時は強化' : 'コレクションアイテム',
                  style: const TextStyle(
                    color: Colors.white54,
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
                      color: _shopPanelAccentStrong,
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

  Widget _buildGachaPanel({required bool adsRemoved}) {
    final freeLabel = adsRemoved
        ? '1日1回無料  残り$_remainingPremiumFreeRolls回'
        : '動画で無料  残り$_remainingAdRolls回';
    final freeIcon = adsRemoved ? Icons.card_giftcard : Icons.ondemand_video;
    final canUseFree = adsRemoved
        ? !_isBuying &&
            _premiumFreeRollsUsed < GachaManager.dailyPremiumFreeRollLimit
        : !_isBuying && _adRollsUsed < GachaManager.dailyAdRollLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 12),
          child: Text(
            'ガチャ',
            style: TextStyle(
              color: GameThemeColors.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1E2D).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: GameThemeColors.cyanBorder,
              width: 1.4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _shopPanelAccent.withValues(alpha: 0.42),
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: _shopPanelAccentStrong,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'コレクションガチャ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'スタンプ、アイコン、フレームを入手できます',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isBuying
                    ? null
                    : () {
                        _playUiTap();
                        unawaited(_rollGacha());
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _shopPanelAccent.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(
                      color: GameThemeColors.cyanBorder,
                      width: 1.4,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ガチャを引く',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(width: 10),
                    HexagonCoinAmount(
                      GachaManager.rollCost,
                      color: Color(0xFFEAF6FF),
                      iconSize: 17,
                      fontSize: 15,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: canUseFree
                    ? () {
                        _playUiTap();
                        unawaited(
                          adsRemoved
                              ? _rollPremiumDailyFreeGacha()
                              : _rollFreeAdGacha(),
                        );
                      }
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _shopPanelAccentStrong,
                  side: BorderSide(
                    color: _shopPanelAccentStrong.withValues(alpha: 0.50),
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: Icon(freeIcon, size: 18),
                label: Text(
                  freeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
          'sword' => Icons.gavel,
          'hexagon' => Icons.hexagon,
          'trophy' => Icons.emoji_events,
          'medal' => Icons.military_tech,
          'crown' => Icons.workspace_premium,
          'diamond' => Icons.diamond,
          'fire' => Icons.local_fire_department,
          'water' => Icons.water_drop,
          'moon' => Icons.dark_mode,
          'visibility' => Icons.visibility,
          'rocket' => Icons.rocket_launch,
          'shield' => Icons.shield,
          'terminal' => Icons.terminal,
          'smile' => Icons.sentiment_satisfied_alt,
          'ribbon' => Icons.workspace_premium,
          'heart' => Icons.favorite,
          'music' => Icons.music_note,
          'cafe' => Icons.coffee,
          'flower' => Icons.local_florist,
          'bell' => Icons.notifications,
          'skull' => Icons.dangerous,
          _ => Icons.person,
        };
      case ItemType.frame:
        return Icons.crop_square;
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

  Widget _coinBadge() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 78, maxWidth: 96),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          border: Border.all(
            color: GameThemeColors.cyanBorder,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            const HexagonCoinIcon(size: 16),
            const SizedBox(width: 4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '$_coins',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFFEAF6FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorFromFrameName(String? colorName) {
    return switch (colorName) {
      'red' => Colors.redAccent,
      'orange' => Colors.orangeAccent,
      'yellow' => GameThemeColors.computer,
      'lime' => Colors.limeAccent,
      'green' => GameThemeColors.endless,
      'blue' => GameThemeColors.blueSide,
      'purple' => Colors.purpleAccent,
      'black' => Colors.white70,
      _ => GameThemeColors.cyan,
    };
  }
}

class _ShopPageTitle extends StatelessWidget {
  const _ShopPageTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          subtitle,
          style: const TextStyle(
            color: GameThemeColors.cyan,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 3.5,
          ),
        ),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
