import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';
import '../audio/seamless_bgm.dart';
import '../audio/sfx.dart';
import '../data/player_data_manager.dart';
import '../game/arena_manager.dart';
import '../game/mission_catalog.dart';
import '../game/mission_manager.dart';
import '../data/models/game_item.dart';
import '../network/multiplayer_manager.dart';
import '../network/ranking_manager.dart';
import '../game/game_models.dart';
import '../game/components/ball_component.dart';
import 'components/banner_ad_widget.dart';
import 'components/rewarded_ad_manager.dart';
import 'components/stamp_widget.dart';
import 'collection_screen.dart';
import 'game_screen.dart';
import 'profile_screen.dart';
import 'ranking_screen.dart';
import 'record_screen.dart';
import 'shop_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _playerNameKey = 'player_name';
  static const Duration _homeBgmDuration = Duration(microseconds: 96003651);
  static const bool _debugControlsEnabled =
      bool.fromEnvironment('ENABLE_DEBUG_CONTROLS', defaultValue: true);
  final MultiplayerManager _multiplayerManager = MultiplayerManager();
  final RankingManager _rankingManager = RankingManager.instance;
  final PlayerDataManager _playerDataManager = PlayerDataManager.instance;
  final ArenaManager _arenaManager = ArenaManager.instance;
  final MissionManager _missionManager = MissionManager.instance;
  final TextEditingController _playerNameController = TextEditingController();
  late final List<BallColor> _rotatingBallColors = _randomRotatingBallColors();
  bool _isBusy = false;
  int _rating = MultiplayerManager.initialRating;
  int _level = 1;
  int _currentLevelExp = 0;
  int _nextLevelRequiredExp = 1000;
  int _coins = PlayerDataManager.initialCoins;
  int _claimableMissionCount = 0;
  int _completedMissionCount = 0;
  bool _isLoadingProfile = true;
  late AnimationController _animController;
  bool _isHomeBgmPlaying = false;

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  List<BallColor> _randomRotatingBallColors() {
    final random = math.Random();
    return List.generate(
      3,
      (_) => BallColor.values[random.nextInt(BallColor.values.length)],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPlayerName();
    unawaited(_loadPlayerEconomy());
    unawaited(_maybeResumeSavedOnlineSession());
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    unawaited(_startHomeBgm());
  }

  @override
  void dispose() {
    unawaited(_stopHomeBgm());
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    _playerNameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startHomeBgm(forceRestart: true));
    }
  }

  Future<void> _startHomeBgm({bool forceRestart = false}) async {
    if (_isHomeBgmPlaying && !forceRestart) {
      return;
    }
    try {
      _isHomeBgmPlaying = true;
      await SeamlessBgm.instance.setMasterVolume(
        AppSettings.instance.musicVolume.value,
      );
      await SeamlessBgm.instance.play(
        assetPath: 'audio/home_screen_bgm01.wav',
        duration: _homeBgmDuration,
        volume: 0.18,
        forceRestart: forceRestart,
      );
    } catch (_) {
      _isHomeBgmPlaying = false;
    }
  }

  Future<void> _stopHomeBgm() async {
    if (!_isHomeBgmPlaying && !SeamlessBgm.instance.isPlaying) {
      return;
    }
    _isHomeBgmPlaying = false;
    try {
      await SeamlessBgm.instance.stop();
    } catch (_) {
      // BGM停止失敗で画面遷移や破棄を止めない。
    }
  }

  Future<void> _loadPlayerEconomy() async {
    try {
      await _playerDataManager.load();
      await _playerDataManager.checkDailyReset();
      await _missionManager.load();
      await _arenaManager.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncPlayerEconomyState();
      });
    } catch (_) {
      // ローカルデータ読込に失敗してもホーム表示は継続する。
    }
  }

  Future<void> _refreshPlayerEconomy() async {
    await _playerDataManager.load();
    await _playerDataManager.checkDailyReset();
    await _missionManager.load();
    await _arenaManager.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _syncPlayerEconomyState();
    });
  }

  void _syncPlayerEconomyState() {
    _level = _playerDataManager.level;
    _currentLevelExp = _playerDataManager.currentLevelExp;
    _nextLevelRequiredExp = _playerDataManager.nextLevelRequiredExp;
    _coins = _playerDataManager.coins;
    _claimableMissionCount = _missionManager.claimableCount;
    _completedMissionCount =
        _playerDataManager.currentMissions.where((mission) {
      final progress = (mission['progress'] as num?)?.toInt() ?? 0;
      final target = (mission['target'] as num?)?.toInt() ?? 0;
      return progress >= target;
    }).length;
  }

  double get _levelProgress {
    if (_nextLevelRequiredExp <= 0) {
      return 0;
    }
    return (_currentLevelExp / _nextLevelRequiredExp).clamp(0.0, 1.0);
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
                                .clamp(192.0, 280.0);

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final edgePadding = compact ? 8.0 : 16.0;
        final gap = compact ? 6.0 : 12.0;
        final levelProgressWidth = compact ? 34.0 : 52.0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: edgePadding,
            vertical: 8,
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  _playUiTap();
                  unawaited(_showLevelDetailsDialog());
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withValues(alpha: 0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Lv.$_level',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 5 : 7),
                      Container(
                        width: levelProgressWidth,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _levelProgress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent,
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.cyanAccent,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: _buildProfileButton(compact: compact),
                  ),
                ),
              ),
              SizedBox(width: gap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: compact ? 68 : 78,
                  maxWidth: compact ? 82 : 96,
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amberAccent.withValues(alpha: 0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.monetization_on,
                        color: Colors.amberAccent,
                        size: compact ? 14 : 16,
                      ),
                      SizedBox(width: compact ? 3 : 4),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '$_coins',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileButton({required bool compact}) {
    final displayName = _playerNameController.text.trim().isEmpty
        ? 'プレイヤー'
        : _playerNameController.text.trim();

    return InkWell(
      onTap: () {
        _playUiTap();
        unawaited(_openProfileScreen());
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: compact ? 34 : 36,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.purpleAccent.withValues(alpha: 0.58),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.purpleAccent.withValues(alpha: 0.18),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: compact ? 18 : 22,
              height: compact ? 18 : 22,
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.purpleAccent.withValues(alpha: 0.65),
                ),
              ),
              child: Icon(
                Icons.person,
                color: Colors.white,
                size: compact ? 13 : 15,
              ),
            ),
            SizedBox(width: compact ? 5 : 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  displayName,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: compact ? 0.4 : 0.8,
                    fontSize: compact ? 13 : 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProfileScreen() async {
    await _playerDataManager.setCurrentRating(_rating);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    final savedName = await _readSavedPlayerName();
    if (!mounted) {
      return;
    }
    setState(() {
      _playerNameController.text = savedName;
    });
    _multiplayerManager.setPlayerName(savedName);
    unawaited(_multiplayerManager.updateUserName(savedName));
    unawaited(
      _rankingManager.updateMyRating(
        rating: _rating,
        displayName: savedName,
      ),
    );
  }

  void _openRecordScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecordScreen()),
    );
  }

  void _openCollectionScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CollectionScreen()),
    );
  }

  Widget _buildTopBanner2() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: _openRankingScreen,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.pinkAccent.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.pinkAccent.withValues(alpha: 0.14),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('シーズン 0',
                          style: TextStyle(
                              color: Colors.pinkAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2)),
                      Text(_isLoadingProfile ? 'レート: ...' : 'レート: $_rating',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: _openRankingScreen,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.pinkAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amberAccent.withValues(alpha: 0.22),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.emoji_events,
                          color: Colors.amberAccent, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              _buildRoundIcon(
                Icons.notifications,
                Colors.cyanAccent,
                () => unawaited(_showAlert(context, 'お知らせ', '現在のお知らせはありません。')),
                tooltip: 'お知らせ',
              ),
              const SizedBox(width: 8),
              _buildRoundIcon(
                Icons.settings,
                Colors.purpleAccent,
                () => unawaited(_showSettingsDialog()),
                tooltip: '設定',
              ),
              const SizedBox(width: 8),
              if (_debugControlsEnabled) ...[
                _buildRoundIcon(
                  Icons.bug_report,
                  Colors.purpleAccent,
                  () => unawaited(_showDebugMenu()),
                  tooltip: 'デバッグ',
                ),
                const SizedBox(width: 8),
              ],
              _buildRoundIcon(
                Icons.bar_chart,
                Colors.lightBlueAccent,
                _openRecordScreen,
                tooltip: 'レコード',
              ),
              const SizedBox(width: 8),
              _buildRoundIcon(
                Icons.assignment_turned_in,
                Colors.amberAccent,
                () => unawaited(_showDailyMissionsDialog(context)),
                tooltip: 'デイリーミッション',
                badgeCount: _claimableMissionCount,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoundIcon(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    required String tooltip,
    int badgeCount = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          _playUiTap();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
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
            if (badgeCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Colors.pinkAccent, blurRadius: 8),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openRankingScreen() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: const RankingScreen(),
        ),
      ),
    );
  }

  Future<void> _showLevelDetailsDialog() async {
    await _refreshPlayerEconomy();
    if (!mounted) {
      return;
    }

    final currentLevel = _playerDataManager.level;
    final currentLevelExp = _playerDataManager.currentLevelExp;
    final requiredExp = _playerDataManager.nextLevelRequiredExp;
    final remainingExp = _playerDataManager.remainingExpToNextLevel;
    final nextRewardCoins = (currentLevel + 1) * 500;
    final progress = requiredExp <= 0
        ? 0.0
        : (currentLevelExp / requiredExp).clamp(0.0, 1.0);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          title: 'LEVEL STATUS',
          accentColor: Colors.cyanAccent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.42),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT LEVEL  $currentLevel',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: Colors.white12,
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.cyanAccent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'EXP  $currentLevelExp / $requiredExp',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '次のレベルまで あと $remainingExp EXP',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '次のレベルアップ報酬： $nextRewardCoins コイン',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildCyberDialogButton(
                label: '閉じる',
                accentColor: Colors.cyanAccent,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
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
          (color: _rotatingBallColors[0], x: 0.0, y: -triRadius),
          (color: _rotatingBallColors[1], x: -baseSize / 2, y: triRadius / 2),
          (color: _rotatingBallColors[2], x: baseSize / 2, y: triRadius / 2),
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
                        child: _buildGridButton('エンドレス', Colors.greenAccent,
                            () => _startGame(context, false),
                            alignment: Alignment.topLeft)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildGridButton(
                            'フレンド\n対戦',
                            Colors.redAccent,
                            _isBusy
                                ? null
                                : () => _showFriendBattleDialog(context),
                            alignment: Alignment.topRight)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _buildGridButton(
                            'CPU\n対戦',
                            Colors.yellowAccent,
                            _isBusy
                                ? null
                                : () => _showCpuDifficultyDialog(context),
                            alignment: Alignment.bottomLeft)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildArenaGridButton(Colors.lightBlueAccent,
                            _isBusy ? null : () => _startArenaMatch(context),
                            alignment: Alignment.bottomRight)),
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
                const glowAlpha = 0.4;
                const glowBlur = 28.0;

                return InkWell(
                  onTap: _isBusy || _isLoadingProfile
                      ? null
                      : () {
                          _playUiTap();
                          _startRandomMatch(context);
                        },
                  borderRadius: BorderRadius.circular(84),
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0F0F13),
                      border: Border.all(
                        color: const Color(0xFF0F0F13),
                        width: 5,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.purpleAccent.withValues(alpha: 0.18),
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
                            spreadRadius: 3,
                          ),
                          BoxShadow(
                            color: Colors.pinkAccent.withValues(alpha: 0.18),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ランク戦',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: 2,
                                shadows: [
                                  const Shadow(
                                    color: Colors.purpleAccent,
                                    blurRadius: 11,
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
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.amberAccent
                                      .withValues(alpha: 0.66),
                                ),
                              ),
                              child: Text(
                                _isLoadingProfile ? 'レート ...' : 'レート $_rating',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ModeButtonBorderOverlayPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridButton(String title, Color accentColor, VoidCallback? onTap,
      {Alignment alignment = Alignment.center}) {
    final textAlign = alignment.x < 0
        ? TextAlign.left
        : alignment.x > 0
            ? TextAlign.right
            : TextAlign.center;

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              _playUiTap();
              onTap();
            },
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
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              title,
              textAlign: textAlign,
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

  Widget _buildArenaGridButton(Color accentColor, VoidCallback? onTap,
      {Alignment alignment = Alignment.center}) {
    final isActive = _arenaManager.isArenaActive;
    final hasFinishedRun = !isActive &&
        (_arenaManager.currentWins > 0 || _arenaManager.currentLosses > 0);
    final losses = _arenaManager.currentLosses.clamp(0, 3).toInt();
    final lossMarks =
        List.generate(3, (index) => index < losses ? '×' : '·').join(' ');
    final crossAxisAlignment = alignment.x > 0
        ? CrossAxisAlignment.end
        : alignment.x < 0
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center;
    final currentReward =
        _arenaManager.previewRewardForWins(_arenaManager.currentWins);
    final maxReward = _arenaManager.previewRewardForWins(ArenaManager.maxWins);
    final infoText = isActive
        ? '現在報酬 ${currentReward.coins}コイン'
        : hasFinishedRun
            ? '再入場 ${ArenaManager.entryCost}コイン'
            : '入場 ${ArenaManager.entryCost}コイン';
    final rewardText = isActive || hasFinishedRun
        ? '最大報酬 ${maxReward.coins}コイン'
        : '12勝で ${maxReward.coins}コイン';
    final badgeLabel = isActive
        ? '${_arenaManager.currentWins}勝  $lossMarks'
        : hasFinishedRun
            ? '${_arenaManager.currentWins}勝  $lossMarks'
            : '${ArenaManager.entryCost}コイン';

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              _playUiTap();
              onTap();
            },
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
        child: Stack(
          children: [
            Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: crossAxisAlignment,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.black.withValues(alpha: 0.72)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isActive
                              ? Colors.amberAccent
                              : Colors.white.withValues(alpha: 0.32),
                          width: 1.2,
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: Colors.amberAccent
                                      .withValues(alpha: 0.18),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                      child: isActive
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_arenaManager.currentWins}勝',
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  lossMarks,
                                  style: TextStyle(
                                    color: losses == 0
                                        ? Colors.white38
                                        : Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              badgeLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: hasFinishedRun
                                    ? Colors.amberAccent
                                    : Colors.white70,
                                fontSize: hasFinishedRun ? 12 : 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                    ),
                    const SizedBox(height: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: alignment.x > 0
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Text(
                          infoText,
                          textAlign: alignment.x > 0
                              ? TextAlign.right
                              : TextAlign.left,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: alignment.x > 0
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Text(
                          rewardText,
                          textAlign: alignment.x > 0
                              ? TextAlign.right
                              : TextAlign.left,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '闘技場',
                      textAlign:
                          alignment.x > 0 ? TextAlign.right : TextAlign.left,
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: 1.6,
                        shadows: [
                          Shadow(color: accentColor, blurRadius: 8),
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _arenaRewardSummaryText(ArenaReward reward) {
    final parts = <String>['${reward.coins}コイン'];
    if (reward.title != null) {
      parts.add(reward.title!);
    }
    return parts.join('  ');
  }

  bool get _hasArenaFinishedRun =>
      !_arenaManager.isArenaActive &&
      (_arenaManager.currentWins >= ArenaManager.maxWins ||
          _arenaManager.currentLosses >= ArenaManager.maxLosses);

  Future<bool> _showArenaReentryDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: Colors.lightBlueAccent,
          title: 'ARENA再入場',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_arenaManager.currentWins}勝 ${_arenaManager.currentLosses}敗 の戦績です。\n'
                '${ArenaManager.entryCost}コインを払って再入場しますか？',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'キャンセル',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '再入場',
                      accentColor: Colors.lightBlueAccent,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return result == true;
  }

  Future<void> _showArenaEntryRewardsDialog(BuildContext context) {
    final milestones = List<int>.generate(ArenaManager.maxWins + 1, (i) => i);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: Colors.lightBlueAccent,
          title: 'ARENA報酬',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '敗北3回で終了 / 12勝で最大報酬',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final wins in milestones) ...[
                        _buildArenaRewardMilestone(wins),
                        if (wins != milestones.last) const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildCyberDialogButton(
                label: 'OK',
                accentColor: Colors.lightBlueAccent,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArenaRewardMilestone(int wins) {
    final reward = _arenaManager.previewRewardForWins(wins);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.lightBlueAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.lightBlueAccent.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
            ),
            child: Text(
              '$wins勝',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _arenaRewardSummaryText(reward),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _missionDisplayTitle(Map<String, dynamic> mission) {
    final id = mission['id']?.toString() ?? '';
    return MissionCatalog.localizedTitleForId(id) ??
        mission['title']?.toString() ??
        'ミッション';
  }

  Widget _buildBottomBannerTop() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomTextButton(
            Icons.storefront,
            'ショップ',
            () => _openDailyShop(context),
          ),
          _buildBottomTextButton(
            Icons.collections_bookmark,
            'コレクション',
            _openCollectionScreen,
          ),
          _buildBottomTextButton(
            Icons.help_outline,
            '遊び方',
            () => unawaited(
              _showAlert(context, '遊び方', '遊び方は準備中です。'),
            ),
          ),
          _buildBottomTextButton(
            Icons.block,
            '広告消',
            () => unawaited(
              _showAlert(context, '広告消', '広告削除機能は準備中です。'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTextButton(
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        _playUiTap();
        onTap();
      },
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
    if (isCpuMode) {
      unawaited(_missionManager.recordEvent('play_match'));
    } else {
      unawaited(_missionManager.recordEvent('play_endless'));
    }
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
          title: 'CPU対戦',
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
      onTap: () {
        _playUiTap();
        onTap();
      },
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

  Future<void> _showFriendBattleDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: Colors.redAccent,
          title: 'フレンド対戦',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '作成',
                      accentColor: Colors.redAccent,
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        unawaited(_createRoom(context));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '参加',
                      accentColor: Colors.lightBlueAccent,
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        unawaited(_joinRoom(context));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildCyberDialogButton(
                label: 'キャンセル',
                accentColor: Colors.white54,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDailyShop(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShopScreen()),
    );
    await _refreshPlayerEconomy();
  }

  Future<void> _showDailyMissionsDialog(BuildContext context) async {
    await _refreshPlayerEconomy();
    if (!context.mounted) return;

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> refreshDialogState() async {
              await _refreshPlayerEconomy();
              setDialogState(() {});
            }

            final dialogMissions = _playerDataManager.currentMissions;
            final isAllComplete = _missionManager.allMissionsComplete;
            final isAllClearBonusClaimed =
                _missionManager.isAllClearBonusClaimed;
            final canClaimAllClearBonus =
                isAllComplete && !isAllClearBonusClaimed;
            final rewardAdClaimAmount = _missionManager.allClearClaimAmount;

            return _buildCyberDialog(
              accentColor: Colors.amberAccent,
              title: 'デイリーミッション',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_completedMissionCount / ${dialogMissions.length} 達成',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.amberAccent, blurRadius: 8)
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < dialogMissions.length; i++) ...[
                    _buildSimplifiedMissionTile(
                      index: i,
                      mission: dialogMissions[i],
                      onClaimed: (amount) async {
                        await refreshDialogState();
                        if (context.mounted && amount > 0) {
                          await _showAlert(
                            context,
                            'ミッション報酬',
                            '+$amount コインを受け取りました。',
                          );
                        }
                      },
                    ),
                    if (i != dialogMissions.length - 1)
                      const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: !canClaimAllClearBonus
                        ? null
                        : () async {
                            try {
                              final rewarded = await RewardedAdManager.instance
                                  .showDoubleRewardAd();
                              if (!rewarded) {
                                if (context.mounted) {
                                  await _showAlert(
                                    context,
                                    '広告エラー',
                                    '動画の視聴が完了しませんでした。',
                                  );
                                }
                                return;
                              }

                              final amount =
                                  await _missionManager.claimAllClearBonus();
                              await refreshDialogState();

                              if (context.mounted) {
                                await _showAlert(
                                  context,
                                  'リワード報酬',
                                  '動画リワードで +$amount コインを受け取りました。',
                                );
                              }
                            } catch (error) {
                              if (context.mounted) {
                                await _showAlert(context, 'ERROR', '$error');
                              }
                            }
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: canClaimAllClearBonus
                            ? Colors.amberAccent.withValues(alpha: 0.2)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: canClaimAllClearBonus
                              ? Colors.amberAccent
                              : Colors.white24,
                          width: 2,
                        ),
                        boxShadow: canClaimAllClearBonus
                            ? [
                                const BoxShadow(
                                  color: Colors.amberAccent,
                                  blurRadius: 8,
                                  spreadRadius: 0,
                                )
                              ]
                            : [],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            canClaimAllClearBonus
                                ? Icons.card_giftcard
                                : Icons.lock_outline,
                            color: canClaimAllClearBonus
                                ? Colors.amberAccent
                                : Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isAllClearBonusClaimed
                                      ? 'リワード受取済み'
                                      : 'リワード x2 ボーナス',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: canClaimAllClearBonus
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  canClaimAllClearBonus
                                      ? '動画広告で +$rewardAdClaimAmount'
                                      : isAllComplete
                                          ? '受取済み'
                                          : 'すべて達成で解放',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildCyberDialogButton(
                    label: '閉じる',
                    accentColor: Colors.white54,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSimplifiedMissionTile({
    required int index,
    required Map<String, dynamic> mission,
    required Future<void> Function(int amount) onClaimed,
  }) {
    final progress = (mission['progress'] as num?)?.toInt() ?? 0;
    final target = (mission['target'] as num?)?.toInt() ?? 0;
    final reward = (mission['rewardCoins'] as num?)?.toInt() ?? 0;
    final claimed = mission['claimed'] as bool? ?? false;
    final isDone = progress >= target;
    final canClaim = isDone && !claimed;

    return InkWell(
      onTap: !canClaim
          ? null
          : () async {
              final amount = await _missionManager.claimMissionReward(index);
              await onClaimed(amount);
            },
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: canClaim
                  ? Colors.greenAccent.withValues(alpha: 0.14)
                  : isDone
                      ? Colors.amberAccent.withValues(alpha: 0.15)
                      : Colors.amberAccent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: canClaim
                    ? Colors.greenAccent
                    : isDone
                        ? Colors.amberAccent
                        : Colors.amberAccent.withValues(alpha: 0.3),
                width: canClaim ? 2 : 1,
              ),
              boxShadow: canClaim
                  ? [
                      BoxShadow(
                        color: Colors.greenAccent.withValues(alpha: 0.28),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _missionDisplayTitle(mission),
                        style: TextStyle(
                          color: canClaim
                              ? Colors.greenAccent
                              : Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: canClaim
                            ? Colors.greenAccent.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: canClaim
                              ? Colors.greenAccent
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        claimed
                            ? '受取済み'
                            : canClaim
                                ? 'CLAIM +$reward'
                                : '+$reward',
                        style: TextStyle(
                          color: claimed
                              ? Colors.grey
                              : canClaim
                                  ? Colors.greenAccent
                                  : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value:
                            target == 0 ? 0 : (progress / target).clamp(0, 1),
                        color: isDone
                            ? Colors.amberAccent
                            : Colors.amberAccent.withValues(alpha: 0.5),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$progress / $target',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
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

  Future<void> _startArenaMatch(BuildContext context) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    var dialogOpen = false;
    try {
      await _arenaManager.load();
      if (!_arenaManager.isArenaActive) {
        if (_hasArenaFinishedRun) {
          if (!context.mounted) {
            return;
          }
          final shouldReenter = await _showArenaReentryDialog(context);
          if (!shouldReenter) {
            return;
          }
        }
        try {
          await _arenaManager.enterArena();
          await _missionManager.recordEvent('enter_arena');
        } catch (error) {
          if (!context.mounted) {
            return;
          }
          await _showAlert(context, 'コインが足りません', '$error');
          return;
        }
        await _refreshPlayerEconomy();
        if (!context.mounted) {
          return;
        }
        await _showArenaEntryRewardsDialog(context);
        return;
      }
      if (!context.mounted) {
        return;
      }

      final currentWins = _arenaManager.currentWins;
      final currentReward = _arenaRewardSummaryText(
        _arenaManager.previewRewardForWins(currentWins),
      );
      dialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return _buildCyberDialog(
              accentColor: Colors.lightBlueAccent,
              title: '闘技場',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_arenaManager.currentWins}勝 ${_arenaManager.currentLosses}敗\n報酬 $currentReward\n対戦相手を検索中...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
                        color: Colors.lightBlueAccent,
                        backgroundColor:
                            Colors.lightBlueAccent.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildCyberDialogButton(
                    label: 'キャンセル',
                    accentColor: Colors.lightBlueAccent,
                    onPressed: () {
                      unawaited(_multiplayerManager.cancelArenaMatchmaking());
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
      final roomId = await _multiplayerManager.startArenaMatch(currentWins);
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
            isArenaMode: true,
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
      await _showAlert(context, '闘技場マッチ失敗', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
      unawaited(_multiplayerManager.cancelArenaMatchmaking());
    }
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
    await _playerDataManager.setPlayerName(savedName);

    try {
      final rating = await _multiplayerManager.initializeUser(name: savedName);
      unawaited(_rankingManager.updateMyRating(rating: rating));
      unawaited(_playerDataManager.setCurrentRating(rating));
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
      unawaited(_playerDataManager.setCurrentRating(_rating));
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

  Future<void> _startRandomMatch(
    BuildContext context, {
    bool isArenaMode = false,
  }) async {
    if (_isBusy) {
      return;
    }
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
              title: 'ランク戦',
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
                    label: 'キャンセル',
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
      await _missionManager.recordEvent('start_ranked_match');
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
            isArenaMode: isArenaMode,
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
      if (mounted) {
        setState(() {
          _isBusy = false;
          _rating = _multiplayerManager.currentRating;
        });
      }
      unawaited(_multiplayerManager.cancelMatchmaking());
    }
  }

  Future<void> _maybeResumeSavedOnlineSession() async {
    final resolution = await _multiplayerManager.inspectSavedSession();
    if (!mounted || resolution == null) {
      return;
    }

    final session = resolution.session;
    if (!resolution.isResolved) {
      unawaited(_stopHomeBgm());
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameScreen.online(
            roomId: session.roomId,
            isHost: session.isHost,
            isRankedMode: session.isRankedMode,
            isArenaMode: session.isArenaMode,
          ),
        ),
      );
      return;
    }

    if (resolution.newRating != null) {
      _multiplayerManager.currentRating = resolution.newRating!;
      unawaited(_playerDataManager.setCurrentRating(resolution.newRating!));
      unawaited(
        _rankingManager.updateMyRating(rating: resolution.newRating!),
      );
    }
    await _applyResolvedOnlineSessionLocally(resolution);
    await _multiplayerManager.clearSavedSession();
    await _refreshPlayerEconomy();
    if (!mounted) {
      return;
    }
    setState(() {
      _rating = resolution.newRating ?? _multiplayerManager.currentRating;
    });
  }

  Future<void> _applyResolvedOnlineSessionLocally(
    SavedSessionResolution resolution,
  ) async {
    final isWin = resolution.isWin;
    if (isWin == null) {
      return;
    }

    final mode = resolution.session.isArenaMode ? 'ARENA' : 'RANKED';
    await _playerDataManager.recordMatchResult(
      isWin: isWin,
      mode: mode,
      opponentName: resolution.opponentName ?? 'UNKNOWN',
      maxCombo: 0,
      wazaCounts: const {
        'straight': 0,
        'pyramid': 0,
        'hexagon': 0,
      },
      ratingAfter: resolution.newRating,
    );
    if (resolution.session.isArenaMode) {
      await _arenaManager.recordArenaMatch(isWin);
    }
  }

  Future<String?> _showRoomIdDialog(BuildContext context) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: Colors.amberAccent,
          title: 'ルーム参加',
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
                      label: 'キャンセル',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '参加',
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

  Future<void> _showSettingsDialog() async {
    double musicVolume = AppSettings.instance.musicVolume.value;
    double sfxVolume = AppSettings.instance.sfxVolume.value;
    var layout = AppSettings.instance.controlLayout.value;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> updateMusic(double value) async {
              setDialogState(() {
                musicVolume = value;
              });
              await AppSettings.instance.setMusicVolume(value);
              await SeamlessBgm.instance.setMasterVolume(value);
            }

            Future<void> updateSfx(double value) async {
              setDialogState(() {
                sfxVolume = value;
              });
              await AppSettings.instance.setSfxVolume(value);
            }

            Future<void> updateLayout(ControlLayoutPreset preset) async {
              setDialogState(() {
                layout = preset;
              });
              await AppSettings.instance.setControlLayout(preset);
            }

            return _buildCyberDialog(
              accentColor: Colors.purpleAccent,
              title: '設定',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSettingsSectionTitle('オーディオ'),
                  _buildSettingsSlider(
                    label: '音楽',
                    value: musicVolume,
                    onChanged: updateMusic,
                  ),
                  const SizedBox(height: 10),
                  _buildSettingsSlider(
                    label: '効果音',
                    value: sfxVolume,
                    onChanged: updateSfx,
                  ),
                  const SizedBox(height: 18),
                  _buildSettingsSectionTitle('操作パネル'),
                  const SizedBox(height: 8),
                  for (final preset in ControlLayoutPreset.values) ...[
                    _buildControlLayoutOption(
                      preset: preset,
                      selected: preset == layout,
                      onTap: () => unawaited(updateLayout(preset)),
                    ),
                    if (preset != ControlLayoutPreset.values.last)
                      const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 16),
                  _buildCyberDialogButton(
                    label: '閉じる',
                    accentColor: Colors.white54,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.cyanAccent,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSettingsSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ${(value * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Slider(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.cyanAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildControlLayoutOption({
    required ControlLayoutPreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final icons = switch (preset) {
      ControlLayoutPreset.rotateMoveMoveRotate => const [
          Icons.rotate_left,
          Icons.arrow_left,
          Icons.arrow_right,
          Icons.rotate_right,
        ],
      ControlLayoutPreset.moveMoveRotateRotate => const [
          Icons.arrow_left,
          Icons.arrow_right,
          Icons.rotate_left,
          Icons.rotate_right,
        ],
      ControlLayoutPreset.rotateRotateMoveMove => const [
          Icons.rotate_left,
          Icons.rotate_right,
          Icons.arrow_left,
          Icons.arrow_right,
        ],
      ControlLayoutPreset.moveRotateRotateMove => const [
          Icons.arrow_left,
          Icons.rotate_left,
          Icons.rotate_right,
          Icons.arrow_right,
        ],
    };

    return InkWell(
      onTap: () {
        _playUiTap();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? Colors.cyanAccent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.cyanAccent.withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final icon in icons)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0x1100FFFF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.cyanAccent.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: Colors.cyanAccent,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (selected)
              const Icon(
                Icons.check_circle,
                color: Colors.cyanAccent,
              ),
          ],
        ),
      ),
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
      onPressed: () {
        _playUiTap();
        onPressed();
      },
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

  Future<void> _showDebugMenu() async {
    if (!_debugControlsEnabled) {
      return;
    }

    await _refreshPlayerEconomy();
    if (!mounted) {
      return;
    }

    final rateController = TextEditingController(text: '$_rating');
    final arenaWinsController =
        TextEditingController(text: '${_arenaManager.currentWins}');
    final arenaLossesController =
        TextEditingController(text: '${_arenaManager.currentLosses}');
    final coinsController = TextEditingController(text: '$_coins');
    final expDeltaController = TextEditingController(text: '1000');
    var arenaActive = _arenaManager.isArenaActive;

    int intValue(TextEditingController controller, int fallback) {
      return int.tryParse(controller.text.trim()) ?? fallback;
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> applyDebugValues() async {
                final nextRating = intValue(rateController, _rating);
                final nextCoins = intValue(coinsController, _coins);
                final nextWins =
                    intValue(arenaWinsController, _arenaManager.currentWins);
                final nextLosses = intValue(
                    arenaLossesController, _arenaManager.currentLosses);

                _multiplayerManager.currentRating = nextRating;
                await _playerDataManager.setCurrentRating(nextRating);
                await _playerDataManager.setCoinsForDebug(nextCoins);
                await _playerDataManager.updateMaxArenaWins(nextWins);
                await _arenaManager.setArenaStateForDebug(
                  isActive: arenaActive,
                  wins: nextWins,
                  losses: nextLosses,
                );
                unawaited(_rankingManager.updateMyRating(rating: nextRating));

                if (!mounted) {
                  return;
                }
                setState(() {
                  _rating = nextRating;
                });
                await _refreshPlayerEconomy();
              }

              Future<void> adjustExp(int sign) async {
                final delta = intValue(expDeltaController, 0).abs() * sign;
                await _playerDataManager.adjustExpForDebug(delta);
                await _refreshPlayerEconomy();
              }

              return SafeArea(
                child: Container(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F13).withValues(alpha: 0.97),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(
                      color: Colors.purpleAccent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'デバッグ操作',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.purpleAccent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                color: Colors.purpleAccent,
                                blurRadius: 4,
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildDebugNumberField('レート', rateController),
                        const SizedBox(height: 10),
                        _buildDebugNumberField('コイン', coinsController),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDebugNumberField(
                                '闘技場 勝利数',
                                arenaWinsController,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDebugNumberField(
                                '闘技場 敗北数',
                                arenaLossesController,
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: arenaActive,
                          onChanged: (value) {
                            setSheetState(() {
                              arenaActive = value;
                            });
                          },
                          activeThumbColor: Colors.lightBlueAccent,
                          title: const Text(
                            '闘技場 エントリー中',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildCyberDialogButton(
                          label: '値を反映',
                          accentColor: Colors.cyanAccent,
                          onPressed: () => unawaited(applyDebugValues()),
                        ),
                        const SizedBox(height: 16),
                        _buildDebugNumberField('EXP 変化量', expDeltaController),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCyberDialogButton(
                                label: 'EXP +',
                                accentColor: Colors.greenAccent,
                                onPressed: () => unawaited(adjustExp(1)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildCyberDialogButton(
                                label: 'EXP -',
                                accentColor: Colors.redAccent,
                                onPressed: () => unawaited(adjustExp(-1)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildCyberDialogButton(
                          label: 'ミッション一覧',
                          accentColor: Colors.amberAccent,
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(_showDailyMissionsDialog(context));
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildCyberDialogButton(
                          label: 'スタンプ確認',
                          accentColor: Colors.purpleAccent,
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _showStampDebugPreview();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      rateController.dispose();
      arenaWinsController.dispose();
      arenaLossesController.dispose();
      coinsController.dispose();
      expDeltaController.dispose();
    }
  }

  Widget _buildDebugNumberField(
    String label,
    TextEditingController controller,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.white60,
          fontWeight: FontWeight.bold,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Colors.cyanAccent.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.cyanAccent),
        ),
      ),
    );
  }

  void _showStampDebugPreview() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F13).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border:
                Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              const Text(
                'スタンプ確認',
                style: TextStyle(
                  color: Colors.purpleAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  shadows: [Shadow(color: Colors.purpleAccent, blurRadius: 4)],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: GameItemCatalog.commonStamps.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final item = GameItemCatalog.commonStamps[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  const Text('Lv.1',
                                      style: TextStyle(
                                          color: Colors.white38, fontSize: 10)),
                                  const SizedBox(height: 4),
                                  StampWidget(item: item, level: 1),
                                ],
                              ),
                              Column(
                                children: [
                                  const Text('Lv.2',
                                      style: TextStyle(
                                          color: Colors.white38, fontSize: 10)),
                                  const SizedBox(height: 4),
                                  StampWidget(item: item, level: 2),
                                ],
                              ),
                              Column(
                                children: [
                                  const Text('Lv.3',
                                      style: TextStyle(
                                          color: Colors.white38, fontSize: 10)),
                                  const SizedBox(height: 4),
                                  StampWidget(item: item, level: 3),
                                ],
                              ),
                              Column(
                                children: [
                                  const Text('Lv.4',
                                      style: TextStyle(
                                          color: Colors.white38, fontSize: 10)),
                                  const SizedBox(height: 4),
                                  StampWidget(item: item, level: 4),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeButtonBorderOverlayPainter extends CustomPainter {
  static const double _strokeWidth = 2;
  static const double _arcRadius = 76.3;
  static const double _arcGap = 0.065;

  final List<Color> _colors = [
    Colors.greenAccent,
    Colors.redAccent,
    Colors.yellowAccent,
    Colors.lightBlueAccent,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final arcRect = Rect.fromCircle(center: center, radius: _arcRadius);
    final arcs = [
      (start: math.pi + _arcGap, color: _colors[0]),
      (start: -math.pi / 2 + _arcGap, color: _colors[1]),
      (start: math.pi / 2 + _arcGap, color: _colors[2]),
      (start: _arcGap, color: _colors[3]),
    ];

    for (final arc in arcs) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _strokeWidth
        ..color = arc.color.withValues(alpha: 0.58);
      canvas.drawArc(
        arcRect,
        arc.start,
        math.pi / 2 - (_arcGap * 2),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ModeButtonBorderOverlayPainter oldDelegate) {
    return true;
  }
}
