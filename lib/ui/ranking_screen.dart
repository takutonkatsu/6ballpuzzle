import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../data/player_data_manager.dart';
import '../network/multiplayer_manager.dart';
import '../network/ranked_season_manager.dart';
import '../network/ranking_manager.dart';
import '../network/server_time_manager.dart';
import 'components/hexagon_currency_icons.dart';
import 'profile_screen.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _SeasonResultViewData {
  const _SeasonResultViewData({
    required this.seasonName,
    required this.rating,
    required this.rank,
    required this.record,
    required this.winRate,
  });

  final String seasonName;
  final String rating;
  final String rank;
  final String record;
  final String winRate;

  factory _SeasonResultViewData.fromLog(String log) {
    final lines = log
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    String valueAfter(String prefix, String fallback) {
      final line = lines.cast<String?>().firstWhere(
            (line) => line?.startsWith(prefix) ?? false,
            orElse: () => null,
          );
      if (line == null) {
        return fallback;
      }
      return line.substring(prefix.length).trim();
    }

    return _SeasonResultViewData(
      seasonName: lines.isEmpty ? '前シーズン 結果' : lines.first,
      rating: valueAfter('最終レート:', '-'),
      rank: valueAfter('最終順位:', '圏外'),
      record: valueAfter('勝敗:', '-'),
      winRate: valueAfter('勝率:', '-'),
    );
  }
}

enum _RankingTab {
  currentSeason,
  dailyWins,
  endless,
}

class _RankingScreenState extends State<RankingScreen> {
  static const Duration _rankingOperationTimeout = Duration(seconds: 8);

  final RankingManager _rankingManager = RankingManager.instance;
  final MultiplayerManager _multiplayerManager = MultiplayerManager.instance;

  bool _isLoading = false;
  List<RankingEntry> _entries = const [];
  String? _errorMessage;
  _RankingTab _selectedTab = _RankingTab.currentSeason;
  int _rankingLoadSerial = 0;
  Timer? _remainingTimer;
  String _remainingLabel = '残り--';
  String _dailyRemainingLabel = '残り--';
  String _loadedSeasonId = '';
  String _loadedDailyDateKey = '';

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  @override
  void initState() {
    super.initState();
    _remainingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_updateServerClockLabels()),
    );
    unawaited(_updateServerClockLabels(forceRefresh: true));
    _loadRankings();
  }

  @override
  void dispose() {
    _remainingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRankings() async {
    final requestTab = _selectedTab;
    final requestSerial = ++_rankingLoadSerial;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final syncFuture = (switch (requestTab) {
        _RankingTab.endless => _syncEndlessBeforeLoad(),
        _ => _syncCurrentSeasonBeforeLoad(),
      })
          .timeout(_rankingOperationTimeout);
      final entriesFuture = switch (requestTab) {
        _RankingTab.currentSeason => await _rankingManager
            .fetchTopRankings(forceRefresh: true)
            .timeout(_rankingOperationTimeout),
        _RankingTab.dailyWins => await _rankingManager
            .fetchTopDailyWinRankings(forceRefresh: true)
            .timeout(_rankingOperationTimeout),
        _RankingTab.endless => await _rankingManager
            .fetchTopEndlessScoreRankings(forceRefresh: true)
            .timeout(_rankingOperationTimeout),
      };
      await syncFuture;
      final entries = entriesFuture;
      if (!mounted) {
        return;
      }
      final nowJst = await ServerTimeManager.instance.nowJst();
      if (!mounted ||
          requestSerial != _rankingLoadSerial ||
          requestTab != _selectedTab) {
        return;
      }
      final loadedSeasonId =
          RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
      setState(() {
        _entries = entries;
        _loadedSeasonId = loadedSeasonId;
        _loadedDailyDateKey = RankingManager.todayKeyJst(
          nowJstOverride: nowJst,
        );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (requestSerial != _rankingLoadSerial || requestTab != _selectedTab) {
        return;
      }
      setState(() {
        _errorMessage = _rankingLoadErrorMessage(error);
        _isLoading = false;
      });
    }
  }

  Future<void> _updateServerClockLabels({bool forceRefresh = false}) async {
    if (!mounted) {
      return;
    }
    try {
      final nowJst =
          await ServerTimeManager.instance.nowJst(forceRefresh: forceRefresh);
      final currentSeasonId =
          RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
      final currentDailyDateKey =
          RankingManager.todayKeyJst(nowJstOverride: nowJst);
      if (!mounted) {
        return;
      }
      setState(() {
        _remainingLabel =
            RankedSeasonManager.remainingLabel(nowJstOverride: nowJst);
        _dailyRemainingLabel =
            RankingManager.dailyRemainingLabel(nowJstOverride: nowJst);
      });
      if (currentSeasonId != _loadedSeasonId ||
          (_selectedTab == _RankingTab.dailyWins &&
              currentDailyDateKey != _loadedDailyDateKey)) {
        unawaited(_loadRankings());
      }
    } catch (_) {
      // サーバー時刻の一時取得失敗では、ランキング画面の表示を止めない。
    }
  }

  Future<void> _syncCurrentSeasonBeforeLoad() async {
    try {
      await _rankingManager
          .syncSeasonStateForCurrentPlayer()
          .timeout(_rankingOperationTimeout);
    } catch (_) {
      // シーズン同期に失敗しても、ランキングの読み込み自体は試す。
    }
    await PlayerDataManager.instance.load();
    await _showSeasonResultLogIfNeeded();
    final seasonRating = PlayerDataManager.instance.currentRating;
    _multiplayerManager.currentRating = seasonRating;
    try {
      await _rankingManager
          .updateMyRating(
            rating: seasonRating,
            displayName: PlayerDataManager.instance.displayPlayerName,
          )
          .timeout(_rankingOperationTimeout);
    } catch (_) {
      // 新シーズンの自分の行作成に失敗しても、一覧読み込みは続ける。
    }
  }

  Future<void> _syncEndlessBeforeLoad() async {
    try {
      await PlayerDataManager.instance.load();
      await _rankingManager
          .syncEndlessScore(
            displayName: PlayerDataManager.instance.displayPlayerName,
          )
          .timeout(_rankingOperationTimeout);
    } catch (_) {
      // エンドレスランキングは恒久ランキングなので、シーズン同期には依存しない。
    }
  }

  Future<void> _showSeasonResultLogIfNeeded() async {
    final log =
        await PlayerDataManager.instance.consumePendingRankedSeasonResultLog();
    if (log == null || log.isEmpty || !mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: _buildSeasonDialogFrame(
                title: 'シーズン結果',
                width: 360,
                child: _buildSeasonResultLog(log),
                actions: [
                  _buildSeasonDialogButton(
                    label: 'OK',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            );
          },
        ),
      );
    });
  }

  String _rankingLoadErrorMessage(Object error) {
    if (error is FirebaseException &&
        (error.code == 'permission-denied' ||
            (error.code == 'unknown' &&
                (error.message ?? '').toLowerCase().contains('permission')))) {
      return 'ランキングの読み込み権限がありません。テスト環境のDatabase Rulesを確認してください。';
    }
    return '通信状況を確認して、もう一度お試しください。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              _buildModeTabs(),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141421),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.45),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withValues(alpha: 0.16),
                        blurRadius: 24,
                      ),
                      BoxShadow(
                        color: Colors.purpleAccent.withValues(alpha: 0.12),
                        blurRadius: 36,
                      ),
                    ],
                  ),
                  child: _buildBody(),
                ),
              ),
              if (_selectedTab == _RankingTab.currentSeason ||
                  _selectedTab == _RankingTab.dailyWins) ...[
                const SizedBox(height: 10),
                _selectedTab == _RankingTab.dailyWins
                    ? _buildDailyFooter()
                    : _buildSeasonFooter(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            child: SizedBox(
              width: 44,
              height: 44,
              child: _buildBackButton(context),
            ),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              HexagonTrophyIcon(size: 33),
              SizedBox(width: 10),
              _RankingPageTitle(
                title: 'ランキング',
                subtitle: 'LEADERBOARD',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return IconButton(
      onPressed: () {
        _playUiTap();
        Navigator.of(context).pop();
      },
      icon: const Icon(Icons.arrow_back_ios_new),
      tooltip: '戻る',
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ランキングを取得できませんでした',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _playUiTap();
                  unawaited(_loadRankings());
                },
                child: const Text('再読み込み'),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return const Center(
        child: Text(
          'まだランキングデータがありません',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final rank = _displayRankAt(index);
        final isMe = _isCurrentPlayer(entry);
        return _buildRankingRow(
          entry,
          rank,
          isMe,
          tab: _selectedTab,
        );
      },
    );
  }

  bool _isCurrentPlayer(RankingEntry entry) {
    final myUid = _multiplayerManager.myUid;
    final myPublicId = PlayerDataManager.instance.playerId;
    if (myUid != null && entry.uid == myUid) {
      return true;
    }
    return myPublicId.isNotEmpty && entry.publicId == myPublicId;
  }

  int _displayRankAt(int index) {
    if (index <= 0) {
      return 1;
    }
    final current = _entries[index];
    final previous = _entries[index - 1];
    final isSameScore = switch (_selectedTab) {
      _RankingTab.currentSeason => current.rating == previous.rating,
      _RankingTab.dailyWins => current.dailyWins == previous.dailyWins,
      _RankingTab.endless =>
        current.highestEndlessScore == previous.highestEndlessScore,
    };
    if (isSameScore) {
      return _displayRankAt(index - 1);
    }
    return index + 1;
  }

  Widget _buildModeTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
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
      child: Row(
        children: [
          _buildModeTab(
            label: '今シーズン',
            selected: _selectedTab == _RankingTab.currentSeason,
            onTap: () => _selectTab(_RankingTab.currentSeason),
          ),
          _buildModeTab(
            label: '今日の勝利数',
            selected: _selectedTab == _RankingTab.dailyWins,
            onTap: () => _selectTab(_RankingTab.dailyWins),
          ),
          _buildModeTab(
            label: 'エンドレス',
            selected: _selectedTab == _RankingTab.endless,
            onTap: () => _selectTab(_RankingTab.endless),
          ),
        ],
      ),
    );
  }

  void _selectTab(_RankingTab tab) {
    if (_selectedTab == tab) {
      return;
    }
    _playUiTap();
    setState(() {
      _selectedTab = tab;
      _entries = const [];
      _errorMessage = null;
    });
    unawaited(_loadRankings());
  }

  Widget _buildModeTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      Colors.cyanAccent.withValues(alpha: 0.35),
                      const Color(0xFF0B84FF).withValues(alpha: 0.28),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: Colors.cyanAccent.withValues(alpha: 0.85))
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRankingRow(
    RankingEntry entry,
    int rank,
    bool isMe, {
    required _RankingTab tab,
  }) {
    final accent = switch (rank) {
      1 => Colors.amberAccent,
      2 => const Color(0xFFE5E7EB),
      3 => const Color(0xFFCD7F32),
      _ => Colors.cyanAccent,
    };
    final rankIsTop = rank <= 3;
    final topFillColor = switch (rank) {
      1 => const Color(0xFF9A7218),
      2 => const Color(0xFF768394),
      3 => const Color(0xFF924A24),
      _ => const Color(0xFF101827),
    };

    return InkWell(
      onTap: () => _openPlayerProfile(entry, rank, tab),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: rankIsTop ? topFillColor.withValues(alpha: 0.96) : null,
          gradient: rankIsTop
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF101827).withValues(alpha: 0.96),
                    const Color(0xFF070B14).withValues(alpha: 0.98),
                  ],
                ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent.withValues(alpha: rankIsTop ? 0.88 : 0.24),
            width: rankIsTop ? 1.3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: rankIsTop ? 0.28 : 0.06),
              blurRadius: rankIsTop ? 12 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: rankIsTop ? 0.28 : 0.20),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: accent.withValues(alpha: rankIsTop ? 0.78 : 0.34),
                  width: rankIsTop ? 1.2 : 1,
                ),
              ),
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      rankIsTop ? accent : Colors.white.withValues(alpha: 0.78),
                  fontSize: rankIsTop ? 14 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildResponsiveRankingNameText(
                entry.displayName,
                color: Colors.white.withValues(alpha: 0.92),
                maxFontSize: 15,
              ),
            ),
            const SizedBox(width: 10),
            _buildRankingValue(entry, accent, tab),
          ],
        ),
      ),
    );
  }

  void _openPlayerProfile(RankingEntry entry, int rank, _RankingTab tab) {
    _playUiTap();
    final rankLabel = tab == _RankingTab.currentSeason ? '$rank位' : null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          playerUid: entry.uid,
          initialEntry: entry,
          initialRankLabel: rankLabel,
        ),
      ),
    );
  }

  Widget _buildRankingValue(
    RankingEntry entry,
    Color accent,
    _RankingTab tab,
  ) {
    switch (tab) {
      case _RankingTab.currentSeason:
        return _rankingValuePill(
          child: HexagonTrophyAmount(
            entry.rating,
            color: Colors.amberAccent,
            iconSize: 16,
            fontSize: 15,
          ),
          accent: Colors.amberAccent,
        );
      case _RankingTab.dailyWins:
        return _rankingValuePill(
          child: Text(
            '${entry.dailyWins}勝',
            style: const TextStyle(
              color: Color(0xFFEAF6FF),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          accent: accent,
        );
      case _RankingTab.endless:
        return _rankingValuePill(
          child: Text(
            '${entry.highestEndlessScore}',
            style: const TextStyle(
              color: Color(0xFFEAF6FF),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          suffix: '点',
          accent: accent,
        );
    }
  }

  Widget _rankingValuePill({
    required Widget child,
    required Color accent,
    String suffix = '',
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72, maxWidth: 112),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                if (suffix.isNotEmpty)
                  Text(
                    suffix,
                    style: const TextStyle(
                      color: Color(0xFFEAF6FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveRankingNameText(
    String name, {
    required Color color,
    required double maxFontSize,
  }) {
    return SizedBox(
      width: double.infinity,
      height: maxFontSize + 5,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            name,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: maxFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeasonFooter() {
    return Row(
      children: [
        _buildRemainingPill(_remainingLabel),
        const Spacer(),
        InkWell(
          onTap: () {
            _playUiTap();
            unawaited(_showPastSeasonsDialog());
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.42),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.amberAccent.withValues(alpha: 0.10),
                  blurRadius: 14,
                ),
              ],
            ),
            child: const Text(
              '過去シーズン',
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyFooter() {
    return Row(
      children: [
        _buildRemainingPill(_dailyRemainingLabel),
        const Spacer(),
        _buildFooterActionButton(
          label: '昨日の勝利数',
          onTap: _showYesterdayDailyRankingDialog,
        ),
      ],
    );
  }

  Widget _buildFooterActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        _playUiTap();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.amberAccent.withValues(alpha: 0.38),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.amberAccent.withValues(alpha: 0.08),
              blurRadius: 14,
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildRemainingPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Future<void> _showPastSeasonsDialog() async {
    final seasonIds = await _rankingManager.fetchArchivedSeasonIds();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: _buildSeasonDialogFrame(
            title: '過去シーズン',
            width: 360,
            child: seasonIds.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '確定済みのシーズンはまだありません',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: seasonIds.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final seasonId = seasonIds[index];
                      return _buildSeasonSelectButton(
                        seasonId: seasonId,
                        onTap: () {
                          _playUiTap();
                          Navigator.of(dialogContext).pop();
                          unawaited(_showSeasonRankingDialog(seasonId));
                        },
                      );
                    },
                  ),
            actions: [
              _buildSeasonDialogButton(
                label: '閉じる',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showYesterdayDailyRankingDialog() async {
    final nowJst = await ServerTimeManager.instance.nowJst();
    final yesterday = nowJst.subtract(const Duration(days: 1));
    final dateLabel =
        '${yesterday.month}/${yesterday.day} ${RankedSeasonManager.seasonName(
      RankedSeasonManager.currentSeasonId(nowJstOverride: yesterday),
    )}';
    final entries = await _rankingManager
        .fetchYesterdayDailyWinRankings()
        .timeout(_rankingOperationTimeout);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: _buildSeasonDialogFrame(
            title: '昨日の勝利数ランキング',
            width: 390,
            child: SizedBox(
              height: 420,
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        '$dateLabel のランキングデータがありません',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _buildRankingRow(
                          entry,
                          _displayDailyRankForEntries(entries, index),
                          _isCurrentPlayer(entry),
                          tab: _RankingTab.dailyWins,
                        );
                      },
                    ),
            ),
            actions: [
              _buildSeasonDialogButton(
                label: '閉じる',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSeasonRankingDialog(String seasonId) async {
    final entries = await _rankingManager.fetchSeasonRankings(seasonId);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: _buildSeasonDialogFrame(
            title: '${RankedSeasonManager.seasonName(seasonId)} ランキング',
            width: 390,
            child: SizedBox(
              height: 420,
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                        'ランキングデータがありません',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _buildCompactSeasonRankingRow(
                          entry,
                          entry.finalRank ?? _displayRankForEntries(index),
                        );
                      },
                    ),
            ),
            actions: [
              _buildSeasonDialogButton(
                label: '閉じる',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSeasonDialogFrame({
    required String title,
    required double width,
    required Widget child,
    required List<Widget> actions,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF101321),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.cyanAccent.withValues(alpha: 0.52),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.18),
              blurRadius: 28,
            ),
            BoxShadow(
              color: Colors.pinkAccent.withValues(alpha: 0.10),
              blurRadius: 36,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            child,
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeasonResultLog(String message) {
    final result = _SeasonResultViewData.fromLog(message);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.42),
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              Text(
                result.seasonName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              HexagonTrophyAmount(
                int.tryParse(result.rating) ?? 0,
                color: Colors.amberAccent,
                iconSize: 30,
                fontSize: 34,
              ),
              const SizedBox(height: 4),
              Text(
                'FINAL RATE',
                style: TextStyle(
                  color: Colors.cyanAccent.withValues(alpha: 0.78),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildSeasonResultMetric('RANK', result.rank)),
            const SizedBox(width: 8),
            Expanded(child: _buildSeasonResultMetric('RECORD', result.record)),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSeasonResultMetric('WIN RATE', result.winRate),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSeasonResultMetric(String label, String value) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  Widget _buildSeasonSelectButton({
    required String seasonId,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.amberAccent.withValues(alpha: 0.38),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    RankedSeasonManager.seasonName(seasonId),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    seasonId,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.cyanAccent,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeasonDialogButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
      child: Text(label),
    );
  }

  int _displayRankForEntries(int index) {
    return index + 1;
  }

  int _displayDailyRankForEntries(List<RankingEntry> entries, int index) {
    if (index <= 0) {
      return 1;
    }
    if (entries[index].dailyWins == entries[index - 1].dailyWins) {
      return _displayDailyRankForEntries(entries, index - 1);
    }
    return index + 1;
  }

  Widget _buildCompactSeasonRankingRow(RankingEntry entry, int rank) {
    return _buildRankingRow(
      entry,
      rank,
      _isCurrentPlayer(entry),
      tab: _RankingTab.currentSeason,
    );
  }
}

class _RankingPageTitle extends StatelessWidget {
  const _RankingPageTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
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
            fontSize: 18,
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
