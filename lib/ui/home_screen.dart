import 'package:flutter/material.dart';

import '../network/multiplayer_manager.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MultiplayerManager _multiplayerManager = MultiplayerManager();
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '6-BALL PUZZLE',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.blueAccent, blurRadius: 20),
                ],
              ),
            ),
            const SizedBox(height: 60),
            _buildMenuButton(
              context,
              'ENDLESS MODE',
              Icons.loop,
              () => _startGame(context, false),
            ),
            const SizedBox(height: 24),
            _buildMenuButton(
              context,
              'CPU VS MODE',
              Icons.smart_toy,
              () => _startGame(context, true),
            ),
            const SizedBox(height: 24),
            _buildMenuButton(
              context,
              'CREATE ROOM',
              Icons.add_link,
              _isBusy ? null : () => _createRoom(context),
            ),
            const SizedBox(height: 24),
            _buildMenuButton(
              context,
              'JOIN ROOM',
              Icons.login,
              _isBusy ? null : () => _joinRoom(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback? onPressed,
  ) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        backgroundColor: const Color(0xFF1E1E32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: Colors.white24, width: 2),
      ),
      onPressed: onPressed,
      child: SizedBox(
        width: 240,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.amberAccent, size: 28),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startGame(BuildContext context, bool isCpuMode) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => GameScreen(isCpuMode: isCpuMode),
      ),
    );
  }

  Future<void> _createRoom(BuildContext context) async {
    setState(() {
      _isBusy = true;
    });

    try {
      await _multiplayerManager.createRoom();
      if (!context.mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen.online(
            roomId: _multiplayerManager.currentRoomId,
            isHost: true,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      await _showAlert(context, 'ルーム作成に失敗しました', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _joinRoom(BuildContext context) async {
    final roomId = await _showRoomIdDialog(context);
    if (!mounted || roomId == null) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      final joined = await _multiplayerManager.joinRoom(roomId);
      if (!context.mounted) {
        return;
      }

      if (!joined) {
        await _showAlert(
          context,
          'ルームに参加できません',
          '部屋が見つからないか、すでに対戦中です。',
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen.online(
            roomId: roomId,
            isHost: false,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      await _showAlert(context, '接続エラー', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<String?> _showRoomIdDialog(BuildContext context) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E32),
          title: const Text(
            '4桁のルームIDを入力',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '1234',
              counterText: '',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                final roomId = controller.text.trim();
                if (RegExp(r'^\d{4}$').hasMatch(roomId)) {
                  Navigator.of(dialogContext).pop(roomId);
                }
              },
              child: const Text('JOIN'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAlert(
    BuildContext context,
    String title,
    String message,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E32),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
