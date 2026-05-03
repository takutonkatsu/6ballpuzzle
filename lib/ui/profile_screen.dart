import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sfx.dart';
import '../data/models/badge_item.dart';
import '../data/player_data_manager.dart';
import '../network/multiplayer_manager.dart';
import 'components/hexagon_currency_icons.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const int _nameChangeCost = 10000;

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
    return Scaffold(
      backgroundColor: const Color(0xFF070912),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('プロフィール'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _ScanlineBackground()),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          else
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildIdentityCard(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    final equippedBadges = _playerData.equippedBadgeIds
        .map(BadgeCatalog.findById)
        .whereType<BadgeItem>()
        .toList();

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101423).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.cyanAccent, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withValues(alpha: 0.28),
            blurRadius: 30,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.purpleAccent.withValues(alpha: 0.14),
            blurRadius: 48,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.cyanAccent),
                ),
                child: Icon(
                  _playerIconData(_playerData.equippedPlayerIconId),
                  color: Colors.cyanAccent,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _playerData.displayPlayerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID ${_playerData.playerId}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '名前変更',
                onPressed: () {
                  _playUiTap();
                  unawaited(_editName());
                },
                icon: const Icon(Icons.edit, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _buildRateAndSkin(),
          const SizedBox(height: 22),
          const Row(
            children: [
              Text(
                'BADGES',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildBadgeSlot(
                  equippedBadges.isNotEmpty ? equippedBadges[0] : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildBadgeSlot(
                  equippedBadges.length > 1 ? equippedBadges[1] : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRateAndSkin() {
    return Row(
      children: [
        Expanded(
          child: _profileMetric(
            label: 'RATE',
            value: '${_playerData.currentRating}',
            color: Colors.pinkAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 92,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                CustomPaint(
                  size: const Size(48, 48),
                  painter: _BallSkinPreviewPainter(
                    skinId: _playerData.equippedBallSkinId,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _skinLabel(_playerData.equippedBallSkinId),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _profileMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeSlot(BadgeItem? badge) {
    return Container(
      height: 82,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.32)),
      ),
      child: badge == null
          ? const Center(
              child: Text(
                'EMPTY',
                style: TextStyle(
                  color: Colors.white38,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(badge.icon, color: Colors.amberAccent, size: 24),
                const SizedBox(height: 8),
                Text(
                  badge.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _playerData.playerName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151827),
          title: const Text('名前変更'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '・10文字以内',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Row(
                children: [
                  Text(
                    '・変更には',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(width: 4),
                  HexagonCoinAmount(
                    _nameChangeCost,
                    color: Colors.white70,
                    iconSize: 13,
                    fontSize: 12,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'が必要です',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '・不適切な名前の使用はアカウント停止に繋がる恐れがあります',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 10,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                decoration: const InputDecoration(counterText: ''),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _playUiTap();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                _playUiTap();
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || nextName == null) {
      return;
    }

    final previousName = _playerData.playerName;
    if (nextName == previousName) {
      return;
    }

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151827),
          title: const Text('消費します'),
          content: const Row(
            children: [
              Text(
                '名前の変更には ',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
              HexagonCoinAmount(
                _nameChangeCost,
                color: Colors.white70,
                iconSize: 16,
                fontSize: 14,
              ),
              Text(
                ' を消費します。',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _playUiTap();
                Navigator.of(confirmContext).pop(false);
              },
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                _playUiTap();
                Navigator.of(confirmContext).pop(true);
              },
              child: const Text('変更する'),
            ),
          ],
        );
      },
    );
    if (shouldProceed != true || !mounted) {
      return;
    }

    try {
      await _playerData.spendCoins(_nameChangeCost);
      await _playerData.setPlayerName(nextName);
      _multiplayerManager.setPlayerName(_playerData.playerName);
      await _multiplayerManager.updateUserName(_playerData.playerName);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  String _skinLabel(String skinId) {
    return switch (skinId) {
      'skin_neon_chrome' => 'NEON CHROME',
      'skin_black_ice' => 'BLACK ICE',
      _ => 'DEFAULT',
    };
  }

  IconData _playerIconData(String iconId) {
    return switch (iconId) {
      'icon_bolt' => Icons.bolt,
      'icon_star' => Icons.star,
      'icon_gamepad' => Icons.sports_esports,
      _ => Icons.person,
    };
  }
}

class _ScanlineBackground extends StatelessWidget {
  const _ScanlineBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanlinePainter(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF080A14), Color(0xFF101020)],
          ),
        ),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BallSkinPreviewPainter extends CustomPainter {
  const _BallSkinPreviewPainter({required this.skinId});

  final String skinId;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final colors = switch (skinId) {
      'skin_black_ice' => [Colors.white, Colors.lightBlueAccent, Colors.black],
      'skin_neon_chrome' => [Colors.white, Colors.purpleAccent, Colors.cyan],
      _ => [Colors.white, Colors.cyanAccent, Colors.blueAccent],
    };
    final paint = Paint()
      ..shader = RadialGradient(colors: colors).createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(covariant _BallSkinPreviewPainter oldDelegate) {
    return oldDelegate.skinId != skinId;
  }
}
