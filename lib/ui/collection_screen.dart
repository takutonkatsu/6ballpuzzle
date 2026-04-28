import 'package:flutter/material.dart';

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

  static const _playerIcons = <({String id, IconData icon, String label})>[
    (id: 'default', icon: Icons.person, label: 'デフォルト'),
    (id: 'bolt', icon: Icons.bolt, label: 'ボルト'),
    (id: 'star', icon: Icons.star, label: 'スター'),
    (id: 'gamepad', icon: Icons.sports_esports, label: 'ゲーム'),
  ];

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
    final stamps = _playerData.ownedItems.where((item) => item.isStamp).toList();
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
    final skins = <({String id, String label})>[
      (id: 'default', label: 'DEFAULT'),
      (id: 'skin_neon_chrome', label: 'NEON CHROME'),
      (id: 'skin_black_ice', label: 'BLACK ICE'),
    ];

    return _grid(
      children: [
        for (final skin in skins)
          _simpleCard(
            title: skin.label,
            subtitle: ownedSkinIds.contains(skin.id) ? '使用可能' : '未所持',
            icon: Icons.blur_on,
            selected: _playerData.equippedBallSkinId == skin.id,
            onTap: ownedSkinIds.contains(skin.id)
                ? () async {
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
    return _grid(
      children: [
        for (final icon in _playerIcons)
          _simpleCard(
            title: icon.label,
            subtitle: 'プロフィール用',
            icon: icon.icon,
            selected: _playerData.equippedPlayerIconId == icon.id,
            onTap: () async {
              await _playerData.setEquippedPlayerIconId(icon.id);
              if (!mounted) {
                return;
              }
              setState(() {});
            },
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
      onTap: onTap,
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
            Icon(icon, color: selected ? Colors.amberAccent : Colors.white70, size: 32),
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
      default:
        return Icons.chat_bubble;
    }
  }
}
