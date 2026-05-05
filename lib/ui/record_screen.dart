import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../data/player_data_manager.dart';
import '../network/ranking_manager.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/hexagon_grid_background.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final RankingManager _rankingManager = RankingManager.instance;
  bool _loading = true;
  RankingSummary? _rankingSummary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _playerData.load();
    RankingSummary? summary;
    try {
      summary = await _rankingManager.fetchMySummary();
    } catch (_) {
      summary = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _rankingSummary = summary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A12),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () {
              AppSfx.playUiTap();
              Navigator.of(context).pop();
            },
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x3325F4FF),
                  Color(0x00000000),
                ],
              ),
            ),
          ),
          title: const _RecordPageTitle(
            title: 'レコード',
            subtitle: 'PLAYER DATA',
          ),
          centerTitle: true,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(62),
            child: _RecordNeonTabBar(
              tabs: [
                '総合',
                '対戦履歴',
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            const HexagonGridBackground(
              color: Colors.cyanAccent,
              opacity: 0.04,
              hexRadius: 30,
            ),
            _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  )
                : TabBarView(
                    children: [
                      _summaryTab(),
                      _historyTab(),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTab() {
    final counts = _playerData.modePlayCounts;
    return _tabList(
      children: [
        _playStyleRadar(),
        _wazaTotalsPanel(),
        _sectionTitle('総合'),
        _statGrid([
          _StatItem('総プレイ回数', '${_playerData.totalMatches}'),
          _StatItem('勝利数', '${_playerData.totalWins}'),
          _StatItem('累計消去ボール数', '${_playerData.totalClearedBalls}'),
          _StatItem('平均連鎖数', _playerData.averageChain.toStringAsFixed(1)),
          _StatItem('総ログイン日数', '${_playerData.totalLoginDays}日'),
          _StatItem('初めてプレイした日', _formatDate(_playerData.accountCreatedAt)),
        ]),
        _sectionTitle('ランク戦 / 今シーズン'),
        _statGrid([
          _StatItem('勝利数', '${_playerData.rankedWins}'),
          _StatItem.rich('現在', _ratingValue(_playerData.currentRating)),
          _StatItem('順位', _rankingSummary?.ratingRankLabel ?? '取得中'),
          _StatItem.rich('最高到達', _ratingValue(_playerData.highestRating)),
          _StatItem('最大連勝数', '${_playerData.rankedMaxWinStreak}'),
        ]),
        _sectionTitle('ランク戦 / 過去のシーズン'),
        _statGrid([
          _StatItem.rich(
            '最高レート',
            _ratingValue(_playerData.highestRating, suffix: ' / シーズン0'),
          ),
          _StatItem(
            '最高順位',
            _playerData.bestRankedRank > 0
                ? '${_playerData.bestRankedRank}位'
                : '記録なし',
          ),
        ]),
        _sectionTitle('アリーナ'),
        _statGrid([
          _StatItem('最高勝利数', '${_playerData.maxArenaWins}'),
          _StatItem('挑戦回数', '${_playerData.arenaChallengeCount}'),
          _StatItem('12勝達成回数', '${_playerData.arenaPerfectClearCount}'),
        ]),
        _sectionTitle('エンドレス'),
        _statGrid([
          _StatItem('挑戦回数', '${counts['SOLO'] ?? 0}'),
          _StatItem('最高スコア', '${_playerData.highestEndlessScore}'),
        ]),
      ],
    );
  }

  Widget _playStyleRadar() {
    final matches = math.max(1, _playerData.totalMatches);
    final counts = _playerData.wazaCounts;
    final days = math.max(
      1,
      DateTime.now().difference(_playerData.accountCreatedAt).inDays + 1,
    );
    final hexAvg = (counts['hexagon'] ?? 0) / matches;
    final pyramidAvg = (counts['pyramid'] ?? 0) / matches;
    final straightAvg = (counts['straight'] ?? 0) / matches;
    final normalClearAvg = _playerData.totalNormalClearedBalls / matches;
    final dailyPlayAvg = _playerData.totalMatches / days;
    final averageChain = _playerData.averageChain;
    final values = [
      _score(hexAvg, 5),
      _score(pyramidAvg, 5),
      _score(straightAvg, 5),
      _score(normalClearAvg, 500),
      _score(averageChain, 10),
      _score(dailyPlayAvg, 20),
    ];
    const labels = [
      'ヘキサゴン',
      'ピラミッド',
      'ストレート',
      '通常消し',
      '連鎖',
      'プレイ頻度',
    ];
    final details = [
      '${hexAvg.toStringAsFixed(1)} / 5.0',
      '${pyramidAvg.toStringAsFixed(1)} / 5.0',
      '${straightAvg.toStringAsFixed(1)} / 5.0',
      '${normalClearAvg.toStringAsFixed(0)} / 500',
      '${averageChain.toStringAsFixed(1)} / 10',
      '${dailyPlayAvg.toStringAsFixed(1)} / 20',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: _panelDecoration(Colors.purpleAccent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'プレイスタイル',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: CustomPaint(
              painter: _RadarChartPainter(
                values: values,
                labels: labels,
                details: details,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  double _score(double value, double maxValue) {
    if (maxValue <= 0) {
      return 0;
    }
    return ((value / maxValue) * 100).clamp(0, 100).toDouble();
  }

  Widget _wazaTotalsPanel() {
    final counts = _playerData.wazaCounts;
    final maxCount = [
      counts['straight'] ?? 0,
      counts['pyramid'] ?? 0,
      counts['hexagon'] ?? 0,
      1,
    ].reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('ワザ累計'),
        _barStat('ヘキサゴン', counts['hexagon'] ?? 0, maxCount, Colors.pinkAccent),
        const SizedBox(height: 10),
        _barStat(
            'ピラミッド', counts['pyramid'] ?? 0, maxCount, Colors.purpleAccent),
        const SizedBox(height: 10),
        _barStat('ストレート', counts['straight'] ?? 0, maxCount, Colors.cyanAccent),
      ],
    );
  }

  Widget _historyTab() {
    final history = _playerData.matchHistory.take(30).toList();
    if (history.isEmpty) {
      return const Center(
        child: Text(
          'まだ対戦履歴がありません',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) => _historyTile(history[index]),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemCount: history.length,
    );
  }

  Widget _tabList({required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: children
          .expand((child) => [child, const SizedBox(height: 14)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _statGrid(List<_StatItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration:
              _panelDecoration(Colors.cyanAccent.withValues(alpha: 0.7)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              item.valueWidget ??
                  Text(
                    item.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _barStat(String label, int value, int maxValue, Color color) {
    final factor = maxValue == 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '$value',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: factor,
              minHeight: 10,
              color: color,
              backgroundColor: Colors.white12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(MatchHistoryEntry entry) {
    final color = _modeColor(entry.mode);
    final title = entry.mode == 'SOLO' ? 'エンドレス' : entry.opponentName;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(color).copyWith(
        color: color.withValues(alpha: 0.12),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            alignment: Alignment.center,
            child: Text(
              _resultLabel(entry),
              style: TextStyle(
                color: entry.isWin ? Colors.cyanAccent : Colors.pinkAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_localizedMode(entry.mode)}  ${_formatDateTime(entry.playedAt)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (entry.mode == 'SOLO' && entry.score != null)
            _scoreSummary(entry.score!)
          else if (entry.ratingAfter != null)
            _ratingSummary(entry),
        ],
      ),
    );
  }

  Widget _scoreSummary(int score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'SCORE',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '$score',
          style: const TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _ratingSummary(MatchHistoryEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        HexagonTrophyAmount(
          entry.ratingAfter!,
          color: Colors.amberAccent,
          iconSize: 15,
          fontSize: 14,
        ),
        if (entry.ratingDelta != null)
          Text(
            entry.ratingDelta! >= 0
                ? '+${entry.ratingDelta}'
                : '${entry.ratingDelta}',
            style: TextStyle(
              color: entry.ratingDelta! >= 0
                  ? Colors.cyanAccent
                  : Colors.pinkAccent,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }

  Widget _ratingValue(int rating, {String suffix = ''}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HexagonTrophyAmount(
          rating,
          color: Colors.amberAccent,
          iconSize: 16,
          fontSize: 18,
        ),
        if (suffix.isNotEmpty)
          Flexible(
            child: Text(
              suffix,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  BoxDecoration _panelDecoration(Color color) {
    return BoxDecoration(
      color: const Color(0xFF111827).withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.36)),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.08),
          blurRadius: 14,
        ),
      ],
    );
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)}';
  }

  String _resultLabel(MatchHistoryEntry entry) {
    if (entry.isForfeitWin) {
      return '不戦勝';
    }
    return entry.isWin ? '勝ち' : '負け';
  }

  Color _modeColor(String mode) {
    return switch (mode) {
      'RANKED' => Colors.purpleAccent,
      'FRIEND' => Colors.redAccent,
      'CPU' => Colors.amberAccent,
      'ARENA' => Colors.lightBlueAccent,
      'SOLO' => Colors.greenAccent,
      _ => Colors.white54,
    };
  }

  String _localizedMode(String mode) {
    return switch (mode) {
      'RANKED' => 'ランク戦',
      'ARENA' => 'アリーナ',
      'CPU' => 'コンピュータ対戦',
      'SOLO' => 'エンドレス',
      'FRIEND' => 'フレンド対戦',
      _ => mode,
    };
  }
}

class _RecordPageTitle extends StatelessWidget {
  const _RecordPageTitle({
    required this.title,
    required this.subtitle,
  });

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
            color: Colors.cyanAccent,
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
            shadows: [
              Shadow(color: Colors.cyanAccent, blurRadius: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordNeonTabBar extends StatelessWidget {
  const _RecordNeonTabBar({required this.tabs});

  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withValues(alpha: 0.12),
            blurRadius: 18,
          ),
        ],
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.cyanAccent.withValues(alpha: 0.35),
              const Color(0xFF0B84FF).withValues(alpha: 0.28),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.85)),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        tabs: [
          for (final tab in tabs) Tab(text: tab),
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem(this.label, this.value) : valueWidget = null;

  const _StatItem.rich(this.label, this.valueWidget) : value = '';

  final String label;
  final String value;
  final Widget? valueWidget;
}

class _RadarChartPainter extends CustomPainter {
  const _RadarChartPainter({
    required this.values,
    required this.labels,
    required this.details,
  });

  final List<double> values;
  final List<String> labels;
  final List<String> details;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 6);
    final radius = math.min(size.width, size.height) * 0.32;
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fillPaint = Paint()
      ..color = Colors.purpleAccent.withValues(alpha: 0.24)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    for (var step = 1; step <= 4; step++) {
      canvas.drawPath(
        _polygonPath(center, radius * step / 4, List.filled(6, 100)),
        gridPaint,
      );
    }
    for (var i = 0; i < 6; i++) {
      final point = _point(center, radius, i, 100);
      canvas.drawLine(center, point, axisPaint);
    }

    final valuePath = _polygonPath(center, radius, values);
    canvas.drawPath(valuePath, fillPaint);
    canvas.drawPath(valuePath, linePaint);

    for (var i = 0; i < labels.length; i++) {
      final labelPoint = _point(center, radius + 28, i, 100);
      final textPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${labels[i]}\n',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: details[i],
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 88);
      textPainter.paint(
        canvas,
        Offset(
          labelPoint.dx - textPainter.width / 2,
          labelPoint.dy - textPainter.height / 2,
        ),
      );
    }
  }

  Path _polygonPath(Offset center, double radius, List<double> sourceValues) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final point = _point(center, radius, i, sourceValues[i]);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  Offset _point(Offset center, double radius, int index, double value) {
    final angle = -math.pi / 2 + (math.pi * 2 / 6) * index;
    final scaled = radius * (value.clamp(0, 100) / 100);
    return Offset(
      center.dx + math.cos(angle) * scaled,
      center.dy + math.sin(angle) * scaled,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.labels != labels ||
        oldDelegate.details != details;
  }
}
