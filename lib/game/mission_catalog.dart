import '../app_settings.dart';

class MissionDefinition {
  const MissionDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.eventKey,
    required this.target,
    required this.rewardCoins,
  });

  final String id;
  final String title;
  final String description;
  final String eventKey;
  final int target;
  final int rewardCoins;

  Map<String, dynamic> toMissionMap() {
    return {
      'id': id,
      'title': AppSettings.instance.translate(
        MissionCatalog.localizedTitleForId(id) ?? title,
      ),
      'description': description,
      'eventKey': eventKey,
      'target': target,
      'rewardCoins': rewardCoins,
      'progress': 0,
      'claimed': false,
    };
  }
}

class RegularMissionDefinition {
  const RegularMissionDefinition({
    required this.id,
    required this.title,
    required this.progressKey,
    required this.initialTarget,
    required this.targetStep,
    required this.rewardCoins,
  });

  final String id;
  final String title;
  final String progressKey;
  final int initialTarget;
  final int targetStep;
  final int rewardCoins;

  int targetForClaimedCount(int claimedCount) {
    return initialTarget + targetStep * claimedCount;
  }
}

class MissionCatalog {
  MissionCatalog._();

  static const List<String> rewardedAdMissionIds = ['watch_rewarded_ad_1'];
  static const List<String> loginRewardMissionIds = ['login_bonus_1'];
  static const String requiredEndlessMissionId = 'score_endless_10000';
  static const List<String> temporarilyDisabledMissionIds = [
    'win_arena_match_1',
    'regular_daily_win_rank_first',
  ];

  static bool isRewardedAdMissionId(String id) {
    return rewardedAdMissionIds.contains(id);
  }

  static bool isLoginRewardMissionId(String id) {
    return loginRewardMissionIds.contains(id);
  }

  static bool isTemporarilyDisabledMissionId(String id) {
    return temporarilyDisabledMissionIds.contains(id);
  }

  static List<MissionDefinition> get activeDailyPool {
    return dailyPool
        .where((mission) => !isTemporarilyDisabledMissionId(mission.id))
        .toList(growable: false);
  }

  static String? localizedTitleForId(String id) {
    return switch (id) {
      'win_matches_3' => '対戦で3勝する',
      'win_ranked_match_1' => 'ランク戦で1勝する',
      'play_cpu_match_1' => 'コンピュータ対戦を1回プレイする',
      'use_straight_1' => '対戦中にストレートを累計1回決める',
      'use_pyramid_1' => '対戦中にピラミッドを累計1回決める',
      'use_hexagon_1' => '対戦中にヘキサゴンを累計1回決める',
      'clear_balls_100' => '対戦中にボールを累計100個消す',
      'use_waza_5' => '対戦中にフォーメーションを累計5回決める',
      'play_matches_5' => '対戦を累計5回プレイする',
      'win_arena_match_1' => 'アリーナで1勝する',
      'score_endless_10000' => 'エンドレスモードで10000点を達成する',
      'roll_gacha_1' => 'ガチャを1回引く',
      'watch_rewarded_ad_1' => '動画広告を見る',
      'login_bonus_1' => 'ログイン報酬を受け取る',
      _ => null,
    };
  }

  static const List<MissionDefinition> dailyPool = [
    MissionDefinition(
      id: 'watch_rewarded_ad_1',
      title: '動画広告を見る',
      description: '動画広告を1回見る',
      eventKey: 'watch_rewarded_ad',
      target: 1,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'win_matches_3',
      title: '対戦で3勝する',
      description: '対戦で3勝する',
      eventKey: 'win_match',
      target: 3,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'win_ranked_match_1',
      title: 'ランク戦で1勝する',
      description: 'ランク戦で1勝する',
      eventKey: 'win_ranked_match',
      target: 1,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'play_cpu_match_1',
      title: 'コンピュータ対戦を1回プレイする',
      description: 'コンピュータ対戦を1回プレイする',
      eventKey: 'play_cpu',
      target: 1,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'use_straight_1',
      title: '対戦中にストレートを累計1回決める',
      description: '対戦中にストレートを累計1回決める',
      eventKey: 'use_straight',
      target: 1,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'use_pyramid_1',
      title: '対戦中にピラミッドを累計1回決める',
      description: '対戦中にピラミッドを累計1回決める',
      eventKey: 'use_pyramid',
      target: 1,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'use_hexagon_1',
      title: '対戦中にヘキサゴンを累計1回決める',
      description: '対戦中にヘキサゴンを累計1回決める',
      eventKey: 'use_hexagon',
      target: 1,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'clear_balls_100',
      title: '対戦中にボールを累計100個消す',
      description: '対戦中にボールを累計100個消す',
      eventKey: 'clear_balls',
      target: 100,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'use_waza_5',
      title: '対戦中にフォーメーションを累計5回決める',
      description: '対戦中にフォーメーションを累計5回決める',
      eventKey: 'use_waza',
      target: 5,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'play_matches_5',
      title: '対戦を累計5回プレイする',
      description: '対戦を累計5回プレイする',
      eventKey: 'play_match',
      target: 5,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'win_arena_match_1',
      title: 'アリーナで1勝する',
      description: 'アリーナで1勝する',
      eventKey: 'win_arena_match',
      target: 1,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'score_endless_10000',
      title: 'エンドレスモードで10000点を達成する',
      description: 'エンドレスモードで10000点を達成する',
      eventKey: 'score_endless_10000',
      target: 1,
      rewardCoins: 500,
    ),
    MissionDefinition(
      id: 'roll_gacha_1',
      title: 'ガチャを1回引く',
      description: 'ガチャを1回引く',
      eventKey: 'roll_gacha',
      target: 1,
      rewardCoins: 500,
    ),
  ];

  static const List<RegularMissionDefinition> regularMissions = [
    RegularMissionDefinition(
      id: 'regular_ranked_wins',
      title: 'ランク戦で〇〇勝する',
      progressKey: 'ranked_wins',
      initialTarget: 5,
      targetStep: 5,
      rewardCoins: 500,
    ),
    RegularMissionDefinition(
      id: 'regular_endless_score',
      title: 'エンドレスで〇〇点を達成する',
      progressKey: 'highest_endless_score',
      initialTarget: 50000,
      targetStep: 50000,
      rewardCoins: 1000,
    ),
    RegularMissionDefinition(
      id: 'regular_rewarded_ads',
      title: '動画広告を〇〇回見る',
      progressKey: 'rewarded_ad_views',
      initialTarget: 3,
      targetStep: 3,
      rewardCoins: 1000,
    ),
    RegularMissionDefinition(
      id: 'regular_login_days',
      title: '〇〇日ログインする',
      progressKey: 'total_login_days',
      initialTarget: 5,
      targetStep: 5,
      rewardCoins: 1000,
    ),
    RegularMissionDefinition(
      id: 'regular_ranked_rating',
      title: 'ランク戦で〇〇を達成する',
      progressKey: 'highest_rating',
      initialTarget: 1500,
      targetStep: 500,
      rewardCoins: 1000,
    ),
    RegularMissionDefinition(
      id: 'regular_hexagon_count',
      title: 'ヘキサゴンを〇〇回決める',
      progressKey: 'waza_hexagon',
      initialTarget: 20,
      targetStep: 20,
      rewardCoins: 500,
    ),
    RegularMissionDefinition(
      id: 'regular_pyramid_count',
      title: 'ピラミッドを〇〇回決める',
      progressKey: 'waza_pyramid',
      initialTarget: 20,
      targetStep: 20,
      rewardCoins: 500,
    ),
    RegularMissionDefinition(
      id: 'regular_straight_count',
      title: 'ストレートを〇〇回決める',
      progressKey: 'waza_straight',
      initialTarget: 20,
      targetStep: 20,
      rewardCoins: 500,
    ),
    RegularMissionDefinition(
      id: 'regular_cleared_balls',
      title: '累計消去ボール数〇〇個を達成する',
      progressKey: 'total_cleared_balls',
      initialTarget: 1000,
      targetStep: 1000,
      rewardCoins: 500,
    ),
  ];
}
