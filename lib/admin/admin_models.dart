import 'dart:convert';

class AdminPlayerSummary {
  const AdminPlayerSummary({
    required this.uid,
    required this.displayName,
    required this.publicId,
    required this.updatedAt,
    required this.raw,
  });

  final String uid;
  final String displayName;
  final String publicId;
  final int? updatedAt;
  final Map<String, dynamic> raw;

  int get totalMatches => _nestedInt(raw, const ['overall', 'totalMatches']);
  int get totalWins => _nestedInt(raw, const ['overall', 'totalWins']);
  int get totalLosses => _nestedInt(raw, const ['overall', 'totalLosses']);
  int get nonEndlessMatches => modePlayCounts.entries
      .where((entry) => entry.key != 'SOLO')
      .fold(0, (total, entry) => total + entry.value);
  int get currentRating => _nestedInt(raw, const ['ranked', 'currentRating']);
  int get highestRating => _nestedInt(raw, const ['ranked', 'highestRating']);
  int get rankedWins => _nestedInt(raw, const ['ranked', 'wins']);
  int get rankedLosses => _nestedInt(raw, const ['ranked', 'losses']);
  int get rankedMatches => _nestedInt(raw, const ['ranked', 'matches']);
  int get seasonRankedWins => _firstNestedInt(raw, const [
        ['ranked', 'seasonWins'],
        ['ranked', 'currentSeason', 'wins'],
        ['currentSeason', 'rankedWins'],
        ['seasonRankedWins'],
      ]);
  int get seasonRankedLosses => _firstNestedInt(raw, const [
        ['ranked', 'seasonLosses'],
        ['ranked', 'currentSeason', 'losses'],
        ['currentSeason', 'rankedLosses'],
        ['seasonRankedLosses'],
      ]);
  int get seasonRankedMatches {
    final explicit = _firstNestedInt(raw, const [
      ['ranked', 'seasonMatches'],
      ['ranked', 'currentSeason', 'matches'],
      ['currentSeason', 'rankedMatches'],
      ['seasonRankedMatches'],
    ]);
    if (explicit > 0) {
      return explicit;
    }
    return seasonRankedWins + seasonRankedLosses;
  }

  int get rankedMaxWinStreak =>
      _nestedInt(raw, const ['ranked', 'maxWinStreak']);
  int get bestRankedRank => _nestedInt(raw, const ['ranked', 'bestRankedRank']);
  Map<String, int> get dailyWinRankPlacements => intMapValue(
      _nestedValue(raw, const ['ranked', 'dailyWinRankPlacements']));
  int get arenaMaxWins => _nestedInt(raw, const ['arena', 'maxWins']);
  int get endlessHighestScore =>
      _nestedInt(raw, const ['endless', 'highestScore']);
  int get endlessPlayCount => _nestedInt(raw, const ['endless', 'playCount']);
  int get level => _nestedInt(raw, const ['economy', 'level']);
  int get coins => _nestedInt(raw, const ['economy', 'coins']);
  bool get adsRemoved =>
      _nestedValue(raw, const ['economy', 'adsRemoved']) == true;
  int get totalLoginDays =>
      _nestedInt(raw, const ['overall', 'totalLoginDays']);
  int get totalClearedBalls =>
      _nestedInt(raw, const ['overall', 'totalClearedBalls']);
  int get totalNormalClearedBalls =>
      _nestedInt(raw, const ['overall', 'totalNormalClearedBalls']);
  int get maxChain => _nestedInt(raw, const ['overall', 'maxChain']);
  double get averageChain =>
      doubleValue(_nestedValue(raw, const ['overall', 'averageChain'])) ?? 0;
  String get accountCreatedAt => formatDateTimeText(
        _nonEmptyString(
                _nestedValue(raw, const ['overall', 'accountCreatedAtText'])) ??
            _nonEmptyString(
                _nestedValue(raw, const ['overall', 'accountCreatedAt'])),
      );
  String get lastLoginDate =>
      _nonEmptyString(_nestedValue(raw, const ['overall', 'lastLoginDate'])) ??
      '';
  String get recordDate => _nonEmptyString(raw['recordDate']) ?? '';
  Map<String, int> get modePlayCounts => intMapValue(raw['modePlayCounts']);
  Map<String, int> get todayModePlayCounts =>
      intMapValue(_nestedValue(raw, const ['today', 'modePlayCounts']));
  Map<String, int> get wazaCounts => intMapValue(raw['wazaCounts']);
  Map<String, int> get todayWazaCounts =>
      intMapValue(_nestedValue(raw, const ['today', 'wazaCounts']));
  int get todayTotalMatches => _nestedInt(raw, const ['today', 'totalMatches']);
  int get todayRankedMatches =>
      _nestedInt(raw, const ['today', 'ranked', 'matches']);
  int get todayRankedWins => _nestedInt(raw, const ['today', 'ranked', 'wins']);
  int get todayRankedLosses =>
      _nestedInt(raw, const ['today', 'ranked', 'losses']);
  int get todayRankedRatingStart =>
      _nestedInt(raw, const ['today', 'ranked', 'ratingStart']);
  int get todayRankedRatingCurrent =>
      _nestedInt(raw, const ['today', 'ranked', 'ratingCurrent']);
  int get todayRankedRatingDelta =>
      _nestedInt(raw, const ['today', 'ranked', 'ratingDelta']);
  Map<String, AdminCpuStats> get cpuStats {
    final rawByDifficulty =
        _nestedValue(raw, const ['cpu', 'byDifficulty']) is Map
            ? _nestedValue(raw, const ['cpu', 'byDifficulty']) as Map
            : const {};
    return {
      for (final entry in rawByDifficulty.entries)
        entry.key.toString(): AdminCpuStats.fromValue(entry.value),
    };
  }

  int get friendMatches => _nestedInt(raw, const ['friend', 'matches']);
  List<AdminMatchHistoryEntry> get matchHistory =>
      listValue(raw['matchHistory'])
          .whereType<Map>()
          .map((entry) => AdminMatchHistoryEntry.fromMap(
                Map<String, dynamic>.from(stringDynamicMap(entry)),
              ))
          .toList();
  List<String> get equippedBadgeIds =>
      listValue(_nestedValue(raw, const ['collection', 'equippedBadgeIds']))
          .map((item) => item.toString())
          .toList();
  String get equippedIconId =>
      _nonEmptyString(
          _nestedValue(raw, const ['collection', 'equippedPlayerIconId'])) ??
      '';
  List<String> get ownedBadgeIds =>
      listValue(_nestedValue(raw, const ['collection', 'unlockedBadgeIds']))
          .map((item) => item.toString())
          .toList();
  List<String> get ownedStampIds =>
      listValue(_nestedValue(raw, const ['collection', 'ownedStampIds']))
          .map((item) => item.toString())
          .toList();

  String get updatedAtLabel => formatTimestamp(updatedAt);

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return uid.toLowerCase().contains(normalized) ||
        displayName.toLowerCase().contains(normalized) ||
        publicId.toLowerCase().contains(normalized);
  }
}

class AdminCpuStats {
  const AdminCpuStats({
    required this.matches,
    required this.wins,
    required this.losses,
  });

  final int matches;
  final int wins;
  final int losses;

  double get winRate => matches <= 0 ? 0 : wins / matches * 100;

  factory AdminCpuStats.fromValue(Object? value) {
    final raw = stringDynamicMap(value);
    return AdminCpuStats(
      matches: intValue(raw['matches']) ?? 0,
      wins: intValue(raw['wins']) ?? 0,
      losses: intValue(raw['losses']) ?? 0,
    );
  }
}

class AdminMatchHistoryEntry {
  const AdminMatchHistoryEntry({
    required this.isWin,
    required this.opponentName,
    required this.mode,
    required this.playedAt,
    this.score,
    this.ratingAfter,
    this.ratingDelta,
  });

  final bool isWin;
  final String opponentName;
  final String mode;
  final String playedAt;
  final int? score;
  final int? ratingAfter;
  final int? ratingDelta;

  int? get ratingBefore => ratingAfter == null || ratingDelta == null
      ? null
      : ratingAfter! - ratingDelta!;

  factory AdminMatchHistoryEntry.fromMap(Map<String, dynamic> raw) {
    return AdminMatchHistoryEntry(
      isWin: raw['isWin'] == true,
      opponentName: _nonEmptyString(raw['opponentName']) ?? 'UNKNOWN',
      mode: _nonEmptyString(raw['mode']) ?? 'MATCH',
      playedAt: _nonEmptyString(raw['playedAt']) ?? '',
      score: intValue(raw['score']),
      ratingAfter: intValue(raw['ratingAfter']),
      ratingDelta: intValue(raw['ratingDelta']),
    );
  }
}

class AdminWaitingPlayer {
  const AdminWaitingPlayer({
    required this.uid,
    required this.name,
    required this.status,
    required this.queue,
    required this.rating,
    required this.wins,
    required this.timestamp,
  });

  final String uid;
  final String name;
  final String status;
  final String queue;
  final int? rating;
  final int? wins;
  final int? timestamp;

  String get timestampLabel => formatTimestamp(timestamp);
}

class AdminRoomSummary {
  const AdminRoomSummary({
    required this.roomId,
    required this.status,
    required this.mode,
    required this.seed,
    required this.players,
    required this.results,
    required this.raw,
  });

  final String roomId;
  final String status;
  final String mode;
  final int? seed;
  final Map<String, AdminRoomPlayer> players;
  final Map<String, AdminBattleResult> results;
  final Map<String, dynamic> raw;

  AdminRoomPlayer? get host => players['host'];
  AdminRoomPlayer? get guest => players['guest'];
  bool get isLive => status == 'playing' || status == 'waiting';

  String get title {
    final hostName = host?.displayName ?? 'HOST';
    final guestName = guest?.displayName ?? 'GUEST';
    return '$hostName vs $guestName';
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return roomId.toLowerCase().contains(normalized) ||
        status.toLowerCase().contains(normalized) ||
        mode.toLowerCase().contains(normalized) ||
        players.values.any((player) => player.matches(normalized));
  }
}

class AdminBattleResult {
  const AdminBattleResult({
    required this.role,
    required this.isWin,
    required this.oldRating,
    required this.newRating,
    required this.delta,
    required this.timestamp,
  });

  final String role;
  final bool? isWin;
  final int? oldRating;
  final int? newRating;
  final int? delta;
  final int? timestamp;
}

class AdminRoomPlayer {
  const AdminRoomPlayer({
    required this.role,
    required this.uid,
    required this.displayName,
    required this.status,
    required this.rating,
    required this.board,
    required this.activePiece,
    required this.ojamaSpawns,
    required this.raw,
  });

  final String role;
  final String uid;
  final String displayName;
  final String status;
  final int? rating;
  final Map<String, int> board;
  final AdminActivePiece? activePiece;
  final List<AdminOjamaSpawn> ojamaSpawns;
  final Map<String, dynamic> raw;

  bool matches(String query) {
    return uid.toLowerCase().contains(query) ||
        displayName.toLowerCase().contains(query) ||
        status.toLowerCase().contains(query);
  }
}

class AdminOjamaSpawn {
  const AdminOjamaSpawn({
    required this.id,
    required this.items,
    required this.dropSeed,
    required this.timestamp,
  });

  final String id;
  final List<dynamic> items;
  final int? dropSeed;
  final int? timestamp;
}

class AdminActivePiece {
  const AdminActivePiece({
    required this.x,
    required this.y,
    required this.rotation,
    required this.colors,
    required this.nextColors,
    required this.action,
    required this.dropSeed,
    required this.movingLeft,
    required this.movingRight,
    required this.contactSlideDirection,
    required this.timestamp,
  });

  final double? x;
  final double? y;
  final int? rotation;
  final List<int> colors;
  final List<int> nextColors;
  final String action;
  final int? dropSeed;
  final bool? movingLeft;
  final bool? movingRight;
  final double? contactSlideDirection;
  final int? timestamp;
}

class AdminRoomDetail {
  const AdminRoomDetail({
    required this.summary,
    required this.rawJson,
  });

  final AdminRoomSummary summary;
  final String rawJson;
}

class AdminOverallStats {
  const AdminOverallStats({
    required this.todayKey,
    required this.todayNewPlayers,
    required this.todayLoginPlayers,
    required this.totalPlayers,
    required this.modePlayCounts,
  });

  final String todayKey;
  final int todayNewPlayers;
  final int todayLoginPlayers;
  final int totalPlayers;
  final Map<String, int> modePlayCounts;
}

class AdminRealtimeSnapshot {
  const AdminRealtimeSnapshot({
    required this.onlinePlayers,
    required this.waitingPlayers,
    required this.gameActivities,
  });

  final List<AdminPlayerSummary> onlinePlayers;
  final List<AdminWaitingPlayer> waitingPlayers;
  final List<AdminGameActivity> gameActivities;
}

class AdminGameActivity {
  const AdminGameActivity({
    required this.uid,
    required this.displayName,
    required this.publicId,
    required this.mode,
    required this.roomId,
    required this.enteredAt,
    required this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String publicId;
  final String mode;
  final String roomId;
  final int? enteredAt;
  final int? updatedAt;

  String get modeLabel {
    switch (mode) {
      case 'endless':
        return 'エンドレス';
      case 'cpu':
        return 'コンピュータ';
      case 'ranked':
        return 'ランク戦';
      case 'arena':
        return 'アリーナ';
      case 'friend':
        return 'フレンド';
      default:
        return mode.isEmpty ? '不明' : mode;
    }
  }

  String get updatedAtLabel => formatTimestamp(updatedAt);
}

Map<String, dynamic> stringDynamicMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      entry.key.toString(): normalizeJson(entry.value),
  };
}

Object? normalizeJson(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): normalizeJson(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(normalizeJson).toList();
  }
  return value;
}

String prettyJson(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(normalizeJson(value));
}

AdminPlayerSummary playerSummaryFromEntry(String uid, Object? value) {
  final raw = stringDynamicMap(value);
  return AdminPlayerSummary(
    uid: raw['uid']?.toString().trim().isNotEmpty == true
        ? raw['uid'].toString()
        : uid,
    displayName: _nonEmptyString(raw['displayName']) ?? 'Player',
    publicId: _nonEmptyString(raw['publicId']) ?? '',
    updatedAt: intValue(raw['updatedAt']),
    raw: raw,
  );
}

AdminWaitingPlayer waitingPlayerFromEntry(
  String uid,
  String queue,
  Object? value,
) {
  final raw = stringDynamicMap(value);
  return AdminWaitingPlayer(
    uid: uid,
    queue: queue,
    name: _nonEmptyString(raw['name']) ?? 'Player',
    status: _nonEmptyString(raw['status']) ?? 'waiting',
    rating: intValue(raw['rating']),
    wins: intValue(raw['wins']),
    timestamp: intValue(raw['timestamp']) ?? intValue(raw['joinedAt']),
  );
}

AdminGameActivity gameActivityFromEntry(String uid, Object? value) {
  final raw = stringDynamicMap(value);
  return AdminGameActivity(
    uid: _nonEmptyString(raw['uid']) ?? uid,
    displayName: _nonEmptyString(raw['displayName']) ?? 'Player',
    publicId: _nonEmptyString(raw['publicId']) ?? '',
    mode: _nonEmptyString(raw['mode']) ?? '',
    roomId: _nonEmptyString(raw['roomId']) ?? '',
    enteredAt: intValue(raw['enteredAt']),
    updatedAt: intValue(raw['updatedAt']) ?? intValue(raw['clientUpdatedAt']),
  );
}

AdminRoomSummary roomSummaryFromEntry(String roomId, Object? value) {
  final raw = stringDynamicMap(value);
  final playersRaw = raw['players'] is Map ? raw['players'] as Map : const {};
  final players = <String, AdminRoomPlayer>{};
  for (final entry in playersRaw.entries) {
    final role = entry.key.toString();
    players[role] = roomPlayerFromEntry(role, entry.value);
  }
  final resultsRaw = raw['results'] is Map ? raw['results'] as Map : const {};
  final results = <String, AdminBattleResult>{};
  for (final entry in resultsRaw.entries) {
    final role = entry.key.toString();
    results[role] = battleResultFromEntry(role, entry.value);
  }
  return AdminRoomSummary(
    roomId: roomId,
    status: _nonEmptyString(raw['status']) ?? 'unknown',
    mode: _roomMode(raw),
    seed: intValue(raw['seed']),
    players: players,
    results: results,
    raw: raw,
  );
}

AdminRoomPlayer roomPlayerFromEntry(String role, Object? value) {
  final raw = stringDynamicMap(value);
  return AdminRoomPlayer(
    role: role,
    uid: _nonEmptyString(raw['uid']) ?? '',
    displayName: _nonEmptyString(raw['name']) ??
        _nonEmptyString(raw['displayName']) ??
        role.toUpperCase(),
    status: _nonEmptyString(raw['status']) ?? 'unknown',
    rating: intValue(raw['rating']),
    board: boardFromValue(raw['board']),
    activePiece: activePieceFromValue(raw['activePiece']),
    ojamaSpawns: ojamaSpawnsFromValue(raw['ojamaSpawns']),
    raw: raw,
  );
}

AdminBattleResult battleResultFromEntry(String role, Object? value) {
  final raw = stringDynamicMap(value);
  return AdminBattleResult(
    role: role,
    isWin: raw['isWin'] is bool ? raw['isWin'] as bool : null,
    oldRating: intValue(raw['oldRating']),
    newRating: intValue(raw['newRating']),
    delta: intValue(raw['delta']),
    timestamp: intValue(raw['timestamp']),
  );
}

Map<String, int> boardFromValue(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final result = <String, int>{};
  for (final entry in value.entries) {
    final color = intValue(entry.value);
    if (color == null) {
      continue;
    }
    result[entry.key.toString()] = color;
  }
  return result;
}

AdminActivePiece? activePieceFromValue(Object? value) {
  if (value is! Map) {
    return null;
  }
  final raw = stringDynamicMap(value);
  final colors =
      listValue(raw['colors']).map(intValue).whereType<int>().toList();
  final nextColors =
      listValue(raw['nextColors']).map(intValue).whereType<int>().toList();
  return AdminActivePiece(
    x: doubleValue(raw['x']),
    y: doubleValue(raw['y']),
    rotation: intValue(raw['rotation']),
    colors: colors,
    nextColors: nextColors,
    action: _nonEmptyString(raw['action']) ?? '',
    dropSeed: intValue(raw['dropSeed']),
    movingLeft: raw['movingLeft'] is bool ? raw['movingLeft'] as bool : null,
    movingRight: raw['movingRight'] is bool ? raw['movingRight'] as bool : null,
    contactSlideDirection: doubleValue(raw['contactSlideDirection']),
    timestamp: intValue(raw['timestamp']),
  );
}

List<AdminOjamaSpawn> ojamaSpawnsFromValue(Object? value) {
  if (value is! Map) {
    return const [];
  }
  final spawns = <AdminOjamaSpawn>[];
  for (final entry in value.entries) {
    final raw = stringDynamicMap(entry.value);
    final items = listValue(raw['items']);
    if (items.isEmpty) {
      continue;
    }
    spawns.add(
      AdminOjamaSpawn(
        id: entry.key.toString(),
        items: items,
        dropSeed: intValue(raw['dropSeed']),
        timestamp: intValue(raw['timestamp']),
      ),
    );
  }
  spawns.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
  return spawns;
}

List<Object?> listValue(Object? value) {
  if (value is List) {
    return value;
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return entries.map((entry) => entry.value).toList();
  }
  return const [];
}

Map<String, int> intMapValue(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      if (intValue(entry.value) != null)
        entry.key.toString(): intValue(entry.value)!,
  };
}

int? intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? doubleValue(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

String formatTimestamp(int? millis) {
  if (millis == null || millis <= 0) {
    return '-';
  }
  final local = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String formatDateTimeText(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return '';
  }
  final normalized = text.contains('/') && !text.contains('-')
      ? text.replaceFirstMapped(
          RegExp(r'^(\d{4})/(\d{2})/(\d{2})/'),
          (match) => '${match[1]}-${match[2]}-${match[3]} ',
        )
      : text.replaceFirst('T', ' ');
  final withoutFraction = normalized.split('.').first;
  final parsed = DateTime.tryParse(withoutFraction);
  if (parsed != null) {
    return _formatDateTime(parsed.toLocal());
  }
  final legacy = RegExp(
    r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ /T](\d{1,2}):(\d{1,2}):(\d{1,2})',
  ).firstMatch(text);
  if (legacy != null) {
    return '${legacy[1]}-${legacy[2]!.padLeft(2, '0')}-${legacy[3]!.padLeft(2, '0')} '
        '${legacy[4]!.padLeft(2, '0')}:${legacy[5]!.padLeft(2, '0')}:${legacy[6]!.padLeft(2, '0')}';
  }
  return withoutFraction;
}

String _formatDateTime(DateTime local) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

int _nestedInt(Map<String, dynamic> raw, List<String> path) {
  return intValue(_nestedValue(raw, path)) ?? 0;
}

int _firstNestedInt(Map<String, dynamic> raw, List<List<String>> paths) {
  for (final path in paths) {
    final value = intValue(_nestedValue(raw, path));
    if (value != null) {
      return value;
    }
  }
  return 0;
}

Object? _nestedValue(Map<String, dynamic> raw, List<String> path) {
  Object? cursor = raw;
  for (final segment in path) {
    if (cursor is! Map || !cursor.containsKey(segment)) {
      return null;
    }
    cursor = cursor[segment];
  }
  return cursor;
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String _roomMode(Map<String, dynamic> raw) {
  final mode = _nonEmptyString(raw['mode']);
  if (mode != null) {
    return mode;
  }
  if (raw['ranked'] == true) {
    return 'ranked';
  }
  return 'casual';
}
