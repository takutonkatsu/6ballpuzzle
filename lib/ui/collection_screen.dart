import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../data/models/badge_item.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../game/components/ball_component.dart';
import '../game/game_models.dart';
import '../network/multiplayer_manager.dart';
import '../network/ranking_manager.dart';
import 'components/season_rank_badge_icon.dart';
import 'components/hexagon_grid_background.dart';
import 'components/screen_bottom_banner_ad.dart';
import 'theme/game_theme_colors.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen>
    with SingleTickerProviderStateMixin {
  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final MultiplayerManager _multiplayerManager = MultiplayerManager.instance;
  bool _loading = true;

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  @override
  void initState() {
    super.initState();
    _load();
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
    return DefaultTabController(
      length: 5,
      child: Scaffold(
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
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(62),
            child: _NeonTabBar(tabs: ['スタンプ', 'バッジ', 'ボール', 'アイコン', 'フレーム']),
          ),
        ),
        body: Stack(
          children: [
            const HexagonGridBackground(
              color: GameThemeColors.cyan,
              opacity: 0.04,
              hexRadius: 30,
            ),
            _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: GameThemeColors.cyan),
                  )
                : TabBarView(
                    children: [
                      _buildStampsTab(),
                      _buildBadgesTab(),
                      _buildSkinsTab(),
                      _buildIconsTab(),
                      _buildFramesTab(),
                    ],
                  ),
          ],
        ),
      ),
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
    final equipped = _playerData.equippedStampIds.toSet();
    return _grid(
      children: [
        for (final stamp in stampCatalog)
          _simpleCard(
            title: stamp.name,
            subtitle: !ownedStampIds.contains(stamp.id)
                ? '未所持'
                : equipped.contains(stamp.id)
                    ? '装備中 ${equipped.length} / 6  Lv.${stamp.level}'
                    : 'タップで装備  Lv.${stamp.level}',
            icon: _iconForStamp(stamp.iconName),
            selected: equipped.contains(stamp.id),
            available: ownedStampIds.contains(stamp.id),
            onTap: ownedStampIds.contains(stamp.id)
                ? () async {
                    _playUiTap();
                    final next = equipped.toList();
                    if (next.contains(stamp.id)) {
                      next.remove(stamp.id);
                    } else if (next.length < 6) {
                      next.add(stamp.id);
                    } else {
                      next.removeAt(0);
                      next.add(stamp.id);
                    }
                    await _playerData.setEquippedStampIds(next);
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                  }
                : null,
          ),
      ],
    );
  }

  Widget _buildBadgesTab() {
    final seasonBadges = _playerData.seasonRankBadges;
    final unlocked = {
      ..._playerData.unlockedBadgeIds,
      ...seasonBadges.map((badge) => badge.id),
    };
    final equipped = _playerData.equippedBadgeIds.toSet();
    final visibleBadges = BadgeCatalog.visibleBadgesFor(unlocked);
    return _grid(
      children: [
        for (final badge in seasonBadges)
          _simpleCard(
            title: badge.label,
            subtitle: equipped.contains(badge.id)
                ? '装備中'
                : '${badge.seasonName} ${badge.rank}位',
            icon: Icons.workspace_premium,
            leading: SeasonRankBadgeIcon(
              rank: badge.rank,
              kind: badge.kind,
              size: 28,
            ),
            accentColor: _seasonRankColor(badge.rank),
            replaceSelectedIcon: false,
            selected: equipped.contains(badge.id),
            available: true,
            onTap: () async {
              _playUiTap();
              final next = equipped.toSet();
              if (next.contains(badge.id)) {
                next.remove(badge.id);
              } else if (next.length < 2) {
                next.add(badge.id);
              } else {
                final first = next.first;
                next.remove(first);
                next.add(badge.id);
              }
              await _playerData.setEquippedBadgeIds(next.toList());
              await _multiplayerManager.updateUserName(
                _playerData.playerName,
              );
              if (!mounted) {
                return;
              }
              setState(() {});
            },
          ),
        for (final badge in visibleBadges)
          _simpleCard(
            title: badge.label,
            subtitle: _badgeSubtitle(
              badge: badge,
              unlocked: unlocked,
              equipped: equipped,
            ),
            icon: badge.icon,
            accentColor: badge.frameColor,
            replaceSelectedIcon: false,
            selected: equipped.contains(badge.id),
            available: unlocked.contains(badge.id),
            onTap: unlocked.contains(badge.id)
                ? () async {
                    _playUiTap();
                    final next = equipped.toSet();
                    if (next.contains(badge.id)) {
                      next.remove(badge.id);
                    } else if (next.length < 2) {
                      next.add(badge.id);
                    } else {
                      final first = next.first;
                      next.remove(first);
                      next.add(badge.id);
                    }
                    await _playerData.setEquippedBadgeIds(next.toList());
                    await _multiplayerManager.updateUserName(
                      _playerData.playerName,
                    );
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                  }
                : null,
          ),
      ],
    );
  }

  Color _seasonRankColor(int rank) {
    if (rank == 1) {
      return const Color(0xFFFFD54A);
    }
    if (rank <= 10) {
      return const Color(0xFFB8C7FF);
    }
    return GameThemeColors.ranked;
  }

  String _badgeSubtitle({
    required BadgeItem badge,
    required Set<String> unlocked,
    required Set<String> equipped,
  }) {
    final nextBadge = BadgeCatalog.nextEvolutionBadgeFor(badge);
    if (badge.evolutionGroup == null) {
      return badge.unlockedCondition.description;
    }
    if (!unlocked.contains(badge.id)) {
      return badge.unlockedCondition.description;
    }
    if (nextBadge == null) {
      return '${badge.unlockedCondition.description}\n最高Lv達成';
    }
    return '${badge.unlockedCondition.description}\n次Lv.${nextBadge.level}: ${nextBadge.unlockedCondition.description}';
  }

  Widget _buildSkinsTab() {
    final ownedSkinIds = {
      'default',
      ..._playerData.ownedItems
          .where((item) => item.type == ItemType.skin)
          .map((item) => item.id),
    };

    return _grid(
      children: [
        for (final skin in [
          const (id: 'default', label: 'デフォルト', colorName: null),
          ...GameItemCatalog.ballSkins.map(
            (item) => (
              id: item.id,
              label: item.name,
              colorName: item.colorName,
            ),
          ),
        ])
          _simpleCard(
            title: skin.label,
            subtitle: _playerData.equippedBallSkinId == skin.id
                ? '装備中'
                : ownedSkinIds.contains(skin.id)
                    ? 'タップで装備'
                    : '未所持',
            icon: Icons.circle,
            leading: _skinPreview(skin.id),
            accentColor: skin.colorName == 'prism'
                ? const Color(0xFFFFD54A)
                : GameThemeColors.cyan,
            replaceSelectedIcon: false,
            selected: _playerData.equippedBallSkinId == skin.id,
            available: ownedSkinIds.contains(skin.id),
            onTap: ownedSkinIds.contains(skin.id)
                ? () async {
                    _playUiTap();
                    await _playerData.setEquippedBallSkinId(skin.id);
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                  }
                : null,
          ),
      ],
    );
  }

  Widget _buildIconsTab() {
    final ownedIconIds = {
      ..._playerData.ownedItems
          .where((item) => item.type == ItemType.icon)
          .map((item) => item.id),
    };
    return _grid(
      children: [
        _simpleCard(
          title: 'デフォルト',
          subtitle:
              _playerData.equippedPlayerIconId == 'default' ? '装備中' : 'タップで装備',
          icon: Icons.person,
          selected: _playerData.equippedPlayerIconId == 'default',
          available: true,
          onTap: () async {
            _playUiTap();
            await _playerData.setEquippedPlayerIconId('default');
            await _multiplayerManager.updateUserName(_playerData.playerName);
            if (!mounted) {
              return;
            }
            setState(() {});
          },
        ),
        for (final icon in GameItemCatalog.playerIcons)
          _simpleCard(
            title: icon.name,
            subtitle: _playerData.equippedPlayerIconId == icon.id
                ? '装備中'
                : ownedIconIds.contains(icon.id)
                    ? 'タップで装備'
                    : '未所持',
            icon: _iconForPlayerIcon(icon.iconName),
            selected: _playerData.equippedPlayerIconId == icon.id,
            available: ownedIconIds.contains(icon.id),
            onTap: ownedIconIds.contains(icon.id)
                ? () async {
                    _playUiTap();
                    await _playerData.setEquippedPlayerIconId(icon.id);
                    await _multiplayerManager.updateUserName(
                      _playerData.playerName,
                    );
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                  }
                : null,
          ),
      ],
    );
  }

  Widget _buildFramesTab() {
    final ownedFrameIds = {
      ..._playerData.ownedItems
          .where((item) => item.type == ItemType.frame)
          .map((item) => item.id),
    };
    return _grid(
      children: [
        _simpleCard(
          title: 'デフォルト',
          subtitle:
              _playerData.equippedIconFrameId == 'default' ? '装備中' : 'タップで装備',
          icon: Icons.crop_square,
          leading: _defaultFramePreview(GameThemeColors.cyan),
          selected: _playerData.equippedIconFrameId == 'default',
          available: true,
          onTap: () async {
            _playUiTap();
            await _playerData.setEquippedIconFrameId('default');
            await _multiplayerManager.updateUserName(_playerData.playerName);
            if (!mounted) {
              return;
            }
            setState(() {});
          },
        ),
        for (final frame in GameItemCatalog.iconFrames)
          _simpleCard(
            title: frame.name,
            subtitle: _playerData.equippedIconFrameId == frame.id
                ? '装備中'
                : ownedFrameIds.contains(frame.id)
                    ? 'タップで装備'
                    : '未所持',
            icon: Icons.crop_square,
            leading: _framePreview(frame),
            accentColor: _frameColor(frame),
            selected: _playerData.equippedIconFrameId == frame.id,
            available: ownedFrameIds.contains(frame.id),
            onTap: ownedFrameIds.contains(frame.id)
                ? () async {
                    _playUiTap();
                    await _playerData.setEquippedIconFrameId(frame.id);
                    await _multiplayerManager.updateUserName(
                      _playerData.playerName,
                    );
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                  }
                : null,
          ),
      ],
    );
  }

  Widget _grid({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 520 ? 3 : 2;
        return GridView.count(
          padding: const EdgeInsets.all(12),
          crossAxisCount: crossAxisCount,
          childAspectRatio: 2.35,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: children,
        );
      },
    );
  }

  Widget _simpleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? leading,
    Color? accentColor,
    bool replaceSelectedIcon = true,
    required bool selected,
    required bool available,
    required VoidCallback? onTap,
  }) {
    final muted = !available;
    final accent = accentColor ?? GameThemeColors.cyan;
    final borderColor = selected
        ? accent
        : muted
            ? Colors.white.withValues(alpha: 0.06)
            : accent.withValues(alpha: 0.38);
    final backgroundColor = selected
        ? accent.withValues(alpha: 0.14)
        : muted
            ? const Color(0xFF0B1019)
            : const Color(0xFF111827);
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              onTap();
            },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                leading ??
                    Icon(
                      selected && replaceSelectedIcon
                          ? Icons.check_circle
                          : icon,
                      color: selected
                          ? accent
                          : muted
                              ? Colors.white24
                              : accent.withValues(alpha: 0.9),
                      size: 24,
                    ),
                if (muted)
                  const Positioned(
                    right: -4,
                    bottom: -4,
                    child: Icon(Icons.lock, size: 12, color: Colors.white54),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: muted ? Colors.white54 : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  ..._responsiveSubtitleLines(
                    subtitle,
                    color: selected
                        ? accent
                        : muted
                            ? Colors.white38
                            : Colors.white54,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _responsiveSubtitleLines(
    String subtitle, {
    required Color color,
    required FontWeight fontWeight,
  }) {
    return subtitle
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(2)
        .map(
          (line) => SizedBox(
            width: double.infinity,
            height: 13,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  line,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: fontWeight,
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  IconData _iconForStamp(String? iconName) {
    switch (iconName) {
      case 'handshake':
        return Icons.handshake;
      case 'water_drop':
        return Icons.water_drop;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'thumb_up':
        return Icons.thumb_up;
      case 'coffee':
        return Icons.coffee;
      case 'visibility':
        return Icons.visibility;
      case 'memory':
        return Icons.memory;
      default:
        return Icons.chat_bubble;
    }
  }

  IconData _iconForPlayerIcon(String? iconName) {
    switch (iconName) {
      case 'bolt':
        return Icons.bolt;
      case 'star':
        return Icons.star;
      case 'gamepad':
        return Icons.sports_esports;
      case 'sword':
        return Icons.gavel;
      case 'hexagon':
        return Icons.hexagon;
      case 'trophy':
        return Icons.emoji_events;
      case 'medal':
        return Icons.military_tech;
      case 'crown':
        return Icons.workspace_premium;
      case 'diamond':
        return Icons.diamond;
      case 'fire':
        return Icons.local_fire_department;
      case 'water':
        return Icons.water_drop;
      case 'moon':
        return Icons.dark_mode;
      case 'visibility':
        return Icons.visibility;
      case 'rocket':
        return Icons.rocket_launch;
      case 'shield':
        return Icons.shield;
      case 'terminal':
        return Icons.terminal;
      case 'smile':
        return Icons.sentiment_satisfied_alt;
      case 'ribbon':
        return Icons.workspace_premium;
      case 'heart':
        return Icons.favorite;
      case 'music':
        return Icons.music_note;
      case 'cafe':
        return Icons.coffee;
      case 'flower':
        return Icons.local_florist;
      case 'bell':
        return Icons.notifications;
      case 'skull':
        return Icons.dangerous;
      default:
        return Icons.person;
    }
  }

  Widget _skinPreview(String skinId) {
    return SizedBox(
      width: 28,
      height: 28,
      child: MiniBallWidget(
        ballColor: BallColor.blue,
        size: 28,
        showOuterGlow: false,
        ballSkinId: skinId,
      ),
    );
  }

  Widget _defaultFramePreview(Color color) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2.4),
      ),
    );
  }

  Widget _framePreview(GameItem frame) {
    final color = _frameColor(frame);
    if (frame.colorName == 'rainbow') {
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF4D6D),
              Color(0xFFFFD54A),
              Color(0xFF35F0FF),
              Color(0xFFB91DFF),
              Color(0xFFFF4D6D),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Container(
          margin: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      );
    }
    return _defaultFramePreview(color);
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
      'black' => Colors.white70,
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
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _NeonTabBar extends StatelessWidget {
  const _NeonTabBar({required this.tabs});

  final List<String> tabs;

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
          fontSize: 12,
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
                  child: Text(
                    tab,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
