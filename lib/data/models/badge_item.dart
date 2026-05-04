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
      _ => 'ワザ',
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
  });

  final String id;
  final String label;
  final IconData icon;
  final BadgeUnlockCondition unlockedCondition;
  final int? level;

  Color get frameColor {
    return switch (level) {
      1 => Colors.white,
      2 => const Color(0xFFCD7F32),
      3 => const Color(0xFFC0C0C0),
      4 => const Color(0xFFFFD54F),
      5 => const Color(0xFFB56CFF),
      _ => Colors.amberAccent,
    };
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
        unlockedCondition: BadgeUnlockCondition(
          type: BadgeUnlockType.accountYears,
          threshold: year,
        ),
      ),
    const BadgeItem(
      id: 'rank_top_100',
      label: 'ランク戦TOP100',
      icon: Icons.leaderboard,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.bestRankedRank,
        threshold: 100,
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
}
