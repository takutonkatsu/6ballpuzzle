import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../audio/sfx.dart';
import '../data/models/badge_item.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../firebase_database_provider.dart';
import '../moderation/moderation_manager.dart';
import '../network/multiplayer_manager.dart';
import '../network/ranking_manager.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/player_icon_image.dart';
import 'components/season_rank_badge_icon.dart';
import 'theme/game_theme_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.playerUid,
    this.initialEntry,
    this.initialRankLabel,
  });

  final String? playerUid;
  final RankingEntry? initialEntry;
  final String? initialRankLabel;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const int _nameChangeCost = 10000;

  final PlayerDataManager _playerData = PlayerDataManager.instance;
  final MultiplayerManager _multiplayerManager = MultiplayerManager.instance;
  final RankingManager _rankingManager = RankingManager.instance;
  bool _loading = true;
  _ProfileViewData? _profile;
  bool _showAllOwnedBadges = false;
  OverlayEntry? _badgeInfoOverlay;

  bool get _isOwnProfile {
    final playerUid = widget.playerUid;
    final myUid = _multiplayerManager.myUid;
    return playerUid == null ||
        playerUid.isEmpty ||
        (myUid != null && playerUid == myUid);
  }

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  @override
  void dispose() {
    _dismissBadgeInfoOverlay();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isOwnProfile) {
      await _loadRemoteProfile();
      return;
    }

    await _playerData.load();
    var currentRankLabel =
        _rankingManager.cachedMySummary()?.ratingRankLabel ?? '未取得';
    if (_playerData.currentRating <= MultiplayerManager.initialRating) {
      currentRankLabel = '圏外';
    } else if (currentRankLabel == '未取得') {
      try {
        currentRankLabel = await _rankingManager.fetchRatingRankLabelForPlayer(
          uid: _multiplayerManager.myUid ?? '',
          publicId: _playerData.playerId,
        );
      } catch (_) {
        currentRankLabel = '未取得';
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = _ProfileViewData.fromLocal(
        _playerData,
        currentRankLabel: currentRankLabel,
      );
      _loading = false;
    });
  }

  Future<void> _loadRemoteProfile() async {
    _ProfileViewData? profile;
    final rankLabel = await _fetchRemoteRankLabel();
    final uid = widget.playerUid ?? widget.initialEntry?.uid ?? '';
    final publicId = widget.initialEntry?.publicId ?? '';
    final currentEntry = widget.initialEntry;
    final fallbackEntry = currentEntry;
    try {
      if (uid.isNotEmpty) {
        final snapshot =
            await AppFirebaseDatabase.ref().child('publicProfiles/$uid').get();
        final raw = snapshot.value;
        if (raw is Map) {
          profile = _ProfileViewData.fromRecordSummary(
            Map<dynamic, dynamic>.from(raw),
            fallbackEntry: fallbackEntry,
            currentRankLabel: rankLabel,
          );
        }
      }
    } catch (_) {
      profile = null;
    }
    if (profile == null) {
      try {
        if (uid.isNotEmpty) {
          final snapshot = await AppFirebaseDatabase.ref()
              .child('playerRecordSummaries/$uid')
              .get();
          final raw = snapshot.value;
          if (raw is Map) {
            profile = _ProfileViewData.fromRecordSummary(
              Map<dynamic, dynamic>.from(raw),
              fallbackEntry: fallbackEntry,
              currentRankLabel: rankLabel,
            );
          }
        }
      } catch (_) {
        profile = null;
      }
    }
    profile ??= _ProfileViewData.fromRankingEntry(
      fallbackEntry,
      currentRankLabel: rankLabel,
    );
    final currentEntryFromRanking = await _fetchCurrentRankingEntry(
      uid: uid,
      publicId: publicId,
    );
    profile = profile.withCurrentProfileFields(
      rankingEntry: currentEntryFromRanking ?? currentEntry,
    );
    final seasonBadges = await _fetchRemoteSeasonRankBadges(profile);
    if (seasonBadges.isNotEmpty) {
      profile = profile.copyWithSeasonRankBadges(seasonBadges);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  Future<RankingEntry?> _fetchCurrentRankingEntry({
    required String uid,
    required String publicId,
  }) async {
    try {
      return await _rankingManager.fetchCurrentEntryForPlayer(
        uid: uid,
        publicId: publicId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchRemoteRankLabel() async {
    try {
      return await _rankingManager.fetchRatingRankLabelForPlayer(
        uid: widget.playerUid ?? widget.initialEntry?.uid ?? '',
        publicId: widget.initialEntry?.publicId ?? '',
      );
    } catch (_) {
      return widget.initialRankLabel ?? '圏外';
    }
  }

  Future<List<SeasonRankBadge>> _fetchRemoteSeasonRankBadges(
    _ProfileViewData profile,
  ) async {
    try {
      return await _rankingManager.fetchSeasonRankBadgesForPlayer(
        uid: widget.playerUid ?? widget.initialEntry?.uid ?? '',
        publicId: profile.publicId.isNotEmpty
            ? profile.publicId
            : widget.initialEntry?.publicId ?? '',
      );
    } catch (_) {
      return profile.seasonRankBadges;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070912),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            _playUiTap();
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
        title: const _ProfilePageTitle(
          title: 'プロフィール',
          subtitle: 'PLAYER PROFILE',
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _ScanlineBackground()),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: GameThemeColors.cyan),
            )
          else
            SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  _dismissBadgeInfoOverlay();
                },
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildIdentityCard(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    final profile = _profile;
    if (profile == null) {
      return _emptyPanel('プロフィールを読み込めませんでした');
    }
    final equippedBadges = profile.equippedBadgeIds
        .map(_badgeDisplayForId)
        .whereType<_BadgeDisplay>()
        .toList();
    final ownedBadges = _ownedBadgeDisplays(profile);
    final currentRank = profile.currentRankLabel;

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF101423).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: GameThemeColors.cyan, width: 1.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileHeader(profile, equippedBadges),
          const SizedBox(height: 20),
          _sectionTitle('基本情報'),
          const SizedBox(height: 10),
          _buildMetricGrid(
            [
              _MetricData(
                label: 'バトル勝利数',
                value: _formatNumber(profile.totalWins),
                color: Colors.white,
              ),
              _MetricData(
                label: 'レベル',
                value: '${profile.level}',
                color: Colors.white,
              ),
              _MetricData(
                label: '現在のレート',
                value: _formatNumber(profile.currentRating),
                color: Colors.amberAccent,
                showTrophy: true,
              ),
              _MetricData(
                label: '現在の順位',
                value: currentRank,
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle('所持バッジ一覧'),
          const SizedBox(height: 10),
          _buildOwnedBadgeList(ownedBadges),
          const SizedBox(height: 22),
          _sectionTitle('これまでの戦績'),
          const SizedBox(height: 10),
          _buildCareerRecord(),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(
    _ProfileViewData profile,
    List<_BadgeDisplay> equippedBadges,
  ) {
    final iconFrameColor = _playerIconFrameColor(profile.playerIconFrameId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPlayerIconAvatar(
              iconId: profile.playerIconId,
              frameId: profile.playerIconFrameId,
              color: iconFrameColor,
              size: 62,
              iconSize: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: SizedBox(
                height: 62,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _profileNameText(profile.displayName),
                          ),
                          const SizedBox(width: 4),
                          if (_isOwnProfile)
                            IconButton(
                              tooltip: '名前変更',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 34,
                              ),
                              onPressed: () {
                                _playUiTap();
                                unawaited(_editName());
                              },
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.white70,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _buildEquippedBadges(equippedBadges),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _smallInfoLine('プレイヤーID：', profile.publicId),
      ],
    );
  }

  Widget _buildPlayerIconAvatar({
    required String iconId,
    required String frameId,
    required Color color,
    required double size,
    required double iconSize,
  }) {
    final icon = PlayerIconImage(
      iconId: iconId,
      fallbackIcon: _playerIconData(iconId),
      color: Colors.white,
      size: iconSize,
    );
    final innerBackgroundColor = playerIconInnerBackgroundColor(
      iconId,
      const Color(0xFF111827),
      frameId: frameId,
    );
    if (GameItemCatalog.byId(frameId)?.colorName == 'rainbow') {
      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              Color(0xFFFF4D6D),
              Color(0xFFFFD54A),
              Color(0xFF35F0FF),
              Color(0xFFB91DFF),
              Color(0xFFFF4D6D),
            ],
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: innerBackgroundColor,
            shape: BoxShape.circle,
          ),
          child: Center(child: icon),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: playerIconInnerBackgroundColor(
          iconId,
          color.withValues(alpha: 0.12),
          frameId: frameId,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: icon,
    );
  }

  Widget _profileNameText(String name) {
    return SizedBox(
      height: 30,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            name,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallInfoLine(String label, String value) {
    return Text(
      '$label$value',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildEquippedBadges(List<_BadgeDisplay> badges) {
    final shownBadges = badges.take(3).toList();
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          for (final badge in shownBadges) ...[
            Builder(
              builder: (badgeContext) => InkWell(
                onTap: () {
                  _playUiTap();
                  _showBadgeInfoPopup(badgeContext, badge);
                },
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(child: badge.icon),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildBadgeInfoPopup(_BadgeDisplay badge) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xF20D1424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.58)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _popupFittedLine(
            badge.label,
            color: Colors.white,
            fontSize: 11.5,
          ),
          const SizedBox(height: 4),
          _popupFittedLine(
            badge.detail,
            color: Colors.white70,
            fontSize: 10,
            height: 14,
          ),
        ],
      ),
    );
  }

  Widget _popupFittedLine(
    String text, {
    required Color color,
    required double fontSize,
    double? height,
  }) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _dismissBadgeInfoOverlay() {
    _badgeInfoOverlay?.remove();
    _badgeInfoOverlay = null;
  }

  void _showBadgeInfoPopup(BuildContext anchorContext, _BadgeDisplay badge) {
    _dismissBadgeInfoOverlay();
    final overlay = Overlay.of(context);
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) {
      return;
    }
    final anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    const width = 150.0;
    const estimatedHeight = 62.0;
    final left = (anchorTopLeft.dx + anchorBox.size.width / 2 - width / 2)
        .clamp(12.0, max(12.0, overlayBox.size.width - width - 12))
        .toDouble();
    var top = anchorTopLeft.dy + anchorBox.size.height + 8;
    if (top + estimatedHeight > overlayBox.size.height - 12) {
      top = max(12.0, anchorTopLeft.dy - estimatedHeight - 8);
    }
    _badgeInfoOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissBadgeInfoOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Material(
              color: Colors.transparent,
              child: _buildBadgeInfoPopup(badge),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_badgeInfoOverlay!);
  }

  Widget _buildMetricGrid(List<_MetricData> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 2;
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                child: _profileMetric(
                  label: metric.label,
                  value: metric.value,
                  color: metric.color,
                  showTrophy: metric.showTrophy,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildRecordGrid(List<_MetricData> records) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 2;
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final record in records)
              SizedBox(
                width: itemWidth,
                child: _recordTile(
                  record.label,
                  record.value,
                  showTrophy: record.showTrophy,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBadgeGrid(List<_BadgeDisplay> badges) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 4;
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * 6)) / columns;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final badge in badges)
              SizedBox(
                width: itemWidth,
                child: Builder(
                  builder: (badgeContext) => GestureDetector(
                    onTap: () {
                      _playUiTap();
                      _showBadgeInfoPopup(badgeContext, badge);
                    },
                    child: _ownedBadgeChip(badge),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _profileMetric({
    required String label,
    required String value,
    required Color color,
    bool showTrophy = false,
  }) {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.34))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppSettings.instance.translate(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          if (showTrophy)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: HexagonTrophyAmount(
                int.tryParse(value.replaceAll(',', '')) ?? 0,
                color: color,
                iconSize: 20,
                fontSize: 22,
              ),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  _BadgeDisplay? _badgeDisplayForId(String id) {
    final seasonBadge = SeasonRankBadge.fromId(id);
    if (seasonBadge != null) {
      return _BadgeDisplay(
        id: id,
        label: seasonBadge.label,
        detail: seasonBadge.seasonName,
        color: Colors.amberAccent,
        icon: SeasonRankBadgeIcon(
          rank: seasonBadge.rank,
          kind: seasonBadge.kind,
          size: 40,
        ),
        rank: seasonBadge.rank,
      );
    }
    final badge = BadgeCatalog.findById(id);
    if (badge == null) {
      return null;
    }
    return _BadgeDisplay(
      id: id,
      label: badge.label,
      detail: badge.unlockedCondition.description,
      color: badge.frameColor,
      icon: Icon(badge.icon, color: badge.frameColor, size: 40),
      isProgressBadge: _isProgressOwnedBadge(badge),
    );
  }

  List<_BadgeDisplay> _ownedBadgeDisplays(_ProfileViewData profile) {
    final displays = <_BadgeDisplay>[];
    final unlocked = profile.unlockedBadgeIds.toSet();
    for (final badge in BadgeCatalog.visibleBadgesFor(unlocked)) {
      if (!unlocked.contains(badge.id)) {
        continue;
      }
      final display = _badgeDisplayForId(badge.id);
      if (display != null) {
        displays.add(display);
      }
    }
    for (final badge in profile.seasonRankBadges) {
      if (badge.seasonId.isEmpty || badge.rank <= 0) {
        continue;
      }
      displays.add(
        _BadgeDisplay(
          id: badge.id,
          label: badge.label,
          detail: badge.seasonName,
          color: Colors.amberAccent,
          icon: SeasonRankBadgeIcon(
            rank: badge.rank,
            kind: badge.kind,
            size: 40,
          ),
          rank: badge.rank,
        ),
      );
    }
    displays.sort(_compareOwnedBadges);
    return displays;
  }

  bool _isProgressOwnedBadge(BadgeItem badge) {
    return badge.unlockedCondition.type == BadgeUnlockType.totalMatches ||
        badge.unlockedCondition.type == BadgeUnlockType.wazaCount;
  }

  int _compareOwnedBadges(_BadgeDisplay a, _BadgeDisplay b) {
    final groupDiff = _badgeSortGroup(a).compareTo(_badgeSortGroup(b));
    if (groupDiff != 0) {
      return groupDiff;
    }
    if (a.rank != null || b.rank != null) {
      final rankA = a.rank ?? 9999;
      final rankB = b.rank ?? 9999;
      final rankDiff = rankA.compareTo(rankB);
      if (rankDiff != 0) {
        return rankDiff;
      }
    }
    return a.label.compareTo(b.label);
  }

  int _badgeSortGroup(_BadgeDisplay badge) {
    if (badge.rank != null) {
      return 0;
    }
    if (badge.isProgressBadge) {
      return 2;
    }
    return 1;
  }

  Widget _buildOwnedBadgeList(List<_BadgeDisplay> badges) {
    if (badges.isEmpty) {
      return _emptyPanel('所持バッジはまだありません');
    }
    final visibleBadges =
        _showAllOwnedBadges ? badges : badges.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBadgeGrid(visibleBadges),
        if (badges.length > visibleBadges.length) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: () {
                _playUiTap();
                _dismissBadgeInfoOverlay();
                setState(() => _showAllOwnedBadges = true);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: GameThemeColors.cyan,
                side: BorderSide(
                  color: GameThemeColors.cyan.withValues(alpha: 0.64),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text(
                'さらに表示',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ] else if (_showAllOwnedBadges && badges.length > 8) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: () {
                _playUiTap();
                _dismissBadgeInfoOverlay();
                setState(() => _showAllOwnedBadges = false);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: GameThemeColors.cyan,
                side: BorderSide(
                  color: GameThemeColors.cyan.withValues(alpha: 0.64),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text(
                '表示を減らす',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ownedBadgeChip(_BadgeDisplay badge) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: badge.color.withValues(alpha: 0.45)),
        ),
        child: Center(child: badge.icon),
      ),
    );
  }

  Widget _buildCareerRecord() {
    final profile = _profile;
    if (profile == null) {
      return _emptyPanel('戦績を読み込めませんでした');
    }
    final wazaCounts = profile.wazaCounts;
    return Column(
      children: [
        _buildThreeRecordRow(
          [
            _MetricData(
              label: 'ヘキサゴン回数',
              value: _formatNumber(wazaCounts['hexagon'] ?? 0),
              color: Colors.white,
            ),
            _MetricData(
              label: 'ピラミッド回数',
              value: _formatNumber(wazaCounts['pyramid'] ?? 0),
              color: Colors.white,
            ),
            _MetricData(
              label: 'ストレート回数',
              value: _formatNumber(wazaCounts['straight'] ?? 0),
              color: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildRecordGrid(
          [
            _MetricData(
              label: '最大連勝数',
              value: _formatNumber(profile.maxWinStreak),
              color: Colors.white,
            ),
            _MetricData(
              label: '累計消去ボール数',
              value: _formatNumber(profile.totalClearedBalls),
              color: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildRecordGrid(
          [
            _MetricData(
              label: '最高到達レート',
              value: _formatNumber(profile.highestRating),
              color: Colors.white,
              showTrophy: true,
            ),
            _MetricData(
              label: 'エンドレス最高スコア',
              value: _formatNumber(profile.highestEndlessScore),
              color: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildBestSeasonRankTile(_bestSeasonRankBadge(profile)),
      ],
    );
  }

  SeasonRankBadge? _bestSeasonRankBadge(_ProfileViewData profile) {
    final badges = profile.seasonRankBadges
        .where((badge) =>
            badge.kind == SeasonRankBadgeKind.ranked &&
            badge.rank > 0 &&
            badge.seasonId.isNotEmpty)
        .toList();
    if (badges.isEmpty) {
      return null;
    }
    badges.sort((a, b) {
      final rankDiff = a.rank.compareTo(b.rank);
      if (rankDiff != 0) {
        return rankDiff;
      }
      return b.seasonId.compareTo(a.seasonId);
    });
    return badges.first;
  }

  Widget _buildBestSeasonRankTile(SeasonRankBadge? badge) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '最高シーズン順位',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (badge == null)
            const SizedBox(height: 24)
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${badge.rank}位',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (badge.rating != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '/',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    HexagonTrophyAmount(
                      badge.rating!,
                      color: Colors.amberAccent,
                      iconSize: 18,
                      fontSize: 20,
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '/',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    badge.seasonName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
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

  Widget _buildThreeRecordRow(List<_MetricData> records) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 20) / 3;
        return Row(
          children: [
            for (var i = 0; i < records.length; i++) ...[
              SizedBox(
                width: itemWidth,
                child: _recordTile(records[i].label, records[i].value),
              ),
              if (i != records.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _recordTile(
    String label,
    String value, {
    bool showTrophy = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (showTrophy)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: HexagonTrophyAmount(
                int.tryParse(value.replaceAll(',', '')) ?? 0,
                color: Colors.amberAccent,
                iconSize: 18,
                fontSize: 20,
              ),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyPanel(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white54,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    Color accentColor = GameThemeColors.cyan,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 18,
            decoration: BoxDecoration(
                color: accentColor, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              AppSettings.instance.translate(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _playerData.playerName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B0F18),
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: GameThemeColors.cyan.withValues(alpha: 0.85),
              width: 2,
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: GameThemeColors.cyan.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: GameThemeColors.cyan.withValues(alpha: 0.72),
                  ),
                ),
                child: const Icon(
                  Icons.drive_file_rename_outline_rounded,
                  color: GameThemeColors.cyan,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '名前変更',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        offset: Offset(0, 1.5),
                        blurRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white70, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '10文字以内 / 不適切な名前は使用できません',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Text(
                      '変更コスト',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 8),
                    HexagonCoinAmount(
                      _nameChangeCost,
                      color: Color(0xFFFFE082),
                      iconSize: 15,
                      fontSize: 13,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLength: 10,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  cursorColor: GameThemeColors.cyan,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.34),
                    hintStyle: const TextStyle(color: Colors.white38),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: GameThemeColors.cyan.withValues(alpha: 0.40),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: GameThemeColors.cyan,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _playUiTap();
                      Navigator.of(dialogContext).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.38),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'キャンセル',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _playUiTap();
                      Navigator.of(dialogContext).pop(controller.text.trim());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GameThemeColors.cyan,
                      foregroundColor: const Color(0xFF042026),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      '保存',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || nextName == null) {
      return;
    }
    late final String validatedName;
    try {
      validatedName = await ModerationManager.instance
          .validateAndSanitizePlayerName(nextName);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showNameErrorDialog('$error');
      return;
    }

    final previousName = _playerData.playerName;
    if (validatedName == previousName) {
      return;
    }
    if (!mounted) {
      return;
    }

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B0F18),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: GameThemeColors.cyan.withValues(alpha: 0.78),
              width: 2,
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          title: const Text(
            '名前を変更しますか？',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              shadows: [
                Shadow(
                  color: Colors.black,
                  offset: Offset(0, 1.5),
                  blurRadius: 1,
                ),
              ],
            ),
          ),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '消費',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: 8),
                HexagonCoinAmount(
                  _nameChangeCost,
                  color: Color(0xFFFFE082),
                  iconSize: 18,
                  fontSize: 16,
                ),
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _playUiTap();
                      Navigator.of(confirmContext).pop(false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.38),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'キャンセル',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _playUiTap();
                      Navigator.of(confirmContext).pop(true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GameThemeColors.cyan,
                      foregroundColor: const Color(0xFF042026),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      '変更する',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (shouldProceed != true || !mounted) {
      return;
    }

    try {
      await _playerData.spendCoins(_nameChangeCost);
      await _playerData.setPlayerName(validatedName);
      _multiplayerManager.setPlayerName(_playerData.playerName);
      await _multiplayerManager.updateUserName(_playerData.playerName);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF151827),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: Colors.redAccent.withValues(alpha: 0.5),
            ),
          ),
          content: Text(
            '$error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _profile = _ProfileViewData.fromLocal(
        _playerData,
        currentRankLabel: _profile?.currentRankLabel ?? '未取得',
      );
    });
  }

  Future<void> _showNameErrorDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B0F18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: GameThemeColors.cyan.withValues(alpha: 0.72),
              width: 1.5,
            ),
          ),
          title: const Text(
            '名前エラー',
            style: TextStyle(
              color: GameThemeColors.cyan,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: GameThemeColors.cyan,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatNumber(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final reverseIndex = text.length - i;
      buffer.write(text[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  IconData _playerIconData(String iconId) {
    return switch (iconId) {
      'icon_bolt' => Icons.bolt,
      'icon_star' => Icons.star,
      'icon_gamepad' => Icons.sports_esports,
      'icon_sword' => Icons.gavel,
      'icon_hexagon' => Icons.hexagon,
      'icon_hexagon2' => Icons.hexagon,
      'icon_trophy' => Icons.emoji_events,
      'icon_medal' => Icons.military_tech,
      'icon_crown' => Icons.workspace_premium,
      'icon_diamond' => Icons.diamond,
      'icon_fire' => Icons.local_fire_department,
      'icon_water' => Icons.water_drop,
      'icon_moon' => Icons.dark_mode,
      'icon_visibility' => Icons.visibility,
      'icon_rocket' => Icons.rocket_launch,
      'icon_shield' => Icons.shield,
      'icon_terminal' => Icons.terminal,
      'icon_smile' => Icons.sentiment_satisfied_alt,
      'icon_ribbon' => Icons.workspace_premium,
      'icon_heart' => Icons.favorite,
      'icon_music' => Icons.music_note,
      'icon_cafe' => Icons.coffee,
      'icon_flower' => Icons.local_florist,
      'icon_bell' => Icons.notifications,
      'icon_skull' => Icons.dangerous,
      _ => Icons.person,
    };
  }

  Color _playerIconFrameColor(String frameId) {
    final frame = GameItemCatalog.byId(frameId);
    return switch (frame?.colorName) {
      'red' => Colors.redAccent,
      'orange' => Colors.orangeAccent,
      'yellow' => GameThemeColors.computer,
      'lime' => Colors.limeAccent,
      'green' => GameThemeColors.endless,
      'blue' => GameThemeColors.blueSide,
      'purple' => Colors.purpleAccent,
      'white' => Colors.white,
      'black' => const Color(0xFF05070D),
      'rainbow' => const Color(0xFFFFD54A),
      _ => GameThemeColors.cyan,
    };
  }
}

class _ProfileViewData {
  const _ProfileViewData({
    required this.displayName,
    required this.publicId,
    required this.playerIconId,
    required this.playerIconFrameId,
    required this.equippedBadgeIds,
    required this.unlockedBadgeIds,
    required this.seasonRankBadges,
    required this.totalWins,
    required this.level,
    required this.currentRating,
    required this.currentRankLabel,
    required this.totalClearedBalls,
    required this.highestRating,
    required this.maxWinStreak,
    required this.bestRankedRank,
    required this.highestEndlessScore,
    required this.wazaCounts,
  });

  final String displayName;
  final String publicId;
  final String playerIconId;
  final String playerIconFrameId;
  final List<String> equippedBadgeIds;
  final List<String> unlockedBadgeIds;
  final List<SeasonRankBadge> seasonRankBadges;
  final int totalWins;
  final int level;
  final int currentRating;
  final String currentRankLabel;
  final int totalClearedBalls;
  final int highestRating;
  final int maxWinStreak;
  final int bestRankedRank;
  final int highestEndlessScore;
  final Map<String, int> wazaCounts;

  _ProfileViewData copyWithSeasonRankBadges(List<SeasonRankBadge> badges) {
    return _ProfileViewData(
      displayName: displayName,
      publicId: publicId,
      playerIconId: playerIconId,
      playerIconFrameId: playerIconFrameId,
      equippedBadgeIds: equippedBadgeIds,
      unlockedBadgeIds: unlockedBadgeIds,
      seasonRankBadges: badges,
      totalWins: totalWins,
      level: level,
      currentRating: currentRating,
      currentRankLabel: currentRankLabel,
      totalClearedBalls: totalClearedBalls,
      highestRating: highestRating,
      maxWinStreak: maxWinStreak,
      bestRankedRank: bestRankedRank,
      highestEndlessScore: highestEndlessScore,
      wazaCounts: wazaCounts,
    );
  }

  _ProfileViewData withCurrentProfileFields({
    RankingEntry? rankingEntry,
  }) {
    final rankingName = rankingEntry?.displayName.trim();
    return _ProfileViewData(
      displayName:
          (rankingName == null || rankingName.isEmpty ? null : rankingName) ??
              displayName,
      publicId: rankingEntry?.publicId ?? publicId,
      playerIconId: playerIconId,
      playerIconFrameId: playerIconFrameId,
      equippedBadgeIds: equippedBadgeIds,
      unlockedBadgeIds: unlockedBadgeIds,
      seasonRankBadges: seasonRankBadges,
      totalWins: totalWins,
      level: level,
      currentRating: rankingEntry?.rating ?? currentRating,
      currentRankLabel: currentRankLabel,
      totalClearedBalls: totalClearedBalls,
      highestRating: max(
        highestRating,
        rankingEntry?.rating ?? currentRating,
      ),
      maxWinStreak: maxWinStreak,
      bestRankedRank: bestRankedRank,
      highestEndlessScore: max(
        highestEndlessScore,
        rankingEntry?.highestEndlessScore ?? 0,
      ),
      wazaCounts: wazaCounts,
    );
  }

  factory _ProfileViewData.fromLocal(
    PlayerDataManager playerData, {
    required String currentRankLabel,
  }) {
    return _ProfileViewData(
      displayName: playerData.displayPlayerName,
      publicId: playerData.playerId,
      playerIconId: playerData.equippedPlayerIconId,
      playerIconFrameId: playerData.equippedIconFrameId,
      equippedBadgeIds: playerData.equippedBadgeIds,
      unlockedBadgeIds: playerData.unlockedBadgeIds,
      seasonRankBadges: playerData.seasonRankBadges,
      totalWins: playerData.totalWins,
      level: playerData.level,
      currentRating: playerData.currentRating,
      currentRankLabel: currentRankLabel,
      totalClearedBalls: playerData.totalClearedBalls,
      highestRating: playerData.highestRating,
      maxWinStreak: playerData.rankedMaxWinStreak,
      bestRankedRank: playerData.bestRankedRank,
      highestEndlessScore: playerData.highestEndlessScore,
      wazaCounts: playerData.wazaCounts,
    );
  }

  factory _ProfileViewData.fromRecordSummary(
    Map<dynamic, dynamic> data, {
    RankingEntry? fallbackEntry,
    required String currentRankLabel,
  }) {
    final overall = _mapValue(data['overall']);
    final economy = _mapValue(data['economy']);
    final collection = _mapValue(data['collection']);
    final ranked = _mapValue(data['ranked']);
    final endless = _mapValue(data['endless']);
    final wazaCounts = _intMapValue(data['wazaCounts']);
    return _ProfileViewData(
      displayName: _stringValue(data['displayName']) ??
          fallbackEntry?.displayName ??
          'Player',
      publicId: _stringValue(data['publicId']) ?? fallbackEntry?.publicId ?? '',
      playerIconId: _stringValue(collection['equippedPlayerIconId']) ?? '',
      playerIconFrameId:
          _stringValue(collection['equippedIconFrameId']) ?? 'default',
      equippedBadgeIds: _stringListValue(collection['equippedBadgeIds']),
      unlockedBadgeIds: _stringListValue(collection['unlockedBadgeIds']),
      seasonRankBadges: _seasonRankBadgesValue(collection['seasonRankBadges']),
      totalWins: _intValue(overall['totalWins']) ?? 0,
      level: _intValue(economy['level']) ?? 1,
      currentRating: _intValue(ranked['currentRating']) ??
          fallbackEntry?.rating ??
          MultiplayerManager.initialRating,
      currentRankLabel: currentRankLabel,
      totalClearedBalls: _intValue(overall['totalClearedBalls']) ?? 0,
      highestRating: max(
        _intValue(ranked['highestRating']) ?? MultiplayerManager.initialRating,
        fallbackEntry?.rating ?? MultiplayerManager.initialRating,
      ),
      maxWinStreak: _intValue(ranked['maxWinStreak']) ?? 0,
      bestRankedRank: _intValue(ranked['bestRankedRank']) ?? 0,
      highestEndlessScore: max(
        _intValue(endless['highestScore']) ?? 0,
        fallbackEntry?.highestEndlessScore ?? 0,
      ),
      wazaCounts: wazaCounts,
    );
  }

  factory _ProfileViewData.fromRankingEntry(
    RankingEntry? entry, {
    required String currentRankLabel,
  }) {
    return _ProfileViewData(
      displayName: entry?.displayName ?? 'Player',
      publicId: entry?.publicId ?? '',
      playerIconId: '',
      playerIconFrameId: 'default',
      equippedBadgeIds: const [],
      unlockedBadgeIds: const [],
      seasonRankBadges: const [],
      totalWins: entry?.seasonWins ?? 0,
      level: 1,
      currentRating: entry?.rating ?? MultiplayerManager.initialRating,
      currentRankLabel: currentRankLabel,
      totalClearedBalls: 0,
      highestRating: entry?.rating ?? MultiplayerManager.initialRating,
      maxWinStreak: 0,
      bestRankedRank: 0,
      highestEndlessScore: entry?.highestEndlessScore ?? 0,
      wazaCounts: const {},
    );
  }

  static Map<dynamic, dynamic> _mapValue(Object? value) {
    if (value is Map) {
      return Map<dynamic, dynamic>.from(value);
    }
    return const {};
  }

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<String> _stringListValue(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static Map<String, int> _intMapValue(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return value.map(
      (key, item) => MapEntry(key.toString(), _intValue(item) ?? 0),
    );
  }

  static List<SeasonRankBadge> _seasonRankBadgesValue(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map(
            (item) => SeasonRankBadge.fromJson(Map<String, dynamic>.from(item)))
        .where((badge) => badge.seasonId.isNotEmpty && badge.rank > 0)
        .toList();
  }
}

class _BadgeDisplay {
  const _BadgeDisplay({
    required this.id,
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
    this.rank,
    this.isProgressBadge = false,
  });

  final String id;
  final String label;
  final String detail;
  final Color color;
  final Widget icon;
  final int? rank;
  final bool isProgressBadge;
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.color,
    this.showTrophy = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool showTrophy;
}

class _ProfilePageTitle extends StatelessWidget {
  const _ProfilePageTitle({
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

class _ScanlineBackground extends StatelessWidget {
  const _ScanlineBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanlinePainter(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF080A14), Color(0xFF101020)],
          ),
        ),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GameThemeColors.cyan.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
