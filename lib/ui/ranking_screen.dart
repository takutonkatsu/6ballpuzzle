import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../data/player_data_manager.dart';
import '../network/multiplayer_manager.dart';
import '../network/ranking_manager.dart';
import 'components/hexagon_currency_icons.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  final RankingManager _rankingManager = RankingManager.instance;
  final MultiplayerManager _multiplayerManager = MultiplayerManager.instance;

  bool _isLoading = true;
  List<RankingEntry> _entries = const [];
  String? _errorMessage;
  bool _showDailyWins = false;

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  @override
  void initState() {
    super.initState();
    _loadRankings();
  }

  Future<void> _loadRankings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final entries = _showDailyWins
          ? await _rankingManager.fetchTopDailyWinRankings(forceRefresh: true)
          : await _rankingManager.fetchTopRankings(forceRefresh: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _isLoading = false;
      });
    }
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.amberAccent.withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.amberAccent.withValues(alpha: 0.2),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HexagonTrophyIcon(size: 20),
              SizedBox(width: 8),
              Text(
                'ランキング',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _buildBackButton(context),
      ],
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        _playUiTap();
        Navigator.of(context).pop();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1B1F2E),
        foregroundColor: Colors.cyanAccent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.5)),
      ),
      icon: const Icon(Icons.arrow_back_ios_new, size: 16),
      label: const Text(
        '戻る',
        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
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
      padding: const EdgeInsets.all(14),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final rank = _displayRankAt(index);
        final isMe = _isCurrentPlayer(entry);
        return _buildRankingRow(entry, rank, isMe);
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
    final isSameScore = _showDailyWins
        ? current.dailyWins == previous.dailyWins
        : current.rating == previous.rating;
    if (isSameScore) {
      return _displayRankAt(index - 1);
    }
    return index + 1;
  }

  Widget _buildModeTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          _buildModeTab(
            label: '今シーズン',
            selected: !_showDailyWins,
            onTap: () {
              if (_showDailyWins) {
                _playUiTap();
                setState(() {
                  _showDailyWins = false;
                });
                unawaited(_loadRankings());
              }
            },
          ),
          _buildModeTab(
            label: '今日の勝利数',
            selected: _showDailyWins,
            onTap: () {
              if (!_showDailyWins) {
                _playUiTap();
                setState(() {
                  _showDailyWins = true;
                });
                unawaited(_loadRankings());
              }
            },
          ),
        ],
      ),
    );
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
            color: selected ? Colors.cyanAccent.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5))
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.cyanAccent : Colors.white70,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRankingRow(RankingEntry entry, int rank, bool isMe) {
    final accent = switch (rank) {
      1 => Colors.amberAccent,
      2 => const Color(0xFFE5E7EB),
      3 => const Color(0xFFCD7F32),
      _ => isMe ? Colors.pinkAccent : Colors.white24,
    };
    final backgroundColor = switch (rank) {
      1 => const Color(0x33D4AF37),
      2 => const Color(0x33C0C7D1),
      3 => const Color(0x33B87333),
      _ => isMe
          ? Colors.pinkAccent.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isMe || rank <= 3 ? 0.18 : 0.08),
            blurRadius: isMe || rank <= 3 ? 18 : 10,
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              '$rank',
              style: TextStyle(
                color:
                    rank <= 3 ? accent : Colors.white.withValues(alpha: 0.76),
                fontSize: rank <= 3 ? 16 : null,
                fontWeight: rank <= 3 ? FontWeight.w900 : FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    isMe ? Colors.white : Colors.white.withValues(alpha: 0.92),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _showDailyWins
              ? Text(
                  '${entry.dailyWins}勝',
                  style: TextStyle(
                    color: accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : HexagonTrophyAmount(
                  entry.rating,
                  color: Colors.amberAccent,
                  iconSize: 17,
                  fontSize: 16,
                ),
        ],
      ),
    );
  }
}
