import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../audio/sfx.dart';
import '../data/player_data_manager.dart';
import '../network/multiplayer_manager.dart';
import '../network/endless_season_manager.dart';
import '../network/ranked_season_manager.dart';
import '../network/ranking_manager.dart';
import '../network/server_time_manager.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/game_pressable.dart';
import 'components/screen_bottom_banner_ad.dart';
import 'profile_screen.dart';
import 'theme/game_theme_colors.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({
    super.key,
    this.embedded = false,
    this.active = true,
  });

  final bool embedded;
  final bool active;

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

class _RankingRewardRow {
  const _RankingRewardRow(this.label, this.amount);

  final String label;
  final int amount;
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
  bool _openingPlayerProfile = false;
  Timer? _remainingTimer;
  String _remainingLabel = '残り--';
  String _dailyRemainingLabel = '残り--';
  String _endlessRemainingLabel = '残り--';
  String _loadedSeasonId = '';
  String _loadedEndlessSeasonId = '';
  String _loadedDailyDateKey = '';
  DateTime? _lastSeasonSyncAt;
  bool _hasLoadedOnce = false;

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _activateRankingScreen();
    }
  }

  @override
  void didUpdateWidget(covariant RankingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _activateRankingScreen();
    } else if (oldWidget.active && !widget.active) {
      _remainingTimer?.cancel();
      _remainingTimer = null;
    }
  }

  @override
  void dispose() {
    _remainingTimer?.cancel();
    super.dispose();
  }

  void _activateRankingScreen() {
    _remainingTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_updateServerClockLabels()),
    );
    unawaited(_updateServerClockLabels(forceRefresh: true));
    if (!_hasLoadedOnce) {
      _loadRankings();
    }
  }

  Future<void> _loadRankings() async {
    if (!widget.active) {
      return;
    }
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
            .fetchTopRankings()
            .timeout(_rankingOperationTimeout),
        _RankingTab.dailyWins => await _rankingManager
            .fetchTopDailyWinRankings()
            .timeout(_rankingOperationTimeout),
        _RankingTab.endless => await _rankingManager
            .fetchTopEndlessScoreRankings()
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
      final loadedEndlessSeasonId =
          EndlessSeasonManager.currentSeasonId(nowJstOverride: nowJst);
      setState(() {
        _entries = entries;
        _loadedSeasonId = loadedSeasonId;
        _loadedEndlessSeasonId = loadedEndlessSeasonId;
        _loadedDailyDateKey = RankingManager.todayKeyJst(
          nowJstOverride: nowJst,
        );
        _isLoading = false;
        _hasLoadedOnce = true;
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
        _hasLoadedOnce = true;
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
      final currentEndlessSeasonId =
          EndlessSeasonManager.currentSeasonId(nowJstOverride: nowJst);
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
        _endlessRemainingLabel =
            RankingManager.endlessRemainingLabel(nowJstOverride: nowJst);
      });
      if (widget.active &&
          (currentSeasonId != _loadedSeasonId ||
              (_selectedTab == _RankingTab.endless &&
                  currentEndlessSeasonId != _loadedEndlessSeasonId) ||
              (_selectedTab == _RankingTab.dailyWins &&
                  currentDailyDateKey != _loadedDailyDateKey))) {
        unawaited(_loadRankings());
      }
    } catch (_) {
      // サーバー時刻の一時取得失敗では、ランキング画面の表示を止めない。
    }
  }

  Future<void> _syncCurrentSeasonBeforeLoad() async {
    final lastSync = _lastSeasonSyncAt;
    final shouldSync =
        lastSync == null || DateTime.now().difference(lastSync).inMinutes >= 5;
    if (shouldSync) {
      try {
        await _rankingManager
            .syncSeasonStateForCurrentPlayer()
            .timeout(_rankingOperationTimeout);
        _lastSeasonSyncAt = DateTime.now();
      } catch (_) {
        // シーズン同期に失敗しても、ランキングの読み込み自体は試す。
      }
    }
    await PlayerDataManager.instance.load();
    await _showSeasonResultLogIfNeeded();
    final seasonRating = PlayerDataManager.instance.currentRating;
    _multiplayerManager.currentRating = seasonRating;
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
    final content = SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.embedded ? 12 : 16,
          16,
          widget.embedded ? 8 : 20,
        ),
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
                      color: GameThemeColors.cyan.withValues(alpha: 0.45),
                    )),
                child: _buildBody(),
              ),
            ),
            if (_selectedTab == _RankingTab.currentSeason ||
                _selectedTab == _RankingTab.dailyWins ||
                _selectedTab == _RankingTab.endless) ...[
              const SizedBox(height: 10),
              switch (_selectedTab) {
                _RankingTab.dailyWins => _buildDailyFooter(),
                _RankingTab.endless => _buildEndlessFooter(),
                _RankingTab.currentSeason => _buildSeasonFooter(),
              },
            ],
          ],
        ),
      ),
    );
    if (widget.embedded) {
      return content;
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      bottomNavigationBar: const ScreenBottomBannerAd(),
      body: content,
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
            child: widget.embedded
                ? const SizedBox(width: 44, height: 44)
                : SizedBox(
                    width: 44,
                    height: 44,
                    child: _buildBackButton(context),
                  ),
          ),
          Positioned(
            right: 0,
            child: _buildRewardInfoButton(),
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
    return GamePressable(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        _playUiTap();
        Navigator.of(context).pop();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildRewardInfoButton() {
    return GamePressable(
      onTap: () {
        _playUiTap();
        unawaited(_showRankingRewardDialog());
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: GameThemeColors.cyan.withValues(alpha: 0.46),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.card_giftcard_rounded,
              color: GameThemeColors.cyan,
              size: 18,
            ),
            SizedBox(width: 4),
            Text(
              '報酬',
              style: TextStyle(
                color: GameThemeColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRankingRewardDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: _buildSeasonDialogFrame(
            title: 'ランキング報酬',
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rankingRewardSection(
                  title: 'ランク戦',
                  subtitle: 'シーズン終了後 / 100位まで',
                  rows: const [
                    _RankingRewardRow('1位', 300000),
                    _RankingRewardRow('2〜3位', 150000),
                    _RankingRewardRow('4〜10位', 80000),
                    _RankingRewardRow('11〜30位', 30000),
                    _RankingRewardRow('31〜50位', 10000),
                    _RankingRewardRow('51〜100位', 5000),
                  ],
                ),
                const SizedBox(height: 12),
                _rankingRewardSection(
                  title: 'エンドレス',
                  subtitle: '週間ランキング終了後 / 50位まで',
                  rows: const [
                    _RankingRewardRow('1位', 100000),
                    _RankingRewardRow('2〜3位', 50000),
                    _RankingRewardRow('4〜10位', 25000),
                    _RankingRewardRow('11〜30位', 10000),
                    _RankingRewardRow('31〜50位', 5000),
                  ],
                ),
                const SizedBox(height: 12),
                _rankingRewardSection(
                  title: '今日の勝利数',
                  subtitle: '日付変更後 / 10位まで',
                  rows: const [
                    _RankingRewardRow('1位', 50000),
                    _RankingRewardRow('2〜3位', 20000),
                    _RankingRewardRow('4〜10位', 5000),
                  ],
                ),
              ],
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

  Widget _rankingRewardSection({
    required String title,
    required String subtitle,
    required List<_RankingRewardRow> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: GameThemeColors.cyan.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: GameThemeColors.cyan,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  HexagonCoinAmount(
                    row.amount,
                    iconSize: 15,
                    fontSize: 13,
                    color: const Color(0xFFEAF6FF),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SizedBox.shrink();
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

    final myIndex = _entries.indexWhere(_isCurrentPlayer);
    final myEntry = myIndex == -1 ? null : _entries[myIndex];
    final myRank = myIndex == -1 ? null : _displayRankAt(myIndex);
    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                14,
                12,
                14,
                myEntry == null ? 18 : 86,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    _buildCompetitionSummary(myEntry, myRank),
                    const SizedBox(height: 12),
                    if (_entries.length >= 3) ...[
                      _buildTopPodium(),
                      const SizedBox(height: 12),
                    ],
                    for (var index = _entries.length >= 3 ? 3 : 0;
                        index < _entries.length;
                        index++) ...[
                      _buildRankingRow(
                        _entries[index],
                        _displayRankAt(index),
                        _isCurrentPlayer(_entries[index]),
                        tab: _selectedTab,
                      ),
                      if (index != _entries.length - 1)
                        const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (myEntry != null && myRank != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildMyRankDock(myEntry, myRank),
          ),
      ],
    );
  }

  Widget _buildCompetitionSummary(RankingEntry? myEntry, int? myRank) {
    final accent = switch (_selectedTab) {
      _RankingTab.currentSeason => GameThemeColors.ranked,
      _RankingTab.dailyWins => GameThemeColors.rankedText,
      _RankingTab.endless => GameThemeColors.endless,
    };
    final rewardLine = switch (_selectedTab) {
      _RankingTab.currentSeason => '報酬対象: 100位まで',
      _RankingTab.dailyWins => '報酬対象: 10位まで',
      _RankingTab.endless => '報酬対象: 50位まで',
    };
    final primaryLabel = switch (_selectedTab) {
      _RankingTab.currentSeason => 'シーズンレート',
      _RankingTab.dailyWins => '今日のランク戦勝利数',
      _RankingTab.endless => '今週の最高スコア',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: accent.withValues(alpha: 0.48)),
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              color: accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  rewardLine,
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.88),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                const Text(
                  'あなた',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  myRank == null ? '圏外' : '$myRank位',
                  style: TextStyle(
                    color: myEntry == null ? Colors.white54 : accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPodium() {
    final first = _entries[0];
    final second = _entries[1];
    final third = _entries[2];
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _buildPodiumCard(
              entry: second,
              rank: _displayRankAt(1),
              height: 126,
              color: const Color(0xFFDCE8FF),
              maxNameFontSize: 17,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildPodiumCard(
              entry: first,
              rank: 1,
              height: 150,
              color: const Color(0xFFFFD85A),
              isChampion: true,
              maxNameFontSize: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildPodiumCard(
              entry: third,
              rank: _displayRankAt(2),
              height: 118,
              color: const Color(0xFFFFA35A),
              maxNameFontSize: 17,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumCard({
    required RankingEntry entry,
    required int rank,
    required double height,
    required Color color,
    bool isChampion = false,
    required double maxNameFontSize,
  }) {
    return GamePressable(
      borderRadius: BorderRadius.circular(14),
      onTap: () => unawaited(_openPlayerProfile(entry, rank, _selectedTab)),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isChampion ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: isChampion ? 0.92 : 0.62),
            width: isChampion ? 1.8 : 1.2,
          ),
        ),
        child: Column(
          children: [
            Text(
              '$rank位',
              style: TextStyle(
                color: color,
                fontSize: isChampion ? 18 : 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Center(
                child: _buildResponsiveRankingNameText(
                  entry.displayName,
                  color: Colors.white,
                  maxFontSize: maxNameFontSize,
                  alignment: Alignment.center,
                ),
              ),
            ),
            _buildRankingValue(entry, color, _selectedTab),
          ],
        ),
      ),
    );
  }

  Widget _buildMyRankDock(RankingEntry entry, int rank) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF050810).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GameThemeColors.cyan.withValues(alpha: 0.82),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _buildRankingRow(
        entry,
        rank,
        true,
        tab: _selectedTab,
        dense: true,
        forceStandardStyle: true,
      ),
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
          border:
              Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.28))),
      child: Row(
        children: [
          _buildModeTab(
            label: _seasonTabLabel(),
            subLabel: _seasonPeriodTabLabel(),
            selected: _selectedTab == _RankingTab.currentSeason,
            onTap: () => _selectTab(_RankingTab.currentSeason),
          ),
          _buildModeTab(
            label: 'エンドレス',
            subLabel: '今週のランキング',
            selected: _selectedTab == _RankingTab.endless,
            onTap: () => _selectTab(_RankingTab.endless),
          ),
          _buildModeTab(
            label: '今日の勝利数',
            subLabel: 'ランク戦',
            selected: _selectedTab == _RankingTab.dailyWins,
            onTap: () => _selectTab(_RankingTab.dailyWins),
          ),
        ],
      ),
    );
  }

  String _seasonTabLabel() {
    final seasonId = _loadedSeasonId.trim();
    if (seasonId.isEmpty) {
      return 'シーズン';
    }
    return RankedSeasonManager.seasonName(seasonId);
  }

  String? _seasonPeriodTabLabel() {
    final seasonId = _loadedSeasonId.trim();
    if (seasonId.isEmpty) {
      return null;
    }
    final end = RankedSeasonManager.seasonEndJst(seasonId);
    return '${end.year}年${end.month}月期';
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
    String? subLabel,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GamePressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 54,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      GameThemeColors.cyan.withValues(alpha: 0.35),
                      const Color(0xFF0B84FF).withValues(alpha: 0.28),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(
                    color: GameThemeColors.cyan.withValues(alpha: 0.85))
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              if (subLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  subLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.82)
                        : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
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
    bool dense = false,
    bool forceStandardStyle = false,
  }) {
    final accent = switch (rank) {
      1 => const Color(0xFFFFD85A),
      2 => const Color(0xFFDCE8FF),
      3 => const Color(0xFFFFA35A),
      _ => GameThemeColors.cyan,
    };
    final rankIsTop = rank <= 3 && !forceStandardStyle;
    final topFillColor = switch (rank) {
      1 => const Color(0xFF4A3714),
      2 => const Color(0xFF303A4F),
      3 => const Color(0xFF4A2416),
      _ => const Color(0xFF101827),
    };

    return GamePressable(
      borderRadius: BorderRadius.circular(12),
      onTap: () => unawaited(_openPlayerProfile(entry, rank, tab)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: BoxConstraints(minHeight: dense ? 50 : 58),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 7 : 9,
        ),
        decoration: BoxDecoration(
            color: rankIsTop ? topFillColor.withValues(alpha: 0.98) : null,
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
              color: accent.withValues(alpha: rankIsTop ? 0.9 : 0.24),
              width: rankIsTop ? 1.5 : 1,
            )),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: rankIsTop ? 0.34 : 0.20),
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

  Future<void> _openPlayerProfile(
    RankingEntry entry,
    int rank,
    _RankingTab tab,
  ) async {
    if (_openingPlayerProfile) {
      return;
    }
    _openingPlayerProfile = true;
    _playUiTap();
    try {
      final rankLabel = tab == _RankingTab.currentSeason ? '$rank位' : null;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            playerUid: entry.uid,
            initialEntry: entry,
            initialRankLabel: rankLabel,
          ),
        ),
      );
    } finally {
      _openingPlayerProfile = false;
    }
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
            _formatNumber(entry.highestEndlessScore),
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
    Alignment alignment = Alignment.centerLeft,
  }) {
    return SizedBox(
      width: double.infinity,
      height: maxFontSize + 7,
      child: Align(
        alignment: alignment,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(
            name,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
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
        _buildRemainingPill(
          _remainingLabel,
          onTap: () => unawaited(_showRemainingDetailDialog()),
        ),
        const Spacer(),
        GamePressable(
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
                  color: GameThemeColors.cyan.withValues(alpha: 0.42),
                )),
            child: const Text(
              '過去シーズン',
              style: TextStyle(
                color: GameThemeColors.cyan,
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
        _buildRemainingPill(
          _dailyRemainingLabel,
          onTap: () => unawaited(_showRemainingDetailDialog()),
        ),
        const Spacer(),
        _buildFooterActionButton(
          label: '昨日の勝利数',
          onTap: _showYesterdayDailyRankingDialog,
        ),
      ],
    );
  }

  Widget _buildEndlessFooter() {
    return Row(
      children: [
        _buildRemainingPill(
          _endlessRemainingLabel,
          onTap: () => unawaited(_showRemainingDetailDialog()),
        ),
        const Spacer(),
        _buildFooterActionButton(
          label: '全期間ランキング',
          onTap: _showAllTimeEndlessRankingDialog,
        ),
      ],
    );
  }

  Widget _buildFooterActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GamePressable(
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
              color: GameThemeColors.cyan.withValues(alpha: 0.38),
            )),
        child: Text(
          label,
          style: const TextStyle(
            color: GameThemeColors.cyan,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildRemainingPill(String label, {VoidCallback? onTap}) {
    return GamePressable(
      onTap: onTap == null
          ? null
          : () {
              _playUiTap();
              onTap();
            },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: GameThemeColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 5),
              const Icon(
                Icons.info_outline_rounded,
                color: GameThemeColors.cyan,
                size: 14,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRemainingDetailDialog() async {
    Timer? timer;
    try {
      var nowJst = await ServerTimeManager.instance.nowJst(forceRefresh: true);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
                setDialogState(() {
                  nowJst = nowJst.add(const Duration(seconds: 1));
                });
              });
              final seasonId =
                  RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
              final seasonRemaining =
                  RankedSeasonManager.remaining(nowJstOverride: nowJst);
              final dailyRemaining = _dailyRemaining(nowJst);
              final endlessSeasonId =
                  EndlessSeasonManager.currentSeasonId(nowJstOverride: nowJst);
              final endlessRemaining =
                  EndlessSeasonManager.remaining(nowJstOverride: nowJst);
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: _buildSeasonDialogFrame(
                  title: '残り時間',
                  width: 330,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _remainingDetailRow(
                        RankedSeasonManager.seasonName(seasonId),
                        _formatDurationDetail(seasonRemaining),
                      ),
                      const SizedBox(height: 10),
                      _remainingDetailRow(
                        _endlessWeekLabel(endlessSeasonId),
                        _formatDurationDetail(endlessRemaining),
                      ),
                      const SizedBox(height: 10),
                      _remainingDetailRow(
                        '今日の勝利数',
                        _formatDurationDetail(dailyRemaining),
                      ),
                    ],
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
        },
      );
    } catch (_) {
      // 詳細時刻の一時取得失敗では、ランキング画面の表示を止めない。
    } finally {
      timer?.cancel();
    }
  }

  Widget _remainingDetailRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: GameThemeColors.cyan,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Duration _dailyRemaining(DateTime nowJst) {
    final wallClockNow = DateTime.utc(
      nowJst.year,
      nowJst.month,
      nowJst.day,
      nowJst.hour,
      nowJst.minute,
      nowJst.second,
      nowJst.millisecond,
      nowJst.microsecond,
    );
    final nextDay = DateTime.utc(nowJst.year, nowJst.month, nowJst.day + 1);
    final remaining = nextDay.difference(wallClockNow);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatDurationDetail(Duration value) {
    final days = value.inDays;
    final hours = value.inHours.remainder(24);
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    final hourText = hours.toString().padLeft(2, '0');
    final minuteText = minutes.toString().padLeft(2, '0');
    final secondText = seconds.toString().padLeft(2, '0');
    if (days > 0) {
      return '$days日 $hourText時間 $minuteText分 $secondText秒';
    }
    if (hours > 0) {
      return '$hourText時間 $minuteText分 $secondText秒';
    }
    if (minutes > 0) {
      return '$minuteText分 $secondText秒';
    }
    return '$secondText秒';
  }

  String _endlessWeekLabel(String seasonId) {
    final match = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(seasonId);
    if (match == null) {
      return EndlessSeasonManager.seasonName(seasonId);
    }
    final year = match.group(1) ?? '';
    final week = int.tryParse(match.group(2) ?? '') ?? 0;
    if (year.isEmpty || week <= 0) {
      return EndlessSeasonManager.seasonName(seasonId);
    }
    return '$year年第$week週';
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

  Future<void> _showAllTimeEndlessRankingDialog() async {
    final entries = await _rankingManager.fetchAllTimeEndlessScoreRankings();
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
            title: 'エンドレス 全期間ランキング',
            width: 390,
            child: SizedBox(
              height: 420,
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                        'ランキングデータがありません',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _buildCompactEndlessRankingRow(
                          entry,
                          _displayEndlessRankForEntries(entries, index),
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
                          _displaySeasonRankForEntries(entries, index),
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
              color: GameThemeColors.cyan.withValues(alpha: 0.52),
              width: 1.4,
            )),
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
            color: GameThemeColors.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: GameThemeColors.cyan.withValues(alpha: 0.42),
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
                  color: GameThemeColors.cyan.withValues(alpha: 0.78),
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
    String? label,
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
                    label ?? RankedSeasonManager.seasonName(seasonId),
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
              color: GameThemeColors.cyan,
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
      child: Text(AppSettings.instance.translate(label)),
    );
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

  int _displaySeasonRankForEntries(List<RankingEntry> entries, int index) {
    if (index <= 0) {
      return 1;
    }
    if (entries[index].rating == entries[index - 1].rating) {
      return _displaySeasonRankForEntries(entries, index - 1);
    }
    return index + 1;
  }

  int _displayEndlessRankForEntries(List<RankingEntry> entries, int index) {
    if (index <= 0) {
      return 1;
    }
    if (entries[index].highestEndlessScore ==
        entries[index - 1].highestEndlessScore) {
      return _displayEndlessRankForEntries(entries, index - 1);
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

  Widget _buildCompactEndlessRankingRow(RankingEntry entry, int rank) {
    return _buildRankingRow(
      entry,
      rank,
      _isCurrentPlayer(entry),
      tab: _RankingTab.endless,
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: GameThemeColors.cyan,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 3.5,
          ),
        ),
        Text(
          AppSettings.instance.translate(title),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
