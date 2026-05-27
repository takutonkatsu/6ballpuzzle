import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../firebase_database_provider.dart';
import '../firebase_options_prod.dart' as firebase_prod;
import '../game/components/ball_component.dart';
import '../game/game_models.dart';
import '../game/puzzle_game.dart';
import '../ui/components/hexagon_currency_icons.dart';
import '../ui/components/hexagon_grid_background.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ヘキサゴン 管理',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.amberAccent,
          surface: Color(0xFF141421),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F13),
          foregroundColor: Color(0xFFEAF6FF),
          elevation: 0,
        ),
      ),
      home: const AdminBootstrapScreen(),
    );
  }
}

class AdminBootstrapScreen extends StatefulWidget {
  const AdminBootstrapScreen({super.key});

  @override
  State<AdminBootstrapScreen> createState() => _AdminBootstrapScreenState();
}

class _AdminBootstrapScreenState extends State<AdminBootstrapScreen> {
  late final Future<AdminDatabaseRepository> _bootstrap = _initialize();

  Future<AdminDatabaseRepository> _initialize() async {
    const appName = 'hexagon-prod-admin';
    final options = firebase_prod.DefaultFirebaseOptions.currentPlatform;
    final app = await _initializeFirebaseApp(appName, options);
    AppFirebaseDatabase.useApp(app);
    await FirebaseAuth.instanceFor(app: app).signInAnonymously();
    final database = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: options.databaseURL,
    );
    return AdminDatabaseRepository(database);
  }

  Future<FirebaseApp> _initializeFirebaseApp(
    String appName,
    FirebaseOptions options,
  ) async {
    try {
      return await Firebase.initializeApp(name: appName, options: options);
    } on FirebaseException catch (error) {
      if (error.code == 'duplicate-app') {
        return Firebase.app(appName);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminDatabaseRepository>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return AdminHomeScreen(repository: snapshot.requireData);
        }
        if (snapshot.hasError) {
          return _AdminErrorScreen(error: snapshot.error.toString());
        }
        return const Scaffold(
          body: _AdminBackground(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('PRODデータベースに読み取り専用で接続中'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key, required this.repository});

  final AdminDatabaseRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _AdminBackground(
          child: Column(
            children: [
              const IgnorePointer(child: _AdminTopBanner1()),
              const SizedBox(height: 12),
              const IgnorePointer(child: _AdminTopBanner2()),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const ballHeight = 152.0;
                    const spacing = 8.0;
                    final modeHeight =
                        (constraints.maxHeight - ballHeight - spacing)
                            .clamp(120.0, 280.0);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _AdminRotatingBall(),
                        const SizedBox(height: spacing),
                        _AdminModeSelection(
                          height: modeHeight,
                          onRealtime: () => _push(
                            context,
                            AdminRealtimeScreen(repository: repository),
                          ),
                          onStats: () => _push(
                            context,
                            AdminStatsScreen(repository: repository),
                          ),
                          onPlayers: () => _push(
                            context,
                            AdminPlayersScreen(repository: repository),
                          ),
                          onSpectate: () => _push(
                            context,
                            AdminRoomsScreen(repository: repository),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const _AdminBottomBannerTop(),
              const _AdminBottomBannerPlaceholder(),
            ],
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: screen,
        ),
      ),
    );
  }
}

class _AdminTopBanner1 extends StatelessWidget {
  const _AdminTopBanner1();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final edgePadding = compact ? 8.0 : 16.0;
        final gap = compact ? 6.0 : 12.0;
        final levelProgressWidth = compact ? 34.0 : 52.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: edgePadding, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: 6,
                ),
                decoration: _prodPillDecoration(BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Lv.99',
                        style: TextStyle(
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
                        widthFactor: 0.74,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.cyanAccent, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: _AdminProfileButton(compact: compact),
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
                  decoration: _prodPillDecoration(BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      HexagonCoinIcon(size: compact ? 14 : 16),
                      SizedBox(width: compact ? 3 : 4),
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '999999',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: TextStyle(
                              color: Color(0xFFEAF6FF),
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
}

class _AdminProfileButton extends StatelessWidget {
  const _AdminProfileButton({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 34 : 36,
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
      decoration: _prodPillDecoration(BorderRadius.circular(18)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: compact ? 18 : 22,
            height: compact ? 18 : 22,
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.cyanAccent.withValues(alpha: 0.65)),
            ),
            child: Icon(Icons.person,
                color: Colors.white, size: compact ? 13 : 15),
          ),
          SizedBox(width: compact ? 5 : 8),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '管理プレイヤー',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTopBanner2 extends StatelessWidget {
  const _AdminTopBanner2();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: _prodPillDecoration(BorderRadius.circular(12)),
            child: const Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '管理シーズン',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HexagonTrophyIcon(size: 16),
                        SizedBox(width: 5),
                        Text(
                          '9999',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(color: Color(0xAAFFD54F), blurRadius: 8),
                            ],
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          '1位',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      '本日 99勝  1位',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.cyanAccent,
                  size: 22,
                ),
              ],
            ),
          ),
          const Row(
            children: [
              _AdminRoundIcon(icon: Icons.notifications),
              SizedBox(width: 8),
              _AdminRoundIcon(icon: Icons.settings),
              SizedBox(width: 8),
              _AdminRoundIcon(icon: Icons.bar_chart),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminRoundIcon extends StatelessWidget {
  const _AdminRoundIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.cyanAccent.withValues(alpha: 0.1),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.2), blurRadius: 4),
        ],
      ),
      child: Icon(icon, color: Colors.cyanAccent, size: 20),
    );
  }
}

class _AdminRotatingBall extends StatefulWidget {
  const _AdminRotatingBall();

  @override
  State<_AdminRotatingBall> createState() => _AdminRotatingBallState();
}

class _AdminRotatingBallState extends State<_AdminRotatingBall>
    with SingleTickerProviderStateMixin {
  late final List<BallColor> _colors = _randomRotatingBallColors();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final rotation = _controller.value * math.pi * 2;
        const baseSize = 76.0;
        const centerX = 100.0;
        const centerY = 76.0;
        final triRadius = baseSize / math.sqrt(3);
        final balls = [
          (color: _colors[0], x: 0.0, y: -triRadius),
          (color: _colors[1], x: -baseSize / 2, y: triRadius / 2),
          (color: _colors[2], x: baseSize / 2, y: triRadius / 2),
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

  List<BallColor> _randomRotatingBallColors() {
    final random = math.Random();
    return List.generate(
      3,
      (_) => BallColor.values[random.nextInt(BallColor.values.length)],
    );
  }
}

class _AdminModeSelection extends StatelessWidget {
  const _AdminModeSelection({
    required this.height,
    required this.onRealtime,
    required this.onStats,
    required this.onPlayers,
    required this.onSpectate,
  });

  final double height;
  final VoidCallback onRealtime;
  final VoidCallback onStats;
  final VoidCallback onPlayers;
  final VoidCallback onSpectate;

  @override
  Widget build(BuildContext context) {
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
                      child: _CommandGridButton(
                        title: 'リアルタイム',
                        accentColor: Colors.greenAccent,
                        alignment: Alignment.topLeft,
                        onTap: onRealtime,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CommandGridButton(
                        title: '全体統計',
                        accentColor: Colors.redAccent,
                        alignment: Alignment.topRight,
                        onTap: onStats,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _CommandGridButton(
                        title: 'プレイヤー',
                        accentColor: Colors.yellowAccent,
                        alignment: Alignment.bottomLeft,
                        onTap: onPlayers,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: _EmptyGridButton()),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.center,
            child: InkWell(
              onTap: onSpectate,
              borderRadius: BorderRadius.circular(84),
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0F0F13),
                  border: Border.all(color: const Color(0xFF0F0F13), width: 5),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.purpleAccent.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.purpleAccent, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purpleAccent.withValues(alpha: 0.4),
                        blurRadius: 28,
                        spreadRadius: 3,
                      ),
                      BoxShadow(
                        color: Colors.pinkAccent.withValues(alpha: 0.18),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '観戦',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 3,
                        shadows: [
                          Shadow(color: Colors.purpleAccent, blurRadius: 11),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ModeButtonBorderOverlayPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandGridButton extends StatelessWidget {
  const _CommandGridButton({
    required this.title,
    required this.accentColor,
    required this.alignment,
    required this.onTap,
  });

  final String title;
  final Color accentColor;
  final Alignment alignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textAlign = alignment.x < 0 ? TextAlign.left : TextAlign.right;
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
                color: accentColor.withValues(alpha: 0.08), blurRadius: 22),
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
                      blurRadius: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminBottomBannerTop extends StatelessWidget {
  const _AdminBottomBannerTop();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(
        children: [
          Expanded(child: _BottomCommand(label: 'ショップ', icon: Icons.store)),
          SizedBox(width: 8),
          Expanded(
              child: _BottomCommand(label: 'コレクション', icon: Icons.collections)),
        ],
      ),
    );
  }
}

class _BottomCommand extends StatelessWidget {
  const _BottomCommand({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.12), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminBottomBannerPlaceholder extends StatelessWidget {
  const _AdminBottomBannerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: const Text(
        'PROD READ ONLY / 観戦専用',
        style: TextStyle(
          color: Colors.cyanAccent,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _EmptyGridButton extends StatelessWidget {
  const _EmptyGridButton();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF676D76).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF676D76).withValues(alpha: 0.42),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

class AdminRealtimeScreen extends StatelessWidget {
  const AdminRealtimeScreen({super.key, required this.repository});

  final AdminDatabaseRepository repository;

  @override
  Widget build(BuildContext context) {
    return _AdminScaffold(
      title: 'リアルタイム',
      child: StreamBuilder<AdminRealtimeSnapshot>(
        stream: repository.watchRealtimeSnapshot(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _InlineError(error: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final realtime = snapshot.requireData;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _CountHeader(
                label: '現在マッチング待機中のプレイヤー一覧',
                count: realtime.waitingPlayers.length,
              ),
              if (realtime.waitingPlayers.isEmpty)
                const _EmptyStateText('該当プレイヤーなし')
              else
                for (final player in realtime.waitingPlayers)
                  _WaitingPlayerTile(
                    player: player,
                    onTap: () => _openRealtimePlayerDetail(
                      context,
                      repository,
                      player.uid,
                    ),
                  ),
              const SizedBox(height: 16),
              _CountHeader(
                label: '現在プレイ中のプレイヤー',
                count: realtime.gameActivities.length,
              ),
              if (realtime.gameActivities.isEmpty)
                const _EmptyStateText('該当プレイヤーなし')
              else
                for (final activity in realtime.gameActivities)
                  _GameActivityTile(
                    activity: activity,
                    onTap: () => _openRealtimePlayerDetail(
                      context,
                      repository,
                      activity.uid,
                    ),
                  ),
              const SizedBox(height: 16),
              _CountHeader(
                label: '現在ログイン中のプレイヤー一覧',
                count: realtime.onlinePlayers.length,
              ),
              if (realtime.onlinePlayers.isEmpty)
                const _EmptyStateText('該当プレイヤーなし')
              else
                for (final player in realtime.onlinePlayers)
                  _PlayerTile(
                    player: player,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminPlayerDetailScreen(player: player),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRealtimePlayerDetail(
    BuildContext context,
    AdminDatabaseRepository repository,
    String uid,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final player = await repository.fetchPlayerSummary(uid);
    if (!context.mounted) {
      return;
    }
    if (player == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('プレイヤーデータを取得できませんでした')),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute(
        builder: (_) => AdminPlayerDetailScreen(player: player),
      ),
    );
  }
}

class AdminStatsScreen extends StatelessWidget {
  const AdminStatsScreen({super.key, required this.repository});

  final AdminDatabaseRepository repository;

  @override
  Widget build(BuildContext context) {
    return _AdminScaffold(
      title: '全体統計',
      child: StreamBuilder<AdminOverallStats>(
        stream: repository.watchOverallStats(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _InlineError(error: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.requireData;
          final modeRows = stats.modePlayCounts.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TitleLine(title: '今日', subtitle: stats.todayKey),
                    const SizedBox(height: 12),
                    _StatRow(
                        label: '新規プレイヤー数', value: '${stats.todayNewPlayers}'),
                    _StatRow(
                        label: 'ログインプレイヤー数',
                        value: '${stats.todayLoginPlayers}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _TitleLine(title: '全体', subtitle: ''),
                    const SizedBox(height: 12),
                    _StatRow(label: '総プレイヤー数', value: '${stats.totalPlayers}'),
                    const Divider(height: 24),
                    const Text(
                      '各モードプレイ回数',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (modeRows.isEmpty)
                      const Text('データなし',
                          style: TextStyle(color: Colors.white70))
                    else
                      for (final entry in modeRows)
                        _StatRow(
                            label: _modeLabel(entry.key),
                            value: '${entry.value}'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AdminPlayersScreen extends StatefulWidget {
  const AdminPlayersScreen({super.key, required this.repository});

  final AdminDatabaseRepository repository;

  @override
  State<AdminPlayersScreen> createState() => _AdminPlayersScreenState();
}

class _AdminPlayersScreenState extends State<AdminPlayersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  AdminPlayerSort _sort = AdminPlayerSort.updatedAtDesc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AdminScaffold(
      title: 'プレイヤー',
      child: Column(
        children: [
          _SearchField(
            controller: _searchController,
            hintText: '名前 / publicId / uid',
            onChanged: (value) => setState(() => _query = value),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: DropdownButtonFormField<AdminPlayerSort>(
              initialValue: _sort,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'ソート',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.black54,
                isDense: true,
              ),
              items: [
                for (final sort in AdminPlayerSort.values)
                  DropdownMenuItem(value: sort, child: Text(sort.label)),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _sort = value);
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AdminRoomSummary>>(
              stream: widget.repository.watchRooms(),
              builder: (context, roomSnapshot) {
                if (roomSnapshot.hasError) {
                  return _InlineError(error: roomSnapshot.error.toString());
                }
                if (!roomSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rooms = roomSnapshot.requireData;
                return StreamBuilder<List<AdminPlayerSummary>>(
                  stream: widget.repository.watchPlayerSummaries(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _InlineError(error: snapshot.error.toString());
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final players = snapshot.requireData
                        .where((player) => player.matches(_query))
                        .toList()
                      ..sort(_sort.compare);
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: players.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _CountHeader(
                              label: 'Players', count: players.length);
                        }
                        final player = players[index - 1];
                        final liveRoom = _liveRoomForPlayer(player.uid, rooms);
                        return _PlayerTile(
                          player: player,
                          liveRoom: liveRoom,
                          onSpectate: liveRoom == null
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AdminRoomWatchScreen(
                                        repository: widget.repository,
                                        roomId: liveRoom.roomId,
                                      ),
                                    ),
                                  ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AdminPlayerDetailScreen(player: player),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  AdminRoomSummary? _liveRoomForPlayer(
    String uid,
    List<AdminRoomSummary> rooms,
  ) {
    if (uid.isEmpty) {
      return null;
    }
    for (final room in rooms) {
      if (!room.isLive || room.status != 'playing') {
        continue;
      }
      if (room.players.values.any((player) => player.uid == uid)) {
        return room;
      }
    }
    return null;
  }
}

enum AdminPlayerSort {
  name,
  updatedAtDesc,
  installOrder,
  publicId,
  uid,
  rating,
  todayRankedWins,
  endless;

  String get label {
    return switch (this) {
      AdminPlayerSort.name => '名前',
      AdminPlayerSort.updatedAtDesc => '最終更新',
      AdminPlayerSort.installOrder => 'インストール順',
      AdminPlayerSort.publicId => 'publicID',
      AdminPlayerSort.uid => 'uID',
      AdminPlayerSort.rating => 'レート',
      AdminPlayerSort.todayRankedWins => 'ランク戦の本日の勝利数',
      AdminPlayerSort.endless => 'エンドレス',
    };
  }

  int compare(AdminPlayerSummary a, AdminPlayerSummary b) {
    return switch (this) {
      AdminPlayerSort.name => a.displayName.compareTo(b.displayName),
      AdminPlayerSort.updatedAtDesc =>
        (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0),
      AdminPlayerSort.installOrder =>
        a.accountCreatedAt.compareTo(b.accountCreatedAt),
      AdminPlayerSort.publicId => a.publicId.compareTo(b.publicId),
      AdminPlayerSort.uid => a.uid.compareTo(b.uid),
      AdminPlayerSort.rating => b.currentRating.compareTo(a.currentRating),
      AdminPlayerSort.todayRankedWins =>
        b.todayRankedWins.compareTo(a.todayRankedWins),
      AdminPlayerSort.endless =>
        b.endlessHighestScore.compareTo(a.endlessHighestScore),
    };
  }
}

class AdminRoomsScreen extends StatefulWidget {
  const AdminRoomsScreen({super.key, required this.repository});

  final AdminDatabaseRepository repository;

  @override
  State<AdminRoomsScreen> createState() => _AdminRoomsScreenState();
}

class _AdminRoomsScreenState extends State<AdminRoomsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _liveOnly = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AdminScaffold(
      title: '観戦',
      child: Column(
        children: [
          _SearchField(
            controller: _searchController,
            hintText: 'room / player / status',
            onChanged: (value) => setState(() => _query = value),
            trailing: IconButton(
              icon: Icon(_liveOnly ? Icons.filter_alt : Icons.filter_alt_off),
              onPressed: () => setState(() => _liveOnly = !_liveOnly),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AdminRoomSummary>>(
              stream: widget.repository.watchRooms(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _InlineError(error: snapshot.error.toString());
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rooms = snapshot.requireData
                    .where((room) => !_liveOnly || room.isLive)
                    .where((room) => room.matches(_query))
                    .toList();
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: rooms.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _CountHeader(
                          label: _liveOnly ? 'Live Battles' : 'Rooms',
                          count: rooms.length);
                    }
                    final room = rooms[index - 1];
                    return _RoomTile(
                      room: room,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AdminRoomWatchScreen(
                            repository: widget.repository,
                            roomId: room.roomId,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AdminRoomWatchScreen extends StatefulWidget {
  const AdminRoomWatchScreen({
    super.key,
    required this.repository,
    required this.roomId,
  });

  final AdminDatabaseRepository repository;
  final String roomId;

  @override
  State<AdminRoomWatchScreen> createState() => _AdminRoomWatchScreenState();
}

class _AdminRoomWatchScreenState extends State<AdminRoomWatchScreen> {
  late final PuzzleGame _hostGame = _newSpectatorGame(Colors.cyanAccent);
  late final PuzzleGame _guestGame = _newSpectatorGame(Colors.pinkAccent);
  final List<StreamSubscription<dynamic>> _gameSubscriptions = [];
  Map<String, int> _hostBoard = const {};
  Map<String, int> _guestBoard = const {};
  String? _hostPieceSignature;
  String? _guestPieceSignature;
  final Set<String> _hostOjamaIds = {};
  final Set<String> _guestOjamaIds = {};

  PuzzleGame _newSpectatorGame(Color wallColor) {
    return PuzzleGame(
      autoStart: false,
      isCpuMode: true,
      isRemotePlayerMode: true,
      wallColor: wallColor,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startGameSubscriptions();
      }
    });
  }

  void _startGameSubscriptions() {
    if (_gameSubscriptions.isNotEmpty) {
      return;
    }
    _gameSubscriptions
      ..add(widget.repository
          .watchRoomPlayerBoard(widget.roomId, 'host')
          .listen((board) => _syncBoard(_hostGame, board, isHost: true)))
      ..add(widget.repository
          .watchRoomPlayerBoard(widget.roomId, 'guest')
          .listen((board) => _syncBoard(_guestGame, board, isHost: false)))
      ..add(widget.repository
          .watchRoomPlayerActivePiece(widget.roomId, 'host')
          .listen((piece) => _syncActivePiece(_hostGame, piece, isHost: true)))
      ..add(widget.repository
          .watchRoomPlayerActivePiece(widget.roomId, 'guest')
          .listen(
              (piece) => _syncActivePiece(_guestGame, piece, isHost: false)))
      ..add(widget.repository
          .watchRoomPlayerOjamaSpawns(widget.roomId, 'host')
          .listen((spawn) => _syncOjama(_hostGame, spawn, isHost: true)))
      ..add(widget.repository
          .watchRoomPlayerOjamaSpawns(widget.roomId, 'guest')
          .listen((spawn) => _syncOjama(_guestGame, spawn, isHost: false)));
  }

  @override
  void dispose() {
    for (final subscription in _gameSubscriptions) {
      subscription.cancel();
    }
    _hostGame.pauseEngine();
    _guestGame.pauseEngine();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AdminScaffold(
      title: '観戦',
      child: StreamBuilder<AdminRoomDetail?>(
        stream: widget.repository.watchRoom(widget.roomId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _InlineError(error: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.requireData;
          if (detail == null) {
            return const Center(child: Text('Room not found'));
          }
          final room = detail.summary;
          _syncPlayer(_hostGame, room.host, isHost: true);
          _syncPlayer(_guestGame, room.guest, isHost: false);
          return Stack(
            children: [
              Column(
                children: [
                  _BattleHeader(room: room),
                  Expanded(
                    child: _SpectatorBattleView(
                      topGame: _hostGame,
                      bottomGame: _guestGame,
                      topPlayer: room.host,
                      bottomPlayer: room.guest,
                    ),
                  ),
                ],
              ),
              if (room.status == 'game_over' || room.results.isNotEmpty)
                _ResultOverlay(room: room),
            ],
          );
        },
      ),
    );
  }

  void _syncPlayer(PuzzleGame game, AdminRoomPlayer? player,
      {required bool isHost}) {
    _syncBoard(game, player?.board ?? const <String, int>{}, isHost: isHost);
    _syncActivePiece(game, player?.activePiece, isHost: isHost);
    for (final spawn in player?.ojamaSpawns ?? const <AdminOjamaSpawn>[]) {
      _syncOjama(game, spawn, isHost: isHost);
    }
    if (player?.status == 'dead' &&
        game.gameStateWrapper.value != GameState.gameover) {
      game.gameOver();
    }
  }

  void _syncBoard(PuzzleGame game, Map<String, int> board,
      {required bool isHost}) {
    if (!game.hasLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncBoard(game, board, isHost: isHost);
        }
      });
      return;
    }
    final previousBoard = isHost ? _hostBoard : _guestBoard;
    if (!_sameBoard(previousBoard, board)) {
      game.applyRemoteBoardStateWithSpectatorEffects(
        Map<String, dynamic>.from(board),
      );
      if (isHost) {
        _hostBoard = Map<String, int>.from(board);
      } else {
        _guestBoard = Map<String, int>.from(board);
      }
    }
  }

  void _syncActivePiece(PuzzleGame game, AdminActivePiece? piece,
      {required bool isHost}) {
    if (!game.hasLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncActivePiece(game, piece, isHost: isHost);
        }
      });
      return;
    }
    final previousSignature =
        isHost ? _hostPieceSignature : _guestPieceSignature;
    final signature = piece == null ? null : _activePieceSignature(piece);
    if (piece != null && signature != previousSignature) {
      _applyActivePiece(game, piece);
      if (isHost) {
        _hostPieceSignature = signature;
      } else {
        _guestPieceSignature = signature;
      }
    }
  }

  String _activePieceSignature(AdminActivePiece piece) {
    return [
      piece.timestamp,
      piece.action,
      piece.x?.toStringAsFixed(2),
      piece.y?.toStringAsFixed(2),
      piece.rotation,
      piece.colors.join(','),
      piece.nextColors.join(','),
      piece.dropSeed,
      piece.movingLeft,
      piece.movingRight,
      piece.contactSlideDirection?.toStringAsFixed(3),
    ].join('|');
  }

  void _syncOjama(PuzzleGame game, AdminOjamaSpawn spawn,
      {required bool isHost}) {
    if (!game.hasLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncOjama(game, spawn, isHost: isHost);
        }
      });
      return;
    }
    final seenOjama = isHost ? _hostOjamaIds : _guestOjamaIds;
    if (!seenOjama.add(spawn.id)) {
      return;
    }
    game.spawnRemoteOjama(
      spawn.items,
      spawn.dropSeed ?? DateTime.now().microsecondsSinceEpoch,
    );
  }

  bool _sameBoard(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  void _applyActivePiece(PuzzleGame game, AdminActivePiece piece) {
    final colors = _parseBallColors(piece.colors);
    final nextColors = _parseBallColors(piece.nextColors);
    final action = piece.action.isEmpty ? 'move' : piece.action;
    final x = piece.x;
    final y = piece.y;
    final rotation = piece.rotation;

    var movingLeft = piece.movingLeft ?? game.isMovingLeft;
    var movingRight = piece.movingRight ?? game.isMovingRight;
    if (piece.movingLeft == null || piece.movingRight == null) {
      switch (action) {
        case 'start_left':
          movingLeft = true;
          break;
        case 'stop_left':
          movingLeft = false;
          break;
        case 'start_right':
          movingRight = true;
          break;
        case 'stop_right':
          movingRight = false;
          break;
        case 'spawn':
        case 'hard_drop':
          movingLeft = false;
          movingRight = false;
          break;
      }
    }
    game.syncRemoteActivePieceInputState(
      movingLeft: movingLeft,
      movingRight: movingRight,
      contactSlideDirection: piece.contactSlideDirection,
    );
    if (piece.dropSeed != null) {
      game.currentDropSeed = piece.dropSeed!;
      game.syncDropRng = math.Random(piece.dropSeed!);
    }
    if (nextColors.isNotEmpty) {
      game.nextPieceColors.value = nextColors;
    }

    if (action != 'spawn' && action != 'hard_drop') {
      _ensureRemoteActivePiece(game, colors);
      game.syncRemoteActivePieceInputState(
        movingLeft: movingLeft,
        movingRight: movingRight,
        contactSlideDirection: piece.contactSlideDirection,
      );
    }

    switch (action) {
      case 'spawn':
        if (colors.length == 3) {
          game.spawnRemotePiece(colors);
        }
        if (x != null && y != null && rotation != null) {
          game.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.1,
          );
        }
        break;
      case 'rotate_left':
      case 'rotate_right':
      case 'start_left':
      case 'stop_left':
      case 'start_right':
      case 'stop_right':
        if (x != null && y != null && rotation != null) {
          game.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.08,
          );
        }
        break;
      case 'hard_drop':
        unawaited(game.applyRemoteHardDrop(
          x: x,
          y: y,
          rotation: rotation,
        ));
        break;
      default:
        if (x != null && y != null && rotation != null) {
          game.syncRemoteActivePieceTransform(
            x: x,
            y: y,
            rotation: rotation,
            duration: 0.08,
          );
        }
    }
  }

  List<BallColor> _parseBallColors(List<int> rawColors) {
    return rawColors
        .where((index) => index >= 0 && index < BallColor.values.length)
        .map((index) => BallColor.values[index])
        .toList();
  }

  void _ensureRemoteActivePiece(PuzzleGame game, List<BallColor> colors) {
    if (game.activePiece != null || colors.length != 3) {
      return;
    }
    game.spawnRemotePiece(colors);
  }
}

class _SpectatorBattleView extends StatelessWidget {
  const _SpectatorBattleView({
    required this.topGame,
    required this.bottomGame,
    required this.topPlayer,
    required this.bottomPlayer,
  });

  final PuzzleGame topGame;
  final PuzzleGame bottomGame;
  final AdminRoomPlayer? topPlayer;
  final AdminRoomPlayer? bottomPlayer;

  static const double _gameViewportWidth = 308;
  static const double _gameViewportHeight = 480;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _SpectatorGameArea(
            game: topGame,
            player: topPlayer,
            roleLabel: 'HOST',
            accentColor: Colors.cyanAccent,
          ),
        ),
        Container(height: 1, color: Colors.cyanAccent.withValues(alpha: 0.22)),
        Expanded(
          child: _SpectatorGameArea(
            game: bottomGame,
            player: bottomPlayer,
            roleLabel: 'GUEST',
            accentColor: Colors.pinkAccent,
          ),
        ),
      ],
    );
  }
}

class _SpectatorGameArea extends StatelessWidget {
  const _SpectatorGameArea({
    required this.game,
    required this.player,
    required this.roleLabel,
    required this.accentColor,
  });

  final PuzzleGame game;
  final AdminRoomPlayer? player;
  final String roleLabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePanelWidth =
            math.min(120.0, math.max(76.0, constraints.maxWidth / 5));
        final scale = math.min(
          constraints.maxWidth / _SpectatorBattleView._gameViewportWidth,
          constraints.maxHeight / _SpectatorBattleView._gameViewportHeight,
        );
        final ballSize = math.min(22.0, math.max(16.0, scale * 30));

        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _SpectatorBattleView._gameViewportWidth,
                    height: _SpectatorBattleView._gameViewportHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(child: GameWidget(game: game)),
                        _SpectatorWazaNameOverlay(game: game),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: sidePanelWidth,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NameBadge(
                      roleLabel: roleLabel,
                      name: player?.displayName ?? '-',
                      rating: player?.rating,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 12),
                    _SpectatorNextPiecePanel(
                      game: game,
                      accentColor: accentColor,
                      ballSize: ballSize,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpectatorNextPiecePanel extends StatelessWidget {
  const _SpectatorNextPiecePanel({
    required this.game,
    required this.accentColor,
    required this.ballSize,
  });

  final PuzzleGame game;
  final Color accentColor;
  final double ballSize;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: ballSize * 2 + 16,
        height: ballSize * 2 + 40,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E28),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.5),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.15),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NEXT',
              style: TextStyle(
                color: accentColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: accentColor, blurRadius: 2)],
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<List<BallColor>>(
              valueListenable: game.nextPieceColors,
              builder: (context, colors, child) => _SpectatorPieceIcon(
                colors: colors,
                size: ballSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpectatorPieceIcon extends StatelessWidget {
  const _SpectatorPieceIcon({
    required this.colors,
    required this.size,
  });

  final List<BallColor> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (colors.length != 3) {
      return const SizedBox.shrink();
    }

    final hSpacing = size + 2;
    final vSpacing = size;

    return SizedBox(
      width: hSpacing + size,
      height: vSpacing + size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: hSpacing / 2,
            top: 0,
            child: MiniBallWidget(ballColor: colors[0], size: size),
          ),
          Positioned(
            left: 0,
            top: vSpacing,
            child: MiniBallWidget(ballColor: colors[1], size: size),
          ),
          Positioned(
            left: hSpacing,
            top: vSpacing,
            child: MiniBallWidget(ballColor: colors[2], size: size),
          ),
        ],
      ),
    );
  }
}

class _SpectatorWazaNameOverlay extends StatelessWidget {
  const _SpectatorWazaNameOverlay({required this.game});

  final PuzzleGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: game.wazaNameNotifier,
      builder: (context, wazaName, child) {
        if (wazaName == null || wazaName.isEmpty) {
          return const SizedBox.shrink();
        }
        return Positioned(
          left: 0,
          right: 0,
          top: 168,
          child: IgnorePointer(
            child: Center(
              child: Text(
                wazaName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.9),
                      blurRadius: 12,
                    ),
                    const Shadow(
                      color: Colors.black,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({required this.room});

  final AdminRoomSummary room;

  @override
  Widget build(BuildContext context) {
    final host = room.results['host'];
    final guest = room.results['guest'];
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.38),
          alignment: Alignment.center,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF101018).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.purpleAccent.withValues(alpha: 0.64)),
              boxShadow: [
                BoxShadow(
                  color: Colors.purpleAccent.withValues(alpha: 0.26),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'RESULT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 14),
                _ResultPlayerRow(
                  player: room.host,
                  opponent: room.guest,
                  result: host,
                  accentColor: Colors.cyanAccent,
                ),
                const SizedBox(height: 10),
                _ResultPlayerRow(
                  player: room.guest,
                  opponent: room.host,
                  result: guest,
                  accentColor: Colors.pinkAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultPlayerRow extends StatelessWidget {
  const _ResultPlayerRow({
    required this.player,
    required this.opponent,
    required this.result,
    required this.accentColor,
  });

  final AdminRoomPlayer? player;
  final AdminRoomPlayer? opponent;
  final AdminBattleResult? result;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final delta = result?.delta;
    final deltaLabel = delta == null
        ? '-'
        : delta > 0
            ? '+$delta'
            : '$delta';
    final deltaColor = delta == null
        ? Colors.white70
        : delta >= 0
            ? Colors.cyanAccent
            : Colors.pinkAccent;
    final outcome = _outcomeLabel(player, opponent, result);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player?.displayName ?? '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  outcome,
                  style: TextStyle(
                      color: accentColor, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          Text(
            '${result?.oldRating ?? player?.rating ?? '-'} → ${result?.newRating ?? '-'}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 10),
          Text(
            deltaLabel,
            style: TextStyle(
              color: deltaColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  String _outcomeLabel(
    AdminRoomPlayer? player,
    AdminRoomPlayer? opponent,
    AdminBattleResult? result,
  ) {
    if (result?.isWin == true) {
      return 'WIN';
    }
    if (result?.isWin == false) {
      return 'LOSE';
    }
    final playerStatus = player?.status;
    final opponentStatus = opponent?.status;
    if (playerStatus == 'dead' || playerStatus == 'left') {
      return 'LOSE';
    }
    if (opponentStatus == 'dead' || opponentStatus == 'left') {
      return 'WIN';
    }
    return playerStatus ?? '-';
  }
}

class AdminPlayerDetailScreen extends StatelessWidget {
  const AdminPlayerDetailScreen({super.key, required this.player});

  final AdminPlayerSummary player;

  @override
  Widget build(BuildContext context) {
    final history = player.matchHistory.take(30).toList();
    return _AdminScaffold(
      title: player.displayName,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _TitleLine(title: '基本情報', subtitle: ''),
                const SizedBox(height: 12),
                _StatRow(label: '名前', value: player.displayName),
                _StatRow(label: '最終更新', value: player.updatedAtLabel),
                _StatRow(
                    label: 'アカウント作成日',
                    value: player.accountCreatedAt.isEmpty
                        ? '-'
                        : player.accountCreatedAt),
                _StatRow(label: 'コイン', value: '${player.coins}'),
                _StatRow(label: 'レベル', value: '${player.level}'),
                _StatRow(
                    label: '広告削除課金有無', value: player.adsRemoved ? 'あり' : 'なし'),
                const Divider(height: 24),
                SelectableText(
                    'publicID: ${player.publicId.isEmpty ? '-' : player.publicId}'),
                SelectableText('uID: ${player.uid}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatsSection(
            title: 'バトル基本情報',
            rows: [
              ('総バトル回数（エンドレスを含まない）', '${player.nonEndlessMatches}'),
              ('ランク戦プレイ回数', '${player.modePlayCounts['RANKED'] ?? 0}'),
              ('コンピュータプレイ回数', '${player.modePlayCounts['CPU'] ?? 0}'),
              ('フレンドプレイ回数', '${player.modePlayCounts['FRIEND'] ?? 0}'),
              ('ヘキサゴン回数', '${player.wazaCounts['hexagon'] ?? 0}'),
              ('ピラミッド回数', '${player.wazaCounts['pyramid'] ?? 0}'),
              ('ストレート回数', '${player.wazaCounts['straight'] ?? 0}'),
              ('累計消去ボール数', '${player.totalClearedBalls}'),
              ('通常消しボール数', '${player.totalNormalClearedBalls}'),
              ('平均連鎖数', player.averageChain.toStringAsFixed(2)),
              ('最大連鎖数', '${player.maxChain}'),
            ],
          ),
          const SizedBox(height: 12),
          _StatsSection(
            title: '今日',
            rows: [
              (
                '総バトル回数(エンドレスを含まない)',
                '${_nonEndlessCount(player.todayModePlayCounts)}'
              ),
              ('ランク戦プレイ回数', '${player.todayModePlayCounts['RANKED'] ?? 0}'),
              ('コンピュータプレイ回数', '${player.todayModePlayCounts['CPU'] ?? 0}'),
              ('フレンドプレイ回数', '${player.todayModePlayCounts['FRIEND'] ?? 0}'),
              ('ランク戦 対戦回数', '${player.todayRankedMatches}'),
              ('ランク戦 勝利数', '${player.todayRankedWins}'),
              ('ランク戦 敗北数', '${player.todayRankedLosses}'),
              (
                'ランク戦 勝率',
                _rate(player.todayRankedWins, player.todayRankedMatches)
              ),
              ('ランク戦 開始レート', '${player.todayRankedRatingStart}'),
              ('ランク戦 現在レート', '${player.todayRankedRatingCurrent}'),
              ('ランク戦 レート変化', _signed(player.todayRankedRatingDelta)),
            ],
          ),
          const SizedBox(height: 12),
          _StatsSection(
            title: 'ランク戦(今シーズン)',
            rows: [
              ('対戦回数', '${player.seasonRankedMatches}'),
              ('勝利数', '${player.seasonRankedWins}'),
              ('敗北数', '${player.seasonRankedLosses}'),
              (
                '勝率',
                _rate(player.seasonRankedWins, player.seasonRankedMatches)
              ),
              ('現在レート', '${player.currentRating}'),
              ('最高到達レート', '${player.highestRating}'),
              ('最大連勝数', '${player.rankedMaxWinStreak}'),
            ],
          ),
          const SizedBox(height: 12),
          _StatsSection(
            title: 'ランク戦(オールシーズン)',
            rows: [
              (
                '最高順位',
                player.bestRankedRank <= 0 ? '-' : '${player.bestRankedRank}位'
              ),
              ('最高レート', '${player.highestRating}'),
              ('対戦回数', '${player.rankedMatches}'),
              ('勝利数', '${player.rankedWins}'),
              ('敗北数', '${player.rankedLosses}'),
              ('勝率', _rate(player.rankedWins, player.rankedMatches)),
              ('最大連勝数', '${player.rankedMaxWinStreak}'),
              (
                '本日の勝利数へのランクイン順位とその回数',
                player.dailyWinRankPlacements.isEmpty
                    ? '-'
                    : player.dailyWinRankPlacements.entries
                        .map((entry) => '${entry.key}:${entry.value}回')
                        .join(' / '),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CpuStatsSection(player: player),
          const SizedBox(height: 12),
          _StatsSection(
            title: 'フレンド対戦',
            rows: [('対戦回数', '${player.friendMatches}')],
          ),
          const SizedBox(height: 12),
          _StatsSection(
            title: 'エンドレス',
            rows: [
              ('挑戦回数', '${player.endlessPlayCount}'),
              ('最高スコア', '${player.endlessHighestScore}'),
            ],
          ),
          const SizedBox(height: 12),
          _CollectionSection(player: player),
          const SizedBox(height: 12),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _TitleLine(title: 'バトル履歴', subtitle: '直近30件'),
                const SizedBox(height: 12),
                _CyberSmallButton(
                  label: 'バトル履歴を見る',
                  icon: Icons.history,
                  onPressed: history.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AdminBattleHistoryScreen(
                                player: player,
                                history: history,
                              ),
                            ),
                          ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _JsonCard(raw: prettyJson(player.raw)),
        ],
      ),
    );
  }
}

class AdminBattleHistoryScreen extends StatelessWidget {
  const AdminBattleHistoryScreen({
    super.key,
    required this.player,
    required this.history,
  });

  final AdminPlayerSummary player;
  final List<AdminMatchHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    return _AdminScaffold(
      title: '${player.displayName} 履歴',
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: history.length,
        itemBuilder: (context, index) {
          return _HistoryTile(entry: history[index]);
        },
      ),
    );
  }
}

class _AdminScaffold extends StatelessWidget {
  const _AdminScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _AdminBackground(child: child),
    );
  }
}

class _AdminBackground extends StatelessWidget {
  const _AdminBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const HexagonGridBackground(
          color: Colors.cyanAccent,
          opacity: 0.035,
          hexRadius: 30,
        ),
        child,
      ],
    );
  }
}

class _BattleHeader extends StatelessWidget {
  const _BattleHeader({required this.room});

  final AdminRoomSummary room;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        border: Border(
          bottom: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              room.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            '${room.status} / ${room.mode}',
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _NameBadge extends StatelessWidget {
  const _NameBadge({
    required this.roleLabel,
    required this.name,
    required this.rating,
    required this.accentColor,
  });

  final String roleLabel;
  final String name;
  final int? rating;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.58)),
        boxShadow: [
          BoxShadow(color: accentColor.withValues(alpha: 0.14), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            roleLabel,
            style: TextStyle(
              color: accentColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            'R ${rating ?? '-'}',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.onTap,
    this.liveRoom,
    this.onSpectate,
  });

  final AdminPlayerSummary player;
  final VoidCallback? onTap;
  final AdminRoomSummary? liveRoom;
  final VoidCallback? onSpectate;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF141421).withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: onTap,
        leading: onSpectate == null
            ? null
            : IconButton(
                icon: const Icon(Icons.visibility),
                color: Colors.cyanAccent,
                tooltip: '観戦',
                onPressed: onSpectate,
              ),
        title: Text(player.displayName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${player.publicId.isEmpty ? player.uid : player.publicId} / ${player.updatedAtLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('R ${player.currentRating}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${player.totalWins}-${player.totalLosses}'),
          ],
        ),
      ),
    );
  }
}

class _WaitingPlayerTile extends StatelessWidget {
  const _WaitingPlayerTile({
    required this.player,
    required this.onTap,
  });

  final AdminWaitingPlayer player;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF141421).withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.hourglass_top, color: Colors.amberAccent),
        title: Text(player.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${player.queue == 'arena_matchmaking' ? 'アリーナ' : 'ランク戦'} / ${player.timestampLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          player.rating == null ? '${player.wins ?? 0}勝' : 'R ${player.rating}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _GameActivityTile extends StatelessWidget {
  const _GameActivityTile({
    required this.activity,
    required this.onTap,
  });

  final AdminGameActivity activity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF141421).withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.sports_esports, color: Colors.cyanAccent),
        title: Text(
          activity.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            activity.publicId.isEmpty ? activity.uid : activity.publicId,
            activity.updatedAtLabel,
          ].join(' / '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              activity.modeLabel,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            if (activity.roomId.isNotEmpty)
              Text(
                activity.roomId,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateText extends StatelessWidget {
  const _EmptyStateText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Text(text, style: const TextStyle(color: Colors.white70)),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap});

  final AdminRoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF141421).withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          room.status == 'playing'
              ? Icons.play_circle_fill
              : Icons.meeting_room,
          color: room.status == 'playing' ? const Color(0xFF52D273) : null,
        ),
        title: Text(room.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${room.roomId} / ${room.status} / ${room.mode}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.trailing,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          suffixIcon: trailing,
          hintText: hintText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.black54,
          isDense: true,
        ),
      ),
    );
  }
}

class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text('$count'),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF141421).withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.28)),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _TitleLine extends StatelessWidget {
  const _TitleLine({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child:
                  Text(label, style: const TextStyle(color: Colors.white70))),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: Colors.cyanAccent)),
        ],
      ),
    );
  }
}

class _JsonCard extends StatelessWidget {
  const _JsonCard({required this.raw});

  final String raw;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Raw JSON', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              raw,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleLine(title: title, subtitle: ''),
          const SizedBox(height: 12),
          for (final row in rows) _StatRow(label: row.$1, value: row.$2),
        ],
      ),
    );
  }
}

class _CpuStatsSection extends StatelessWidget {
  const _CpuStatsSection({required this.player});

  final AdminPlayerSummary player;

  @override
  Widget build(BuildContext context) {
    final entries = player.cpuStats.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitleLine(title: 'コンピュータ対戦', subtitle: ''),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text('CPU強さ別データなし', style: TextStyle(color: Colors.white70))
          else
            for (final entry in entries)
              _StatRow(
                label: entry.key,
                value:
                    '${entry.value.matches}戦 ${entry.value.wins}勝 ${entry.value.losses}敗 ${entry.value.winRate.toStringAsFixed(1)}%',
              ),
        ],
      ),
    );
  }
}

class _CollectionSection extends StatelessWidget {
  const _CollectionSection({required this.player});

  final AdminPlayerSummary player;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitleLine(title: 'コレクション', subtitle: ''),
          const SizedBox(height: 12),
          _StatRow(
            label: '装備バッジ',
            value: player.equippedBadgeIds.isEmpty
                ? '-'
                : player.equippedBadgeIds.join(', '),
          ),
          _StatRow(
            label: '装備アイコン',
            value: player.equippedIconId.isEmpty ? '-' : player.equippedIconId,
          ),
          _StatRow(label: '所持バッジ', value: '${player.ownedBadgeIds.length}'),
          _StatRow(label: '所持スタンプ', value: '${player.ownedStampIds.length}'),
          if (player.ownedBadgeIds.isNotEmpty) ...[
            const Divider(height: 22),
            SelectableText(
              player.ownedBadgeIds.join(', '),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
          if (player.ownedStampIds.isNotEmpty) ...[
            const Divider(height: 22),
            SelectableText(
              player.ownedStampIds.join(', '),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}

class _CyberSmallButton extends StatelessWidget {
  const _CyberSmallButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.cyanAccent.withValues(alpha: 0.18),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final AdminMatchHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final title = switch (entry.mode) {
      'RANKED' => 'ランク戦',
      'CPU' => 'CPU戦',
      'FRIEND' => 'フレンド戦',
      'SOLO' => 'エンドレス',
      _ => entry.mode,
    };
    final detail = switch (entry.mode) {
      'RANKED' =>
        '${entry.isWin ? '勝利' : '敗北'} / ${_signed(entry.ratingDelta ?? 0)} / ${entry.ratingBefore ?? '-'}→${entry.ratingAfter ?? '-'} / ${entry.opponentName}',
      'CPU' => '${entry.isWin ? '勝利' : '敗北'} / ${entry.opponentName}',
      'FRIEND' => '${entry.isWin ? '勝利' : '敗北'} / ${entry.opponentName}',
      'SOLO' => 'スコア ${entry.score ?? 0}',
      _ => entry.opponentName,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF141421).withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text(
          _formatIsoDate(entry.playedAt),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error, style: const TextStyle(color: Colors.redAccent)),
      ),
    );
  }
}

class _AdminErrorScreen extends StatelessWidget {
  const _AdminErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AdminBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error, style: const TextStyle(color: Colors.redAccent)),
          ),
        ),
      ),
    );
  }
}

class _ModeButtonBorderOverlayPainter extends CustomPainter {
  static const double _strokeWidth = 2;
  static const double _arcRadius = 76.3;
  static const double _arcGap = 0.065;

  final List<Color> _colors = const [
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
      canvas.drawArc(
        arcRect,
        arc.start,
        math.pi / 2 - (_arcGap * 2),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _strokeWidth
          ..color = arc.color.withValues(alpha: 0.58),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ModeButtonBorderOverlayPainter oldDelegate) {
    return false;
  }
}

BoxDecoration _prodPillDecoration(BorderRadius borderRadius) {
  return BoxDecoration(
    color: Colors.black54,
    borderRadius: borderRadius,
    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
    boxShadow: [
      BoxShadow(
          color: Colors.cyanAccent.withValues(alpha: 0.16), blurRadius: 8),
    ],
  );
}

String _modeLabel(String mode) {
  return switch (mode) {
    'SOLO' => 'エンドレス',
    'RANKED' => 'ランク戦',
    'CPU' => 'コンピュータ',
    'FRIEND' => 'フレンド',
    _ => mode,
  };
}

int _nonEndlessCount(Map<String, int> counts) {
  return counts.entries
      .where((entry) => entry.key != 'SOLO')
      .fold(0, (total, entry) => total + entry.value);
}

String _rate(int wins, int matches) {
  if (matches <= 0) {
    return '0.0%';
  }
  return '${(wins / matches * 100).toStringAsFixed(1)}%';
}

String _signed(int value) => value > 0 ? '+$value' : '$value';

String _formatIsoDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value.isEmpty ? '-' : value;
  }
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.month)}/${two(local.day)}\n${two(local.hour)}:${two(local.minute)}';
}
