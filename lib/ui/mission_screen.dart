import 'dart:async';

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../audio/sfx.dart';
import '../data/player_data_manager.dart';
import '../game/mission_catalog.dart';
import '../game/mission_manager.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/hexagon_grid_background.dart';
import 'components/rewarded_ad_manager.dart';

class MissionScreen extends StatefulWidget {
  const MissionScreen({super.key});

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  final MissionManager _missionManager = MissionManager.instance;
  final PlayerDataManager _playerData = PlayerDataManager.instance;
  bool _loading = true;
  final Set<String> _pressedClaimKeys = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _playerData.load();
    await _playerData.checkDailyReset();
    await _missionManager.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _runClaimWithPress(
    String key,
    Future<void> Function() action,
  ) async {
    if (_pressedClaimKeys.contains(key)) {
      return;
    }
    setState(() {
      _pressedClaimKeys.add(key);
    });
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (mounted) {
      setState(() {
        _pressedClaimKeys.remove(key);
      });
    }
    await action();
  }

  void _playUiTap() {
    AppSfx.playUiTap();
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
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () {
              _playUiTap();
              Navigator.of(context).pop();
            },
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _coinBadge()),
            ),
          ],
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x3325F4FF), Color(0x00000000)],
              ),
            ),
          ),
          title: const _MissionPageTitle(title: 'ミッション', subtitle: 'MISSION'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(62),
            child: _MissionNeonTabBar(tabs: ['デイリー', 'レギュラー']),
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
                      _dailyTab(),
                      _regularTab(),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _dailyTab() {
    final missions = _playerData.currentMissions;
    final completed = missions.where((mission) {
      final progress = (mission['progress'] as num?)?.toInt() ?? 0;
      final target = (mission['target'] as num?)?.toInt() ?? 0;
      return progress >= target;
    }).length;
    final adsRemoved = AppSettings.instance.adsRemoved.value;
    final showAllClearBonus = !adsRemoved && missions.isNotEmpty;
    final canClaimAllClearBonus = showAllClearBonus &&
        _missionManager.allMissionsComplete &&
        !_missionManager.isAllClearBonusClaimed;

    return _tabList(
      children: [
        _sectionHeader('$completed / ${missions.length} 達成'),
        for (var i = 0; i < missions.length; i++) ...[
          _dailyMissionTile(mission: missions[i]),
          if (i != missions.length - 1) const SizedBox(height: 10),
        ],
        if (showAllClearBonus) ...[
          const SizedBox(height: 14),
          _dailyAllClearBonusCard(
            canClaim: canClaimAllClearBonus,
            alreadyClaimed: _missionManager.isAllClearBonusClaimed,
          ),
        ],
      ],
    );
  }

  Widget _regularTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _missionManager.regularMissions(),
      builder: (context, snapshot) {
        final missions = snapshot.data ?? const [];
        if (missions.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          );
        }
        return _tabList(
          children: [
            for (var i = 0; i < missions.length; i++) ...[
              _regularMissionTile(mission: missions[i]),
              if (i != missions.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _tabList({required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: children,
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _coinBadge() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 78, maxWidth: 96),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          border: Border.all(
            color: Colors.cyanAccent.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.16),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            const HexagonCoinIcon(size: 16),
            const SizedBox(width: 4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '${_playerData.coins}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: const TextStyle(
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
    );
  }

  Widget _dailyMissionTile({required Map<String, dynamic> mission}) {
    final progress = (mission['progress'] as num?)?.toInt() ?? 0;
    final target = (mission['target'] as num?)?.toInt() ?? 0;
    final reward = _missionManager.rewardCoinsFor(mission);
    final claimed = mission['claimed'] as bool? ?? false;
    final isDone = progress >= target;
    final canClaim = isDone && !claimed;
    final adsRemoved = AppSettings.instance.adsRemoved.value;
    final missionId = mission['id']?.toString() ?? '';
    final isRewardedAdMission = MissionCatalog.isRewardedAdMissionId(missionId);
    final canReroll = !claimed && !canClaim && !isRewardedAdMission;

    return InkWell(
      onTap: claimed || canClaim || !isRewardedAdMission
          ? null
          : () async {
              _playUiTap();
              if (!adsRemoved) {
                final rewarded =
                    await RewardedAdManager.instance.showDoubleRewardAd();
                if (!rewarded) {
                  await _showAlert('広告エラー', '動画の視聴が完了しませんでした。');
                  return;
                }
              }
              await _missionManager.completeRewardedAdMissionById(missionId);
              await _load();
            },
      borderRadius: BorderRadius.circular(10),
      child: _missionContainer(
        canClaim: canClaim,
        isAdMission: isRewardedAdMission && !claimed,
        isDone: isDone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isRewardedAdMission) ...[
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 18,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    _missionDisplayTitle(mission),
                    style: TextStyle(
                      color: canClaim
                          ? Colors.lightBlueAccent
                          : isRewardedAdMission && !claimed
                              ? Colors.cyanAccent
                              : Colors.lightBlueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _rewardBadge(
                  reward: reward,
                  claimed: claimed,
                  canClaim: canClaim,
                  onPressed: canClaim
                      ? () async {
                          _playUiTap();
                          await _runClaimWithPress(
                            'daily:$missionId',
                            () async {
                              await _missionManager.claimMissionRewardById(
                                missionId,
                              );
                              await _load();
                            },
                          );
                        }
                      : null,
                  pressed: _pressedClaimKeys.contains('daily:$missionId'),
                ),
                if (canReroll) ...[
                  const SizedBox(width: 8),
                  _rerollButton(missionId: missionId, adsRemoved: adsRemoved),
                ],
              ],
            ),
            const SizedBox(height: 6),
            _progressRow(
              progress: progress,
              target: target,
              canClaim: canClaim,
              isDone: isDone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _regularMissionTile({required Map<String, dynamic> mission}) {
    final progress = (mission['progress'] as num?)?.toInt() ?? 0;
    final target = (mission['target'] as num?)?.toInt() ?? 0;
    final reward = (mission['rewardCoins'] as num?)?.toInt() ?? 0;
    final canClaim = mission['claimable'] as bool? ?? false;
    final progressKey = mission['progressKey']?.toString() ?? '';
    final isAdMission = progressKey == 'rewarded_ad_views';

    return InkWell(
      onTap: canClaim || !isAdMission
          ? null
          : () async {
              _playUiTap();
              if (AppSettings.instance.adsRemoved.value) {
                await _missionManager.recordRewardedAdView();
              } else {
                final rewarded =
                    await RewardedAdManager.instance.showDoubleRewardAd();
                if (!rewarded) {
                  await _showAlert('広告エラー', '動画の視聴が完了しませんでした。');
                  return;
                }
              }
              await _load();
            },
      borderRadius: BorderRadius.circular(10),
      child: _missionContainer(
        canClaim: canClaim,
        isAdMission: isAdMission && !canClaim,
        isDone: canClaim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isAdMission) ...[
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 18,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(child: _regularMissionTitle(mission)),
                const SizedBox(width: 8),
                _rewardBadge(
                  reward: reward,
                  claimed: false,
                  canClaim: canClaim,
                  onPressed: canClaim
                      ? () async {
                          _playUiTap();
                          final id = mission['id']?.toString() ?? '';
                          await _runClaimWithPress(
                            'regular:$id',
                            () async {
                              await _missionManager.claimRegularMissionReward(
                                id,
                              );
                              await _load();
                            },
                          );
                        }
                      : null,
                  pressed: _pressedClaimKeys.contains(
                    'regular:${mission['id']?.toString() ?? ''}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _progressRow(
              progress: progress,
              target: target,
              canClaim: canClaim,
              isDone: canClaim,
              progressKey: progressKey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _missionContainer({
    required bool canClaim,
    required bool isAdMission,
    required bool isDone,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: canClaim
            ? Colors.lightBlueAccent.withValues(alpha: 0.12)
            : isAdMission
                ? Colors.cyanAccent.withValues(alpha: 0.12)
                : isDone
                    ? Colors.lightBlueAccent.withValues(alpha: 0.15)
                    : Colors.cyanAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: canClaim
              ? Colors.lightBlueAccent.withValues(alpha: 0.48)
              : isAdMission
                  ? Colors.cyanAccent.withValues(alpha: 0.75)
                  : isDone
                      ? Colors.lightBlueAccent
                      : Colors.cyanAccent.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: null,
      ),
      child: child,
    );
  }

  Widget _rewardBadge({
    required int reward,
    required bool claimed,
    required bool canClaim,
    Future<void> Function()? onPressed,
    bool pressed = false,
  }) {
    final badge = AnimatedScale(
      scale: pressed ? 0.90 : 1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: canClaim
              ? (pressed ? const Color(0xFF0B5EA8) : const Color(0xFF1E88E5))
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: canClaim
                ? Colors.cyanAccent.withValues(alpha: pressed ? 1 : 0.75)
                : Colors.white.withValues(alpha: 0.2),
          ),
          boxShadow: canClaim
              ? [
                  BoxShadow(
                    color: Colors.lightBlueAccent.withValues(
                      alpha: pressed ? 0.10 : 0.28,
                    ),
                    blurRadius: pressed ? 4 : 12,
                  ),
                ]
              : null,
        ),
        child: claimed
            ? const Text(
                '受取済み',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canClaim) ...[
                    const Text(
                      '受け取る',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  HexagonCoinAmount(
                    reward,
                    color: canClaim ? Colors.white : Colors.white70,
                    iconSize: 13,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ],
              ),
      ),
    );
    if (!canClaim || onPressed == null || claimed) {
      return badge;
    }
    return InkWell(
      onTap: () => unawaited(onPressed()),
      borderRadius: BorderRadius.circular(999),
      child: badge,
    );
  }

  Widget _progressRow({
    required int progress,
    required int target,
    required bool canClaim,
    required bool isDone,
    String progressKey = '',
  }) {
    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: target == 0 ? 0 : (progress / target).clamp(0, 1),
            color: canClaim
                ? Colors.cyanAccent.withValues(alpha: 0.5)
                : isDone
                    ? Colors.lightBlueAccent
                    : Colors.cyanAccent.withValues(alpha: 0.5),
            backgroundColor: Colors.white12,
          ),
        ),
        const SizedBox(width: 10),
        _progressLabel(
          progress: progress,
          target: target,
          progressKey: progressKey,
        ),
      ],
    );
  }

  Widget _progressLabel({
    required int progress,
    required int target,
    required String progressKey,
  }) {
    if (progressKey == 'highest_rating') {
      return HexagonTrophyAmount(
        progress,
        suffix: ' / $target',
        color: Colors.white70,
        iconSize: 13,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      );
    }
    return Text(
      '$progress / $target',
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }

  Widget _regularMissionTitle(Map<String, dynamic> mission) {
    final progressKey = mission['progressKey']?.toString() ?? '';
    final target = (mission['target'] as num?)?.toInt() ?? 0;
    final title = mission['title']?.toString() ?? 'ミッション';
    final parts = title.split('〇〇');
    if (progressKey != 'highest_rating' || parts.length < 2) {
      return Text(
        title.replaceFirst('〇〇', '$target'),
        style: TextStyle(
          color: progressKey == 'rewarded_ad_views'
              ? Colors.cyanAccent
              : Colors.lightBlueAccent,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          parts.first,
          style: const TextStyle(
            color: Colors.lightBlueAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        HexagonTrophyAmount(
          target,
          iconSize: 14,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
        Text(
          parts.skip(1).join('〇〇'),
          style: const TextStyle(
            color: Colors.lightBlueAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _rerollButton({
    required String missionId,
    required bool adsRemoved,
  }) {
    return InkWell(
      onTap: () async {
        _playUiTap();
        if (!adsRemoved) {
          final rewarded =
              await RewardedAdManager.instance.showDoubleRewardAd();
          if (!rewarded) {
            await _showAlert('広告エラー', '動画の視聴が完了しませんでした。');
            return;
          }
        }
        try {
          await _missionManager.rerollMissionById(missionId);
          await _load();
        } catch (error) {
          await _showAlert('ERROR', '$error');
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 46,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.cyanAccent.withValues(alpha: 0.24),
              Colors.purpleAccent.withValues(alpha: 0.22),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.68)),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.18),
              blurRadius: 10,
            ),
            BoxShadow(
              color: Colors.purpleAccent.withValues(alpha: 0.14),
              blurRadius: 14,
            ),
          ],
        ),
        child: const Icon(
          Icons.sync_rounded,
          color: Colors.cyanAccent,
          size: 20,
        ),
      ),
    );
  }

  Widget _dailyAllClearBonusCard({
    required bool canClaim,
    required bool alreadyClaimed,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: canClaim
            ? Colors.cyanAccent.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: canClaim
              ? Colors.cyanAccent.withValues(alpha: 0.72)
              : Colors.white.withValues(alpha: 0.2),
          width: canClaim ? 1.5 : 1,
        ),
        boxShadow: canClaim
            ? [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.16),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            alreadyClaimed
                ? Icons.check_circle_rounded
                : Icons.ondemand_video_rounded,
            color: canClaim ? Colors.cyanAccent : Colors.white54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alreadyClaimed ? '全達成ボーナス受取済み' : '全達成ボーナス',
                  style: TextStyle(
                    color: canClaim ? Colors.cyanAccent : Colors.white70,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alreadyClaimed
                      ? '本日の受け取りは完了しています'
                      : canClaim
                          ? '動画広告を見ると今日の追加報酬を受け取れます'
                          : '4つすべて達成すると動画広告で受け取れます',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: !canClaim
                ? null
                : () async {
                    _playUiTap();
                    await _runClaimWithPress('all_clear', () async {
                      final rewarded =
                          await RewardedAdManager.instance.showDoubleRewardAd();
                      if (!rewarded) {
                        await _showAlert('広告エラー', '動画の視聴が完了しませんでした。');
                        return;
                      }
                      await _missionManager.claimAllClearBonus();
                      await _load();
                    });
                  },
            borderRadius: BorderRadius.circular(999),
            child: AnimatedScale(
              scale: _pressedClaimKeys.contains('all_clear') ? 0.90 : 1,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: canClaim
                      ? (_pressedClaimKeys.contains('all_clear')
                          ? const Color(0xFF0B5EA8)
                          : const Color(0xFF1E88E5))
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: canClaim
                        ? Colors.cyanAccent.withValues(alpha: 0.75)
                        : Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: HexagonCoinAmount(
                  _missionManager.allClearClaimAmount,
                  color: canClaim ? const Color(0xFFEAF6FF) : Colors.white54,
                  iconSize: 16,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
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

  Future<void> _showAlert(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151723),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.55)),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _playUiTap();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _MissionPageTitle extends StatelessWidget {
  const _MissionPageTitle({
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
            shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 12)],
          ),
        ),
      ],
    );
  }
}

class _MissionNeonTabBar extends StatelessWidget {
  const _MissionNeonTabBar({required this.tabs});

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
        onTap: (_) => AppSfx.playUiTap(),
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
        tabs: [for (final tab in tabs) Tab(text: tab)],
      ),
    );
  }
}
