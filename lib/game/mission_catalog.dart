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
      'title': title,
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

  static const List<MissionDefinition> dailyPool = [
    MissionDefinition(
      id: 'play_matches_3',
      title: 'MATCH RUNNER',
      description: '対戦を3回プレイする',
      eventKey: 'play_match',
      target: 3,
      rewardCoins: 800,
    ),
    MissionDefinition(
      id: 'win_matches_2',
      title: 'WIN PROTOCOL',
      description: '対戦で2勝する',
      eventKey: 'win_match',
      target: 2,
      rewardCoins: 1200,
    ),
    MissionDefinition(
      id: 'roll_gacha_2',
      title: 'DATA DIGGER',
      description: 'ガチャを2回回す',
      eventKey: 'roll_gacha',
      target: 2,
      rewardCoins: 700,
    ),
    MissionDefinition(
      id: 'enter_arena_1',
      title: 'ARENA DIVE',
      description: 'アリーナに1回エントリーする',
      eventKey: 'enter_arena',
      target: 1,
      rewardCoins: 1000,
    ),
    MissionDefinition(
      id: 'play_endless_1',
      title: 'ENDLESS BOOT',
      description: 'エンドレスを1回開始する',
      eventKey: 'play_endless',
      target: 1,
      rewardCoins: 600,
    ),
    MissionDefinition(
      id: 'play_random_match_1',
      title: 'RANK LINK',
      description: 'ランダムマッチを1回開始する',
      eventKey: 'start_ranked_match',
      target: 1,
      rewardCoins: 900,
    ),
  ];
}
