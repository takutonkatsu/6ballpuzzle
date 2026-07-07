import 'package:flutter/material.dart';

enum BadgeUnlockType {
  always,
  highestRating,
  totalMatches,
  arenaPerfectClearCount,
  accountYears,
  wazaCount,
  highestEndlessScore,
  bestRankedRank,
}

class BadgeUnlockCondition {
  const BadgeUnlockCondition({
    required this.type,
    this.threshold = 0,
    this.wazaKey,
  });

  final BadgeUnlockType type;
  final int threshold;
  final String? wazaKey;

  bool isUnlocked({
    required int highestRating,
    required int totalMatches,
    required int arenaPerfectClearCount,
    required Duration accountAge,
    required Map<String, int> wazaCounts,
    required int highestEndlessScore,
    required int bestRankedRank,
  }) {
    switch (type) {
      case BadgeUnlockType.always:
        return true;
      case BadgeUnlockType.highestRating:
        return highestRating >= threshold;
      case BadgeUnlockType.totalMatches:
        return totalMatches >= threshold;
      case BadgeUnlockType.arenaPerfectClearCount:
        return arenaPerfectClearCount >= threshold;
      case BadgeUnlockType.accountYears:
        return accountAge.inDays >= threshold * 365;
      case BadgeUnlockType.wazaCount:
        return wazaCounts[wazaKey] != null && wazaCounts[wazaKey]! >= threshold;
      case BadgeUnlockType.highestEndlessScore:
        return highestEndlessScore >= threshold;
      case BadgeUnlockType.bestRankedRank:
        return bestRankedRank > 0 && bestRankedRank <= threshold;
    }
  }

  String get description {
    switch (type) {
      case BadgeUnlockType.always:
        return '初期解放';
      case BadgeUnlockType.highestRating:
        return '最高レート $threshold';
      case BadgeUnlockType.totalMatches:
        return '総プレイ $threshold回';
      case BadgeUnlockType.arenaPerfectClearCount:
        return 'アリーナ12勝 $threshold回';
      case BadgeUnlockType.accountYears:
        return 'プレイ歴 $threshold年';
      case BadgeUnlockType.wazaCount:
        return '${_wazaLabel(wazaKey)} $threshold回';
      case BadgeUnlockType.highestEndlessScore:
        return 'エンドレス最高 $threshold';
      case BadgeUnlockType.bestRankedRank:
        return 'ランク戦最高 $threshold位以内';
    }
  }

  static String _wazaLabel(String? key) {
    return switch (key) {
      'straight' => 'ストレート',
      'pyramid' => 'ピラミッド',
      'hexagon' => 'ヘキサゴン',
      _ => 'フォーメーション',
    };
  }
}

class BadgeItem {
  const BadgeItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.unlockedCondition,
    this.level,
    this.evolutionGroup,
  });

  final String id;
  final String label;
  final IconData icon;
  final BadgeUnlockCondition unlockedCondition;
  final int? level;
  final String? evolutionGroup;

  Color get frameColor {
    return switch (level) {
      1 => const Color(0xFF8A7A62),
      2 => const Color(0xFFCD7F32),
      3 => const Color(0xFFDDE6F0),
      4 => const Color(0xFFFFD54F),
      5 => const Color(0xFFB56CFF),
      _ => Colors.amberAccent,
    };
  }
}

class SeasonRankBadge {
  const SeasonRankBadge({
    required this.seasonId,
    required this.rank,
    this.kind = SeasonRankBadgeKind.ranked,
    this.rating,
    this.score,
  });

  static final RegExp _idPattern =
      RegExp(r'^season_rank_(\d{4}-\d{2})_(\d{1,3})$');
  static final RegExp _typedIdPattern = RegExp(
      r'^(ranked|endless)_rank_([0-9]{4}(?:-[0-9]{2}|-W[0-9]{2}))_(\d{1,3})$');

  final String seasonId;
  final int rank;
  final SeasonRankBadgeKind kind;
  final int? rating;
  final int? score;

  String get id => idFor(seasonId: seasonId, rank: rank, kind: kind);
  String get label => '${kind.label} $rank位';
  String get detailLabel => '$rank位　$seasonName';
  String get seasonName => kind == SeasonRankBadgeKind.endless
      ? _endlessSeasonName(seasonId)
      : _rankedSeasonName(seasonId);

  Map<String, dynamic> toJson() {
    return {
      'seasonId': seasonId,
      'rank': rank,
      'kind': kind.key,
      if (rating != null) 'rating': rating,
      if (score != null) 'score': score,
    };
  }

  factory SeasonRankBadge.fromJson(Map<String, dynamic> json) {
    return SeasonRankBadge(
      seasonId: json['seasonId']?.toString() ?? '',
      rank: _intValue(json['rank']) ?? 0,
      kind: SeasonRankBadgeKind.fromKey(json['kind']?.toString()),
      rating: _intValue(json['rating']),
      score: _intValue(json['score']),
    );
  }

  static String idFor({
    required String seasonId,
    required int rank,
    SeasonRankBadgeKind kind = SeasonRankBadgeKind.ranked,
  }) {
    if (kind == SeasonRankBadgeKind.ranked &&
        RegExp(r'^\d{4}-\d{2}$').hasMatch(seasonId)) {
      return 'season_rank_${seasonId}_$rank';
    }
    return '${kind.key}_rank_${seasonId}_$rank';
  }

  static SeasonRankBadge? fromId(String id) {
    final typedMatch = _typedIdPattern.firstMatch(id);
    if (typedMatch != null) {
      final rank = int.tryParse(typedMatch.group(3) ?? '');
      if (rank == null || rank <= 0) {
        return null;
      }
      return SeasonRankBadge(
        kind: SeasonRankBadgeKind.fromKey(typedMatch.group(1)),
        seasonId: typedMatch.group(2) ?? '',
        rank: rank,
      );
    }
    final match = _idPattern.firstMatch(id);
    if (match == null) {
      return null;
    }
    final rank = int.tryParse(match.group(2) ?? '');
    if (rank == null || rank <= 0) {
      return null;
    }
    return SeasonRankBadge(
      seasonId: match.group(1) ?? '',
      rank: rank,
    );
  }

  static bool isSeasonRankBadgeId(String id) => fromId(id) != null;

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  static String _rankedSeasonName(String seasonId) {
    final parts = seasonId.split('-');
    if (parts.length != 2) {
      return 'シーズン0';
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) {
      return 'シーズン0';
    }
    const baseYear = 2026;
    const baseMonth = 5;
    final number = (year - baseYear) * 12 + (month - baseMonth);
    return 'シーズン$number';
  }

  static String _endlessSeasonName(String seasonId) {
    final match = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(seasonId);
    if (match == null) {
      return 'エンドレス';
    }
    return '${match.group(1)}年 第${match.group(2)}週';
  }
}

enum SeasonRankBadgeKind {
  ranked,
  endless;

  String get key => switch (this) {
        SeasonRankBadgeKind.ranked => 'ranked',
        SeasonRankBadgeKind.endless => 'endless',
      };

  String get label => switch (this) {
        SeasonRankBadgeKind.ranked => 'ランク戦',
        SeasonRankBadgeKind.endless => 'エンドレス',
      };

  static SeasonRankBadgeKind fromKey(String? key) {
    return key == 'endless'
        ? SeasonRankBadgeKind.endless
        : SeasonRankBadgeKind.ranked;
  }
}

class BadgeCatalog {
  BadgeCatalog._();

  static final List<BadgeItem> allBadges = [
    ..._leveledBadges(
      idPrefix: 'total_play',
      label: '総プレイ回数',
      icon: Icons.sports_esports,
      type: BadgeUnlockType.totalMatches,
      thresholds: const [10, 50, 100, 500, 1000],
    ),
    ..._leveledBadges(
      idPrefix: 'hexagon_count',
      label: '累計ヘキサゴン',
      icon: Icons.hexagon,
      type: BadgeUnlockType.wazaCount,
      thresholds: const [10, 50, 100, 1000, 10000],
      wazaKey: 'hexagon',
    ),
    ..._leveledBadges(
      idPrefix: 'pyramid_count',
      label: '累計ピラミッド',
      icon: Icons.change_history,
      type: BadgeUnlockType.wazaCount,
      thresholds: const [10, 50, 100, 1000, 10000],
      wazaKey: 'pyramid',
    ),
    ..._leveledBadges(
      idPrefix: 'straight_count',
      label: '累計ストレート',
      icon: Icons.linear_scale,
      type: BadgeUnlockType.wazaCount,
      thresholds: const [10, 50, 100, 1000, 10000],
      wazaKey: 'straight',
    ),
    ..._leveledBadges(
      idPrefix: 'arena_12_clear',
      label: 'アリーナ12勝',
      icon: Icons.workspace_premium,
      type: BadgeUnlockType.arenaPerfectClearCount,
      thresholds: const [1, 5, 10, 30, 100],
    ),
    for (var year = 1; year <= 10; year++)
      BadgeItem(
        id: 'anniversary_$year',
        label: '$year周年',
        icon: Icons.cake,
        level: year,
        evolutionGroup: 'anniversary',
        unlockedCondition: BadgeUnlockCondition(
          type: BadgeUnlockType.accountYears,
          threshold: year,
        ),
      ),
  ];

  static List<BadgeItem> _leveledBadges({
    required String idPrefix,
    required String label,
    required IconData icon,
    required BadgeUnlockType type,
    required List<int> thresholds,
    String? wazaKey,
  }) {
    return [
      for (var i = 0; i < thresholds.length; i++)
        BadgeItem(
          id: '${idPrefix}_lv${i + 1}',
          label: '$label Lv.${i + 1}',
          icon: icon,
          level: i + 1,
          evolutionGroup: idPrefix,
          unlockedCondition: BadgeUnlockCondition(
            type: type,
            threshold: thresholds[i],
            wazaKey: wazaKey,
          ),
        ),
    ];
  }

  static BadgeItem? findById(String id) {
    for (final badge in allBadges) {
      if (badge.id == id) {
        return badge;
      }
    }
    return null;
  }

  static List<BadgeItem> visibleBadgesFor(Set<String> unlockedIds) {
    final visible = <BadgeItem>[];
    final visibleGroups = <String>{};
    for (final badge in allBadges) {
      final group = _evolutionGroupFor(badge);
      if (group == null) {
        visible.add(badge);
        continue;
      }
      if (!visibleGroups.add(group)) {
        continue;
      }
      final badges = allBadges
          .where((item) => _evolutionGroupFor(item) == group)
          .toList()
        ..sort((a, b) => (a.level ?? 0).compareTo(b.level ?? 0));
      final highestUnlocked = badges.where((badge) {
        return unlockedIds.contains(badge.id);
      }).fold<BadgeItem?>(null, (current, badge) {
        if (current == null || (badge.level ?? 0) > (current.level ?? 0)) {
          return badge;
        }
        return current;
      });
      visible.add(highestUnlocked ?? badges.first);
    }
    return visible;
  }

  static String evolvedBadgeIdFor(String id, Set<String> unlockedIds) {
    final badge = findById(id);
    final group = badge == null ? null : _evolutionGroupFor(badge);
    if (badge == null || group == null) {
      return id;
    }
    final candidates = allBadges
        .where((item) =>
            _evolutionGroupFor(item) == group && unlockedIds.contains(item.id))
        .toList()
      ..sort((a, b) => (b.level ?? 0).compareTo(a.level ?? 0));
    return candidates.isEmpty ? id : candidates.first.id;
  }

  static BadgeItem? nextEvolutionBadgeFor(BadgeItem badge) {
    final group = _evolutionGroupFor(badge);
    if (group == null) {
      return null;
    }
    final currentLevel = badge.level ?? 0;
    final candidates = allBadges
        .where((item) =>
            _evolutionGroupFor(item) == group &&
            (item.level ?? 0) > currentLevel)
        .toList()
      ..sort((a, b) => (a.level ?? 0).compareTo(b.level ?? 0));
    return candidates.isEmpty ? null : candidates.first;
  }

  static String? _evolutionGroupFor(BadgeItem badge) {
    if (badge.evolutionGroup != null) {
      return badge.evolutionGroup;
    }
    if (RegExp(r'^anniversary_\d+$').hasMatch(badge.id)) {
      return 'anniversary';
    }
    return null;
  }
}
