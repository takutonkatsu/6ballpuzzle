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
    final stamps =
        _playerData.ownedItems.where((item) => item.isStamp).toList();
    if (stamps.isEmpty) {
      return _emptyState('まだスタンプを持っていません');
    }
    return _grid(
      children: [
        for (final stamp in stamps)
          _simpleCard(
            title: stamp.name,
            subtitle: 'Lv.${stamp.level}',
            icon: _iconForStamp(stamp.iconName),
            selected: false,
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
            subtitle: unlocked.contains(badge.id) ? '装備可能' : '未解放',
            icon: badge.icon,
            selected: equipped.contains(badge.id),
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
          const (id: 'default', label: 'DEFAULT'),
          ...GameItemCatalog.epicSkins
              .map((item) => (id: item.id, label: item.name)),
        ])
          _simpleCard(
            title: skin.label,
            subtitle: ownedSkinIds.contains(skin.id) ? '使用可能' : '未所持',
            icon: Icons.blur_on,
            selected: _playerData.equippedBallSkinId == skin.id,
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
          title: 'DEFAULT',
          subtitle: '初期アイコン',
          icon: Icons.person,
          selected: _playerData.equippedPlayerIconId == 'default',
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
            subtitle: ownedIconIds.contains(icon.id) ? '使用可能' : '未所持',
            icon: _iconForPlayerIcon(icon.iconName),
            selected: _playerData.equippedPlayerIconId == icon.id,
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
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      childAspectRatio: 1.05,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: children,
    );
  }

  Widget _simpleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              onTap();
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? Colors.cyanAccent.withValues(alpha: 0.12)
              : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.cyanAccent
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: selected ? Colors.amberAccent : Colors.white70,
                size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
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
