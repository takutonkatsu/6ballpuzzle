import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/multiplayer_manager.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const _playerNameKey = 'player_name';
  final MultiplayerManager _multiplayerManager = MultiplayerManager();
  final TextEditingController _playerNameController = TextEditingController();
  bool _isBusy = false;
  String _playerName = '';
  int _rating = MultiplayerManager.initialRating;
  bool _isLoadingProfile = true;
  String? _queuedPlayerName;
  String _lastPersistedPlayerName = '';
  bool _isPersistingPlayerName = false;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _loadPlayerName();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    _playerNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBanner1(),
            const SizedBox(height: 12),
            _buildTopBanner2(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _build3DRotatingBall(),
                        _buildModeSelectionCutout(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildBottomBannerTop(),
            _buildBottomBannerAdPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBanner1() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.2), blurRadius: 8)],
            ),
            child: Row(
              children: [
                const Text('Lv.12', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  width: 50,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.7,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [BoxShadow(color: Colors.cyanAccent, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _playerNameController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'PLAYER NAME',
                    hintStyle: const TextStyle(color: Colors.white38),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    filled: true,
                    fillColor: Colors.black54,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: Colors.purpleAccent.withOpacity(0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Colors.purpleAccent),
                    ),
                  ),
                  onChanged: _savePlayerName,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.amberAccent.withOpacity(0.2), blurRadius: 8)],
            ),
            child: const Row(
              children: [
                Icon(Icons.monetization_on, color: Colors.amberAccent, size: 16),
                SizedBox(width: 4),
                Text('1,250', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBanner2() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.pinkAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SEASON 3', style: TextStyle(color: Colors.pinkAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    Text(_isLoadingProfile ? 'RATE: ...' : 'RATE: $_rating', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.pinkAccent.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emoji_events, color: Colors.pinkAccent, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildRoundIcon(Icons.notifications, Colors.cyanAccent, () {}),
              const SizedBox(width: 8),
              _buildRoundIcon(Icons.store, Colors.purpleAccent, () {}),
              const SizedBox(width: 8),
              _buildRoundIcon(Icons.assignment, Colors.amberAccent, () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoundIcon(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 4)],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _build3DRotatingBall() {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(_animController.value * 2 * 3.14159),
          child: child,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNeonBall(Colors.cyanAccent),
          _buildNeonBall(Colors.purpleAccent),
          _buildNeonBall(Colors.pinkAccent),
        ],
      ),
    );
  }

  Widget _buildNeonBall(Color glowColor) {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: glowColor.withOpacity(0.8),
        boxShadow: [
          BoxShadow(color: glowColor, blurRadius: 15, spreadRadius: 2),
        ],
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _buildModeSelectionCutout() {
    return SizedBox(
      height: 280,
      width: 320,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildGridButton('ENDLESS\nMODE', Colors.cyanAccent, () => _startGame(context, false))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildGridButton('CPU VS\nMODE', Colors.purpleAccent, () => _startGame(context, true))),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildGridButton('CREATE\nROOM', Colors.pinkAccent, _isBusy ? null : () => _createRoom(context))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildGridButton('JOIN\nROOM', Colors.amberAccent, _isBusy ? null : () => _joinRoom(context))),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.center,
            child: InkWell(
              onTap: _isBusy || _isLoadingProfile ? null : () => _startRandomMatch(context),
              borderRadius: BorderRadius.circular(60),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0F0F13),
                  border: Border.all(color: const Color(0xFF0F0F13), width: 8), 
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.pinkAccent.withOpacity(0.2),
                    border: Border.all(color: Colors.pinkAccent, width: 2),
                    boxShadow: [BoxShadow(color: Colors.pinkAccent.withOpacity(0.6), blurRadius: 20)],
                  ),
                  child: const Center(
                    child: Text(
                      'RANDOM\nMATCH',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.2,
                        shadows: [Shadow(color: Colors.pinkAccent, blurRadius: 10)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridButton(String title, Color accentColor, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 2,
                shadows: [Shadow(color: accentColor, blurRadius: 10)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBannerTop() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomTextButton(Icons.settings, 'SETTINGS'),
          _buildBottomTextButton(Icons.bar_chart, 'RECORDS'),
          _buildBottomTextButton(Icons.help_outline, 'HOW TO'),
          _buildBottomTextButton(Icons.do_not_disturb_alt, 'NO ADS'),
        ],
      ),
    );
  }

  Widget _buildBottomTextButton(IconData icon, String label) {
    return InkWell(
      onTap: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.cyanAccent.withOpacity(0.7), size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.cyanAccent.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBottomBannerAdPlaceholder() {
    return Container(
      width: double.infinity,
      height: 50,
      color: Colors.black,
      alignment: Alignment.center,
      child: const Text('ADVERTISEMENT', style: TextStyle(color: Colors.white24, letterSpacing: 4, fontSize: 12)),
    );
  }

  void _startGame(BuildContext context, bool isCpuMode) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => GameScreen(isCpuMode: isCpuMode),
      ),
    );
  }

  Future<void> _loadPlayerName() async {
    final savedName = await _readSavedPlayerName();
    if (!mounted) {
      return;
    }

    setState(() {
      _playerName = savedName;
      _playerNameController.text = savedName;
    });
    _multiplayerManager.setPlayerName(savedName);
    _lastPersistedPlayerName = savedName;

    try {
      final rating = await _multiplayerManager.initializeUser(name: savedName);
      if (!mounted) {
        return;
      }
      setState(() {
        _rating = rating;
        _isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rating = _multiplayerManager.currentRating;
        _isLoadingProfile = false;
      });
    }
  }

  void _savePlayerName(String value) {
    final nextName = value.trim();
    setState(() {
      _playerName = nextName;
    });
    _multiplayerManager.setPlayerName(nextName);
    _queuePlayerNameSave(nextName);
  }

  void _queuePlayerNameSave(String name) {
    _queuedPlayerName = name;
    if (_isPersistingPlayerName) {
      return;
    }
    unawaited(_drainPlayerNameSaveQueue());
  }

  Future<void> _drainPlayerNameSaveQueue() async {
    _isPersistingPlayerName = true;
    try {
      while (_queuedPlayerName != null) {
        final nextName = _queuedPlayerName!;
        _queuedPlayerName = null;
        if (nextName == _lastPersistedPlayerName) {
          continue;
        }
        await _writeSavedPlayerName(nextName);
        _lastPersistedPlayerName = nextName;
        await _multiplayerManager.updateUserName(nextName);
      }
    } finally {
      _isPersistingPlayerName = false;
      if (_queuedPlayerName != null) {
        unawaited(_drainPlayerNameSaveQueue());
      }
    }
  }

  Future<String> _readSavedPlayerName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_playerNameKey) ?? '';
    } on MissingPluginException {
      return '';
    }
  }

  Future<void> _writeSavedPlayerName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_playerNameKey, name);
    } on MissingPluginException {
      // The app can still run if a dev build has not been fully rebuilt after
      // adding the plugin; the value will persist once registration is active.
    }
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

  Future<void> _startRandomMatch(BuildContext context) async {
    setState(() {
      _isBusy = true;
    });

    var dialogOpen = false;
    try {
      dialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E32),
              title: const Text(
                '対戦相手を検索中...',
                style: TextStyle(color: Colors.white),
              ),
              content: const SizedBox(
                height: 64,
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.amberAccent,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    unawaited(_multiplayerManager.cancelMatchmaking());
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('キャンセル'),
                ),
              ],
            );
          },
        ).then((_) {
          dialogOpen = false;
        }),
      );

      await Future<void>.delayed(Duration.zero);
      final roomId = await _multiplayerManager.startRandomMatch(_rating);
      if (!context.mounted) {
        return;
      }

      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (roomId == null) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen.online(
            roomId: roomId,
            isHost: _multiplayerManager.isHost,
            isRankedMode: true,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await _showAlert(context, 'ランダムマッチに失敗しました', '$error');
    } finally {
      await _multiplayerManager.cancelMatchmaking();
      if (mounted) {
        setState(() {
          _isBusy = false;
          _rating = _multiplayerManager.currentRating;
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
