import 'package:flutter/material.dart';

import '../data/player_data_manager.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final PlayerDataManager _playerData = PlayerDataManager.instance;
  bool _loading = true;

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
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A12),
        appBar: AppBar(
          backgroundColor: const Color(0xFF101423),
          title: const Text('レコード'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '対戦'),
              Tab(text: 'ワザ'),
              Tab(text: '履歴'),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              )
            : TabBarView(
                children: [
                  _combatTab(),
                  _techniqueTab(),
                  _historyTab(),
                ],
              ),
      ),
    );
  }

  Widget _combatTab() {
    final counts = _playerData.modePlayCounts;
    final winRate = _playerData.totalMatches == 0
        ? 0.0
        : (_playerData.totalWins / _playerData.totalMatches) * 100;
    return _tabList(
      children: [
        _bigStat('勝率', '${winRate.toStringAsFixed(1)}%', Colors.cyanAccent),
        _sectionTitle('モード別プレイ回数'),
        _statGrid([
          _StatItem('総プレイ回数', '${_playerData.totalMatches}'),
          _StatItem('ランク戦', '${counts['RANKED'] ?? 0}'),
          _StatItem('闘技場', '${counts['ARENA'] ?? 0}'),
          _StatItem('CPU戦', '${counts['CPU'] ?? 0}'),
          _StatItem('1Pモード', '${counts['SOLO'] ?? 0}'),
          _StatItem('フレンド対戦', '${counts['FRIEND'] ?? 0}'),
        ]),
        _sectionTitle('全体成績'),
        _statGrid([
          _StatItem('勝利', '${_playerData.totalWins}'),
          _StatItem('敗北', '${_playerData.totalLosses}'),
          _StatItem('最高レート', '${_playerData.highestRating}'),
          _StatItem('闘技場最高勝利', '${_playerData.maxArenaWins}'),
          _StatItem('闘技場挑戦回数', '${_playerData.arenaChallengeCount}'),
        ]),
      ],
    );
  }

  Widget _techniqueTab() {
    final counts = _playerData.wazaCounts;
    final maxCount = [
      counts['straight'] ?? 0,
      counts['pyramid'] ?? 0,
      counts['hexagon'] ?? 0,
      1,
    ].reduce((a, b) => a > b ? a : b);
    return _tabList(
      children: [
        _bigStat('最大連鎖', '${_playerData.maxCombo}', Colors.amberAccent),
        _barStat('ストレート', counts['straight'] ?? 0, maxCount, Colors.cyanAccent),
        _barStat(
            'ピラミッド', counts['pyramid'] ?? 0, maxCount, Colors.purpleAccent),
        _barStat('ヘキサゴン', counts['hexagon'] ?? 0, maxCount, Colors.pinkAccent),
      ],
    );
  }

  Widget _historyTab() {
    final history = _playerData.matchHistory;
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

  Widget _bigStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(color),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
        childAspectRatio: 2.4,
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
    final color = entry.isWin ? Colors.cyanAccent : Colors.pinkAccent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(color),
      child: Row(
        children: [
          Container(
            width: 46,
            alignment: Alignment.center,
            child: Text(
              entry.isWin ? '勝利' : '敗北',
              style: TextStyle(
                color: color,
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
                  entry.opponentName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_localizedMode(entry.mode)}  ${_formatDate(entry.playedAt)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (entry.ratingAfter != null)
            Text(
              '${entry.ratingAfter}',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration(Color color) {
    return BoxDecoration(
      color: const Color(0xFF111827).withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.36)),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.08),
          blurRadius: 14,
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)}';
  }

  String _localizedMode(String mode) {
    return switch (mode) {
      'RANKED' => 'ランク戦',
      'ARENA' => '闘技場',
      'CPU' => 'CPU戦',
      'SOLO' => '1Pモード',
      'FRIEND' => 'フレンド対戦',
      _ => mode,
    };
  }
}

class _StatItem {
  const _StatItem(this.label, this.value);

  final String label;
  final String value;
}
