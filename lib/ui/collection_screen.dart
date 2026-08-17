import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../audio/audio_selection_manager.dart';
import '../audio/seamless_bgm.dart';
import '../audio/sfx.dart';
import '../data/models/badge_item.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../game/components/ball_component.dart';
import '../game/effect_skin.dart';
import '../game/game_models.dart';
import '../network/multiplayer_manager.dart';
import '../network/ranking_manager.dart';
import 'components/hexagon_grid_background.dart';
import 'components/player_icon_image.dart';
import 'components/screen_bottom_banner_ad.dart';
import 'components/season_rank_badge_icon.dart';
import 'components/stamp_square_tile.dart';
import 'theme/game_theme_colors.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen>
    with SingleTickerProviderStateMixin {
  static const Set<String> _hiddenAudioSectionIds = {
    'delete',
    'drop',
    'hard_drop',
    'obstacle_drop',
    'rotation',
  };

  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final MultiplayerManager _multiplayerManager = MultiplayerManager.instance;
  final ScrollController _stampScrollController = ScrollController();
  late final TabController _tabController;
  bool _loading = true;
  GameItem? _pendingStampToEquip;
  OverlayEntry? _stampInfoOverlay;
  OverlayEntry? _collectionItemOverlay;
  bool _showAllProfileIcons = false;
  bool _showAllProfileFrames = false;
  bool _showAllProfileBanners = false;
  bool _showAllProfileBadges = false;
  String? _pendingBadgeToEquipId;
  final AudioPlayer _audioPreviewPlayer = AudioPlayer();
  StreamSubscription<void>? _audioPreviewCompleteSubscription;
  Timer? _audioPreviewStopTimer;
  String? _previewingAudioId;
  bool _bgmSuspendedForAudioPreview = false;
  final Map<String, String> _selectedAudioPreviewIds = {};
  String? _activeAudioChoiceId;

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(_handleTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _dismissStampInfoOverlay();
    _dismissCollectionItemOverlay();
    _audioPreviewStopTimer?.cancel();
    _audioPreviewCompleteSubscription?.cancel();
    if (_bgmSuspendedForAudioPreview) {
      unawaited(SeamlessBgm.instance.resumeFromExternalAudio());
    }
    unawaited(_audioPreviewPlayer.dispose());
    _stampScrollController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging || _tabController.index != 0) {
      _cancelStampReplace();
    }
  }

  void _cancelStampReplace() {
    if (_pendingStampToEquip == null) {
      return;
    }
    _dismissCollectionItemOverlay();
    setState(() {
      _pendingStampToEquip = null;
    });
  }

  Future<void> _load() async {
    await _playerData.load();
    final savedAudioSelections = await _loadAudioSelections();
    try {
      await RankingManager.instance.syncSeasonRankBadgesForCurrentPlayer();
      await _playerData.load();
    } catch (_) {
      // バッジ同期に失敗しても、保存済みのコレクションは表示する。
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _selectedAudioPreviewIds
        ..clear()
        ..addAll(savedAudioSelections);
    });
  }

  Future<Map<String, String>> _loadAudioSelections() async {
    return AudioSelectionManager.loadSelections();
  }

  Future<void> _saveAudioSelection(String sectionId, String itemId) async {
    await AudioSelectionManager.saveSelection(sectionId, itemId);
  }

  Future<void> _applyAudioSelection(String sectionId, String itemId) async {
    await _saveAudioSelection(sectionId, itemId);
    if (sectionId == 'home_bgm') {
      await _restartSelectedHomeBgm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        if (!widget.embedded)
          const HexagonGridBackground(
            color: GameThemeColors.cyan,
            opacity: 0.04,
            hexRadius: 30,
          ),
        _loading
            ? const SizedBox.shrink()
            : TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStampsTab(),
                  _buildProfileTab(),
                  _buildEffectsTab(),
                  _buildAudioTab(),
                ],
              ),
      ],
    );
    if (widget.embedded) {
      return Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  const _PageTitle(
                    title: 'コレクション',
                    subtitle: 'COLLECTION',
                  ),
                  const SizedBox(height: 10),
                  _NeonTabBar(
                    controller: _tabController,
                    tabs: const ['スタンプ', 'プロフィール', 'エフェクト', 'ミュージック'],
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF080A12),
      bottomNavigationBar: const ScreenBottomBannerAd(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
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
              colors: [Color(0x3325F4FF), Color(0x00000000)],
            ),
          ),
        ),
        title: const _PageTitle(title: 'コレクション', subtitle: 'COLLECTION'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: _NeonTabBar(
            controller: _tabController,
            tabs: const ['スタンプ', 'プロフィール', 'エフェクト', 'ミュージック'],
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildStampsTab() {
    final ownedStampsById = {
      for (final item in _playerData.ownedItems.where((item) => item.isStamp))
        item.id: item,
    };
    final stampCatalog = GameItemCatalog.allItems
        .where((item) => item.isStamp)
        .map((item) => item.copyWith(level: ownedStampsById[item.id]?.level))
        .toList();
    final ownedStampIds = ownedStampsById.keys.toSet();
    final equippedStampIds = _playerData.equippedStampIds;
    final equippedStampIdSet = equippedStampIds
        .where((id) => id != PlayerDataManager.emptyStampSlotId)
        .toSet();
    final equippedStamps = [
      for (final stampId in equippedStampIds)
        stampId == PlayerDataManager.emptyStampSlotId
            ? null
            : ownedStampsById[stampId] ?? GameItemCatalog.byId(stampId),
    ];
    final visibleStampCatalog = stampCatalog
        .where((stamp) => !equippedStampIdSet.contains(stamp.id))
        .toList();
    final ownedStampCount =
        stampCatalog.where((stamp) => ownedStampIds.contains(stamp.id)).length;
    final isReplacing = _pendingStampToEquip != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 360 ? 10.0 : 14.0;
        final gap = constraints.maxWidth < 360 ? 7.0 : 9.0;
        final tileWidth =
            (constraints.maxWidth - horizontalPadding * 2 - gap * 3) / 4;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: isReplacing ? _cancelStampReplace : null,
          child: ListView(
            controller: _stampScrollController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              26,
            ),
            children: [
              _stampSectionHeader(
                '装備スタンプ',
                infoText: 'バトル中に表示される順番です',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var index = 0;
                      index < PlayerDataManager.maxEquippedStampCount;
                      index++)
                    SizedBox(
                      width: tileWidth,
                      child: Builder(
                        builder: (tileContext) => StampSquareTile(
                          item: index < equippedStamps.length
                              ? equippedStamps[index]
                              : null,
                          level: index < equippedStamps.length
                              ? equippedStamps[index]?.level
                              : null,
                          highlight: isReplacing,
                          onTap: () {
                            if (isReplacing) {
                              _replaceEquippedStamp(index);
                              return;
                            }
                            final stamp = index < equippedStamps.length
                                ? equippedStamps[index]
                                : null;
                            if (stamp == null) {
                              return;
                            }
                            _playUiTap();
                            _showCollectionItemPopup(
                              tileContext,
                              _profileChoicePopup(
                                actionLabel: '外す',
                                onAction: () => _removeEquippedStamp(index),
                                showFrame: false,
                              ),
                              width: tileWidth,
                              estimatedHeight: 36,
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
              if (isReplacing) ...[
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    '入れ替える場所を選択',
                    style: TextStyle(
                      color: GameThemeColors.cyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: SizedBox(
                    width: min(tileWidth * 1.12, 108),
                    child: StampSquareTile(
                      item: _pendingStampToEquip,
                      level: _pendingStampToEquip?.level,
                      showLevel: true,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 22),
                _stampSectionHeader(
                  'スタンプ一覧',
                  infoText: 'タップして装備スロットへ入れ替え',
                  metricText: '入手済み：$ownedStampCount/${stampCatalog.length}',
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final stamp in visibleStampCatalog)
                      SizedBox(
                        width: tileWidth,
                        child: Builder(
                          builder: (tileContext) => StampSquareTile(
                            item: stamp,
                            level: stamp.level,
                            showLevel: ownedStampIds.contains(stamp.id),
                            available: ownedStampIds.contains(stamp.id),
                            onTap: ownedStampIds.contains(stamp.id)
                                ? () {
                                    _playUiTap();
                                    _showCollectionItemPopup(
                                      tileContext,
                                      _profileChoicePopup(
                                        actionLabel: '使う',
                                        onAction: () =>
                                            _startStampReplace(stamp),
                                        showFrame: false,
                                      ),
                                      width: tileWidth,
                                      estimatedHeight: 36,
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _stampSectionHeader(
    String title, {
    String? infoText,
    String? metricText,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E2D).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
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
                    fontSize: 15,
                  ),
                ),
                if (metricText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    metricText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GameThemeColors.cyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (infoText != null) ...[
            const SizedBox(width: 8),
            _stampInfoButton(infoText),
          ],
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _stampInfoButton(String message) {
    return Builder(
      builder: (buttonContext) {
        return InkWell(
          onTap: () => _showStampInfoBubble(buttonContext, message),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GameThemeColors.cyan.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: GameThemeColors.cyan.withValues(alpha: 0.56),
              ),
            ),
            child: const Text(
              'i',
              style: TextStyle(
                color: GameThemeColors.cyan,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }

  void _dismissStampInfoOverlay() {
    _stampInfoOverlay?.remove();
    _stampInfoOverlay = null;
  }

  void _dismissCollectionItemOverlay() {
    _collectionItemOverlay?.remove();
    _collectionItemOverlay = null;
  }

  void _showCollectionItemPopup(
    BuildContext anchorContext,
    Widget popup, {
    required double width,
    double estimatedHeight = 112,
  }) {
    _dismissCollectionItemOverlay();
    final overlay = Overlay.of(context);
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) {
      return;
    }
    final anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final maxLeft = max(12.0, overlayBox.size.width - width - 12);
    final left = (anchorTopLeft.dx + anchorBox.size.width / 2 - width / 2)
        .clamp(12.0, maxLeft)
        .toDouble();
    var top = anchorTopLeft.dy + anchorBox.size.height + 6;
    if (top + estimatedHeight > overlayBox.size.height - 12) {
      top = max(12.0, anchorTopLeft.dy - estimatedHeight - 6);
    }
    _collectionItemOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissCollectionItemOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Material(
              color: Colors.transparent,
              child: popup,
            ),
          ),
        ],
      ),
    );
    overlay.insert(_collectionItemOverlay!);
  }

  void _showStampInfoBubble(BuildContext anchorContext, String message) {
    _playUiTap();
    _dismissStampInfoOverlay();
    final overlay = Overlay.of(context);
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) {
      return;
    }
    final anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    const bubbleWidth = 238.0;
    final left = (anchorTopLeft.dx + anchorBox.size.width - bubbleWidth)
        .clamp(12.0, max(12.0, overlayBox.size.width - bubbleWidth - 12))
        .toDouble();
    final top = max(8.0, anchorTopLeft.dy - 62);
    _stampInfoOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissStampInfoOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: bubbleWidth,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF20D1424),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: GameThemeColors.cyan.withValues(alpha: 0.70),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_stampInfoOverlay!);
  }

  void _showDismissibleStampMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          showCloseIcon: true,
          closeIconColor: Colors.white,
          backgroundColor: const Color(0xF20D1424),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: GameThemeColors.cyan.withValues(alpha: 0.58),
            ),
          ),
        ),
      );
  }

  Widget _stampActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: GameThemeColors.cyan,
          foregroundColor: const Color(0xFF04131A),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _startStampReplace(GameItem stamp) {
    _playUiTap();
    _dismissCollectionItemOverlay();
    setState(() {
      _pendingStampToEquip = stamp;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stampScrollController.hasClients) {
        _stampScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _removeEquippedStamp(int slotIndex) async {
    _playUiTap();
    _dismissCollectionItemOverlay();
    final next = _playerData.equippedStampIds
        .take(PlayerDataManager.maxEquippedStampCount)
        .toList();
    if (slotIndex >= next.length ||
        next[slotIndex] == PlayerDataManager.emptyStampSlotId) {
      return;
    }
    final equippedActualCount =
        next.where((id) => id != PlayerDataManager.emptyStampSlotId).length;
    if (equippedActualCount <= 1) {
      _showDismissibleStampMessage('スタンプは少なくとも1つ装備してください。');
      return;
    }
    next[slotIndex] = PlayerDataManager.emptyStampSlotId;
    await _playerData.setEquippedStampIds(next);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _replaceEquippedStamp(int slotIndex) async {
    final stamp = _pendingStampToEquip;
    if (stamp == null) {
      return;
    }
    _playUiTap();
    final next = _playerData.equippedStampIds
        .take(PlayerDataManager.maxEquippedStampCount)
        .toList();
    while (next.length <= slotIndex &&
        next.length < PlayerDataManager.maxEquippedStampCount) {
      next.add(PlayerDataManager.emptyStampSlotId);
    }
    final existingIndex = next.indexOf(stamp.id);
    if (slotIndex >= next.length) {
      return;
    } else if (existingIndex == slotIndex) {
      // No-op: keep the current slot order when the same stamp is selected.
    } else if (existingIndex >= 0) {
      final displacedStampId = next[slotIndex];
      next[slotIndex] = stamp.id;
      next[existingIndex] = displacedStampId;
    } else {
      next[slotIndex] = stamp.id;
    }
    await _playerData.setEquippedStampIds(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingStampToEquip = null;
    });
  }

  Widget _buildProfileTab() {
    final ownedIconIds = _playerData.ownedItems
        .where((item) => item.type == ItemType.icon)
        .map((item) => item.id)
        .toSet();
    final ownedFrameIds = _playerData.ownedItems
        .where((item) => item.type == ItemType.frame)
        .map((item) => item.id)
        .toSet();
    final ownedBannerIds = _playerData.ownedItems
        .where((item) => item.type == ItemType.banner)
        .map((item) => item.id)
        .toSet();
    final iconEntries = _orderedProfileItems(
      currentId: _playerData.equippedPlayerIconId,
      items: [
        const GameItem(
          id: 'default',
          name: 'デフォルト',
          type: ItemType.icon,
          rarity: ItemRarity.common,
          iconName: 'person',
        ),
        ...GameItemCatalog.playerIcons,
      ],
      ownedIds: {'default', ...ownedIconIds},
    );
    final frameEntries = _orderedProfileItems(
      currentId: _playerData.equippedIconFrameId,
      items: [
        const GameItem(
          id: 'default',
          name: 'デフォルト',
          type: ItemType.frame,
          rarity: ItemRarity.common,
          colorName: 'cyan',
        ),
        ...GameItemCatalog.iconFrames,
      ],
      ownedIds: {'default', ...ownedFrameIds},
    );
    final bannerEntries = _orderedProfileItems(
      currentId: _playerData.equippedProfileBannerId,
      items: [
        const GameItem(
          id: 'default',
          name: 'デフォルト',
          type: ItemType.banner,
          rarity: ItemRarity.common,
          colorName: 'cyan',
        ),
        ...GameItemCatalog.profileBanners,
      ],
      ownedIds: {'default', ...ownedBannerIds},
    );
    final badgeEntries = _profileBadgeEntries();
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 360 ? 10.0 : 14.0;
        final gap = constraints.maxWidth < 360 ? 7.0 : 9.0;
        final tileWidth =
            (constraints.maxWidth - horizontalPadding * 2 - gap * 3) / 4;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12,
                horizontalPadding,
                0,
              ),
              child: _profilePreviewCard(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  30,
                ),
                children: [
                  _profileItemSection<GameItem>(
                    title: 'アイコン一覧',
                    metricText:
                        '入手済み：${iconEntries.where((entry) => entry.owned).length}/${iconEntries.length}',
                    entries: iconEntries,
                    showAll: _showAllProfileIcons,
                    tileWidth: tileWidth,
                    gap: gap,
                    onToggleShowAll: () {
                      _playUiTap();
                      _dismissCollectionItemOverlay();
                      setState(
                        () => _showAllProfileIcons = !_showAllProfileIcons,
                      );
                    },
                    tileBuilder: (entry) => _profileIconTile(
                      iconId: entry.item.id,
                      current:
                          _playerData.equippedPlayerIconId == entry.item.id,
                      available: entry.owned,
                    ),
                    onTap: (entry, anchorContext) =>
                        _selectProfileIcon(entry, anchorContext),
                  ),
                  const SizedBox(height: 20),
                  _profileItemSection<GameItem>(
                    title: 'フレーム一覧',
                    metricText:
                        '入手済み：${frameEntries.where((entry) => entry.owned).length}/${frameEntries.length}',
                    entries: frameEntries,
                    showAll: _showAllProfileFrames,
                    tileWidth: tileWidth,
                    gap: gap,
                    onToggleShowAll: () {
                      _playUiTap();
                      _dismissCollectionItemOverlay();
                      setState(
                        () => _showAllProfileFrames = !_showAllProfileFrames,
                      );
                    },
                    tileBuilder: (entry) => _profileFrameTile(
                      frame: entry.item,
                      current: _playerData.equippedIconFrameId == entry.item.id,
                      available: entry.owned,
                    ),
                    onTap: (entry, anchorContext) =>
                        _selectProfileFrame(entry, anchorContext),
                  ),
                  const SizedBox(height: 20),
                  _profileItemSection<GameItem>(
                    title: 'バナー一覧',
                    metricText:
                        '入手済み：${bannerEntries.where((entry) => entry.owned).length}/${bannerEntries.length}',
                    entries: bannerEntries,
                    showAll: _showAllProfileBanners,
                    tileWidth: tileWidth,
                    gap: gap,
                    onToggleShowAll: () {
                      _playUiTap();
                      _dismissCollectionItemOverlay();
                      setState(
                        () => _showAllProfileBanners = !_showAllProfileBanners,
                      );
                    },
                    tileBuilder: (entry) => _profileBannerTile(
                      banner: entry.item,
                      current:
                          _playerData.equippedProfileBannerId == entry.item.id,
                      available: entry.owned,
                    ),
                    onTap: (entry, anchorContext) =>
                        _selectProfileBanner(entry, anchorContext),
                  ),
                  const SizedBox(height: 20),
                  _profileBadgeSection(
                    entries: badgeEntries,
                    showAll: _showAllProfileBadges,
                    tileWidth: tileWidth,
                    gap: gap,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAudioTab() {
    const sections = [
      _AudioPreviewSection(
        id: 'home_bgm',
        title: 'ホームBGM',
        subtitle: 'ホーム画面で流れるBGM',
        items: [
          _AudioPreviewItem(
            id: 'home_bgm_01',
            numberLabel: '01',
            fileName: 'bgm_homeScreen01_Solid_State_Blue_Hero.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'home_bgm_02',
            numberLabel: '02',
            fileName: 'bgm_homeScreen02_ドードドド・スタンピード.mp3',
            isBgm: true,
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'battle_bgm',
        title: 'バトルBGM',
        subtitle: '対戦中に流れるBGM',
        items: [
          _AudioPreviewItem(
            id: 'battle_bgm_01',
            numberLabel: '01',
            fileName: 'bgm_battle01_8の字サーキット_2.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_02',
            numberLabel: '02',
            fileName: 'bgm_battle02_Light_Ray.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_03',
            numberLabel: '03',
            fileName: 'bgm_battle03_小さな台風のケビン.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_04',
            numberLabel: '04',
            fileName: 'bgm_battle04_灼熱のユーロビート_2.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_05',
            numberLabel: '05',
            fileName: 'bgm_battle05_渦巻く砂漠の風.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_06',
            numberLabel: '06',
            fileName: 'bgm_battle06_有明のユーロビート_2.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_07',
            numberLabel: '07',
            fileName: 'bgm_battle07_忘れてたー！_2.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_08',
            numberLabel: '08',
            fileName: 'bgm_battle08バーゲンセール_2.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_09',
            numberLabel: '09',
            fileName: 'bgm_battle09どたばたサーカス_2.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_10',
            numberLabel: '10',
            fileName: 'bgm_battle10_迅雷のユーロビート_2.mp3',
            isBgm: true,
          ),
          _AudioPreviewItem(
            id: 'battle_bgm_11',
            numberLabel: '11',
            fileName: 'bgm_battle11_コミック☆はろはろ！.mp3',
            isBgm: true,
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'ready',
        title: 'READY',
        subtitle: '開始カウントダウン',
        items: [
          _AudioPreviewItem(
            id: 'ready_01',
            numberLabel: '01',
            fileName: 'readyGo01_メニューを開く3.mp3',
          ),
          _AudioPreviewItem(
            id: 'ready_02',
            numberLabel: '02',
            fileName: 'readyGo02_メニューを開く2.mp3',
          ),
          _AudioPreviewItem(
            id: 'ready_03',
            numberLabel: '03',
            fileName: 'readyGo03_3_2_1_GO!!!_レースのスタート音.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'load_screen',
        title: 'ロード画面',
        subtitle: 'アプリ起動時',
        items: [
          _AudioPreviewItem(
            id: 'load_screen_01',
            numberLabel: '01',
            fileName: 'loadScreen01_サウンドロゴ_3.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'winner',
        title: '勝利',
        subtitle: '勝利リザルト',
        items: [
          _AudioPreviewItem(
            id: 'winner_01',
            numberLabel: '01',
            fileName: AppSfx.win,
          ),
          _AudioPreviewItem(
            id: 'winner_02',
            numberLabel: '02',
            fileName: 'winner02_jingle_10.mp3',
          ),
          _AudioPreviewItem(
            id: 'winner_03',
            numberLabel: '03',
            fileName: 'winner03_レトロなゲームクリア音.mp3',
          ),
          _AudioPreviewItem(
            id: 'winner_04',
            numberLabel: '04',
            fileName: 'winner04_ロボユーウィン.mp3',
          ),
          _AudioPreviewItem(
            id: 'winner_05',
            numberLabel: '05',
            fileName: 'winner05_ミニファンファーレ.mp3',
          ),
          _AudioPreviewItem(
            id: 'winner_06',
            numberLabel: '06',
            fileName: 'winner06_流れるようなゲームクリア音.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'loser',
        title: '敗北',
        subtitle: '敗北リザルト',
        items: [
          _AudioPreviewItem(
            id: 'loser_01',
            numberLabel: '01',
            fileName: AppSfx.lose,
          ),
          _AudioPreviewItem(
            id: 'loser_02',
            numberLabel: '02',
            fileName: 'loser02_失敗、ゲームオーバー.mp3',
          ),
          _AudioPreviewItem(
            id: 'loser_03',
            numberLabel: '03',
            fileName: 'loser03_ティロリー.mp3',
          ),
          _AudioPreviewItem(
            id: 'loser_04',
            numberLabel: '04',
            fileName: 'loser04＿ゲームオーバー.mp3',
          ),
          _AudioPreviewItem(
            id: 'loser_05',
            numberLabel: '05',
            fileName: 'loser05_不穏なファンファーレ.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'button',
        title: '決定',
        subtitle: 'ボタン操作',
        items: [
          _AudioPreviewItem(
            id: 'button_01',
            numberLabel: '01',
            fileName: AppSfx.uiTap,
          ),
          _AudioPreviewItem(
            id: 'button_02',
            numberLabel: '02',
            fileName: 'buttonTap02_選択2.mp3',
          ),
          _AudioPreviewItem(
            id: 'button_03',
            numberLabel: '03',
            fileName: 'buttonTap03_8bit選択1.mp3',
          ),
          _AudioPreviewItem(
            id: 'button_04',
            numberLabel: '04',
            fileName: 'buttonTap04_システム決定音_3.mp3',
          ),
          _AudioPreviewItem(
            id: 'button_05',
            numberLabel: '05',
            fileName: 'buttonTap05_セレクト音風な効果音.mp3',
          ),
          _AudioPreviewItem(
            id: 'button_06',
            numberLabel: '06',
            fileName: 'buttonTap06_マイクラアクション.mp3',
          ),
          _AudioPreviewItem(
            id: 'button_07',
            numberLabel: '07',
            fileName: 'buttonTap07_マウスのクリック音.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'matching',
        title: 'マッチング',
        subtitle: 'マッチング成立',
        items: [
          _AudioPreviewItem(
            id: 'matching_01',
            numberLabel: '01',
            fileName: AppSfx.matched,
          ),
          _AudioPreviewItem(
            id: 'matching_02',
            numberLabel: '02',
            fileName: 'matching02_遭遇音.mp3',
          ),
          _AudioPreviewItem(
            id: 'matching_03',
            numberLabel: '03',
            fileName: 'matching03_発見！成功！な嬉しい音.mp3',
          ),
          _AudioPreviewItem(
            id: 'matching_04',
            numberLabel: '04',
            fileName: 'matching04_未来的な決定音、ボタン音.mp3',
          ),
          _AudioPreviewItem(
            id: 'matching_05',
            numberLabel: '05',
            fileName: 'matching05_チープな正解音.mp3',
          ),
          _AudioPreviewItem(
            id: 'matching_06',
            numberLabel: '06',
            fileName: 'matching06_8bit_Start.mp3',
          ),
          _AudioPreviewItem(
            id: 'matching_07',
            numberLabel: '07',
            fileName: 'matching07_STAR_1（OK音、アイテム発見など）.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'formation',
        title: 'フォーメーション',
        subtitle: '成立時の効果音',
        items: [
          _AudioPreviewItem(
            id: 'formation_01',
            numberLabel: '01',
            fileName: 'formation01_メニューを開く4.mp3',
          ),
          _AudioPreviewItem(
            id: 'formation_02',
            numberLabel: '02',
            fileName: 'formation02_決定ボタンを押す16.mp3',
          ),
          _AudioPreviewItem(
            id: 'formation_03',
            numberLabel: '03',
            fileName: 'formation03_HP回復.mp3',
          ),
          _AudioPreviewItem(
            id: 'formation_04',
            numberLabel: '04',
            fileName: 'formation04_おしゃれなテロップ表示音.mp3',
          ),
          _AudioPreviewItem(
            id: 'formation_05',
            numberLabel: '05',
            fileName: 'formation05_切れ味パワーアップ.mp3',
          ),
          _AudioPreviewItem(
            id: 'formation_06',
            numberLabel: '06',
            fileName: 'formation06_レベルアップ、回復.mp3',
          ),
          _AudioPreviewItem(
            id: 'formation_07',
            numberLabel: '07',
            fileName: 'formation07_レベルアップ・経験値アップ.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'delete',
        title: '消去',
        subtitle: 'ボール消去',
        items: [
          _AudioPreviewItem(
            id: 'delete_01',
            numberLabel: '01',
            fileName: 'deleteBall01_決定ボタンを押す42.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'drop',
        title: 'ドロップ',
        subtitle: '自然落下',
        items: [
          _AudioPreviewItem(
            id: 'drop_01',
            numberLabel: '01',
            fileName: 'drop01_カーソル移動12.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'hard_drop',
        title: 'ハードドロップ',
        subtitle: '一気に落とす操作',
        items: [
          _AudioPreviewItem(
            id: 'hard_drop_01',
            numberLabel: '01',
            fileName: 'hardDrop01_カーソル移動5.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'obstacle',
        title: '妨害ボール',
        subtitle: '妨害ボール発生',
        items: [
          _AudioPreviewItem(
            id: 'obstacle_01',
            numberLabel: '01',
            fileName: 'obstacleBallEffect01_データ表示3.mp3',
          ),
          _AudioPreviewItem(
            id: 'obstacle_02',
            numberLabel: '02',
            fileName: 'obstacleBallEffect02_ラスボス・強敵が現れる時の音.mp3',
          ),
          _AudioPreviewItem(
            id: 'obstacle_03',
            numberLabel: '03',
            fileName: 'obstacleBallEffect03_データなどを表示させる時の音.mp3',
          ),
          _AudioPreviewItem(
            id: 'obstacle_04',
            numberLabel: '04',
            fileName: 'obstacleBallEffect04_ポイント大量獲得.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'obstacle_drop',
        title: '妨害ボール落下',
        subtitle: '妨害ボール落下',
        items: [
          _AudioPreviewItem(
            id: 'obstacle_drop_01',
            numberLabel: '01',
            fileName: 'obstacleBallDrop01_決定、ボタン押下34.mp3',
          ),
          _AudioPreviewItem(
            id: 'obstacle_drop_02',
            numberLabel: '02',
            fileName: 'obstacleBallDrop02_ショット音.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'spawn',
        title: 'スポーン',
        subtitle: '操作ボール出現',
        items: [
          _AudioPreviewItem(
            id: 'spawn_01',
            numberLabel: '01',
            fileName: 'spawn01_決定ボタンを押す33.mp3',
          ),
          _AudioPreviewItem(
            id: 'spawn_02',
            numberLabel: '02',
            fileName: 'spawn02_決定ボタンを押す49.mp3',
          ),
          _AudioPreviewItem(
            id: 'spawn_03',
            numberLabel: '03',
            fileName: 'spawn03_システム決定音_2.mp3',
          ),
        ],
      ),
      _AudioPreviewSection(
        id: 'rotation',
        title: '回転',
        subtitle: '回転操作',
        items: [
          _AudioPreviewItem(
            id: 'rotation_01',
            numberLabel: '01',
            fileName: 'rotaion01_キャンセル1.mp3',
          ),
        ],
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
      children: [
        for (final section in sections) ...[
          if (!_hiddenAudioSectionIds.contains(section.id)) ...[
            _audioPreviewSection(section),
            const SizedBox(height: 16),
          ],
        ],
      ],
    );
  }

  Widget _buildEffectsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
      children: [
        _collectionPanel(
          title: 'ボールスキン',
          metricText: '装備中：${_ballSkinName(_playerData.equippedBallSkinId)}',
          subtitle: '盤面内の操作ボールとネクストボールの見た目を変更します',
          child: _ballSkinGrid(),
        ),
        const SizedBox(height: 16),
        _collectionPanel(
          title: 'フォーメーション演出',
          metricText:
              '装備中：${EffectSkinCatalog.byId(_playerData.equippedFormationEffectId).name}',
          child: _effectGrid(
            effects: EffectSkinCatalog.formationEffects,
            equippedId: _playerData.equippedFormationEffectId,
            onEquip: (effect) async {
              _playUiTap();
              await _playerData.setEquippedFormationEffectId(effect.id);
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        _collectionPanel(
          title: '妨害演出',
          metricText:
              '装備中：${EffectSkinCatalog.byId(_playerData.equippedOjamaEffectId).name}',
          child: _effectGrid(
            effects: EffectSkinCatalog.ojamaEffects,
            equippedId: _playerData.equippedOjamaEffectId,
            onEquip: (effect) async {
              _playUiTap();
              await _playerData.setEquippedOjamaEffectId(effect.id);
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _ballSkinGrid() {
    final skins = [
      const GameItem(
        id: 'default',
        name: 'スタンダード',
        type: ItemType.skin,
        rarity: ItemRarity.common,
      ),
      ...GameItemCatalog.ballSkins,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 360 ? 8.0 : 10.0;
        final tileWidth = (constraints.maxWidth - gap * 3) / 4;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final skin in skins)
              SizedBox(
                width: tileWidth,
                child: _ballSkinTile(
                  skin: skin,
                  selected: _playerData.equippedBallSkinId == skin.id,
                  available: _isBallSkinUnlocked(skin),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _ballSkinTile({
    required GameItem skin,
    required bool selected,
    required bool available,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: InkWell(
            onTap: available && !selected
                ? () async {
                    _playUiTap();
                    await _playerData.setEquippedBallSkinId(skin.id);
                    if (mounted) {
                      setState(() {});
                    }
                  }
                : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? GameThemeColors.cyan.withValues(alpha: 0.18)
                    : const Color(0xFF142238).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? GameThemeColors.cyan
                      : Colors.white.withValues(alpha: 0.14),
                  width: selected ? 2.2 : 1.1,
                ),
              ),
              child: Stack(
                children: [
                  Center(child: _ballSkinPreview(skin.id)),
                  if (!available)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Icon(
                        Icons.lock_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          skin.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? GameThemeColors.cyan : Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _ballSkinPreview(String skinId) {
    const size = 68.0;
    const ballSize = 48.0;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: skinId == 'default'
            ? const MiniBallWidget(ballColor: BallColor.blue, size: ballSize)
            : ClipOval(
                child: Image.asset(
                  _ballSkinAssetForPreview(skinId, BallColor.blue),
                  width: ballSize,
                  height: ballSize,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => MiniBallWidget(
                    ballColor: BallColor.blue,
                    size: ballSize,
                    ballSkinId: skinId,
                  ),
                ),
              ),
      ),
    );
  }

  String _ballSkinAssetForPreview(String skinId, BallColor color) {
    final suffix = switch (color) {
      BallColor.blue => 'blue',
      BallColor.green => 'green',
      BallColor.red => 'red',
      BallColor.yellow => 'yellow',
      BallColor.purple => 'purple',
    };
    final prefix = switch (skinId) {
      'skin_orbit' => 'ball_skin_hexa_orbit',
      'skin_arcade' => 'ball_skin_arcade',
      'skin_hexacore' => 'ball_hexacore',
      'skin_element' => 'ball_element',
      'skin_cosmic' => 'ball_cosmic',
      _ => 'ball_skin_hexa_orbit',
    };
    return 'assets/images/BallSkins/${prefix}_$suffix.png';
  }

  String _ballSkinName(String id) {
    if (id == 'default') {
      return 'スタンダード';
    }
    for (final skin in GameItemCatalog.ballSkins) {
      if (skin.id == id) {
        return skin.name;
      }
    }
    return 'スタンダード';
  }

  bool _isBallSkinUnlocked(GameItem skin) {
    if (skin.id == 'default' ||
        _playerData.displayPlayerName ==
            AudioSelectionManager.allAudioUnlockedPlayerName) {
      return true;
    }
    return _playerData.ownedItems.any(
      (item) => item.id == skin.id && item.isSkin,
    );
  }

  Widget _collectionPanel({
    required String title,
    String? metricText,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xE60B1019),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stampSectionHeader(
            title,
            metricText: metricText,
            infoText: subtitle,
            trailing: trailing,
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _effectGrid({
    required List<EffectSkin> effects,
    required String equippedId,
    required ValueChanged<EffectSkin> onEquip,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 360 ? 8.0 : 10.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final effect in effects)
              SizedBox(
                width: width,
                child: _effectTile(
                  effect: effect,
                  selected: equippedId == effect.id,
                  available: _isEffectUnlocked(effect),
                  onEquip: () => onEquip(effect),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _effectTile({
    required EffectSkin effect,
    required bool selected,
    required bool available,
    required VoidCallback onEquip,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected
            ? effect.color.withValues(alpha: 0.18)
            : const Color(0xFF142238).withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? effect.color : Colors.white.withValues(alpha: 0.14),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            effect.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 9),
          _smallActionButton(
            label: selected
                ? '使用中'
                : available
                    ? '使う'
                    : '未所持',
            color: effect.color,
            onTap: selected || !available ? null : onEquip,
            filled: true,
          ),
        ],
      ),
    );
  }

  Widget _smallActionButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
    required bool filled,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.58 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? color.withValues(alpha: 0.95) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withValues(alpha: 0.78)),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: filled ? Colors.black : color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  bool _isEffectUnlocked(EffectSkin effect) {
    if (effect.id == EffectSkinCatalog.defaultFormationId ||
        effect.id == EffectSkinCatalog.defaultOjamaId) {
      return true;
    }
    if (_playerData.displayPlayerName ==
        AudioSelectionManager.allAudioUnlockedPlayerName) {
      return true;
    }
    return _playerData.ownedItems.any(
      (item) => item.id == effect.id && item.isEffect,
    );
  }

  Widget _audioPreviewSection(_AudioPreviewSection section) {
    final savedSelectedId = _selectedAudioPreviewIds[section.id];
    final selectedItem = section.items.firstWhere(
      (item) => item.id == savedSelectedId && _isAudioItemUnlocked(item),
      orElse: () => section.items.first,
    );
    final selectedId = selectedItem.id;
    final sectionPlaying = _previewingAudioId == selectedItem.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stampSectionHeader(
          section.title,
          metricText: section.subtitle,
          trailing: _audioHeaderPlayButton(
            playing: sectionPlaying,
            onTap: () => _toggleAudioPreview(selectedItem),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = constraints.maxWidth < 360 ? 7.0 : 9.0;
            final tileWidth = (constraints.maxWidth - gap * 3) / 4;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in section.items)
                  SizedBox(
                    width: tileWidth,
                    child: _audioPreviewSquare(
                      section: section,
                      item: item,
                      selected: selectedId == item.id,
                      playing: _previewingAudioId == item.id,
                      available: _isAudioItemUnlocked(item),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _audioHeaderPlayButton({
    required bool playing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GameThemeColors.cyan.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: GameThemeColors.cyan.withValues(alpha: 0.56),
          ),
        ),
        child: Icon(
          playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          color: GameThemeColors.cyan,
          size: 21,
        ),
      ),
    );
  }

  Widget _audioPreviewSquare({
    required _AudioPreviewSection section,
    required _AudioPreviewItem item,
    required bool selected,
    required bool playing,
    required bool available,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: InkWell(
            onTap: () {
              setState(() => _activeAudioChoiceId = available ? item.id : null);
              unawaited(_toggleAudioPreview(item, forceRestart: true));
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? GameThemeColors.cyan.withValues(alpha: 0.16)
                    : const Color(0xFF142238).withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: playing
                      ? Colors.white
                      : selected
                          ? GameThemeColors.cyan
                          : Colors.white.withValues(alpha: 0.13),
                  width: selected || playing ? 2.2 : 1.1,
                ),
                boxShadow: [
                  if (playing)
                    BoxShadow(
                      color: GameThemeColors.cyan.withValues(alpha: 0.28),
                      blurRadius: 14,
                    ),
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.isBgm
                              ? Icons.music_note_rounded
                              : Icons.graphic_eq,
                          color: available
                              ? GameThemeColors.cyan
                              : Colors.white.withValues(alpha: 0.42),
                          size: 26,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.numberLabel,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!available)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.24),
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          color: Colors.white70,
                          size: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: _activeAudioChoiceId == item.id
              ? Padding(
                  key: ValueKey('${item.id}_use'),
                  padding: const EdgeInsets.only(top: 6),
                  child: _smallActionButton(
                    label: '使う',
                    color: GameThemeColors.cyan,
                    onTap: () {
                      _playUiTap();
                      setState(() {
                        _selectedAudioPreviewIds[section.id] = item.id;
                        _activeAudioChoiceId = null;
                      });
                      unawaited(_applyAudioSelection(section.id, item.id));
                    },
                    filled: true,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  bool _isAudioItemUnlocked(_AudioPreviewItem item) {
    return AudioSelectionManager.isAudioUnlocked(
      playerName: _playerData.displayPlayerName,
      itemId: item.id,
    );
  }

  Future<void> _toggleAudioPreview(
    _AudioPreviewItem item, {
    bool forceRestart = false,
  }) async {
    if (!forceRestart && _previewingAudioId == item.id) {
      await _stopAudioPreview();
      return;
    }
    await _stopAudioPreview(updateState: false);
    try {
      await _suspendBgmForAudioPreview();
      await _audioPreviewCompleteSubscription?.cancel();
      _audioPreviewCompleteSubscription = _audioPreviewPlayer.onPlayerComplete
          .listen((_) => unawaited(_stopAudioPreview()));
      await _audioPreviewPlayer.setReleaseMode(ReleaseMode.stop);
      final settingsVolume = item.isBgm
          ? AppSettings.instance.musicVolume.value
          : AppSettings.instance.sfxVolume.value;
      await _audioPreviewPlayer.setVolume(settingsVolume.clamp(0.0, 1.0));
      await _audioPreviewPlayer.play(AssetSource('audio/${item.fileName}'));
    } catch (_) {
      await _resumeBgmAfterAudioPreview();
      return;
    }
    if (mounted) {
      setState(() => _previewingAudioId = item.id);
    }
  }

  Future<void> _stopAudioPreview({bool updateState = true}) async {
    _audioPreviewStopTimer?.cancel();
    _audioPreviewStopTimer = null;
    await _audioPreviewCompleteSubscription?.cancel();
    _audioPreviewCompleteSubscription = null;
    try {
      await _audioPreviewPlayer.stop();
    } catch (_) {
      // 試聴停止失敗で画面操作を止めない。
    }
    await _resumeBgmAfterAudioPreview();
    if (updateState && mounted) {
      setState(() => _previewingAudioId = null);
    } else {
      _previewingAudioId = null;
    }
  }

  Future<void> _suspendBgmForAudioPreview() async {
    if (_bgmSuspendedForAudioPreview) {
      return;
    }
    _bgmSuspendedForAudioPreview = true;
    await SeamlessBgm.instance.suspendForExternalAudio();
  }

  Future<void> _resumeBgmAfterAudioPreview() async {
    if (!_bgmSuspendedForAudioPreview) {
      return;
    }
    _bgmSuspendedForAudioPreview = false;
    await SeamlessBgm.instance.resumeFromExternalAudio();
  }

  Future<void> _restartSelectedHomeBgm() async {
    try {
      final selectedBgm = await AudioSelectionManager.selectedHomeBgm();
      await SeamlessBgm.instance.setMasterVolume(
        AppSettings.instance.musicVolume.value,
      );
      await SeamlessBgm.instance.play(
        assetPath: selectedBgm.assetPath,
        duration: selectedBgm.duration,
        volume: 0.576,
        owner: 'home_screen',
        forceRestart: true,
      );
    } catch (_) {
      // ホームBGMの即時反映に失敗しても、次回ホーム再生時に保存済み設定を使う。
    }
  }

  List<_ProfileItemEntry<GameItem>> _orderedProfileItems({
    required String currentId,
    required List<GameItem> items,
    required Set<String> ownedIds,
  }) {
    final entries = [
      for (final item in items)
        _ProfileItemEntry(item: item, owned: ownedIds.contains(item.id)),
    ];
    entries.sort((a, b) {
      if (a.item.id == currentId) {
        return -1;
      }
      if (b.item.id == currentId) {
        return 1;
      }
      if (a.owned != b.owned) {
        return a.owned ? -1 : 1;
      }
      return a.item.name.compareTo(b.item.name);
    });
    return entries;
  }

  Widget _profilePreviewCard() {
    final badgeEntriesById = {
      for (final entry in _profileBadgeEntries()) entry.id: entry,
    };
    final equippedBadges = [
      for (final id in _playerData.equippedBadgeIds)
        if (badgeEntriesById[id] != null) badgeEntriesById[id]!,
    ].take(3).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: _profileBannerGradient(_playerData.equippedProfileBannerId),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _profileIconWithFrame(
            iconId: _playerData.equippedPlayerIconId,
            frameId: _playerData.equippedIconFrameId,
            size: 64,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _playerData.displayPlayerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final badge in equippedBadges) ...[
                      _badgePreviewIcon(badge, size: 30),
                      const SizedBox(width: 6),
                    ],
                    if (equippedBadges.isEmpty)
                      Text(
                        'バッジ未装備',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileIconWithFrame({
    required String iconId,
    required String frameId,
    required double size,
  }) {
    final frame = frameId == 'default' ? null : GameItemCatalog.byId(frameId);
    final color = frame == null ? GameThemeColors.cyan : _frameColor(frame);
    final frameDecoration = frame?.colorName == 'rainbow'
        ? const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                Color(0xFFFF4D6D),
                Color(0xFFFFD54A),
                Color(0xFF35F0FF),
                Color(0xFFB91DFF),
                Color(0xFFFF4D6D),
              ],
            ),
          )
        : BoxDecoration(
            color: playerIconInnerBackgroundColor(
              iconId,
              color.withValues(alpha: 0.12),
              frameId: frameId,
            ),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          );
    return Container(
      width: size,
      height: size,
      decoration: frameDecoration,
      padding: frame?.colorName == 'rainbow' ? const EdgeInsets.all(4) : null,
      child: frame?.colorName == 'rainbow'
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: playerIconInnerBackgroundColor(
                  iconId,
                  const Color(0xFF111827),
                  frameId: frameId,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: PlayerIconImage(
                  iconId: iconId,
                  fallbackIcon: Icons.person,
                  size: size * 0.55,
                ),
              ),
            )
          : Center(
              child: PlayerIconImage(
                iconId: iconId,
                fallbackIcon: Icons.person,
                size: size * 0.55,
              ),
            ),
    );
  }

  Widget _profileIconTile({
    required String iconId,
    required bool current,
    required bool available,
  }) {
    return _profileSquareTile(
      current: current,
      available: available,
      child: PlayerIconImage(
        iconId: iconId,
        fallbackIcon: Icons.person,
        size: 48,
      ),
    );
  }

  Widget _profileFrameTile({
    required GameItem frame,
    required bool current,
    required bool available,
  }) {
    return _profileSquareTile(
      current: current,
      available: available,
      child: _frameOnlyPreview(frame: frame, size: 58),
    );
  }

  Widget _profileBannerTile({
    required GameItem banner,
    required bool current,
    required bool available,
  }) {
    return _profileSquareTile(
      current: current,
      available: available,
      child: _profileBannerPreview(banner: banner),
    );
  }

  Widget _profileBannerPreview({
    required GameItem banner,
  }) {
    return AspectRatio(
      aspectRatio: 1.42,
      child: Container(
        decoration: BoxDecoration(
          gradient: _profileBannerGradient(banner.id),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _bannerColor(banner).withValues(alpha: 0.82),
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.panorama_rounded,
          color: Colors.white.withValues(alpha: 0.82),
          size: 22,
        ),
      ),
    );
  }

  Widget _frameOnlyPreview({
    required GameItem frame,
    required double size,
  }) {
    final color =
        frame.id == 'default' ? GameThemeColors.cyan : _frameColor(frame);
    final decoration = frame.colorName == 'rainbow'
        ? const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                Color(0xFFFF4D6D),
                Color(0xFFFFD54A),
                Color(0xFF35F0FF),
                Color(0xFFB91DFF),
                Color(0xFFFF4D6D),
              ],
            ),
          )
        : BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          );
    return Container(
      width: size,
      height: size,
      decoration: decoration,
      padding: frame.colorName == 'rainbow' ? const EdgeInsets.all(4) : null,
      child: frame.colorName == 'rainbow'
          ? const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF101A2A),
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }

  Widget _profileSquareTile({
    required Widget child,
    required bool current,
    required bool available,
  }) {
    return AspectRatio(
      aspectRatio: 1,
      child: Opacity(
        opacity: available ? 1 : 0.38,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xCC101A2A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: current
                  ? GameThemeColors.cyan
                  : Colors.white.withValues(alpha: 0.12),
              width: current ? 3 : 1.2,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(child: child),
              if (!available)
                const Positioned(
                  right: -2,
                  bottom: -2,
                  child: Icon(Icons.lock, size: 16, color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileItemSection<T>({
    required String title,
    required String metricText,
    required List<_ProfileItemEntry<T>> entries,
    required bool showAll,
    required double tileWidth,
    required double gap,
    required VoidCallback onToggleShowAll,
    required Widget Function(_ProfileItemEntry<T> entry) tileBuilder,
    required void Function(
      _ProfileItemEntry<T> entry,
      BuildContext anchorContext,
    ) onTap,
  }) {
    final visibleEntries = showAll ? entries : entries.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stampSectionHeader(title, metricText: metricText),
        const SizedBox(height: 10),
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final entry in visibleEntries)
              SizedBox(
                width: tileWidth,
                child: Builder(
                  builder: (tileContext) => GestureDetector(
                    onTap: entry.owned ? () => onTap(entry, tileContext) : null,
                    child: tileBuilder(entry),
                  ),
                ),
              ),
          ],
        ),
        if (entries.length > 8) ...[
          const SizedBox(height: 12),
          Center(
            child: _compactToggleButton(
              label: showAll ? '表示を減らす' : 'さらに表示',
              onPressed: onToggleShowAll,
            ),
          ),
        ],
      ],
    );
  }

  Widget _profileBadgeSection({
    required List<_ProfileBadgeEntry> entries,
    required bool showAll,
    required double tileWidth,
    required double gap,
  }) {
    final replacing = _pendingBadgeToEquipId != null;
    final visibleEntries = showAll ? entries : entries.take(8).toList();
    final entriesById = {for (final entry in entries) entry.id: entry};
    final equippedEntries = [
      for (final id in _playerData.equippedBadgeIds)
        if (entriesById[id] != null) entriesById[id]!,
    ];
    final pendingEntry = replacing ? entriesById[_pendingBadgeToEquipId] : null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: replacing
          ? () {
              _playUiTap();
              _dismissCollectionItemOverlay();
              setState(() => _pendingBadgeToEquipId = null);
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stampSectionHeader('バッジ一覧'),
          const SizedBox(height: 10),
          if (replacing) ...[
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final entry in equippedEntries)
                  SizedBox(
                    width: tileWidth,
                    child: GestureDetector(
                      onTap: () => _replaceProfileBadge(
                        entry.id,
                        _pendingBadgeToEquipId!,
                      ),
                      child: _profileSquareTile(
                        current: true,
                        available: entry.owned,
                        child: _badgePreviewIcon(entry, size: 50),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '入れ替える場所を選択',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: GameThemeColors.cyan,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 10),
            if (pendingEntry != null)
              Center(
                child: SizedBox(
                  width: min(tileWidth * 1.12, 108),
                  child: _profileSquareTile(
                    current: false,
                    available: pendingEntry.owned,
                    child: _badgePreviewIcon(pendingEntry, size: 50),
                  ),
                ),
              ),
          ] else ...[
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final entry in visibleEntries)
                  SizedBox(
                    width: tileWidth,
                    child: Builder(
                      builder: (tileContext) => GestureDetector(
                        onTap: () => _handleProfileBadgeTap(entry, tileContext),
                        child: _profileSquareTile(
                          current: entry.equipped,
                          available: entry.owned,
                          child: _badgePreviewIcon(entry, size: 50),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (!replacing && entries.length > 8) ...[
            const SizedBox(height: 12),
            Center(
              child: _compactToggleButton(
                label: showAll ? '表示を減らす' : 'さらに表示',
                onPressed: () {
                  _playUiTap();
                  _dismissCollectionItemOverlay();
                  setState(
                      () => _showAllProfileBadges = !_showAllProfileBadges);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _profileChoicePopup({
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    bool showFrame = true,
  }) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
            ),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          if (title != null) const SizedBox(height: 6),
          _stampActionButton(label: actionLabel, onPressed: onAction),
        ],
      ],
    );
    if (!showFrame) {
      return child;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xF20D1424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.58)),
      ),
      child: child,
    );
  }

  Widget _badgeChoicePopup(_ProfileBadgeEntry entry) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xF20D1424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.58)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _popupFittedLine(
            entry.label,
            color: Colors.white,
            fontSize: 11.5,
          ),
          const SizedBox(height: 4),
          _popupFittedLine(
            entry.detail,
            color: Colors.white70,
            fontSize: 10,
            height: 14,
          ),
          if (entry.nextCondition != null) ...[
            const SizedBox(height: 4),
            _popupFittedLine(
              entry.nextCondition!,
              color: GameThemeColors.cyan,
              fontSize: 9.5,
              height: 13,
            ),
          ],
          const SizedBox(height: 6),
          _stampActionButton(
            label: entry.equipped ? '外す' : '使う',
            onPressed: () => entry.equipped
                ? _unequipProfileBadge(entry.id)
                : _equipProfileBadge(entry.id),
          ),
        ],
      ),
    );
  }

  Widget _popupFittedLine(
    String text, {
    required Color color,
    required double fontSize,
    double height = 16,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }

  Widget _compactToggleButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: GameThemeColors.cyan,
          side: BorderSide(color: GameThemeColors.cyan.withValues(alpha: 0.58)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ),
    );
  }

  void _selectProfileIcon(
    _ProfileItemEntry<GameItem> entry,
    BuildContext anchorContext,
  ) {
    _playUiTap();
    setState(() => _pendingBadgeToEquipId = null);
    _showCollectionItemPopup(
      anchorContext,
      _profileChoicePopup(
        title: entry.item.name,
        actionLabel:
            _playerData.equippedPlayerIconId == entry.item.id ? null : '使う',
        onAction: entry.owned ? () => _equipProfileIcon(entry.item.id) : null,
      ),
      width: 128,
    );
  }

  void _selectProfileFrame(
    _ProfileItemEntry<GameItem> entry,
    BuildContext anchorContext,
  ) {
    _playUiTap();
    setState(() => _pendingBadgeToEquipId = null);
    _showCollectionItemPopup(
      anchorContext,
      _profileChoicePopup(
        title: entry.item.name,
        actionLabel:
            _playerData.equippedIconFrameId == entry.item.id ? null : '使う',
        onAction: entry.owned ? () => _equipProfileFrame(entry.item.id) : null,
      ),
      width: 128,
    );
  }

  void _selectProfileBanner(
    _ProfileItemEntry<GameItem> entry,
    BuildContext anchorContext,
  ) {
    _playUiTap();
    setState(() => _pendingBadgeToEquipId = null);
    _showCollectionItemPopup(
      anchorContext,
      _profileChoicePopup(
        title: entry.item.name,
        actionLabel:
            _playerData.equippedProfileBannerId == entry.item.id ? null : '使う',
        onAction: entry.owned ? () => _equipProfileBanner(entry.item.id) : null,
      ),
      width: 128,
    );
  }

  Future<void> _equipProfileIcon(String iconId) async {
    _playUiTap();
    _dismissCollectionItemOverlay();
    await _playerData.setEquippedPlayerIconId(iconId);
    await _multiplayerManager.updateUserName(_playerData.playerName);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _equipProfileFrame(String frameId) async {
    _playUiTap();
    _dismissCollectionItemOverlay();
    await _playerData.setEquippedIconFrameId(frameId);
    await _multiplayerManager.updateUserName(_playerData.playerName);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _equipProfileBanner(String bannerId) async {
    _playUiTap();
    _dismissCollectionItemOverlay();
    await _playerData.setEquippedProfileBannerId(bannerId);
    await _multiplayerManager.updateUserName(_playerData.playerName);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  List<_ProfileBadgeEntry> _profileBadgeEntries() {
    final seasonBadges = _playerData.seasonRankBadges;
    final ownedSeasonBadgeIds = seasonBadges.map((badge) => badge.id).toSet();
    final unlocked = {..._playerData.unlockedBadgeIds, ...ownedSeasonBadgeIds};
    final equipped = _playerData.equippedBadgeIds.toSet();
    final entries = <_ProfileBadgeEntry>[
      for (final badge in seasonBadges)
        _ProfileBadgeEntry.season(
          badge: badge,
          equipped: equipped.contains(badge.id),
        ),
      for (final badge in BadgeCatalog.visibleBadgesFor(unlocked)
          .where((badge) => unlocked.contains(badge.id)))
        _ProfileBadgeEntry.normal(
          badge: badge,
          owned: true,
          equipped: equipped.contains(badge.id),
          nextCondition: _nextBadgeCondition(badge, unlocked),
        ),
    ];
    entries.sort((a, b) {
      if (a.equipped != b.equipped) {
        return a.equipped ? -1 : 1;
      }
      if (a.equipped && b.equipped) {
        final aIndex = _playerData.equippedBadgeIds.indexOf(a.id);
        final bIndex = _playerData.equippedBadgeIds.indexOf(b.id);
        if (aIndex != bIndex) {
          return aIndex.compareTo(bIndex);
        }
      }
      if (a.rankPriority != b.rankPriority) {
        return a.rankPriority.compareTo(b.rankPriority);
      }
      return a.label.compareTo(b.label);
    });
    return entries;
  }

  String? _nextBadgeCondition(BadgeItem badge, Set<String> unlocked) {
    final nextBadge = BadgeCatalog.nextEvolutionBadgeFor(badge);
    if (nextBadge == null || badge.evolutionGroup == null) {
      return null;
    }
    return '次Lv.${nextBadge.level}: ${nextBadge.unlockedCondition.description}';
  }

  Widget _badgePreviewIcon(_ProfileBadgeEntry entry, {required double size}) {
    if (entry.seasonBadge != null) {
      return SeasonRankBadgeIcon(
        rank: entry.seasonBadge!.rank,
        kind: entry.seasonBadge!.kind,
        size: size,
      );
    }
    return Icon(
      entry.normalBadge?.icon ?? Icons.workspace_premium,
      color: entry.normalBadge?.frameColor ?? GameThemeColors.cyan,
      size: size * 0.72,
    );
  }

  void _handleProfileBadgeTap(
    _ProfileBadgeEntry entry,
    BuildContext anchorContext,
  ) {
    _playUiTap();
    if (_pendingBadgeToEquipId != null) {
      if (entry.equipped) {
        _replaceProfileBadge(entry.id, _pendingBadgeToEquipId!);
      }
      return;
    }
    _showCollectionItemPopup(
      anchorContext,
      _badgeChoicePopup(entry),
      width: 150,
      estimatedHeight: 140,
    );
  }

  Future<void> _equipProfileBadge(String badgeId) async {
    _playUiTap();
    _dismissCollectionItemOverlay();
    final equipped = _playerData.equippedBadgeIds.toList();
    if (equipped.contains(badgeId)) {
      return;
    }
    if (equipped.length >= 3) {
      setState(() {
        _pendingBadgeToEquipId = badgeId;
      });
      return;
    }
    equipped.add(badgeId);
    await _playerData.setEquippedBadgeIds(equipped);
    await _multiplayerManager.updateUserName(_playerData.playerName);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _replaceProfileBadge(String removeId, String addId) async {
    _dismissCollectionItemOverlay();
    final next = _playerData.equippedBadgeIds
        .map((id) => id == removeId ? addId : id)
        .toList();
    await _playerData.setEquippedBadgeIds(next);
    await _multiplayerManager.updateUserName(_playerData.playerName);
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingBadgeToEquipId = null;
    });
  }

  Future<void> _unequipProfileBadge(String badgeId) async {
    _playUiTap();
    _dismissCollectionItemOverlay();
    final next =
        _playerData.equippedBadgeIds.where((id) => id != badgeId).toList();
    await _playerData.setEquippedBadgeIds(next);
    await _multiplayerManager.updateUserName(_playerData.playerName);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Color _frameColor(GameItem frame) {
    return _colorFromFrameName(frame.colorName);
  }

  LinearGradient _profileBannerGradient(String bannerId) {
    final item = bannerId == 'default'
        ? const GameItem(
            id: 'default',
            name: 'デフォルト',
            type: ItemType.banner,
            rarity: ItemRarity.common,
            colorName: 'cyan',
          )
        : GameItemCatalog.byId(bannerId);
    final color = _bannerColor(item);
    final softColor = _softBannerColor(item?.colorName, color);
    return LinearGradient(colors: [softColor, softColor]);
  }

  Color _softBannerColor(String? colorName, Color color) {
    if (colorName == 'white') {
      return const Color(0xFFFBFDFF).withValues(alpha: 0.34);
    }
    if (colorName == 'black') {
      return const Color(0xFF343A45).withValues(alpha: 0.42);
    }
    return (Color.lerp(color, Colors.white, 0.84) ?? color)
        .withValues(alpha: 0.38);
  }

  Color _bannerColor(GameItem? banner) {
    return _colorFromFrameName(banner?.colorName);
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

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});

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
            fontSize: 18,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _NeonTabBar extends StatelessWidget {
  const _NeonTabBar({required this.tabs, required this.controller});

  final List<String> tabs;
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.28)),
      ),
      child: TabBar(
        controller: controller,
        onTap: (_) => AppSfx.playUiTap(),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              GameThemeColors.cyan.withValues(alpha: 0.35),
              const Color(0xFF0B84FF).withValues(alpha: 0.28),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.85)),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        tabs: [
          for (final tab in tabs)
            Tab(
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: switch (tab) {
                    'スタンプ' => Image.asset(
                        'assets/images/BattleStamps/battle_message_stamp.png',
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                      ),
                    'プロフィール' => Image.asset(
                        'assets/images/Profile_Icon.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    'エフェクト' => Image.asset(
                        'assets/images/Effects_Icon.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    'ミュージック' => Image.asset(
                        'assets/images/Music_Icon.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    _ => Text(
                        tab,
                        maxLines: 1,
                        softWrap: false,
                      ),
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileItemEntry<T> {
  const _ProfileItemEntry({
    required this.item,
    required this.owned,
  });

  final T item;
  final bool owned;
}

class _AudioPreviewSection {
  const _AudioPreviewSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<_AudioPreviewItem> items;
}

class _AudioPreviewItem {
  const _AudioPreviewItem({
    required this.id,
    required this.numberLabel,
    required this.fileName,
    this.isBgm = false,
  });

  final String id;
  final String numberLabel;
  final String fileName;
  final bool isBgm;
}

class _ProfileBadgeEntry {
  const _ProfileBadgeEntry._({
    required this.id,
    required this.label,
    required this.detail,
    required this.owned,
    required this.equipped,
    required this.rankPriority,
    this.nextCondition,
    this.normalBadge,
    this.seasonBadge,
  });

  factory _ProfileBadgeEntry.normal({
    required BadgeItem badge,
    required bool owned,
    required bool equipped,
    String? nextCondition,
  }) {
    return _ProfileBadgeEntry._(
      id: badge.id,
      label: badge.label,
      detail: badge.unlockedCondition.description,
      owned: owned,
      equipped: equipped,
      rankPriority: 10000 + (badge.level ?? 0),
      nextCondition: nextCondition,
      normalBadge: badge,
    );
  }

  factory _ProfileBadgeEntry.season({
    required SeasonRankBadge badge,
    required bool equipped,
  }) {
    return _ProfileBadgeEntry._(
      id: badge.id,
      label: badge.label,
      detail: badge.seasonName,
      owned: true,
      equipped: equipped,
      rankPriority: badge.rank,
      seasonBadge: badge,
    );
  }

  final String id;
  final String label;
  final String detail;
  final String? nextCondition;
  final bool owned;
  final bool equipped;
  final int rankPriority;
  final BadgeItem? normalBadge;
  final SeasonRankBadge? seasonBadge;
}
