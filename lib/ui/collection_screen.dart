import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../data/models/badge_item.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
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
  bool _showAllProfileBadges = false;
  String? _pendingBadgeToEquipId;

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
    });
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
                    tabs: const ['スタンプ', 'プロフィール', 'エフェクト', '音声'],
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
            tabs: const ['スタンプ', 'プロフィール', 'エフェクト', '音声'],
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
    return _buildComingSoonTab();
  }

  Widget _buildEffectsTab() {
    return _buildComingSoonTab();
  }

  Widget _buildComingSoonTab() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(22),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1E2D).withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.30)),
        ),
        child: const Text(
          '近日実装予定',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
    );
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
        color: const Color(0xE60B1019),
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
                    '音声' => Image.asset(
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
