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
      'title': MissionCatalog.localizedTitleForId(id) ?? title,
      'description': description,
      'eventKey': eventKey,
      'target': target,
      'rewardCoins': rewardCoins,
      'progress': 0,
      'claimed': false,
    };
  }
}

class MissionCatalog {
  MissionCatalog._();

  static String? localizedTitleForId(String id) {
    return switch (id) {
      'play_matches_3' => '対戦を3回プレイ',
      'win_matches_2' => '対戦で2勝',
      'roll_gacha_2' => 'ガチャを2回',
      'watch_rewarded_ad_1' => '動画広告を見る',
      'enter_arena_1' => 'アリーナにエントリー',
      'play_endless_1' => 'エンドレスを開始',
      'play_random_match_1' => 'ランダムマッチを開始',
      _ => null,
    };
  }

  static const List<MissionDefinition> dailyPool = [
    MissionDefinition(
      id: 'play_matches_3',
      title: '対戦を3回プレイ',
      description: '対戦を3回プレイする',
      eventKey: 'play_match',
      target: 3,
      rewardCoins: 800,
    ),
    MissionDefinition(
      id: 'win_matches_2',
      title: '対戦で2勝',
      description: '対戦で2勝する',
      eventKey: 'win_match',
      target: 2,
      rewardCoins: 1200,
    ),
    MissionDefinition(
      id: 'roll_gacha_2',
      title: 'ガチャを2回',
      description: 'ガチャを2回回す',
      eventKey: 'roll_gacha',
      target: 2,
      rewardCoins: 700,
    ),
    MissionDefinition(
      id: 'watch_rewarded_ad_1',
      title: '動画広告を見る',
      description: '動画広告を1回見る',
      eventKey: 'watch_rewarded_ad',
      target: 1,
      rewardCoins: 1200,
    ),
    MissionDefinition(
      id: 'enter_arena_1',
      title: 'アリーナにエントリー',
      description: 'アリーナに1回エントリーする',
      eventKey: 'enter_arena',
      target: 1,
      rewardCoins: 1000,
    ),
    MissionDefinition(
      id: 'play_endless_1',
      title: 'エンドレスを開始',
      description: 'エンドレスを1回開始する',
      eventKey: 'play_endless',
      target: 1,
      rewardCoins: 600,
    ),
    MissionDefinition(
      id: 'play_random_match_1',
      title: 'ランダムマッチを開始',
      description: 'ランダムマッチを1回開始する',
      eventKey: 'start_ranked_match',
      target: 1,
      rewardCoins: 900,
    ),
  ];
}
