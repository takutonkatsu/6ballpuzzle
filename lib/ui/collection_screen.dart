import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../data/models/badge_item.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../network/multiplayer_manager.dart';

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
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A12),
        appBar: AppBar(
          backgroundColor: const Color(0xFF101423),
          title: const Text('コレクション'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'スタンプ'),
              Tab(text: '実績バッジ'),
              Tab(text: 'ボール'),
              Tab(text: 'アイコン'),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              )
            : TabBarView(
                children: [
                  _buildStampsTab(),
                  _buildBadgesTab(),
                  _buildSkinsTab(),
                  _buildIconsTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildStampsTab() {
    final stamps = _playerData.ownedItems.where((item) => item.isStamp).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (stamps.isEmpty) {
      return _emptyState('まだスタンプを持っていません');
    }
    return _grid(
      children: [
        for (final stamp in stamps)
          _simpleCard(
            title: stamp.name,
            subtitle: '所持中  Lv.${stamp.level}',
            icon: _iconForStamp(stamp.iconName),
            selected: false,
            available: true,
            onTap: null,
          ),
      ],
    );
  }

  Widget _buildBadgesTab() {
    final unlocked = _playerData.unlockedBadgeIds.toSet();
    final equipped = _playerData.equippedBadgeIds.toSet();
    return _grid(
      children: [
        for (final badge in BadgeCatalog.allBadges)
          _simpleCard(
            title: badge.label,
            subtitle: equipped.contains(badge.id)
                ? '装備中'
                : unlocked.contains(badge.id)
                    ? 'タップで装備'
                    : '未解放',
            icon: badge.icon,
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
          const (id: 'default', label: 'デフォルト'),
          ...GameItemCatalog.epicSkins
              .map((item) => (id: item.id, label: item.name)),
        ])
          _simpleCard(
            title: skin.label,
            subtitle: _playerData.equippedBallSkinId == skin.id
                ? '装備中'
                : ownedSkinIds.contains(skin.id)
                    ? 'タップで装備'
                    : '未所持',
            icon: Icons.blur_on,
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
            await _multiplayerManager.updateUserName(
              _playerData.playerName,
            );
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

  Widget _grid({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 520 ? 3 : 2;
        return GridView.count(
          padding: const EdgeInsets.all(12),
          crossAxisCount: crossAxisCount,
          childAspectRatio: 2.6,
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
    required bool selected,
    required bool available,
    required VoidCallback? onTap,
  }) {
    final muted = !available;
    final borderColor = selected
        ? Colors.cyanAccent
        : muted
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.14);
    final backgroundColor = selected
        ? Colors.cyanAccent.withValues(alpha: 0.14)
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
                Icon(
                  selected ? Icons.check_circle : icon,
                  color: selected
                      ? Colors.amberAccent
                      : muted
                          ? Colors.white24
                          : Colors.white70,
                  size: 24,
                ),
                if (muted)
                  const Positioned(
                    right: -4,
                    bottom: -4,
                    child: Icon(
                      Icons.lock,
                      size: 12,
                      color: Colors.white54,
                    ),
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
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Colors.amberAccent
                          : muted
                              ? Colors.white38
                              : Colors.white54,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String text) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(color: Colors.white60),
      ),
    );
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
      default:
        return Icons.person;
    }
  }
}
