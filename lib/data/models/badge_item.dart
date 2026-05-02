import 'package:flutter/material.dart';

enum BadgeUnlockType {
  always,
  highestRating,
  maxArenaWins,
  accountYears,
  totalWins,
  maxCombo,
  wazaCount,
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
    required int maxArenaWins,
    required Duration accountAge,
    required int totalWins,
    required int maxCombo,
    required Map<String, int> wazaCounts,
  }) {
    switch (type) {
      case BadgeUnlockType.always:
        return true;
      case BadgeUnlockType.highestRating:
        return highestRating >= threshold;
      case BadgeUnlockType.maxArenaWins:
        return maxArenaWins >= threshold;
      case BadgeUnlockType.accountYears:
        return accountAge.inDays >= threshold * 365;
      case BadgeUnlockType.totalWins:
        return totalWins >= threshold;
      case BadgeUnlockType.maxCombo:
        return maxCombo >= threshold;
      case BadgeUnlockType.wazaCount:
        return wazaCounts[wazaKey] != null && wazaCounts[wazaKey]! >= threshold;
    }
  }

  String get description {
    switch (type) {
      case BadgeUnlockType.always:
        return '初期解放';
      case BadgeUnlockType.highestRating:
        return '最高レート $threshold';
      case BadgeUnlockType.maxArenaWins:
        return '闘技場 $threshold勝';
      case BadgeUnlockType.accountYears:
        return 'プレイ歴 $threshold年';
      case BadgeUnlockType.totalWins:
        return '通算 $threshold勝';
      case BadgeUnlockType.maxCombo:
        return '最大 $threshold連鎖';
      case BadgeUnlockType.wazaCount:
        return '${_wazaLabel(wazaKey)} $threshold回';
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
  });

  final String id;
  final String label;
  final IconData icon;
  final BadgeUnlockCondition unlockedCondition;
}

class BadgeCatalog {
  BadgeCatalog._();

  static const List<BadgeItem> allBadges = [
    BadgeItem(
      id: 'rookie_pilot',
      label: 'ルーキーパイロット',
      icon: Icons.trip_origin,
      unlockedCondition: BadgeUnlockCondition(type: BadgeUnlockType.always),
    ),
    BadgeItem(
      id: 'rating_1200',
      label: 'レート1200',
      icon: Icons.trending_up,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.highestRating,
        threshold: 1200,
      ),
    ),
    BadgeItem(
      id: 'rating_1500',
      label: 'レート1500',
      icon: Icons.auto_graph,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.highestRating,
        threshold: 1500,
      ),
    ),
    BadgeItem(
      id: 'arena_7',
      label: 'アリーナ7勝',
      icon: Icons.shield,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.maxArenaWins,
        threshold: 7,
      ),
    ),
    BadgeItem(
      id: 'arena_12',
      label: 'アリーナ12勝',
      icon: Icons.emoji_events,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.maxArenaWins,
        threshold: 12,
      ),
    ),
    BadgeItem(
      id: 'anniversary_3',
      label: '3周年',
      icon: Icons.cake,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.accountYears,
        threshold: 3,
      ),
    ),
    BadgeItem(
      id: 'combo_5',
      label: '5連鎖',
      icon: Icons.bolt,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.maxCombo,
        threshold: 5,
      ),
    ),
    BadgeItem(
      id: 'straight_master',
      label: 'ストレートマスター',
      icon: Icons.linear_scale,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.wazaCount,
        threshold: 50,
        wazaKey: 'straight',
      ),
    ),
    BadgeItem(
      id: 'pyramid_architect',
      label: 'ピラミッド職人',
      icon: Icons.change_history,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.wazaCount,
        threshold: 30,
        wazaKey: 'pyramid',
      ),
    ),
    BadgeItem(
      id: 'hexagon_core',
      label: 'ヘキサゴンコア',
      icon: Icons.hexagon,
      unlockedCondition: BadgeUnlockCondition(
        type: BadgeUnlockType.wazaCount,
        threshold: 20,
        wazaKey: 'hexagon',
      ),
    ),
  ];

  static BadgeItem? findById(String id) {
    for (final badge in allBadges) {
      if (badge.id == id) {
        return badge;
      }
    }
    return null;
  }
}
