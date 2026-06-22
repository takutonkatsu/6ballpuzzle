import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../audio/sfx.dart';
import '../auth/auth_manager.dart';
import '../data/player_data_manager.dart';
import '../firebase_database_provider.dart';
import '../network/ranked_season_manager.dart';
import '../network/ranking_manager.dart';
import '../network/server_time_manager.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/hexagon_grid_background.dart';
import 'profile_screen.dart';
import 'theme/game_theme_colors.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final RankingManager _rankingManager = RankingManager.instance;
  bool _loading = true;
  bool _openingOpponentProfile = false;
  RankingSummary? _rankingSummary;
  RankingEntry? _currentSeasonEntry;
  DateTime? _currentSeasonStartJst;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _playerData.load();
    RankingSummary? summary;
    RankingEntry? currentSeasonEntry;
    DateTime? currentSeasonStartJst;
    try {
      summary = await _rankingManager.fetchMySummary();
      final uid = await AuthManager.instance.ensureSignedIn();
      currentSeasonEntry =
          await _rankingManager.fetchCurrentSeasonEntryForPlayer(
        uid: uid,
        publicId: _playerData.playerId,
      );
      final nowJst = await ServerTimeManager.instance.nowJst();
      currentSeasonStartJst = RankedSeasonManager.seasonStartJst(
        RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst),
      );
    } catch (_) {
      summary = null;
    }
    await _playerData.syncRecordSummary();
    if (!mounted) {
      return;
    }
    setState(() {
      _rankingSummary = summary;
      _currentSeasonEntry = currentSeasonEntry;
      _currentSeasonStartJst = currentSeasonStartJst;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: GameThemeColors.background,
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
              color: GameThemeColors.cyan,
              opacity: 0.04,
              hexRadius: 30,
            ),
            _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: GameThemeColors.cyan,
                    ),
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
    final cpuByDifficulty = _cpuRecordByDifficulty();
    final friendRecord = _modeRecord('FRIEND');
    final seasonWins = _currentSeasonEntry?.seasonWins ??
        _currentSeasonRankedHistoryRecord().wins;
    final seasonLosses = _currentSeasonEntry?.seasonLosses ??
        _currentSeasonRankedHistoryRecord().losses;
    final seasonMaxWinStreak = _currentSeasonRankedMaxWinStreak();
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
          _StatItem('勝利数', '$seasonWins'),
          _StatItem('敗北数', '$seasonLosses'),
          _StatItem.rich('現在', _ratingValue(_playerData.currentRating)),
          _StatItem('順位', _rankingSummary?.ratingRankLabel ?? '取得中'),
          _StatItem('対戦数', '${seasonWins + seasonLosses}'),
          _StatItem('最大連勝数', '$seasonMaxWinStreak'),
        ], accentColor: GameThemeColors.ranked),
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
        ], accentColor: GameThemeColors.ranked),
        _sectionTitle('エンドレス'),
        _statGrid([
          _StatItem('挑戦回数', '${counts['SOLO'] ?? 0}'),
          _StatItem(
            '最高スコア',
            _formatNumber(_playerData.highestEndlessScore),
          ),
        ], accentColor: GameThemeColors.endless),
        _sectionTitle('コンピュータ対戦'),
        _statGrid([
          for (final entry in cpuByDifficulty.entries)
            _StatItem(entry.key, _recordText(entry.value)),
        ], accentColor: GameThemeColors.computer),
        _sectionTitle('フレンド対戦'),
        _statGrid([
          _StatItem('総対戦数', '${counts['FRIEND'] ?? 0}'),
          _StatItem('勝敗', _recordText(friendRecord)),
        ], accentColor: GameThemeColors.friend),
        _sectionTitle('アリーナ'),
        _statGrid([
          _StatItem('最高勝利数', '${_playerData.maxArenaWins}'),
          _StatItem('挑戦回数', '${_playerData.arenaChallengeCount}'),
          _StatItem('12勝達成回数', '${_playerData.arenaPerfectClearCount}'),
        ], accentColor: GameThemeColors.arena),
      ],
    );
  }

  Widget _playStyleRadar() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7));
    final recentBattles = _playerData.matchHistory
        .where(
          (entry) => entry.mode != 'SOLO' && !entry.playedAt.isBefore(cutoff),
        )
        .toList();
    final styleBattles =
        recentBattles.where((entry) => entry.hasStyleMetrics).toList();
    final matches = math.max(1, styleBattles.length);
    final counts = <String, int>{
      'straight': 0,
      'pyramid': 0,
      'hexagon': 0,
    };
    var normalClearedBalls = 0;
    var totalChain = 0;
    for (final entry in styleBattles) {
      normalClearedBalls += entry.normalClearedBalls;
      totalChain += entry.maxChain;
      for (final count in entry.wazaCounts.entries) {
        counts[count.key] = (counts[count.key] ?? 0) + count.value;
      }
    }
    final hexAvg = (counts['hexagon'] ?? 0) / matches;
    final pyramidAvg = (counts['pyramid'] ?? 0) / matches;
    final straightAvg = (counts['straight'] ?? 0) / matches;
    final normalClearAvg = normalClearedBalls / matches;
    final dailyPlayAvg = recentBattles.length / 7;
    final averageChain = totalChain / matches;
    final values = [
      _score(hexAvg, 3),
      _score(pyramidAvg, 3),
      _score(straightAvg, 3),
      _score(normalClearAvg, 100),
      _score(averageChain, 5),
      _score(dailyPlayAvg, 100),
    ];
    final labels = [
      'ヘキサゴン',
      'ピラミッド',
      'ストレート',
      '通常消し',
      '連鎖',
      'プレイ頻度',
    ].map(AppSettings.instance.translate).toList();
    final details = [
      '${hexAvg.toStringAsFixed(1)} / 3.0',
      '${pyramidAvg.toStringAsFixed(1)} / 3.0',
      '${straightAvg.toStringAsFixed(1)} / 3.0',
      '${normalClearAvg.toStringAsFixed(0)} / 100',
      '${averageChain.toStringAsFixed(1)} / 5.0',
      '${dailyPlayAvg.toStringAsFixed(1)} / 100',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: _panelDecoration(GameThemeColors.ranked),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppSettings.instance.translate('プレイスタイル（直近7日）'),
            style: const TextStyle(
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
        _sectionTitle('フォーメーション累計'),
        _barStat(
            'ヘキサゴン', counts['hexagon'] ?? 0, maxCount, GameThemeColors.cyan),
        const SizedBox(height: 10),
        _barStat(
            'ピラミッド', counts['pyramid'] ?? 0, maxCount, GameThemeColors.cyan),
        const SizedBox(height: 10),
        _barStat(
            'ストレート', counts['straight'] ?? 0, maxCount, GameThemeColors.cyan),
      ],
    );
  }

  Widget _historyTab() {
    final history = _playerData.matchHistory.take(30).toList();
    if (history.isEmpty) {
      return Center(
        child: Text(
          AppSettings.instance.translate('まだ対戦履歴がありません'),
          style: const TextStyle(color: Colors.white60),
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
        AppSettings.instance.translate(label),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _statGrid(
    List<_StatItem> items, {
    Color accentColor = GameThemeColors.cyan,
  }) {
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
          decoration: _panelDecoration(accentColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppSettings.instance.translate(item.label),
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
                AppSettings.instance.translate(label),
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

  Map<String, _ModeRecord> _cpuRecordByDifficulty() {
    final raw = _playerData.cpuDifficultyRecords;
    _ModeRecord record(String key) {
      final matches = raw['${key}_matches'] ?? 0;
      final wins = raw['${key}_wins'] ?? 0;
      return _ModeRecord(wins: wins, losses: math.max(0, matches - wins));
    }

    return {
      '弱い': record('weak'),
      '普通': record('normal'),
      '強い': record('strong'),
      '鬼': record('oni'),
    };
  }

  _ModeRecord _modeRecord(String mode) {
    var record = const _ModeRecord();
    for (final entry in _playerData.matchHistory.where(
      (history) => history.mode == mode,
    )) {
      record = record.add(entry.isWin);
    }
    return record;
  }

  _ModeRecord _currentSeasonRankedHistoryRecord() {
    var record = const _ModeRecord();
    for (final entry in _currentSeasonRankedHistory()) {
      record = record.add(entry.isWin);
    }
    return record;
  }

  int _currentSeasonRankedMaxWinStreak() {
    var current = 0;
    var best = 0;
    final history = _currentSeasonRankedHistory().toList()
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    for (final entry in history) {
      if (entry.isWin) {
        current++;
        best = math.max(best, current);
      } else {
        current = 0;
      }
    }
    return _currentSeasonStartJst == null
        ? _playerData.seasonRankedMaxWinStreak
        : best;
  }

  Iterable<MatchHistoryEntry> _currentSeasonRankedHistory() {
    final start = _currentSeasonStartJst;
    return _playerData.matchHistory.where((entry) {
      if (entry.mode != 'RANKED') {
        return false;
      }
      if (start == null) {
        return true;
      }
      return !entry.playedAt.isBefore(start);
    });
  }

  String _recordText(_ModeRecord record) {
    return '${record.wins}勝 ${record.losses}敗';
  }

  Widget _historyTile(MatchHistoryEntry entry) {
    final color = _modeColor(entry.mode);
    final title = entry.mode == 'SOLO' ? 'エンドレス' : entry.opponentName;
    final canOpenProfile = _canOpenOpponentProfile(entry);
    final resultColor =
        entry.isWin ? GameThemeColors.blueSide : GameThemeColors.redSide;
    return InkWell(
      onTap: canOpenProfile ? () => _openOpponentProfile(entry) : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF101827).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.56),
            width: 1.3,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 58,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (canOpenProfile) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right,
                            color: color.withValues(alpha: 0.75),
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.42),
                            ),
                          ),
                          child: Text(
                            AppSettings.instance.translate(
                              _localizedMode(entry.mode),
                            ),
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatDateTime(entry.playedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (entry.mode == 'SOLO' && entry.score != null)
              _scoreSummary(entry.score!)
            else if (entry.mode != 'SOLO')
              _ratingSummary(entry, resultColor: resultColor),
          ],
        ),
      ),
    );
  }

  bool _canOpenOpponentProfile(MatchHistoryEntry entry) {
    if (_isRankedCpuHistory(entry)) {
      return false;
    }
    return entry.mode == 'RANKED' ||
        entry.mode == 'FRIEND' ||
        entry.mode == 'ARENA';
  }

  bool _isRankedCpuHistory(MatchHistoryEntry entry) {
    if (entry.mode != 'RANKED') {
      return false;
    }
    final hasOpponentId = entry.opponentUid.trim().isNotEmpty ||
        entry.opponentPublicId.trim().isNotEmpty;
    if (hasOpponentId) {
      return false;
    }
    final name = entry.opponentName.trim();
    return name == 'Player' ||
        name.startsWith('ランクBot') ||
        name.startsWith('CPU') ||
        name.startsWith('コンピュータ');
  }

  Future<void> _openOpponentProfile(MatchHistoryEntry entry) async {
    if (_openingOpponentProfile) {
      return;
    }
    _openingOpponentProfile = true;
    AppSfx.playUiTap();
    try {
      var uid = entry.opponentUid.trim();
      var publicId = entry.opponentPublicId.trim();
      var displayName = entry.opponentName.trim();
      var rating = entry.ratingAfter ?? 1000;

      try {
        final currentEntry = await _rankingManager.fetchCurrentEntryForPlayer(
          uid: uid,
          publicId: publicId,
        );
        if (currentEntry != null) {
          uid = currentEntry.uid;
          publicId = currentEntry.publicId;
          displayName = currentEntry.displayName;
          rating = currentEntry.rating;
        }
      } catch (_) {
        // ランキング側から現在プロフィールを解決できない場合は保存済みIDで続行する。
      }

      if (uid.isEmpty) {
        try {
          final key = _nameLookupKey(displayName);
          final snapshot = await AppFirebaseDatabase.ref()
              .child('playerNameLookup/$key')
              .get();
          final raw = snapshot.value;
          if (raw is Map && raw.isNotEmpty) {
            final first = raw.entries.first;
            final data = first.value is Map
                ? Map<dynamic, dynamic>.from(first.value as Map)
                : <dynamic, dynamic>{};
            uid = data['uid']?.toString() ?? first.key.toString();
            publicId = data['publicId']?.toString() ?? publicId;
            displayName = data['displayName']?.toString() ?? displayName;
            rating = _intValue(data['currentRating']) ?? rating;
          }
        } catch (_) {
          uid = '';
        }
      }

      if (!mounted) {
        return;
      }
      if (uid.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppSettings.instance.translate('プロフィールを取得できませんでした'),
            ),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            playerUid: uid,
            initialEntry: RankingEntry(
              uid: uid,
              displayName: displayName.isEmpty ? 'Player' : displayName,
              rating: rating,
              publicId: publicId,
            ),
          ),
        ),
      );
    } finally {
      _openingOpponentProfile = false;
    }
  }

  int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  String _nameLookupKey(String name) {
    final normalized = name.trim().toLowerCase();
    final key = normalized
        .replaceAll(RegExp(r'[\.\#\$\[\]/]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return key.isEmpty ? 'player' : key;
  }

  Widget _scoreSummary(int score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'スコア',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '$score',
          style: const TextStyle(
            color: GameThemeColors.endless,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _ratingSummary(MatchHistoryEntry entry, {required Color resultColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _resultLabel(entry),
          style: TextStyle(
            color: resultColor,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        if (entry.mode == 'RANKED' && entry.ratingAfter != null)
          HexagonTrophyAmount(
            entry.ratingAfter!,
            color: Colors.amberAccent,
            iconSize: 15,
            fontSize: 14,
          ),
        if (entry.mode == 'RANKED' && entry.ratingDelta != null)
          Text(
            entry.ratingDelta! >= 0
                ? '+${entry.ratingDelta}'
                : '${entry.ratingDelta}',
            style: TextStyle(
              color: entry.ratingDelta! >= 0
                  ? GameThemeColors.blueSide
                  : GameThemeColors.redSide,
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

  String _formatNumber(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  String _resultLabel(MatchHistoryEntry entry) {
    if (entry.isForfeitWin) {
      return '不戦勝';
    }
    return entry.isWin ? '勝ち' : '負け';
  }

  Color _modeColor(String mode) {
    return switch (mode) {
      'RANKED' => GameThemeColors.ranked,
      'FRIEND' => GameThemeColors.friend,
      'CPU' => GameThemeColors.computer,
      'ARENA' => GameThemeColors.arena,
      'SOLO' => GameThemeColors.endless,
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
            color: GameThemeColors.cyan,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 3.5,
          ),
        ),
        Text(
          AppSettings.instance.translate(title),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
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
        border: Border.all(
          color: GameThemeColors.cyanBorder.withValues(alpha: 0.18),
        ),
      ),
      child: TabBar(
        onTap: (_) => AppSfx.playUiTap(),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              GameThemeColors.cyan.withValues(alpha: 0.2),
              GameThemeColors.blueSide.withValues(alpha: 0.18),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GameThemeColors.cyanBorder),
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
          for (final tab in tabs)
            Tab(text: AppSettings.instance.translate(tab)),
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

class _ModeRecord {
  const _ModeRecord({this.wins = 0, this.losses = 0});

  final int wins;
  final int losses;

  int get matches => wins + losses;

  _ModeRecord add(bool won) {
    return _ModeRecord(
      wins: wins + (won ? 1 : 0),
      losses: losses + (won ? 0 : 1),
    );
  }
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
      ..color = GameThemeColors.cyan.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fillPaint = Paint()
      ..color = GameThemeColors.ranked.withValues(alpha: 0.24)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = GameThemeColors.cyan
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
                color: GameThemeColors.cyan,
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
