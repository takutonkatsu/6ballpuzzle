import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../audio/audio_selection_manager.dart';
import '../audio/seamless_bgm.dart';
import '../audio/sfx.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../game/components/ball_component.dart';
import '../game/gacha_manager.dart';
import '../game/game_models.dart';
import '../game/mission_manager.dart';
import 'components/gacha_animation_screen.dart';
import 'components/game_pressable.dart';
import 'components/hexagon_grid_background.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/player_icon_image.dart';
import 'components/rewarded_ad_manager.dart';
import 'components/screen_bottom_banner_ad.dart';
import 'theme/game_theme_colors.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({
    super.key,
    this.embedded = false,
    this.onEconomyChanged,
  });

  final bool embedded;
  final FutureOr<void> Function()? onEconomyChanged;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const Color _shopPanelColor = GameThemeColors.surface;
  static const Color _shopPanelAccentStrong = Color(0xFFEAF6FF);
  static const int _dailyShopItemPrice = 15000;
  static const int _permanentShopItemPrice = 500000;
  static const int _medalExchangeItemCost = 200;

  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final GachaManager _gachaManager = GachaManager.instance;
  final MissionManager _missionManager = MissionManager.instance;
  final AudioPlayer _gachaAudioPreviewPlayer = AudioPlayer();

  bool _isLoading = true;
  bool _isBuying = false;
  int _coins = 0;
  int _collectionMedals = 0;
  List<GameItem> _items = const [];
  List<GameItem> _ownedItems = const [];
  int _adRollsUsed = 0;
  int _premiumAdRollsUsed = 0;
  Map<GachaCategory, int> _categoryAdRollsUsed = const {};

  int get _remainingAdRolls =>
      (GachaManager.dailyAdRollLimit - _adRollsUsed).clamp(0, 999);
  int get _remainingPremiumAdRolls =>
      (GachaManager.dailyPremiumAdRollLimit - _premiumAdRollsUsed)
          .clamp(0, 999);
  int _remainingCategoryAdRolls(GachaCategory category) =>
      (GachaManager.categoryAdRollLimit(category) -
              (_categoryAdRollsUsed[category] ?? 0))
          .clamp(0, 999);

  bool get _adsGloballyDisabled =>
      AppSettings.instance.serverAdsGloballyDisabled.value;

  bool get _showsAdGachaButtons => !_adsGloballyDisabled;

  List<_MedalExchangeEntry> get _dailyMedalExchangeItems {
    final random = Random(_dailyExchangeSeed());
    final effects = List<GameItem>.from(GameItemCatalog.effectItems)
      ..sort((a, b) => a.id.compareTo(b.id));
    final audios = List<GameItem>.from(GameItemCatalog.audioItems)
      ..sort((a, b) => a.id.compareTo(b.id));
    final entries = <_MedalExchangeEntry>[];
    if (effects.isNotEmpty) {
      final item = effects[random.nextInt(effects.length)];
      entries.add(
        _MedalExchangeEntry(itemId: item.id, cost: _medalExchangeItemCost),
      );
    }
    final selectedAudioIds = <String>{};
    while (audios.isNotEmpty &&
        selectedAudioIds.length < 2 &&
        selectedAudioIds.length < audios.length) {
      final item = audios[random.nextInt(audios.length)];
      if (selectedAudioIds.add(item.id)) {
        entries.add(
          _MedalExchangeEntry(itemId: item.id, cost: _medalExchangeItemCost),
        );
      }
    }
    return entries;
  }

  int _dailyExchangeSeed() {
    final jstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    return jstNow.year * 10000 + jstNow.month * 100 + jstNow.day;
  }

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  @override
  void initState() {
    super.initState();
    AppSettings.instance.serverAdsGloballyDisabled.addListener(
      _handleServerAdsConfigChanged,
    );
    if (_showsAdGachaButtons) {
      unawaited(RewardedAdManager.instance.warmUp());
    }
    _loadShop();
  }

  @override
  void dispose() {
    AppSettings.instance.serverAdsGloballyDisabled.removeListener(
      _handleServerAdsConfigChanged,
    );
    unawaited(_gachaAudioPreviewPlayer.dispose());
    super.dispose();
  }

  void _handleServerAdsConfigChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
    final premiumAdRollsUsed = await _gachaManager.premiumAdRollsUsedToday();
    final categoryAdRollsUsed = {
      for (final category in [
        GachaCategory.stamp,
        GachaCategory.profile,
        GachaCategory.effect,
        GachaCategory.audio,
      ])
        category: await _gachaManager.categoryAdRollsUsedToday(category),
    };
    if (!mounted) {
      return;
    }
    setState(() {
      _coins = _playerData.coins;
      _collectionMedals = _playerData.collectionMedals;
      _ownedItems = ownedItems;
      _items = items;
      _adRollsUsed = adRollsUsed;
      _premiumAdRollsUsed = premiumAdRollsUsed;
      _categoryAdRollsUsed = categoryAdRollsUsed;
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
      await _notifyEconomyChanged();
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

  Future<void> _exchangeMedalItem(_MedalExchangeEntry entry) async {
    if (_isBuying) {
      return;
    }
    final item = GameItemCatalog.byId(entry.itemId);
    if (item == null || _ownedItems.any((owned) => owned.id == item.id)) {
      return;
    }

    setState(() {
      _isBuying = true;
    });
    try {
      await _playerData.spendCollectionMedals(entry.cost);
      final grantResult = await _playerData.addOrUpgradeItem(item);
      await _loadShop();
      await _notifyEconomyChanged();
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
                  color: GameThemeColors.cyan.withValues(alpha: 0.55)),
            ),
            title: const Text(
              '交換完了',
              style: TextStyle(
                color: GameThemeColors.cyan,
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
      await _showShopErrorDialog(title: '交換失敗', error: error);
    } finally {
      if (mounted) {
        setState(() {
          _isBuying = false;
        });
      }
    }
  }

  Future<void> _rollFreeAdGacha() async {
    if (_adsGloballyDisabled ||
        _isBuying ||
        _adRollsUsed >= GachaManager.dailyAdRollLimit) {
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
      await _notifyEconomyChanged();
      if (!mounted) {
        return;
      }
      await _playGachaResultAudioIfNeeded(result);
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

  Future<void> _rollPremiumAdGacha() async {
    if (_adsGloballyDisabled ||
        _isBuying ||
        _premiumAdRollsUsed >= GachaManager.dailyPremiumAdRollLimit) {
      return;
    }

    setState(() {
      _isBuying = true;
    });
    try {
      for (var i = 0; i < GachaManager.premiumAdRollAdViews; i += 1) {
        final rewarded = await RewardedAdManager.instance.showDoubleRewardAd();
        if (!rewarded) {
          throw StateError('広告の視聴が完了しませんでした。');
        }
      }
      final result = await _gachaManager.rollPremiumAdGacha();
      await _missionManager.recordEvent('roll_gacha');
      await _loadShop();
      await _notifyEconomyChanged();
      if (!mounted) {
        return;
      }
      await _playGachaResultAudioIfNeeded(result);
      await _showGachaResultDialog(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showShopErrorDialog(title: 'プレミアム広告ガチャ失敗', error: error);
    } finally {
      if (mounted) {
        setState(() {
          _isBuying = false;
        });
      }
    }
  }

  Future<void> _rollGacha([
    GachaCategory category = GachaCategory.standard,
  ]) async {
    if (_isBuying) {
      return;
    }

    setState(() {
      _isBuying = true;
    });
    try {
      final result = category == GachaCategory.standard
          ? await _gachaManager.rollGacha()
          : await _gachaManager.rollCategoryGacha(category);
      await _missionManager.recordEvent('roll_gacha');
      await _loadShop();
      await _notifyEconomyChanged();
      if (!mounted) {
        return;
      }
      await _playGachaResultAudioIfNeeded(result);
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

  Future<void> _rollCategoryAdGacha(GachaCategory category) async {
    if (_adsGloballyDisabled ||
        _isBuying ||
        _remainingCategoryAdRolls(category) <= 0) {
      return;
    }

    setState(() {
      _isBuying = true;
    });
    try {
      final adViews = GachaManager.categoryAdRollAdViews(category);
      for (var i = 0; i < adViews; i += 1) {
        final rewarded = await RewardedAdManager.instance.showDoubleRewardAd();
        if (!rewarded) {
          throw StateError('広告の視聴が完了しませんでした。');
        }
      }
      final result = await _gachaManager.rollCategoryAdGacha(category);
      await _missionManager.recordEvent('roll_gacha');
      await _loadShop();
      await _notifyEconomyChanged();
      if (!mounted) {
        return;
      }
      await _playGachaResultAudioIfNeeded(result);
      await _showGachaResultDialog(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showShopErrorDialog(title: '広告ガチャ失敗', error: error);
    } finally {
      if (mounted) {
        setState(() {
          _isBuying = false;
        });
      }
    }
  }

  Future<void> _playGachaResultAudioIfNeeded(GachaRollResult result) async {
    if (!result.item.isAudio) {
      return;
    }
    final fileName = AudioSelectionManager.audioFileForItemId(result.item.id);
    if (fileName == null) {
      return;
    }
    try {
      await SeamlessBgm.instance.suspendForExternalAudio();
      await _gachaAudioPreviewPlayer.stop();
      await _gachaAudioPreviewPlayer.setReleaseMode(ReleaseMode.stop);
      await _gachaAudioPreviewPlayer.setVolume(
        (AppSettings.instance.sfxVolume.value *
                AudioSelectionManager.volumeMultiplierForAudioId(
                    result.item.id))
            .clamp(0.0, 1.0),
      );
      await _gachaAudioPreviewPlayer.play(AssetSource('audio/$fileName'));
      unawaited(
        _gachaAudioPreviewPlayer.onPlayerComplete.first.then(
          (_) => SeamlessBgm.instance.resumeFromExternalAudio(),
        ),
      );
    } catch (_) {
      await SeamlessBgm.instance.resumeFromExternalAudio();
    }
  }

  Future<void> _stopGachaResultAudioAndResumeBgm() async {
    try {
      await _gachaAudioPreviewPlayer.stop();
    } catch (_) {
      // ガチャ結果音の停止失敗で画面復帰は止めない。
    }
    await SeamlessBgm.instance.resumeFromExternalAudio();
  }

  Future<void> _showGachaResultDialog(GachaRollResult result) async {
    await Navigator.of(context).push(
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
    await _stopGachaResultAudioAndResumeBgm();
  }

  Future<void> _notifyEconomyChanged() async {
    await widget.onEconomyChanged?.call();
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
    if (GameItemCatalog.permanentShopItems
        .any((shopItem) => shopItem.id == item.id)) {
      return _permanentShopItemPrice;
    }
    return _dailyShopItemPrice;
  }

  Color _colorFor(GameItem item) {
    return GameThemeColors.cyan;
  }

  Color _iconColorFor(GameItem item) {
    if (item.type == ItemType.frame || item.type == ItemType.banner) {
      return _colorFromFrameName(item.colorName);
    }
    return _colorFor(item);
  }

  String _subtitleFor(GameItem item) {
    if (item.id == 'skin_luxury_prism') {
      return 'ボールスキン / 演出つき';
    }
    switch (item.type) {
      case ItemType.stamp:
        return '対戦スタンプ';
      case ItemType.skin:
        return 'ボールスキン';
      case ItemType.icon:
        return 'プレイヤーアイコン';
      case ItemType.frame:
        return 'アイコンフレーム';
      case ItemType.banner:
        return 'プロフィールバナー';
      case ItemType.vfx:
        return '演出データ';
      case ItemType.audio:
        return 'ミュージック';
    }
  }

  String _detailFor(GameItem item) {
    if (item.id == 'skin_luxury_prism') {
      return 'コレクションアイテム';
    }
    return item.isStamp ? '重複時は強化' : 'コレクションアイテム';
  }

  String _grantResultMessage(ItemGrantResult grantResult) {
    final item = grantResult.item;
    if (!grantResult.isDuplicate) {
      return '${item.name} を獲得しました。';
    }
    if (grantResult.leveledUp) {
      return '${item.name} が Lv.${item.level} になりました。';
    }
    if (grantResult.collectionMedalsAdded > 0) {
      return '${item.name} はすでに所持しています。\nコレクションメダル +${grantResult.collectionMedalsAdded}';
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
    final content = Stack(
      children: [
        if (!widget.embedded)
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  children: [
                    _buildGachaPanel(),
                    const SizedBox(height: 28),
                    _buildMedalExchangePanel(),
                    const SizedBox(height: 32),
                    _sectionTitle('限定コレクション'),
                    for (final item in GameItemCatalog.permanentShopItems.where(
                      (item) => item.id != PlayerDataManager.retiredPrismSkinId,
                    )) ...[
                      _buildItemCard(item),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 20),
                    _sectionTitle('デイリーセール'),
                    for (final item in _items) ...[
                      _buildItemCard(item),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ],
    );
    if (widget.embedded) {
      return Column(
        children: [
          _embeddedHeader('ショップ', 'HEXAGON STORE'),
          Expanded(child: content),
        ],
      );
    }
    return Scaffold(
      backgroundColor: GameThemeColors.background,
      bottomNavigationBar: const ScreenBottomBannerAd(),
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
      body: content,
    );
  }

  Widget _embeddedHeader(String title, String subtitle) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(child: _ShopPageTitle(title: title, subtitle: subtitle)),
            Align(
              alignment: Alignment.centerRight,
              child: _coinBadge(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: GameThemeColors.cyan,
          fontWeight: FontWeight.w900,
          fontSize: 16,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildItemCard(GameItem item) {
    final accent = _colorFor(item);
    final iconAccent = _iconColorFor(item);
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
              border: Border.all(color: iconAccent.withValues(alpha: 0.7)),
            ),
            child: Center(
              child: _itemIconWidget(item, iconAccent),
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
                  _detailFor(item),
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
            child: _shopPressableButton(
              enabled: !_isBuying && canBuy,
              color: accent,
              height: 44,
              radius: 6,
              onTap: () => unawaited(_buyItem(item)),
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

  Widget _buildMedalExchangePanel() {
    final exchangeItems = _dailyMedalExchangeItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _sectionTitle('コレクションメダル交換所')),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _collectionMedalBadge(),
            ),
            const SizedBox(width: 8),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1E2D).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: GameThemeColors.cyan.withValues(alpha: 0.38),
              width: 1.3,
            ),
          ),
          child: Column(
            children: [
              const Text(
                '毎日、エフェクト1枠とミュージック2枠が入れ替わります。所持済みアイテムがガチャで出るとメダルを獲得できます。',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              for (final entry in exchangeItems) ...[
                _medalExchangeCard(entry),
                if (entry != exchangeItems.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _medalExchangeCard(_MedalExchangeEntry entry) {
    final item = GameItemCatalog.byId(entry.itemId);
    if (item == null) {
      return const SizedBox.shrink();
    }
    final owned = _isOwnedForMedalExchange(item);
    final enough = _collectionMedals >= entry.cost;
    final accent = _iconColorFor(item);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.54)),
            ),
            child: Center(child: _itemIconWidget(item, accent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitleFor(item),
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.78),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 94,
            height: 42,
            child: _shopPressableButton(
              enabled: !_isBuying && !owned && enough,
              color: accent,
              height: 42,
              onTap: () => unawaited(_exchangeMedalItem(entry)),
              child: owned
                  ? const Text(
                      '所持済み',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    )
                  : _collectionMedalAmount(entry.cost, compact: true),
            ),
          ),
        ],
      ),
    );
  }

  bool _isOwnedForMedalExchange(GameItem item) {
    if (item.id == 'default') {
      return true;
    }
    if (_playerData.displayPlayerName ==
        AudioSelectionManager.allAudioUnlockedPlayerName) {
      return true;
    }
    if (item.isEffect) {
      return _ownedItems.any((ownedItem) => ownedItem.id == item.id);
    }
    if (item.isAudio) {
      return _ownedItems.any((ownedItem) => ownedItem.id == item.id);
    }
    return _ownedItems.any((ownedItem) => ownedItem.id == item.id);
  }

  Widget _buildGachaPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('ガチャ'),
        _buildFeaturedGachaCard(),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth >= 420;
            final gap = twoColumn ? 12.0 : 10.0;
            final width = twoColumn
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: width,
                  child: _buildGachaTypeCard(
                    title: 'スタンプガチャ',
                    subtitle: '対戦で使えるスタンプ中心',
                    iconAsset:
                        'assets/images/BattleStamps/battle_message_stamp.png',
                    color: GameThemeColors.cyan,
                    price: GachaManager.stampRollCost,
                    category: GachaCategory.stamp,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _buildGachaTypeCard(
                    title: 'プロフィールガチャ',
                    subtitle: 'アイコン・フレーム中心',
                    iconAsset: 'assets/images/Profile_Icon.png',
                    color: const Color(0xFF7AA8FF),
                    price: GachaManager.profileRollCost,
                    category: GachaCategory.profile,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _buildGachaTypeCard(
                    title: 'エフェクトガチャ',
                    subtitle: 'フォーメーション演出など',
                    iconAsset: 'assets/images/Effects_Icon.png',
                    color: const Color(0xFFFFD84D),
                    price: GachaManager.effectRollCost,
                    category: GachaCategory.effect,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _buildGachaTypeCard(
                    title: 'ミュージックガチャ',
                    subtitle: 'BGM・SE コレクション',
                    iconAsset: 'assets/images/Music_Icon.png',
                    color: const Color(0xFFFF7AD9),
                    price: GachaManager.audioRollCost,
                    category: GachaCategory.audio,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFeaturedGachaCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E2D).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GameThemeColors.cyanBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: GameThemeColors.cyan.withValues(alpha: 0.11),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: GameThemeColors.cyan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: GameThemeColors.cyan.withValues(alpha: 0.52),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Image.asset(
                    'assets/images/HomeNav/nav_collection.png',
                    fit: BoxFit.contain,
                  ),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'スタンプ、アイコン、フレームをまとめて狙えます',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _gachaInfoButton(
                color: GameThemeColors.cyan,
                title: 'コレクションガチャ排出率',
                lines: _oddsLinesForCategory(GachaCategory.standard),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: _showsAdGachaButtons ? 2 : 1,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: _showsAdGachaButtons ? 3.1 : 5.8,
            children: [
              _coinOnlyGachaButton(
                label: '通常',
                price: GachaManager.rollCost,
                color: GameThemeColors.cyan,
                onTap: () => _rollGacha(),
              ),
              if (_showsAdGachaButtons)
                _adGachaButton(
                  label: '広告1回',
                  color: GameThemeColors.cyan,
                  remaining: _remainingAdRolls,
                  limit: GachaManager.dailyAdRollLimit,
                  onTap: _rollFreeAdGacha,
                ),
              _coinOnlyGachaButton(
                label: 'プレミアム',
                price: GachaManager.premiumRollCost,
                color: const Color(0xFFFFD84D),
                onTap: () => _rollGacha(GachaCategory.premium),
              ),
              if (_showsAdGachaButtons)
                _adGachaButton(
                  label: '広告3回',
                  color: const Color(0xFFFFD84D),
                  remaining: _remainingPremiumAdRolls,
                  limit: GachaManager.dailyPremiumAdRollLimit,
                  onTap: _rollPremiumAdGacha,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGachaTypeCard({
    required String title,
    required String subtitle,
    required String iconAsset,
    required Color color,
    required int price,
    required GachaCategory category,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _shopPanelColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: color.withValues(alpha: 0.46)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Image.asset(iconAsset, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              _gachaInfoButton(
                color: color,
                title: '$title 排出率',
                lines: _oddsLinesForCategory(category),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _coinOnlyGachaButton(
                  price: price,
                  color: color,
                  onTap: () => _rollGacha(category),
                ),
              ),
              if (_showsAdGachaButtons) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _adGachaButton(
                    label: '広告${GachaManager.categoryAdRollAdViews(category)}回',
                    color: color,
                    remaining: _remainingCategoryAdRolls(category),
                    limit: GachaManager.categoryAdRollLimit(category),
                    onTap: () => _rollCategoryAdGacha(category),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _coinOnlyGachaButton({
    String? label,
    required int price,
    required Color color,
    required Future<void> Function() onTap,
  }) {
    return _shopPressableButton(
      enabled: !_isBuying,
      color: color,
      onTap: () => unawaited(onTap()),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
            ],
            HexagonCoinAmount(
              price,
              color: _shopPanelAccentStrong,
              iconSize: 17,
              fontSize: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _adGachaButton({
    required String label,
    required Color color,
    required int remaining,
    required int limit,
    required Future<void> Function() onTap,
  }) {
    final enabled = !_isBuying && remaining > 0;
    return _shopPressableButton(
      enabled: enabled,
      color: color,
      onTap: () => unawaited(onTap()),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '本日残り$remaining/$limit回',
              maxLines: 1,
              style: TextStyle(
                color: enabled
                    ? Colors.white.withValues(alpha: 0.78)
                    : Colors.white30,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shopPressableButton({
    required bool enabled,
    required Color color,
    required VoidCallback onTap,
    required Widget child,
    double height = 54,
    double radius = 10,
  }) {
    return GamePressable(
      enabled: enabled,
      borderRadius: BorderRadius.circular(radius),
      onTap: () {
        _playUiTap();
        onTap();
      },
      child: Opacity(
        opacity: enabled ? 1 : 0.56,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: enabled
                ? color.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: enabled ? color.withValues(alpha: 0.82) : Colors.white24,
              width: 1.2,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _gachaInfoButton({
    required Color color,
    required String title,
    required List<String> lines,
  }) {
    return IconButton(
      onPressed: () {
        _playUiTap();
        unawaited(
            _showGachaInfoDialog(title: title, color: color, lines: lines));
      },
      icon: Icon(Icons.info_outline_rounded, color: color, size: 20),
      visualDensity: VisualDensity.compact,
      tooltip: '排出率',
    );
  }

  Future<void> _showGachaInfoDialog({
    required String title,
    required Color color,
    required List<String> lines,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151723),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.55)),
        ),
        title: Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: min(MediaQuery.of(context).size.width * 0.82, 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in lines) _oddsLineTile(line, color),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _playUiTap();
              Navigator.of(dialogContext).pop();
            },
            child: Text(
              '閉じる',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _oddsLineTile(String line, Color color) {
    final isHeading = line.startsWith('#');
    final isNote = line.startsWith('※');
    final text = isHeading ? line.substring(1) : line;
    if (isHeading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isNote
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isNote
              ? Colors.white.withValues(alpha: 0.08)
              : color.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isNote ? Colors.white60 : Colors.white.withValues(alpha: 0.88),
          height: 1.35,
          fontWeight: FontWeight.w800,
          fontSize: isNote ? 11 : 12,
        ),
      ),
    );
  }

  List<String> _oddsLinesForCategory(GachaCategory category) {
    final formationEffects = GameItemCatalog.effectItems
        .where((item) => item.id.contains('formation'))
        .toList();
    final ojamaEffects = GameItemCatalog.effectItems
        .where((item) => item.id.contains('ojama'))
        .toList();
    final bgmItems = GameItemCatalog.audioItems
        .where((item) => item.id.contains('bgm'))
        .toList();
    final seItems = GameItemCatalog.audioItems
        .where((item) => !item.id.contains('bgm'))
        .toList();
    const ballSkins = GameItemCatalog.ballSkins;
    final standardEffectAudio = [
      ...GameItemCatalog.effectItems,
      ...GameItemCatalog.audioItems,
      ...GameItemCatalog.ballSkins,
    ];
    final standardProfileItems = [
      ...GameItemCatalog.playerIcons,
      ...GameItemCatalog.standardIconFrames,
      ...GameItemCatalog.profileBanners,
    ];
    final premiumProfileItems = [
      ...GameItemCatalog.playerIcons,
      ...GameItemCatalog.standardIconFrames,
      ...GameItemCatalog.profileBanners,
      ...GameItemCatalog.premiumIconFrames,
    ];
    return switch (category) {
      GachaCategory.stamp => [
          '#カテゴリ別の排出率',
          'スタンプ：100%',
          '#アイテム別の排出率',
          ..._itemOddsLines(GameItemCatalog.commonStamps, 100),
          '※重複したスタンプはLvアップします。',
        ],
      GachaCategory.profile => [
          '#カテゴリ別の排出率',
          'プレイヤーアイコン：50%',
          'フレーム：25%',
          'バナー：25%',
          '#アイテム別の排出率',
          ..._itemOddsLines(GameItemCatalog.playerIcons, 50),
          ..._itemOddsLines(GameItemCatalog.standardIconFrames, 25),
          ..._itemOddsLines(GameItemCatalog.profileBanners, 25),
        ],
      GachaCategory.effect => [
          '#カテゴリ別の排出率',
          'フォーメーション演出：40%',
          '妨害演出：40%',
          'ボールスキン：20%',
          '#アイテム別の排出率',
          ..._itemOddsLines(formationEffects, 40),
          ..._itemOddsLines(ojamaEffects, 40),
          ..._itemOddsLines(ballSkins, 20),
        ],
      GachaCategory.audio => [
          '#カテゴリ別の排出率',
          'BGM：35%',
          'SE：65%',
          '#アイテム別の排出率',
          ..._itemOddsLines(bgmItems, 35),
          ..._itemOddsLines(seItems, 65),
        ],
      GachaCategory.standard => [
          '#通常ガチャ カテゴリ別の排出率',
          'スタンプ：70%',
          'アイコン/フレーム/バナー：25%',
          'エフェクト/ミュージック/ボールスキン：5%',
          '#通常ガチャ アイテム別の排出率',
          ..._itemOddsLines(GameItemCatalog.commonStamps, 70),
          ..._itemOddsLines(standardProfileItems, 25),
          ..._itemOddsLines(standardEffectAudio, 5),
          '#プレミアムガチャ カテゴリ別の排出率',
          'スタンプ：20%',
          'アイコン/フレーム/バナー：40%',
          'エフェクト/ミュージック/ボールスキン：40%',
          '#プレミアムガチャ アイテム別の排出率',
          ..._itemOddsLines(GameItemCatalog.commonStamps, 20),
          ..._itemOddsLines(premiumProfileItems, 40),
          ..._itemOddsLines(standardEffectAudio, 40),
          '※端数処理により表示値と実抽選にわずかな差が出る場合があります。',
        ],
      GachaCategory.premium => [
          '#カテゴリ別の排出率',
          'スタンプ：20%',
          'アイコン/フレーム/バナー：40%',
          'エフェクト/ミュージック/ボールスキン：40%',
          '#アイテム別の排出率',
          ..._itemOddsLines(GameItemCatalog.commonStamps, 20),
          ..._itemOddsLines(premiumProfileItems, 40),
          ..._itemOddsLines(standardEffectAudio, 40),
        ],
    };
  }

  List<String> _itemOddsLines(List<GameItem> items, num categoryPercent) {
    if (items.isEmpty) {
      return const [];
    }
    final value = categoryPercent / items.length;
    final percent = _formatOddsPercent(value);
    return [
      for (final item in items) '${item.name}：$percent%',
    ];
  }

  String _formatOddsPercent(num value) {
    final formatted = value >= 10
        ? value.toStringAsFixed(1)
        : value >= 1
            ? value.toStringAsFixed(2)
            : value.toStringAsFixed(3);
    return formatted.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  IconData _iconForItem(GameItem item) {
    switch (item.type) {
      case ItemType.skin:
        return Icons.circle;
      case ItemType.icon:
        return switch (item.iconName) {
          'bolt' => Icons.bolt,
          'star' => Icons.star,
          'gamepad' => Icons.sports_esports,
          'sword' => Icons.gavel,
          'hexagon' => Icons.hexagon,
          'hexagon2' => Icons.hexagon,
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
      case ItemType.banner:
        return Icons.panorama_rounded;
      case ItemType.vfx:
        return Icons.auto_awesome;
      case ItemType.audio:
        return Icons.music_note_rounded;
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

  Widget _itemIconWidget(GameItem item, Color iconAccent) {
    if (item.type == ItemType.skin) {
      return SizedBox(
        width: 34,
        height: 34,
        child: MiniBallWidget(
          ballColor: BallColor.blue,
          size: 34,
          showOuterGlow: false,
          ballSkinId: item.id,
        ),
      );
    }
    if (item.type == ItemType.frame && item.colorName == 'rainbow') {
      return const RainbowFrameRing(size: 32, strokeWidth: 4);
    }
    if (item.type == ItemType.frame) {
      final frameColor = _colorFromFrameName(item.colorName);
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: frameColor.withValues(alpha: 0.28),
          shape: BoxShape.circle,
          border: Border.all(color: frameColor, width: 2.4),
        ),
      );
    }
    if (item.type == ItemType.banner) {
      final bannerColor = _colorFromFrameName(item.colorName);
      return Container(
        width: 38,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: [
              bannerColor.withValues(alpha: 0.82),
              bannerColor.withValues(alpha: 0.28),
            ],
          ),
          border: Border.all(color: bannerColor, width: 1.6),
        ),
        child: const Icon(
          Icons.panorama_rounded,
          color: Colors.white,
          size: 18,
        ),
      );
    }
    if (item.type == ItemType.icon) {
      return PlayerIconImage(
        iconId: item.id,
        fallbackIcon: _iconForItem(item),
        size: 38,
      );
    }
    if (item.type == ItemType.stamp) {
      return Image.asset(
        'assets/images/BattleStamps/battle_message_stamp.png',
        width: 34,
        height: 34,
        fit: BoxFit.contain,
      );
    }
    if (item.type == ItemType.audio) {
      return Icon(Icons.music_note_rounded, color: iconAccent, size: 32);
    }
    if (item.type == ItemType.vfx) {
      return Icon(Icons.auto_awesome_rounded, color: iconAccent, size: 32);
    }
    return Icon(
      _iconForItem(item),
      color: iconAccent,
      size: 32,
    );
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

  Widget _collectionMedalBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        border:
            Border.all(color: const Color(0xFFFFD84D).withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: _collectionMedalAmount(_collectionMedals, compact: true),
    );
  }

  Widget _collectionMedalAmount(int amount, {bool compact = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/collection_medal.png',
          width: compact ? 17 : 20,
          height: compact ? 17 : 20,
          fit: BoxFit.contain,
        ),
        SizedBox(width: compact ? 4 : 6),
        Text(
          '$amount',
          style: TextStyle(
            color: const Color(0xFFFFE8A3),
            fontWeight: FontWeight.w900,
            fontSize: compact ? 13 : 15,
          ),
        ),
      ],
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
      'white' => Colors.white,
      'black' => const Color(0xFF05070D),
      'rainbow' => const Color(0xFFFFD54A),
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
          AppSettings.instance.translate(title),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _MedalExchangeEntry {
  const _MedalExchangeEntry({
    required this.itemId,
    required this.cost,
  });

  final String itemId;
  final int cost;
}
