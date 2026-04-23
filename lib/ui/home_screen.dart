import 'dart:async';
import 'dart:math' as math;

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/multiplayer_manager.dart';
import '../game/game_models.dart';
import '../game/components/ball_component.dart';
import 'components/banner_ad_widget.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const _playerNameKey = 'player_name';
  final MultiplayerManager _multiplayerManager = MultiplayerManager();
  final TextEditingController _playerNameController = TextEditingController();
  bool _isBusy = false;
  int _rating = MultiplayerManager.initialRating;
  bool _isLoadingProfile = true;
  String? _queuedPlayerName;
  String _lastPersistedPlayerName = '';
  bool _isPersistingPlayerName = false;
  late AnimationController _animController;
  bool _isHomeBgmPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadPlayerName();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    unawaited(_startHomeBgm());
  }

  @override
  void dispose() {
    unawaited(_stopHomeBgm());
    _animController.dispose();
    _playerNameController.dispose();
    super.dispose();
  }

  Future<void> _startHomeBgm() async {
    if (_isHomeBgmPlaying) {
      return;
    }
    _isHomeBgmPlaying = true;
    try {
      await FlameAudio.bgm.play('home_screen_bgm01.mp3', volume: 0.18);
    } catch (_) {
      _isHomeBgmPlaying = false;
    }
  }

  Future<void> _stopHomeBgm() async {
    if (!_isHomeBgmPlaying && !FlameAudio.bgm.isPlaying) {
      return;
    }
    _isHomeBgmPlaying = false;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {
      // BGM停止失敗で画面遷移や破棄を止めない。
    }
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const ballHeight = 152.0;
                        const spacing = 12.0;
                        final modeHeight =
                            (constraints.maxHeight - ballHeight - spacing)
                                .clamp(200.0, 280.0);

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _build3DRotatingBall(),
                            const SizedBox(height: spacing),
                            _buildModeSelectionCutout(height: modeHeight),
                          ],
                        );
                      },
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
              border:
                  Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                    blurRadius: 8)
              ],
            ),
            child: Row(
              children: [
                const Text('Lv.12',
                    style: TextStyle(
                        color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
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
                        boxShadow: const [
                          BoxShadow(color: Colors.cyanAccent, blurRadius: 4)
                        ],
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 132,
                    maxWidth: 172,
                  ),
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _playerNameController,
                      maxLength: 10,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(10),
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'PLAYER NAME',
                        hintStyle: const TextStyle(color: Colors.white38),
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        filled: true,
                        fillColor: Colors.black54,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                              color:
                                  Colors.purpleAccent.withValues(alpha: 0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide:
                              const BorderSide(color: Colors.purpleAccent),
                        ),
                      ),
                      onChanged: _savePlayerName,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              border:
                  Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.amberAccent.withValues(alpha: 0.2),
                    blurRadius: 8)
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.monetization_on,
                    color: Colors.amberAccent, size: 16),
                SizedBox(width: 4),
                Text('1,250',
                    style: TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold)),
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
              border:
                  Border.all(color: Colors.pinkAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SEASON 3',
                        style: TextStyle(
                            color: Colors.pinkAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                    Text(_isLoadingProfile ? 'RATE: ...' : 'RATE: $_rating',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.pinkAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emoji_events,
                        color: Colors.pinkAccent, size: 18),
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
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 4)
          ],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _build3DRotatingBall() {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final rotation = _animController.value * math.pi * 2;
        const baseSize = 76.0;
        const centerX = 100.0;
        const centerY = 76.0;
        final triRadius = baseSize / math.sqrt(3);
        final balls = [
          (color: BallColor.blue, x: 0.0, y: -triRadius),
          (color: BallColor.purple, x: -baseSize / 2, y: triRadius / 2),
          (color: BallColor.red, x: baseSize / 2, y: triRadius / 2),
        ].map((ball) {
          final projectedX = ball.x * math.cos(rotation);
          final depth = -ball.x * math.sin(rotation);
          final scale = 0.92 + ((depth / (baseSize / 2)) + 1) * 0.06;
          final size = baseSize * scale;
          return (
            color: ball.color,
            depth: depth,
            left: centerX + projectedX - size / 2,
            top: centerY + ball.y - size / 2,
            size: size,
          );
        }).toList()
          ..sort((a, b) => a.depth.compareTo(b.depth));

        return SizedBox(
          width: 200,
          height: 152,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final ball in balls)
                Positioned(
                  left: ball.left,
                  top: ball.top,
                  child: MiniBallWidget(
                    ballColor: ball.color,
                    size: ball.size,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeSelectionCutout({double height = 280}) {
    return SizedBox(
      height: height,
      width: 320,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _buildGridButton('ENDLESS', Colors.greenAccent,
                            () => _startGame(context, false))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildGridButton(
                            'CPU\nBATTLE',
                            Colors.yellowAccent,
                            _isBusy
                                ? null
                                : () => _showCpuDifficultyDialog(context))),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _buildGridButton(
                            'CREATE\nROOM',
                            Colors.redAccent,
                            _isBusy ? null : () => _createRoom(context))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildGridButton(
                            'JOIN\nROOM',
                            Colors.lightBlueAccent,
                            _isBusy ? null : () => _joinRoom(context))),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final pulse =
                    (math.sin(_animController.value * math.pi * 2) + 1) / 2;
                final glowAlpha = 0.34 + (pulse * 0.16);
                final glowBlur = 24.0 + (pulse * 8.0);
                final scale = 1.0 + (pulse * 0.018);

                return Transform.scale(
                  scale: scale,
                  child: InkWell(
                    onTap: _isBusy || _isLoadingProfile
                        ? null
                        : () => _startRandomMatch(context),
                    borderRadius: BorderRadius.circular(74),
                    child: Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0F0F13),
                        border: Border.all(
                          color: const Color(0xFF0F0F13),
                          width: 10,
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.purpleAccent.withValues(
                            alpha: 0.16 + (pulse * 0.04),
                          ),
                          border: Border.all(
                            color: Colors.purpleAccent,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purpleAccent.withValues(
                                alpha: glowAlpha,
                              ),
                              blurRadius: glowBlur,
                              spreadRadius: 2 + (pulse * 1.5),
                            ),
                            BoxShadow(
                              color: Colors.pinkAccent.withValues(
                                alpha: 0.14 + (pulse * 0.08),
                              ),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'RANDOM\nMATCH',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 1.4,
                              shadows: [
                                Shadow(
                                  color: Colors.purpleAccent,
                                  blurRadius: 9 + (pulse * 4),
                                ),
                                Shadow(
                                  color: Colors.pinkAccent.withValues(
                                    alpha: 0.45,
                                  ),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridButton(
      String title, Color accentColor, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: accentColor.withValues(alpha: 0.58), width: 2),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.18),
              blurRadius: 12,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 22,
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
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 2,
                shadows: [
                  Shadow(color: accentColor, blurRadius: 8),
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 2,
                  ),
                ],
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
          Icon(icon, color: Colors.cyanAccent.withValues(alpha: 0.7), size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: Colors.cyanAccent.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
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
      child: const BannerAdWidget(),
    );
  }

  void _startGame(
    BuildContext context,
    bool isCpuMode, {
    CPUDifficulty cpuDifficulty = CPUDifficulty.hard,
  }) {
    unawaited(_stopHomeBgm());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => GameScreen(
          isCpuMode: isCpuMode,
          cpuDifficulty: cpuDifficulty,
        ),
      ),
    );
  }

  Future<void> _showCpuDifficultyDialog(BuildContext context) {
    const options = [
      (
        label: '弱い',
        subtitle: 'ゆっくり考えて、よく迷う',
        difficulty: CPUDifficulty.easy,
        color: Colors.greenAccent
      ),
      (
        label: '普通',
        subtitle: 'ほどよく考える標準CPU',
        difficulty: CPUDifficulty.normal,
        color: Colors.cyanAccent
      ),
      (
        label: '強い',
        subtitle: '速く読んでミスが少ない',
        difficulty: CPUDifficulty.hard,
        color: Colors.yellowAccent
      ),
      (
        label: '鬼',
        subtitle: '最速でほぼ最適解を狙う',
        difficulty: CPUDifficulty.oni,
        color: Colors.redAccent
      ),
    ];

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: Colors.yellowAccent,
          title: 'CPU BATTLE',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options) ...[
                _buildCpuDifficultyTile(
                  label: option.label,
                  subtitle: option.subtitle,
                  accentColor: option.color,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _startGame(
                      context,
                      true,
                      cpuDifficulty: option.difficulty,
                    );
                  },
                ),
                if (option != options.last) const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCpuDifficultyTile({
    required String label,
    required String subtitle,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentColor.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.16),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.4,
                      shadows: [Shadow(color: accentColor, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: accentColor),
          ],
        ),
      ),
    );
  }

  Future<void> _loadPlayerName() async {
    final savedName = await _readSavedPlayerName();
    if (!mounted) {
      return;
    }

    setState(() {
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

      unawaited(_stopHomeBgm());
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

      unawaited(_stopHomeBgm());
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
            return _buildCyberDialog(
              accentColor: Colors.pinkAccent,
              title: 'RANDOM MATCH',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '対戦相手を検索中...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Colors.pinkAccent,
                        backgroundColor:
                            Colors.pinkAccent.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildCyberDialogButton(
                    label: 'CANCEL',
                    accentColor: Colors.pinkAccent,
                    onPressed: () {
                      unawaited(_multiplayerManager.cancelMatchmaking());
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ],
              ),
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

      unawaited(_stopHomeBgm());
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
        return _buildCyberDialog(
          accentColor: Colors.amberAccent,
          title: 'JOIN ROOM',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  hintText: '1234',
                  counterText: '',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.24),
                    letterSpacing: 8,
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.35),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Colors.amberAccent.withValues(alpha: 0.45),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.amberAccent),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'CANCEL',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'JOIN',
                      accentColor: Colors.amberAccent,
                      onPressed: () {
                        final roomId = controller.text.trim();
                        if (RegExp(r'^\d{4}$').hasMatch(roomId)) {
                          Navigator.of(dialogContext).pop(roomId);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        return _buildCyberDialog(
          accentColor: Colors.cyanAccent,
          title: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _buildCyberDialogButton(
                label: 'OK',
                accentColor: Colors.cyanAccent,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCyberDialog({
    required String title,
    required Widget child,
    required Color accentColor,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF141421),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.78),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.35),
              blurRadius: 24,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.purpleAccent.withValues(alpha: 0.18),
              blurRadius: 40,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accentColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.4,
                shadows: [Shadow(color: accentColor, blurRadius: 12)],
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCyberDialogButton({
    required String label,
    required Color accentColor,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.75),
          width: 1.4,
        ),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}
