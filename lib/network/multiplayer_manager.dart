import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_selection_manager.dart';
import '../auth/auth_manager.dart';
import '../data/models/game_item.dart';
import '../data/player_data_manager.dart';
import '../firebase_database_provider.dart';
import '../game/game_models.dart';
import '../moderation/moderation_manager.dart';
import 'ranked_season_manager.dart';
import 'realtime_connection_guard.dart';
import 'realtime_transport_client.dart';
import 'server_time_manager.dart';

typedef RoomUpdateCallback = void Function(MultiplayerRoom room);
typedef OpponentBoardUpdateCallback = void Function(Map<String, dynamic> board);
typedef OpponentPieceUpdateCallback = void Function(Map<String, dynamic> piece);
typedef AttackReceivedCallback = void Function(OjamaTask task);
typedef OpponentOjamaSpawnedCallback = void Function(
  List<dynamic> ojamaData,
  int dropSeed,
);
typedef OpponentStampReceivedCallback = void Function(
  String stampId,
  int level,
);
typedef OpponentGameOverCallback = void Function({
  Map<String, dynamic>? finalBoard,
  String? reason,
});
typedef OpponentDisconnectedCallback = void Function();
typedef RematchStartedCallback = void Function(int newSeed);

int? _globalIntValue(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value');
}

class MultiplayerPlayer {
  const MultiplayerPlayer({
    required this.status,
    this.name = 'Player',
    this.uid,
    this.publicId = '',
    this.rating,
    this.badgeIds = const [],
    this.playerIconId = 'default',
    this.playerIconFrameId = 'default',
    this.ballSkinId = 'default',
    this.formationEffectId = 'effect_formation_default',
    this.ojamaEffectId = 'effect_ojama_default',
    this.readySfxId = 'ready_01',
    this.sfxSelectionIds = const {},
  });

  final String status;
  final String name;
  final String? uid;
  final String publicId;
  final int? rating;
  final List<String> badgeIds;
  final String playerIconId;
  final String playerIconFrameId;
  final String ballSkinId;
  final String formationEffectId;
  final String ojamaEffectId;
  final String readySfxId;
  final Map<String, String> sfxSelectionIds;

  factory MultiplayerPlayer.fromMap(Map<dynamic, dynamic>? data) {
    return MultiplayerPlayer(
      status: (data?['status'] as String?) ?? 'waiting',
      name: _normalizePlayerName(data?['name'] as String?),
      uid: data?['uid'] as String?,
      publicId: data?['publicId']?.toString() ?? '',
      rating: _intValue(data?['rating']),
      badgeIds: _stringList(data?['badgeIds']),
      playerIconId:
          ((data?['playerIconId']?.toString() ?? '').trim()).isNotEmpty
              ? data!['playerIconId'].toString().trim()
              : 'default',
      playerIconFrameId:
          ((data?['playerIconFrameId']?.toString() ?? '').trim()).isNotEmpty
              ? data!['playerIconFrameId'].toString().trim()
              : 'default',
      ballSkinId: ((data?['ballSkinId']?.toString() ?? '').trim()).isNotEmpty
          ? data!['ballSkinId'].toString().trim()
          : 'default',
      formationEffectId:
          ((data?['formationEffectId']?.toString() ?? '').trim()).isNotEmpty
              ? data!['formationEffectId'].toString().trim()
              : 'effect_formation_default',
      ojamaEffectId:
          ((data?['ojamaEffectId']?.toString() ?? '').trim()).isNotEmpty
              ? data!['ojamaEffectId'].toString().trim()
              : 'effect_ojama_default',
      readySfxId: ((data?['readySfxId']?.toString() ?? '').trim()).isNotEmpty
          ? data!['readySfxId'].toString().trim()
          : 'ready_01',
      sfxSelectionIds: _stringMap(data?['sfxSelectionIds']),
    );
  }

  static String _normalizePlayerName(String? value) {
    final name = value?.trim() ?? '';
    return name.isEmpty ? 'Player' : name;
  }

  static int? _intValue(Object? value) {
    return _globalIntValue(value);
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return entries
          .map((entry) => '${entry.value}')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        if (entry.key.toString().trim().isNotEmpty &&
            entry.value.toString().trim().isNotEmpty)
          entry.key.toString().trim(): entry.value.toString().trim(),
    };
  }
}

class MultiplayerRoom {
  const MultiplayerRoom({
    required this.roomId,
    required this.status,
    required this.seed,
    required this.players,
    this.isRanked = false,
    this.seasonId,
    this.seasonEndsAt,
    this.hostBoardRows = 12,
    this.guestBoardRows = 12,
  });

  final String roomId;
  final String status;
  final int seed;
  final Map<String, MultiplayerPlayer> players;
  final bool isRanked;
  final String? seasonId;
  final int? seasonEndsAt;
  final int hostBoardRows;
  final int guestBoardRows;

  bool get hasHost => players.containsKey('host');
  bool get hasGuest => players.containsKey('guest');
  bool get bothPlayersJoined => hasHost && hasGuest;
  bool get bothPlayersReady =>
      players['host']?.status == 'ready' && players['guest']?.status == 'ready';
  bool get bothPlayersRematchReady =>
      players['host']?.status == 'rematch_ready' &&
      players['guest']?.status == 'rematch_ready';
  String? statusFor(String roleId) => players[roleId]?.status;
  int boardRowsForRole(String roleId) =>
      roleId == 'guest' ? guestBoardRows : hostBoardRows;

  factory MultiplayerRoom.fromSnapshot(String roomId, Object? value) {
    final map = value is Map<dynamic, dynamic> ? value : <dynamic, dynamic>{};
    final playersRaw = map['players'] as Map<dynamic, dynamic>? ?? {};
    final handicapRowsRaw =
        map['handicapRows'] as Map<dynamic, dynamic>? ?? const {};
    int parseBoardRows(Object? raw) {
      final value = _globalIntValue(raw) ?? 12;
      return value.clamp(3, 12).toInt();
    }

    return MultiplayerRoom(
      roomId: roomId,
      status: (map['status'] as String?) ?? 'waiting',
      seed: (map['seed'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      isRanked: map['mode'] == 'ranked' ||
          map['mode'] == 'arena' ||
          map['ranked'] == true,
      seasonId: map['seasonId']?.toString(),
      seasonEndsAt: _globalIntValue(map['seasonEndsAt']),
      hostBoardRows: parseBoardRows(handicapRowsRaw['host']),
      guestBoardRows: parseBoardRows(handicapRowsRaw['guest']),
      players: {
        for (final entry in playersRaw.entries)
          entry.key.toString(): MultiplayerPlayer.fromMap(
            entry.value is Map<dynamic, dynamic>
                ? entry.value as Map<dynamic, dynamic>
                : null,
          ),
      },
    );
  }
}

class RankedRatingChange {
  const RankedRatingChange({
    required this.oldRating,
    required this.newRating,
    required this.delta,
  });

  final int oldRating;
  final int newRating;
  final int delta;
}

class SavedOnlineSession {
  const SavedOnlineSession({
    required this.roomId,
    required this.roleId,
    required this.isRankedMode,
    required this.isArenaMode,
    required this.savedAt,
    this.snapshot,
  });

  final String roomId;
  final String roleId;
  final bool isRankedMode;
  final bool isArenaMode;
  final int savedAt;
  final Map<String, dynamic>? snapshot;

  bool get isHost => roleId == 'host';

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'roleId': roleId,
      'isRankedMode': isRankedMode,
      'isArenaMode': isArenaMode,
      'savedAt': savedAt,
      if (snapshot != null) 'snapshot': snapshot,
    };
  }

  factory SavedOnlineSession.fromJson(Map<String, dynamic> json) {
    return SavedOnlineSession(
      roomId: json['roomId']?.toString() ?? '',
      roleId: json['roleId']?.toString() ?? '',
      isRankedMode: json['isRankedMode'] == true,
      isArenaMode: json['isArenaMode'] == true,
      savedAt: _globalIntValue(json['savedAt']) ?? 0,
      snapshot: json['snapshot'] is Map
          ? Map<String, dynamic>.from(json['snapshot'] as Map)
          : null,
    );
  }
}

class SavedSessionResolution {
  const SavedSessionResolution({
    required this.session,
    required this.isResolved,
    this.isWin,
    this.oldRating,
    this.newRating,
    this.ratingDelta,
    this.opponentName,
    this.wasAbandoned = false,
    this.wasOfflineDisconnect = false,
  });

  final SavedOnlineSession session;
  final bool isResolved;
  final bool? isWin;
  final int? oldRating;
  final int? newRating;
  final int? ratingDelta;
  final String? opponentName;
  final bool wasAbandoned;
  final bool wasOfflineDisconnect;
}

class RoomResultSnapshot {
  const RoomResultSnapshot({
    required this.isWin,
    this.reason = '',
  });

  final bool isWin;
  final String reason;

  bool get isForfeit =>
      reason == 'offline_forfeit' || reason == 'opponent_offline_forfeit';
}

class _MatchmakingCandidate {
  const _MatchmakingCandidate({
    required this.uid,
    required this.rating,
    required this.timestamp,
  });

  final String uid;
  final int rating;
  final int timestamp;
}

class _RankedMatchmakingConfig {
  const _RankedMatchmakingConfig({
    required this.botFallbackSeconds,
    required this.rangeGrowthPerSecond,
  });

  static const fallback = _RankedMatchmakingConfig(
    botFallbackSeconds: MultiplayerManager.rankedBotFallbackSeconds,
    rangeGrowthPerSecond:
        MultiplayerManager.rankedMatchmakingRangeGrowthPerSecond,
  );

  final int botFallbackSeconds;
  final int rangeGrowthPerSecond;
}

class MultiplayerManager {
  MultiplayerManager._internal();

  static final MultiplayerManager _instance = MultiplayerManager._internal();

  factory MultiplayerManager() => _instance;

  static MultiplayerManager get instance => _instance;

  static const int initialRating = 1000;
  static const int rankedBotMinimumMaxRating = 1500;
  static const int rankedBotRatingLeadOffset = 300;
  static const int rankedBotRatingLeadVariance = 40;
  static const int rankedBotStrengthMinRating = 700;
  static const int rankedMatchmakingInitialRange = 50;
  static const int rankedMatchmakingRangeGrowthPerSecond = 40;
  static const int rankedBotFallbackSeconds = 10;
  static const Duration rankedBotTopRatingTimeout = Duration(seconds: 3);
  static const Duration matchmakingDatabaseOperationTimeout =
      Duration(seconds: 5);
  static const Duration rankedMatchmakingConfigTimeout = Duration(seconds: 2);
  static const Duration rankedMatchmakingConfigCacheTtl = Duration(seconds: 30);
  static const String rankedBotRoomId = '__ranked_bot__';
  static const String _savedSessionPrefsKey = 'multiplayer_saved_session_v2';
  static const List<String> _legacySavedSessionPrefsKeys = [
    'multiplayer_saved_session_v1',
  ];

  final Random _random = Random();
  final RealtimeTransportClient _realtimeTransportClient =
      RealtimeTransportClient();

  String? currentRoomId;
  String? myRoleId;
  String? myUid;
  MultiplayerRoom? currentRoom;
  String playerName = 'Player';
  int currentRating = initialRating;
  bool isRankedMode = false;
  int? rankedBotRating;
  CPUDifficulty? rankedBotDifficulty;
  String rankedBotIconId = 'default';
  String rankedBotFrameId = 'default';
  String? rankedBotSeasonId;
  int? rankedBotSeasonEndsAt;

  StreamSubscription<DatabaseEvent>? _roomSubscription;
  StreamSubscription<DatabaseEvent>? _roomStatusSubscription;
  StreamSubscription<DatabaseEvent>? _myStatusSubscription;
  StreamSubscription<DatabaseEvent>? _opponentBoardSubscription;
  StreamSubscription<DatabaseEvent>? _opponentPieceSubscription;
  StreamSubscription<DatabaseEvent>? _attackSubscription;
  StreamSubscription<DatabaseEvent>? _stampSubscription;
  StreamSubscription<DatabaseEvent>? _opponentOjamaSpawnSubscription;
  StreamSubscription<DatabaseEvent>? _opponentStatusSubscription;
  StreamSubscription<DatabaseEvent>? _matchmakingInviteSubscription;
  Timer? _matchmakingPollTimer;
  Completer<String?>? _matchmakingCompleter;
  RoomUpdateCallback? onRoomUpdated;
  OpponentBoardUpdateCallback? onOpponentBoardUpdated;
  OpponentPieceUpdateCallback? onOpponentPieceUpdated;
  AttackReceivedCallback? onAttackReceived;
  OpponentOjamaSpawnedCallback? onOpponentOjamaSpawned;
  OpponentStampReceivedCallback? onOpponentStampReceived;
  OpponentGameOverCallback? onOpponentGameOver;
  OpponentDisconnectedCallback? onOpponentDisconnected;
  RematchStartedCallback? onRematchStarted;

  String? _lastRoomStatus;
  String? _lastRoomUiSignature;
  bool _hadOpponentPresent = false;
  bool _isLaunchingRematch = false;
  bool _isMatchFound = false;
  bool _isMatchmakingAttemptInProgress = false;
  bool _opponentDisconnectNotified = false;
  bool? _presencePreserveMode;
  DateTime? _matchmakingStartedAt;
  _RankedMatchmakingConfig _activeRankedMatchmakingConfig =
      _RankedMatchmakingConfig.fallback;
  _RankedMatchmakingConfig? _rankedMatchmakingConfigCache;
  DateTime? _rankedMatchmakingConfigCacheAt;
  String? _activeMatchmakingPath;
  int _matchmakingGeneration = 0;

  bool get isHost => myRoleId == 'host';
  bool get isGuest => myRoleId == 'guest';
  String get opponentRoleId => myRoleId == 'host' ? 'guest' : 'host';
  String get displayPlayerName =>
      playerName.trim().isEmpty ? 'Player' : playerName.trim();

  bool isRankedBotRoomId(String? roomId) => roomId == rankedBotRoomId;

  void setPlayerName(String name) {
    final nextName = ModerationManager.instance.sanitizePlayerName(name);
    playerName = nextName.isEmpty ? 'Player' : nextName;
  }

  DatabaseReference get _db {
    return AppFirebaseDatabase.ref();
  }

  Future<List<String>> _currentEquippedBadgeIds() async {
    await PlayerDataManager.instance.load();
    return PlayerDataManager.instance.equippedBadgeIds.toList();
  }

  Future<String> _currentEquippedPlayerIconId() async {
    await PlayerDataManager.instance.load();
    final iconId = PlayerDataManager.instance.equippedPlayerIconId.trim();
    return iconId.isEmpty ? 'default' : iconId;
  }

  Future<String> _currentEquippedIconFrameId() async {
    await PlayerDataManager.instance.load();
    final frameId = PlayerDataManager.instance.equippedIconFrameId.trim();
    return frameId.isEmpty ? 'default' : frameId;
  }

  Future<String> _currentEquippedBallSkinId() async {
    await PlayerDataManager.instance.load();
    final skinId = PlayerDataManager.instance.equippedBallSkinId.trim();
    return skinId.isEmpty ? 'default' : skinId;
  }

  Future<String> _currentEquippedFormationEffectId() async {
    await PlayerDataManager.instance.load();
    final effectId =
        PlayerDataManager.instance.equippedFormationEffectId.trim();
    return effectId.isEmpty ? 'effect_formation_default' : effectId;
  }

  Future<String> _currentEquippedOjamaEffectId() async {
    await PlayerDataManager.instance.load();
    final effectId = PlayerDataManager.instance.equippedOjamaEffectId.trim();
    return effectId.isEmpty ? 'effect_ojama_default' : effectId;
  }

  Future<String> _currentReadySfxId() {
    return AudioSelectionManager.selectedSfxId('ready', 'ready_01');
  }

  Future<Map<String, String>> _currentSfxSelectionIds() async {
    await PlayerDataManager.instance.load();
    return AudioSelectionManager.loadSyncedSfxSelections(
      playerName: PlayerDataManager.instance.displayPlayerName,
    );
  }

  Future<Map<String, Object?>> _buildPlayerPayload({
    required String status,
    int? rating,
  }) async {
    final badgeIds = await _currentEquippedBadgeIds();
    final playerIconId = await _currentEquippedPlayerIconId();
    final playerIconFrameId = await _currentEquippedIconFrameId();
    final ballSkinId = await _currentEquippedBallSkinId();
    final formationEffectId = await _currentEquippedFormationEffectId();
    final ojamaEffectId = await _currentEquippedOjamaEffectId();
    final readySfxId = await _currentReadySfxId();
    final sfxSelectionIds = await _currentSfxSelectionIds();
    return {
      'status': status,
      'name': displayPlayerName,
      'uid': myUid,
      'publicId': PlayerDataManager.instance.playerId,
      if (rating != null) 'rating': rating,
      'badgeIds': badgeIds,
      'playerIconId': playerIconId,
      'playerIconFrameId': playerIconFrameId,
      'ballSkinId': ballSkinId,
      'formationEffectId': formationEffectId,
      'ojamaEffectId': ojamaEffectId,
      'readySfxId': readySfxId,
      'sfxSelectionIds': sfxSelectionIds,
    };
  }

  Future<int> initializeUser({String? name}) async {
    final hasProvidedName = name?.trim().isNotEmpty ?? false;
    if (name != null) {
      setPlayerName(name);
    }

    final uid = await _loadAuthenticatedUid();
    myUid = uid;
    await PlayerDataManager.instance.load();
    final localRating = PlayerDataManager.instance.currentRating;
    final localSeasonId = PlayerDataManager.instance.rankedSeasonId.trim();
    String currentSeasonId = '';
    try {
      currentSeasonId = await _currentSeasonId(forceRefresh: true);
    } catch (_) {
      // サーバー時刻の取得に失敗した場合は、後続の必須シーズン同期で補正する。
    }
    final canTrustLocalSeason =
        currentSeasonId.isEmpty || localSeasonId == currentSeasonId;
    currentRating = canTrustLocalSeason ? localRating : initialRating;

    try {
      final userRef = _db.child('users/$uid');
      final snapshot =
          await userRef.get().timeout(matchmakingDatabaseOperationTimeout);
      final userData = snapshot.value is Map ? snapshot.value as Map : null;
      final remoteRating = _intValue(userData?['rating']);
      final syncedRating = canTrustLocalSeason
          ? localRating
          : (currentSeasonId.isEmpty
              ? (remoteRating ?? initialRating)
              : initialRating);
      currentRating = syncedRating;
      final hasSavedName =
          PlayerDataManager.instance.playerName.trim().isNotEmpty;
      if (!hasProvidedName && !hasSavedName) {
        return currentRating;
      }
      await userRef.update({
        'name': displayPlayerName,
        'publicId': PlayerDataManager.instance.playerId,
        'rating': syncedRating,
        'updatedAt': ServerValue.timestamp,
      }).timeout(matchmakingDatabaseOperationTimeout);
    } on TimeoutException {
      return currentRating;
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ユーザー情報の同期', error));
    }

    return currentRating;
  }

  Future<void> updateUserName(String name) async {
    setPlayerName(name);
    final uid = myUid ?? await _loadAuthenticatedUid();
    myUid = uid;

    final playerIconId = await _currentEquippedPlayerIconId();
    final playerIconFrameId = await _currentEquippedIconFrameId();
    final ballSkinId = await _currentEquippedBallSkinId();
    final formationEffectId = await _currentEquippedFormationEffectId();
    final ojamaEffectId = await _currentEquippedOjamaEffectId();
    final readySfxId = await _currentReadySfxId();
    final sfxSelectionIds = await _currentSfxSelectionIds();
    await _db.child('users/$uid').update({
      'name': displayPlayerName,
      'publicId': PlayerDataManager.instance.playerId,
      'rating': currentRating,
      'updatedAt': ServerValue.timestamp,
    }).timeout(matchmakingDatabaseOperationTimeout);
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId != null && roleId != null) {
      try {
        await _db.child('rooms/$roomId/players/$roleId').update({
          'name': displayPlayerName,
          'publicId': PlayerDataManager.instance.playerId,
          'playerIconId': playerIconId,
          'playerIconFrameId': playerIconFrameId,
          'ballSkinId': ballSkinId,
          'formationEffectId': formationEffectId,
          'ojamaEffectId': ojamaEffectId,
          'readySfxId': readySfxId,
          'sfxSelectionIds': sfxSelectionIds,
          'updatedAt': ServerValue.timestamp,
        }).timeout(matchmakingDatabaseOperationTimeout);
      } catch (_) {
        // 対戦終了直後にルームが削除済みでも、永続プロフィール同期は成功扱いにする。
      }
    }
  }

  int calculateNewRating(int myRating, int opponentRating, bool isWin) {
    final expected = 1 / (1 + pow(10, (opponentRating - myRating) / 400));
    final rawDelta = (100 * ((isWin ? 1 : 0) - expected)).round();
    final delta =
        isWin ? max(5, min(95, rawDelta)) : max(-95, min(-5, rawDelta));
    return myRating + delta;
  }

  Future<RankedRatingChange?> applyRankedResult({
    required bool isWin,
    bool applyOpponentResult = false,
    String? reason,
  }) async {
    if (!isRankedMode) {
      return null;
    }

    final uid = myUid ?? await _loadAuthenticatedUid();
    myUid = uid;

    final oldRating = currentRating;
    final opponentRating =
        currentRoom?.players[opponentRoleId]?.rating ?? oldRating;
    final seasonExpired = await _rankedRoomSeasonExpired(currentRoom);
    final newRating = seasonExpired
        ? oldRating
        : calculateNewRating(oldRating, opponentRating, isWin);
    final delta = newRating - oldRating;

    currentRating = newRating;

    try {
      await _db.child('users/$uid').update({
        'name': displayPlayerName,
        'publicId': PlayerDataManager.instance.playerId,
        'rating': newRating,
        'updatedAt': ServerValue.timestamp,
      });

      final roomId = currentRoomId;
      final roleId = myRoleId;
      if (roomId != null && roleId != null) {
        await _db.child('rooms/$roomId/results/$roleId').set({
          'uid': uid,
          'isWin': isWin,
          'oldRating': oldRating,
          'newRating': newRating,
          'delta': delta,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
          if (seasonExpired) 'seasonExpired': true,
          if (currentRoom?.seasonId != null) 'seasonId': currentRoom!.seasonId,
          'timestamp': ServerValue.timestamp,
        });

        if (applyOpponentResult) {
          await _applyOpponentRankedResult(
            roomId: roomId,
            myOldRating: oldRating,
            opponentWon: !isWin,
            seasonExpired: seasonExpired,
            reason: reason == 'opponent_offline_forfeit'
                ? 'offline_forfeit'
                : reason,
          );
        }
        unawaited(
          _removeRoomIfFinishedAfterDelay(roomId, const Duration(seconds: 5)),
        );
      }
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('レート更新', error));
    }

    return RankedRatingChange(
      oldRating: oldRating,
      newRating: newRating,
      delta: delta,
    );
  }

  Future<RankedRatingChange> applyRankedBotResult({
    required bool isWin,
    required int opponentRating,
  }) async {
    final uid = myUid ?? await _loadAuthenticatedUid();
    myUid = uid;

    final oldRating = currentRating;
    final seasonExpired = await _rankedBotSeasonExpired();
    final newRating = seasonExpired
        ? oldRating
        : calculateNewRating(oldRating, opponentRating, isWin);
    final delta = newRating - oldRating;
    currentRating = newRating;

    await _db.child('users/$uid').update({
      'name': displayPlayerName,
      'rating': newRating,
      'updatedAt': ServerValue.timestamp,
    });

    return RankedRatingChange(
      oldRating: oldRating,
      newRating: newRating,
      delta: delta,
    );
  }

  Future<void> _applyOpponentRankedResult({
    required String roomId,
    required int myOldRating,
    required bool opponentWon,
    required bool seasonExpired,
    String? reason,
  }) async {
    final opponent = currentRoom?.players[opponentRoleId];
    final opponentUid = opponent?.uid;
    final opponentOldRating = opponent?.rating;
    if (opponentUid == null || opponentOldRating == null) {
      return;
    }

    final resultRef = _db.child('rooms/$roomId/results/$opponentRoleId');
    final existingResult = await resultRef.get();
    if (existingResult.exists) {
      return;
    }

    final opponentNewRating = seasonExpired
        ? opponentOldRating
        : calculateNewRating(
            opponentOldRating,
            myOldRating,
            opponentWon,
          );
    final opponentDelta = opponentNewRating - opponentOldRating;
    await resultRef.set({
      'uid': opponentUid,
      'isWin': opponentWon,
      'oldRating': opponentOldRating,
      'newRating': opponentNewRating,
      'delta': opponentDelta,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (seasonExpired) 'seasonExpired': true,
      if (currentRoom?.seasonId != null) 'seasonId': currentRoom!.seasonId,
      'resolvedBy': myUid,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<bool> _rankedRoomSeasonExpired(MultiplayerRoom? room) async {
    if (room?.seasonId == null) {
      return false;
    }
    final nowJst = await ServerTimeManager.instance.nowJst(forceRefresh: true);
    return room!.seasonId !=
        RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
  }

  Future<bool> _rankedBotSeasonExpired() async {
    final seasonId = rankedBotSeasonId;
    if (seasonId == null || seasonId.isEmpty) {
      return false;
    }
    final nowJst = await ServerTimeManager.instance.nowJst(forceRefresh: true);
    return seasonId !=
        RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
  }

  Future<String> _currentSeasonId({bool forceRefresh = false}) async {
    final nowJst =
        await ServerTimeManager.instance.nowJst(forceRefresh: forceRefresh);
    return RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
  }

  Future<String> createRoom() async {
    try {
      await leaveRoom();
      await initializeUser();

      for (int attempt = 0; attempt < 10; attempt++) {
        final hostData = await _buildPlayerPayload(status: 'waiting');
        final roomId = (_random.nextInt(900000) + 100000).toString();
        final roomRef = _db.child('rooms/$roomId');
        final existing = await roomRef.get();
        if (existing.exists) {
          continue;
        }

        final seed = DateTime.now().millisecondsSinceEpoch;
        await roomRef.set({
          'mode': 'friend',
          'status': 'waiting',
          'seed': seed,
          'createdAt': ServerValue.timestamp,
          'updatedAt': ServerValue.timestamp,
          'handicapRows': {
            'host': 12,
            'guest': 12,
          },
          'players': {
            'host': hostData,
          },
        });

        currentRoomId = roomId;
        myRoleId = 'host';
        isRankedMode = false;
        currentRoom = MultiplayerRoom(
          roomId: roomId,
          status: 'waiting',
          seed: seed,
          isRanked: false,
          hostBoardRows: 12,
          guestBoardRows: 12,
          players: {
            'host': MultiplayerPlayer.fromMap(hostData),
          },
        );
        _lastRoomStatus = currentRoom!.status;
        _hadOpponentPresent = false;
        _opponentDisconnectNotified = false;
        _presencePreserveMode = null;
        await _syncPresenceMode();
        _listenRoom();
        _listenGameplayChannels();
        unawaited(_connectRealtimeTransportIfEnabled());
        return roomId;
      }

      throw StateError('ルームIDの生成に失敗しました。もう一度お試しください。');
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ルーム作成', error));
    }
  }

  Future<bool> joinRoom(String roomId) async {
    try {
      await leaveRoom();
      await initializeUser();

      final roomRef = _db.child('rooms/$roomId');
      final snapshot = await roomRef.get();
      if (!snapshot.exists) {
        return false;
      }

      final room = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
      if (room.status != 'waiting' || room.hasGuest) {
        return false;
      }

      final guestData = await _buildPlayerPayload(
        status: 'waiting',
        rating: room.isRanked ? currentRating : null,
      );
      if (room.isRanked) {
        guestData['rating'] = currentRating;
      }

      await roomRef.child('players/guest').set(guestData);

      currentRoomId = roomId;
      myRoleId = 'guest';
      isRankedMode = room.isRanked;
      currentRoom = MultiplayerRoom(
        roomId: room.roomId,
        status: room.status,
        seed: room.seed,
        isRanked: room.isRanked,
        hostBoardRows: room.hostBoardRows,
        guestBoardRows: room.guestBoardRows,
        players: {
          ...room.players,
          'guest': MultiplayerPlayer.fromMap(guestData),
        },
      );
      _lastRoomStatus = currentRoom!.status;
      _hadOpponentPresent = currentRoom!.players.containsKey(opponentRoleId);
      _opponentDisconnectNotified = false;
      _presencePreserveMode = null;
      await _syncPresenceMode();
      _listenRoom();
      _listenGameplayChannels();
      unawaited(_connectRealtimeTransportIfEnabled());
      return true;
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ルーム参加', error));
    }
  }

  Future<String?> startRandomMatch(int myRating) async {
    await cancelMatchmaking();
    final generation = _matchmakingGeneration;
    await initializeUser();
    if (!_isCurrentMatchmakingGeneration(generation)) {
      return null;
    }
    await leaveRoom();
    if (!_isCurrentMatchmakingGeneration(generation)) {
      return null;
    }

    final uid = myUid;
    if (uid == null) {
      throw StateError('ユーザーIDの初期化に失敗しました。');
    }

    currentRating = myRating;
    rankedBotRating = null;
    rankedBotDifficulty = null;
    rankedBotIconId = 'default';
    rankedBotFrameId = 'default';
    rankedBotSeasonId = null;
    rankedBotSeasonEndsAt = null;
    _isMatchFound = false;
    _isMatchmakingAttemptInProgress = false;
    _activeRankedMatchmakingConfig = await _loadRankedMatchmakingConfig();
    _matchmakingStartedAt = DateTime.now();
    _activeMatchmakingPath = 'matchmaking';
    final completer = Completer<String?>();
    _matchmakingCompleter = completer;

    final entryRef = _db.child('matchmaking/$uid');
    Timer? rankedBotTimer;

    try {
      try {
        await entryRef
            .onDisconnect()
            .remove()
            .timeout(matchmakingDatabaseOperationTimeout);
        await _writeWaitingMatchmakingEntry(uid, myRating)
            .timeout(matchmakingDatabaseOperationTimeout);
      } catch (_) {
        // DB待機列が使えない場合でも、Bot補完までは進める。
      }

      _matchmakingInviteSubscription = entryRef.onValue.listen(
        (event) {
          _handleRandomMatchAssignment(event.snapshot.value);
        },
        onError: (Object error, StackTrace stackTrace) {
          _completeMatchmakingError(error, stackTrace);
        },
      );

      unawaited(_tryRandomMatch(myRating));
      _matchmakingPollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_tryRandomMatch(myRating)),
      );
      rankedBotTimer = Timer(
        Duration(seconds: _activeRankedMatchmakingConfig.botFallbackSeconds),
        () => unawaited(_completeRankedBotMatch(myRating)),
      );

      return await completer.future;
    } finally {
      rankedBotTimer?.cancel();
      if (_isCurrentMatchmakingGeneration(generation)) {
        await _cleanupMatchmaking();
      }
    }
  }

  Future<String?> startArenaMatch(int currentWins) async {
    await cancelMatchmaking();
    final generation = _matchmakingGeneration;
    await initializeUser();
    if (!_isCurrentMatchmakingGeneration(generation)) {
      return null;
    }
    await leaveRoom();
    if (!_isCurrentMatchmakingGeneration(generation)) {
      return null;
    }

    final uid = myUid;
    if (uid == null) {
      throw StateError('ユーザーIDの初期化に失敗しました。');
    }

    _isMatchFound = false;
    _isMatchmakingAttemptInProgress = false;
    _matchmakingStartedAt = DateTime.now();
    _activeMatchmakingPath = 'arena_matchmaking';
    final completer = Completer<String?>();
    _matchmakingCompleter = completer;

    final entryRef = _db.child('arena_matchmaking/$uid');

    try {
      await entryRef.onDisconnect().remove();
      await _writeWaitingArenaMatchmakingEntry(uid, currentWins);

      _matchmakingInviteSubscription = entryRef.onValue.listen(
        (event) {
          _handleRandomMatchAssignment(event.snapshot.value);
        },
        onError: (Object error, StackTrace stackTrace) {
          _completeMatchmakingError(error, stackTrace);
        },
      );

      unawaited(_tryArenaMatch(currentWins));
      _matchmakingPollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_tryArenaMatch(currentWins)),
      );

      return await completer.future;
    } finally {
      if (_isCurrentMatchmakingGeneration(generation)) {
        await _cleanupMatchmaking();
      }
    }
  }

  Future<void> cancelMatchmaking() async {
    _matchmakingGeneration++;
    _isMatchFound = true;
    _isMatchmakingAttemptInProgress = false;
    final completer = _matchmakingCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    await _cleanupMatchmaking();
  }

  Future<void> cancelArenaMatchmaking() => cancelMatchmaking();

  bool _isCurrentMatchmakingGeneration(int generation) {
    return generation == _matchmakingGeneration;
  }

  void _handleRandomMatchAssignment(Object? value) {
    if (_isMatchFound || _isMatchmakingAttemptInProgress) {
      return;
    }

    final data = value is Map ? value : null;
    if (data == null) {
      return;
    }

    final roomId = _nonEmptyString(data['roomId']);
    final role = data['role']?.toString();
    if (roomId == null || role == 'host') {
      return;
    }

    unawaited(_acceptRandomMatchAsGuest(roomId));
  }

  Future<void> _acceptRandomMatchAsGuest(String roomId) async {
    if (_isMatchFound || _isMatchmakingAttemptInProgress) {
      return;
    }

    _isMatchFound = true;
    _matchmakingPollTimer?.cancel();

    try {
      final joined = await _joinRoomWhenReady(roomId);
      if (!joined) {
        throw StateError('ランク戦の部屋に参加できませんでした。');
      }
      _completeMatchmaking(roomId);
    } catch (error, stackTrace) {
      _completeMatchmakingError(error, stackTrace);
    }
  }

  Future<void> _tryRandomMatch(int myRating) async {
    final uid = myUid;
    final completer = _matchmakingCompleter;
    if (uid == null ||
        completer == null ||
        completer.isCompleted ||
        _isMatchFound ||
        _isMatchmakingAttemptInProgress) {
      return;
    }

    try {
      await _refreshWaitingMatchmakingEntry(uid, myRating);

      final ownEntrySnapshot = await _db.child('matchmaking/$uid').get();
      final ownEntry =
          ownEntrySnapshot.value is Map ? ownEntrySnapshot.value as Map : null;
      final assignedRoomId = _nonEmptyString(ownEntry?['roomId']);
      final assignedRole = ownEntry?['role']?.toString();
      if (assignedRoomId != null && assignedRole != 'host') {
        unawaited(_acceptRandomMatchAsGuest(assignedRoomId));
        return;
      }
      if (ownEntry == null) {
        await _writeWaitingMatchmakingEntry(uid, myRating);
        return;
      }
      if (_matchmakingStatus(ownEntry) != 'waiting') {
        return;
      }

      final range = _currentMatchmakingRange();
      final rawPlayers = await _fetchRankedMatchmakingEntriesInRange(
        myRating: myRating,
        range: range,
      );
      if (rawPlayers.isEmpty) {
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final candidates = <_MatchmakingCandidate>[];
      for (final entry in rawPlayers) {
        final opponentUid = entry.key.toString();
        if (opponentUid == uid) {
          continue;
        }
        if (await ModerationManager.instance.isBlocked(opponentUid)) {
          continue;
        }

        final data = entry.value;
        if (data is! Map) {
          continue;
        }

        if (_matchmakingStatus(data) != 'waiting') {
          continue;
        }

        if (!_isFreshMatchmakingEntry(data)) {
          continue;
        }

        if (_nonEmptyString(data['roomId']) != null) {
          continue;
        }

        final rating = _intValue(data['rating']);
        if (rating == null) {
          continue;
        }
        final ratingDistance = (rating - myRating).abs();
        final opponentRange = _matchmakingRangeForEntry(data, now);
        if (ratingDistance > range || ratingDistance > opponentRange) {
          continue;
        }

        candidates.add(
          _MatchmakingCandidate(
            uid: opponentUid,
            rating: rating,
            timestamp: _intValue(data['joinedAt']) ??
                _intValue(data['timestamp']) ??
                0,
          ),
        );
      }

      candidates.sort((a, b) {
        final distanceA = (a.rating - myRating).abs();
        final distanceB = (b.rating - myRating).abs();
        final distanceOrder = distanceA.compareTo(distanceB);
        if (distanceOrder != 0) {
          return distanceOrder;
        }
        return a.uid.compareTo(b.uid);
      });

      for (final candidate in candidates) {
        if (_isMatchFound || completer.isCompleted) {
          return;
        }

        if (!_shouldHostRandomMatch(uid, candidate.uid)) {
          continue;
        }

        final hostClaimed = await _claimOwnMatchmakingHost(
          uid: uid,
          opponentUid: candidate.uid,
        );
        if (!hostClaimed) {
          return;
        }

        _isMatchmakingAttemptInProgress = true;
        String? newRoomId;
        try {
          newRoomId = await _generateUniqueRoomId();

          if (_isMatchFound || completer.isCompleted) {
            await _restoreOwnWaitingEntry(uid, myRating);
            return;
          }

          await _createRankedRoom(
            roomId: newRoomId,
            myRating: myRating,
            opponentUid: candidate.uid,
          );

          if (_isMatchFound || completer.isCompleted) {
            await _clearFailedMatchRoomState();
            await _db.child('rooms/$newRoomId').remove();
            return;
          }

          final guestAssigned = await _assignRandomMatchGuest(
            opponentUid: candidate.uid,
            roomId: newRoomId,
            myRating: myRating,
          );
          if (!guestAssigned) {
            await _clearFailedMatchRoomState();
            await _db.child('rooms/$newRoomId').remove();
            await _restoreOwnWaitingEntry(uid, myRating);
            continue;
          }

          await _markOwnMatchAsHost(uid, newRoomId, candidate.uid);

          final guestJoined = await _waitForRankedGuest(newRoomId);
          if (!guestJoined) {
            await _clearGuestInvite(candidate.uid, newRoomId);
            await _clearFailedMatchRoomState();
            await _db.child('rooms/$newRoomId').remove();
            await _restoreOwnWaitingEntry(uid, myRating);
            continue;
          }

          if (completer.isCompleted) {
            await _clearGuestInvite(candidate.uid, newRoomId);
            await _clearFailedMatchRoomState();
            await _db.child('rooms/$newRoomId').remove();
            return;
          }

          _isMatchFound = true;
          _matchmakingPollTimer?.cancel();
          _completeMatchmaking(newRoomId);
          return;
        } catch (_) {
          await _clearFailedMatchRoomState();
          if (newRoomId != null) {
            await _db.child('rooms/$newRoomId').remove();
          }
          await _restoreOwnWaitingEntry(uid, myRating);
          rethrow;
        } finally {
          if (!_isMatchFound) {
            _isMatchmakingAttemptInProgress = false;
          }
        }
      }
    } on FirebaseException catch (error, stackTrace) {
      _completeMatchmakingError(
        StateError(_firebaseErrorMessage('ランク戦検索', error)),
        stackTrace,
      );
    } catch (error, stackTrace) {
      _completeMatchmakingError(error, stackTrace);
    }
  }

  Future<List<MapEntry<String, Object?>>>
      _fetchRankedMatchmakingEntriesInRange({
    required int myRating,
    required int range,
  }) async {
    final lowerBound = myRating - range;
    final upperBound = myRating + range;
    final lowerQuery = _db
        .child('matchmaking')
        .orderByChild('rating')
        .startAt(lowerBound)
        .endAt(myRating)
        .limitToLast(25);
    final upperQuery = _db
        .child('matchmaking')
        .orderByChild('rating')
        .startAt(myRating)
        .endAt(upperBound)
        .limitToFirst(25);
    final snapshots = await Future.wait([lowerQuery.get(), upperQuery.get()]);
    final entriesByUid = <String, Object?>{};
    for (final snapshot in snapshots) {
      final raw = snapshot.value;
      if (raw is Map) {
        for (final entry in raw.entries) {
          entriesByUid['${entry.key}'] = entry.value;
        }
      }
    }
    return entriesByUid.entries.toList();
  }

  Future<void> _completeRankedBotMatch(int myRating) async {
    final completer = _matchmakingCompleter;
    if (completer == null || completer.isCompleted || _isMatchFound) {
      return;
    }

    final topRating = await _loadTopRankingRating();
    if (completer.isCompleted || _isMatchFound) {
      return;
    }

    _isMatchFound = true;
    _matchmakingPollTimer?.cancel();
    currentRating = myRating;
    isRankedMode = true;
    final nowJst = await ServerTimeManager.instance.nowJst(forceRefresh: true);
    rankedBotSeasonId =
        RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
    rankedBotSeasonEndsAt = RankedSeasonManager.seasonEndJst(rankedBotSeasonId!)
        .millisecondsSinceEpoch;
    rankedBotRating = _generateRankedBotRating(
      playerRating: myRating,
      topRating: topRating,
    );
    rankedBotDifficulty = _rankedBotDifficultyForRating(
      playerRating: myRating,
      topRating: topRating,
    );
    rankedBotIconId = _randomRankedBotIconId();
    rankedBotFrameId = _randomRankedBotFrameId();
    completer.complete(rankedBotRoomId);
  }

  String _randomRankedBotIconId() {
    const icons = GameItemCatalog.playerIcons;
    if (icons.isEmpty) {
      return 'default';
    }
    return icons[_random.nextInt(icons.length)].id;
  }

  String _randomRankedBotFrameId() {
    const frames = GameItemCatalog.iconFrames;
    if (frames.isEmpty) {
      return 'default';
    }
    return frames[_random.nextInt(frames.length)].id;
  }

  Future<int> _loadTopRankingRating() async {
    try {
      final snapshot = await _db
          .child('rankedSeasons/seasons/${await _currentSeasonId()}/rankings')
          .orderByChild('rating')
          .limitToLast(25)
          .get()
          .timeout(rankedBotTopRatingTimeout);
      final value = snapshot.value;
      if (value is! Map) {
        return max(initialRating, currentRating);
      }
      var topRating = initialRating;
      for (final entry in value.values) {
        if (entry is Map && _isPlausibleSeasonRankingEntry(entry)) {
          topRating = max(topRating, _intValue(entry['rating']) ?? topRating);
        }
      }
      return max(topRating, currentRating);
    } catch (_) {
      return max(initialRating, currentRating);
    }
  }

  bool _isPlausibleSeasonRankingEntry(Map<dynamic, dynamic> entry) {
    final rating = _intValue(entry['rating']);
    if (rating == null) {
      return false;
    }
    final wins = max(0, _intValue(entry['seasonWins']) ?? 0);
    final losses = max(0, _intValue(entry['seasonLosses']) ?? 0);
    final maxReachable = initialRating + wins * 95 - losses * 5;
    final minReachable = initialRating + wins * 5 - losses * 95;
    return rating >= minReachable && rating <= maxReachable;
  }

  int _rankedBotMaxRating(int topRating) {
    final leadJitter = _random.nextInt(rankedBotRatingLeadVariance * 2 + 1) -
        rankedBotRatingLeadVariance;
    final leadOffset = rankedBotRatingLeadOffset + leadJitter;
    return max(
      rankedBotMinimumMaxRating,
      topRating - leadOffset,
    );
  }

  int _generateRankedBotRating({
    required int playerRating,
    required int topRating,
  }) {
    final botMaxRating = _rankedBotMaxRating(topRating);
    late final int minOffset;
    late final int maxOffset;

    if (playerRating < 1000) {
      minOffset = 0;
      maxOffset = 100;
    } else if (playerRating >= botMaxRating - 200) {
      minOffset = -100;
      maxOffset = 0;
    } else {
      minOffset = -50;
      maxOffset = 50;
    }

    final offset = minOffset + _random.nextInt(maxOffset - minOffset + 1);
    return min(botMaxRating, max(0, playerRating + offset));
  }

  CPUDifficulty _rankedBotDifficultyForRating({
    required int playerRating,
    required int topRating,
  }) {
    final strengthMaxRating = max(rankedBotMinimumMaxRating, topRating);
    final span = max(1, strengthMaxRating - rankedBotStrengthMinRating);
    final step = span / 10;
    final rawLevel =
        ((playerRating - rankedBotStrengthMinRating) / step).floor() + 1;
    final level = rawLevel.clamp(1, 10);
    return switch (level) {
      1 => CPUDifficulty.rankedLv1,
      2 => CPUDifficulty.rankedLv2,
      3 => CPUDifficulty.rankedLv3,
      4 => CPUDifficulty.rankedLv4,
      5 => CPUDifficulty.rankedLv5,
      6 => CPUDifficulty.rankedLv6,
      7 => CPUDifficulty.rankedLv7,
      8 => CPUDifficulty.rankedLv8,
      9 => CPUDifficulty.rankedLv9,
      _ => CPUDifficulty.rankedLv10,
    };
  }

  static int rankedBotLevelForDifficulty(CPUDifficulty difficulty) {
    return switch (difficulty) {
      CPUDifficulty.rankedLv1 => 1,
      CPUDifficulty.rankedLv2 => 2,
      CPUDifficulty.rankedLv3 => 3,
      CPUDifficulty.rankedLv4 => 4,
      CPUDifficulty.rankedLv5 => 5,
      CPUDifficulty.rankedLv6 => 6,
      CPUDifficulty.rankedLv7 => 7,
      CPUDifficulty.rankedLv8 => 8,
      CPUDifficulty.rankedLv9 => 9,
      CPUDifficulty.rankedLv10 => 10,
      CPUDifficulty.easy => 1,
      CPUDifficulty.normal => 5,
      CPUDifficulty.hard => 8,
      CPUDifficulty.oni => 10,
    };
  }

  static String rankedBotLevelLabel(CPUDifficulty difficulty) {
    final level = rankedBotLevelForDifficulty(difficulty);
    return 'Lv.$level';
  }

  Future<void> _tryArenaMatch(int currentWins) async {
    final uid = myUid;
    final completer = _matchmakingCompleter;
    if (uid == null ||
        completer == null ||
        completer.isCompleted ||
        _isMatchFound ||
        _isMatchmakingAttemptInProgress) {
      return;
    }

    try {
      await _refreshWaitingArenaMatchmakingEntry(uid, currentWins);

      final ownEntrySnapshot = await _db.child('arena_matchmaking/$uid').get();
      final ownEntry =
          ownEntrySnapshot.value is Map ? ownEntrySnapshot.value as Map : null;
      final assignedRoomId = _nonEmptyString(ownEntry?['roomId']);
      final assignedRole = ownEntry?['role']?.toString();
      if (assignedRoomId != null && assignedRole != 'host') {
        unawaited(_acceptRandomMatchAsGuest(assignedRoomId));
        return;
      }
      if (ownEntry == null) {
        await _writeWaitingArenaMatchmakingEntry(uid, currentWins);
        return;
      }
      if (_matchmakingStatus(ownEntry) != 'waiting') {
        return;
      }

      final snapshot = await _db.child('arena_matchmaking').get();
      final rawPlayers = snapshot.value;
      if (rawPlayers is! Map) {
        return;
      }

      final candidates = <_MatchmakingCandidate>[];
      for (final entry in rawPlayers.entries) {
        final opponentUid = entry.key.toString();
        if (opponentUid == uid) {
          continue;
        }
        if (await ModerationManager.instance.isBlocked(opponentUid)) {
          continue;
        }

        final data = entry.value;
        if (data is! Map) {
          continue;
        }

        if (_matchmakingStatus(data) != 'waiting') {
          continue;
        }

        if (!_isFreshMatchmakingEntry(data)) {
          continue;
        }

        if (_nonEmptyString(data['roomId']) != null) {
          continue;
        }

        final wins = _intValue(data['wins']);
        if (wins != currentWins) {
          continue;
        }

        candidates.add(
          _MatchmakingCandidate(
            uid: opponentUid,
            rating: wins ?? 0,
            timestamp: _intValue(data['joinedAt']) ??
                _intValue(data['timestamp']) ??
                0,
          ),
        );
      }

      candidates.sort((a, b) => a.uid.compareTo(b.uid));

      for (final candidate in candidates) {
        if (_isMatchFound || completer.isCompleted) {
          return;
        }

        if (!_shouldHostRandomMatch(uid, candidate.uid)) {
          continue;
        }

        final hostClaimed = await _claimMatchmakingHost(
          path: 'arena_matchmaking',
          uid: uid,
          opponentUid: candidate.uid,
        );
        if (!hostClaimed) {
          return;
        }

        _isMatchmakingAttemptInProgress = true;
        String? newRoomId;
        try {
          newRoomId = await _generateUniqueRoomId();

          if (_isMatchFound || completer.isCompleted) {
            await _restoreOwnArenaWaitingEntry(uid, currentWins);
            return;
          }

          await _createArenaRoom(
            roomId: newRoomId,
            currentWins: currentWins,
            opponentUid: candidate.uid,
          );

          final guestAssigned = await _assignArenaMatchGuest(
            opponentUid: candidate.uid,
            roomId: newRoomId,
            currentWins: currentWins,
          );
          if (!guestAssigned) {
            await _clearFailedMatchRoomState();
            await _db.child('rooms/$newRoomId').remove();
            await _restoreOwnArenaWaitingEntry(uid, currentWins);
            continue;
          }

          await _markOwnArenaMatchAsHost(uid, newRoomId, candidate.uid);

          final guestJoined = await _waitForRankedGuest(newRoomId);
          if (!guestJoined) {
            await _clearArenaGuestInvite(candidate.uid, newRoomId);
            await _clearFailedMatchRoomState();
            await _db.child('rooms/$newRoomId').remove();
            await _restoreOwnArenaWaitingEntry(uid, currentWins);
            continue;
          }

          if (completer.isCompleted) {
            await _clearArenaGuestInvite(candidate.uid, newRoomId);
            await _clearFailedMatchRoomState();
            await _db.child('rooms/$newRoomId').remove();
            return;
          }

          _isMatchFound = true;
          _matchmakingPollTimer?.cancel();
          _completeMatchmaking(newRoomId);
          return;
        } catch (_) {
          await _clearFailedMatchRoomState();
          if (newRoomId != null) {
            await _db.child('rooms/$newRoomId').remove();
          }
          await _restoreOwnArenaWaitingEntry(uid, currentWins);
          rethrow;
        } finally {
          if (!_isMatchFound) {
            _isMatchmakingAttemptInProgress = false;
          }
        }
      }
    } on FirebaseException catch (error, stackTrace) {
      _completeMatchmakingError(
        StateError(_firebaseErrorMessage('アリーナマッチ検索', error)),
        stackTrace,
      );
    } catch (error, stackTrace) {
      _completeMatchmakingError(error, stackTrace);
    }
  }

  Future<void> _writeWaitingMatchmakingEntry(String uid, int myRating) async {
    await _db.child('matchmaking/$uid').set({
      'status': 'waiting',
      'rating': myRating,
      'joinedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _writeWaitingArenaMatchmakingEntry(
    String uid,
    int currentWins,
  ) async {
    final playerIconId = await _currentEquippedPlayerIconId();
    final playerIconFrameId = await _currentEquippedIconFrameId();
    final ballSkinId = await _currentEquippedBallSkinId();
    await _db.child('arena_matchmaking/$uid').set({
      'status': 'waiting',
      'wins': currentWins,
      'roomId': null,
      'role': null,
      'name': displayPlayerName,
      'playerIconId': playerIconId,
      'playerIconFrameId': playerIconFrameId,
      'ballSkinId': ballSkinId,
      'joinedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _refreshWaitingMatchmakingEntry(
    String uid,
    int myRating,
  ) async {
    try {
      await _db.child('matchmaking/$uid').update({
        'rating': myRating,
        'timestamp': ServerValue.timestamp,
      });
    } on FirebaseException {
      // 次のポーリングでもう一度更新する。検索自体は既存の待機情報で続ける。
    }
  }

  Future<void> _refreshWaitingArenaMatchmakingEntry(
    String uid,
    int currentWins,
  ) async {
    try {
      final playerIconId = await _currentEquippedPlayerIconId();
      final playerIconFrameId = await _currentEquippedIconFrameId();
      final ballSkinId = await _currentEquippedBallSkinId();
      await _db.child('arena_matchmaking/$uid').update({
        'wins': currentWins,
        'name': displayPlayerName,
        'playerIconId': playerIconId,
        'playerIconFrameId': playerIconFrameId,
        'ballSkinId': ballSkinId,
        'timestamp': ServerValue.timestamp,
      });
    } on FirebaseException {
      // 次のポーリングでもう一度更新する。検索自体は既存の待機情報で続ける。
    }
  }

  bool _shouldHostRandomMatch(String uid, String opponentUid) {
    return uid.compareTo(opponentUid) < 0;
  }

  Future<bool> _claimOwnMatchmakingHost({
    required String uid,
    required String opponentUid,
  }) {
    return _claimMatchmakingHost(
      path: 'matchmaking',
      uid: uid,
      opponentUid: opponentUid,
    );
  }

  Future<bool> _claimMatchmakingHost({
    required String path,
    required String uid,
    required String opponentUid,
  }) async {
    try {
      final ref = _db.child('$path/$uid');
      final snapshot = await ref.get();
      final value = snapshot.value;
      if (value is! Map ||
          _matchmakingStatus(value) != 'waiting' ||
          _nonEmptyString(value['roomId']) != null) {
        return false;
      }

      await ref.update({
        'status': 'matching',
        'role': 'host',
        'guestUid': opponentUid,
        'timestamp': ServerValue.timestamp,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _joinRoomWhenReady(String roomId) async {
    for (var attempt = 0; attempt < 24; attempt++) {
      if (_matchmakingCompleter?.isCompleted ?? true) {
        return false;
      }

      final joined = await joinRoom(roomId);
      if (joined) {
        return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<bool> _assignRandomMatchGuest({
    required String opponentUid,
    required String roomId,
    required int myRating,
  }) async {
    final uid = myUid;
    if (uid == null) {
      return false;
    }

    final range = _currentMatchmakingRange();
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final ref = _db.child('matchmaking/$opponentUid');
      final snapshot = await ref.get();
      final currentValue = snapshot.value;

      if (currentValue is! Map ||
          _matchmakingStatus(currentValue) != 'waiting' ||
          _nonEmptyString(currentValue['roomId']) != null ||
          !_isFreshMatchmakingEntry(currentValue)) {
        return false;
      }

      final opponentRating = _intValue(currentValue['rating']);
      if (opponentRating == null) {
        return false;
      }
      final ratingDistance = (opponentRating - myRating).abs();
      final opponentRange = _matchmakingRangeForEntry(currentValue, now);
      if (ratingDistance > range || ratingDistance > opponentRange) {
        return false;
      }

      await ref.update({
        'status': 'assigned',
        'role': 'guest',
        'roomId': roomId,
        'hostUid': uid,
        'assignedAt': now,
        'timestamp': now,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _assignArenaMatchGuest({
    required String opponentUid,
    required String roomId,
    required int currentWins,
  }) async {
    final uid = myUid;
    if (uid == null) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final ref = _db.child('arena_matchmaking/$opponentUid');
      final snapshot = await ref.get();
      final currentValue = snapshot.value;

      if (currentValue is! Map ||
          _matchmakingStatus(currentValue) != 'waiting' ||
          _nonEmptyString(currentValue['roomId']) != null ||
          !_isFreshMatchmakingEntry(currentValue)) {
        return false;
      }

      final wins = _intValue(currentValue['wins']);
      if (wins != currentWins) {
        return false;
      }

      await ref.update({
        'status': 'assigned',
        'role': 'guest',
        'roomId': roomId,
        'hostUid': uid,
        'assignedAt': now,
        'timestamp': now,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markOwnMatchAsHost(
    String uid,
    String roomId,
    String opponentUid,
  ) async {
    await _db.child('matchmaking/$uid').update({
      'status': 'matched',
      'role': 'host',
      'roomId': roomId,
      'guestUid': opponentUid,
      'assignedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _markOwnArenaMatchAsHost(
    String uid,
    String roomId,
    String opponentUid,
  ) async {
    await _db.child('arena_matchmaking/$uid').update({
      'status': 'matched',
      'role': 'host',
      'roomId': roomId,
      'guestUid': opponentUid,
      'assignedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _restoreOwnWaitingEntry(String uid, int myRating) async {
    if (_isMatchFound || (_matchmakingCompleter?.isCompleted ?? true)) {
      return;
    }

    await _db.child('matchmaking/$uid').set({
      'status': 'waiting',
      'rating': myRating,
      'joinedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _restoreOwnArenaWaitingEntry(
    String uid,
    int currentWins,
  ) async {
    if (_isMatchFound || (_matchmakingCompleter?.isCompleted ?? true)) {
      return;
    }

    final playerIconId = await _currentEquippedPlayerIconId();
    final playerIconFrameId = await _currentEquippedIconFrameId();
    final ballSkinId = await _currentEquippedBallSkinId();
    await _db.child('arena_matchmaking/$uid').set({
      'status': 'waiting',
      'wins': currentWins,
      'roomId': null,
      'role': null,
      'name': displayPlayerName,
      'playerIconId': playerIconId,
      'playerIconFrameId': playerIconFrameId,
      'ballSkinId': ballSkinId,
      'joinedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _createRankedRoom({
    required String roomId,
    required int myRating,
    required String opponentUid,
  }) async {
    final uid = myUid;
    if (uid == null) {
      throw StateError('ユーザーIDの初期化に失敗しました。');
    }

    final hostData = await _buildPlayerPayload(
      status: 'waiting',
      rating: myRating,
    );
    final seed = DateTime.now().millisecondsSinceEpoch;
    final seasonId = await _currentSeasonId(forceRefresh: true);
    final seasonEndsAt =
        RankedSeasonManager.seasonEndJst(seasonId).millisecondsSinceEpoch;
    final roomRef = _db.child('rooms/$roomId');
    await roomRef.set({
      'mode': 'ranked',
      'ranked': true,
      'seasonId': seasonId,
      'seasonEndsAt': seasonEndsAt,
      'status': 'waiting',
      'seed': seed,
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      'matchmaking': {
        'hostUid': uid,
        'guestUid': opponentUid,
      },
      'players': {
        'host': hostData,
      },
    });

    currentRoomId = roomId;
    myRoleId = 'host';
    isRankedMode = true;
    currentRoom = MultiplayerRoom(
      roomId: roomId,
      status: 'waiting',
      seed: seed,
      isRanked: true,
      seasonId: seasonId,
      seasonEndsAt: seasonEndsAt,
      players: {
        'host': MultiplayerPlayer.fromMap(hostData),
      },
    );
    _lastRoomStatus = currentRoom!.status;
    _hadOpponentPresent = false;
    _opponentDisconnectNotified = false;
    _presencePreserveMode = null;
    await _syncPresenceMode();
    _listenRoom();
    _listenGameplayChannels();
    unawaited(_connectRealtimeTransportIfEnabled());
  }

  Future<void> _createArenaRoom({
    required String roomId,
    required int currentWins,
    required String opponentUid,
  }) async {
    final uid = myUid;
    if (uid == null) {
      throw StateError('ユーザーIDの初期化に失敗しました。');
    }

    final hostData = await _buildPlayerPayload(
      status: 'waiting',
      rating: currentRating,
    );
    final seed = DateTime.now().millisecondsSinceEpoch;
    final roomRef = _db.child('rooms/$roomId');
    await roomRef.set({
      'mode': 'arena',
      'status': 'waiting',
      'seed': seed,
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      'matchmaking': {
        'hostUid': uid,
        'guestUid': opponentUid,
        'wins': currentWins,
      },
      'players': {
        'host': hostData,
      },
    });

    currentRoomId = roomId;
    myRoleId = 'host';
    isRankedMode = true;
    currentRoom = MultiplayerRoom(
      roomId: roomId,
      status: 'waiting',
      seed: seed,
      isRanked: true,
      players: {
        'host': MultiplayerPlayer.fromMap(hostData),
      },
    );
    _lastRoomStatus = currentRoom!.status;
    _hadOpponentPresent = false;
    _opponentDisconnectNotified = false;
    _presencePreserveMode = null;
    await _syncPresenceMode();
    _listenRoom();
    _listenGameplayChannels();
    unawaited(_connectRealtimeTransportIfEnabled());
  }

  Future<bool> _waitForRankedGuest(String roomId) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      if (_matchmakingCompleter?.isCompleted ?? true) {
        return false;
      }

      final snapshot = await _db.child('rooms/$roomId').get();
      if (!snapshot.exists) {
        return false;
      }

      final room = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
      currentRoom = room;
      _lastRoomStatus = room.status;
      if (room.hasGuest) {
        _hadOpponentPresent = true;
        return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<String> _generateUniqueRoomId() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final roomId = (_random.nextInt(900000) + 100000).toString();
      final existing = await _db.child('rooms/$roomId').get();
      if (!existing.exists) {
        return roomId;
      }
    }
    throw StateError('ルームIDの生成に失敗しました。もう一度お試しください。');
  }

  Future<void> _clearFailedMatchRoomState() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;

    _roomSubscription?.cancel();
    _roomStatusSubscription?.cancel();
    _myStatusSubscription?.cancel();
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _stampSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _roomSubscription = null;
    _roomStatusSubscription = null;
    _myStatusSubscription = null;
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
    _stampSubscription = null;
    _opponentOjamaSpawnSubscription = null;
    _opponentStatusSubscription = null;

    try {
      if (roomId != null && roleId != null) {
        await _db
            .child('rooms/$roomId/players/$roleId')
            .onDisconnect()
            .cancel();
      }
    } on FirebaseException {
      // 失敗時もローカル状態は破棄し、次の候補検索を継続する。
    }

    currentRoomId = null;
    myRoleId = null;
    currentRoom = null;
    isRankedMode = false;
    rankedBotSeasonId = null;
    rankedBotSeasonEndsAt = null;
    _lastRoomStatus = null;
    _hadOpponentPresent = false;
    _isLaunchingRematch = false;
    _opponentDisconnectNotified = false;
    _presencePreserveMode = null;
    await _realtimeTransportClient.disconnect();
  }

  Future<void> _clearGuestInvite(String opponentUid, String roomId) async {
    final uid = myUid;
    if (uid == null) {
      return;
    }

    try {
      final ref = _db.child('matchmaking/$opponentUid');
      final snapshot = await ref.get();
      final currentValue = snapshot.value;

      if (currentValue is Map &&
          currentValue['roomId'] == roomId &&
          currentValue['hostUid'] == uid) {
        await ref.update({
          'status': 'waiting',
          'roomId': null,
          'role': null,
          'hostUid': null,
          'assignedAt': null,
        });
      }
    } catch (e) {
      // 招待情報は待機エントリの鮮度チェックで自然に無視されるため、失敗しても続行する。
    }
  }

  Future<void> _clearArenaGuestInvite(String opponentUid, String roomId) async {
    final uid = myUid;
    if (uid == null) {
      return;
    }

    try {
      final ref = _db.child('arena_matchmaking/$opponentUid');
      final snapshot = await ref.get();
      final currentValue = snapshot.value;

      if (currentValue is Map &&
          currentValue['roomId'] == roomId &&
          currentValue['hostUid'] == uid) {
        await ref.update({
          'status': 'waiting',
          'roomId': null,
          'role': null,
          'hostUid': null,
          'assignedAt': null,
        });
      }
    } catch (_) {
      // 招待情報は待機エントリの鮮度チェックで自然に無視されるため、失敗しても続行する。
    }
  }

  int _currentMatchmakingRange() {
    final startedAt = _matchmakingStartedAt;
    if (startedAt == null) {
      return rankedMatchmakingInitialRange;
    }
    final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
    return _rankedMatchmakingRangeForElapsedSeconds(elapsedSeconds);
  }

  int _matchmakingRangeForEntry(Map data, int nowMilliseconds) {
    final joinedAt =
        _intValue(data['joinedAt']) ?? _intValue(data['timestamp']);
    if (joinedAt == null) {
      return rankedMatchmakingInitialRange;
    }
    final elapsedSeconds = max(0, nowMilliseconds - joinedAt) ~/ 1000;
    return _rankedMatchmakingRangeForElapsedSeconds(elapsedSeconds);
  }

  int _rankedMatchmakingRangeForElapsedSeconds(int elapsedSeconds) {
    final config = _activeRankedMatchmakingConfig;
    return rankedMatchmakingInitialRange +
        (max(0, elapsedSeconds) * config.rangeGrowthPerSecond);
  }

  Future<_RankedMatchmakingConfig> _loadRankedMatchmakingConfig({
    bool forceRefresh = false,
  }) async {
    final cached = _rankedMatchmakingConfigCache;
    final cachedAt = _rankedMatchmakingConfigCacheAt;
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < rankedMatchmakingConfigCacheTtl) {
      return cached;
    }

    try {
      final snapshot = await _db
          .child('appConfig/rankedMatchmaking')
          .get()
          .timeout(rankedMatchmakingConfigTimeout);
      final value = snapshot.value;
      if (value is! Map) {
        return _cacheRankedMatchmakingConfig(
          _RankedMatchmakingConfig.fallback,
        );
      }

      final botFallbackSeconds =
          (_intValue(value['botFallbackSeconds']) ?? rankedBotFallbackSeconds)
              .clamp(3, 60)
              .toInt();
      final rangeGrowthPerSecond = (_intValue(value['rangeGrowthPerSecond']) ??
              rankedMatchmakingRangeGrowthPerSecond)
          .clamp(0, 200)
          .toInt();
      return _cacheRankedMatchmakingConfig(
        _RankedMatchmakingConfig(
          botFallbackSeconds: botFallbackSeconds,
          rangeGrowthPerSecond: rangeGrowthPerSecond,
        ),
      );
    } catch (_) {
      return _cacheRankedMatchmakingConfig(
        _RankedMatchmakingConfig.fallback,
      );
    }
  }

  _RankedMatchmakingConfig _cacheRankedMatchmakingConfig(
    _RankedMatchmakingConfig config,
  ) {
    _rankedMatchmakingConfigCache = config;
    _rankedMatchmakingConfigCacheAt = DateTime.now();
    return config;
  }

  bool _isFreshMatchmakingEntry(Map data) {
    final timestamp = _intValue(data['timestamp']);
    if (timestamp == null) {
      return true;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - timestamp;
    return age >= -300000 && age < 120000;
  }

  String _matchmakingStatus(Map data) {
    final status = data['status']?.toString();
    return status == null || status.isEmpty ? 'waiting' : status;
  }

  String? _nonEmptyString(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return value;
  }

  void _completeMatchmaking(String? roomId) {
    final completer = _matchmakingCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(roomId);
    }
  }

  void _completeMatchmakingError(Object error, StackTrace stackTrace) {
    final completer = _matchmakingCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  Future<void> _cleanupMatchmaking() async {
    _matchmakingPollTimer?.cancel();
    _matchmakingPollTimer = null;

    await _matchmakingInviteSubscription?.cancel();
    _matchmakingInviteSubscription = null;

    final uid = myUid;
    final path = _activeMatchmakingPath ?? 'matchmaking';
    try {
      if (uid != null) {
        final entryRef = _db.child('$path/$uid');
        await entryRef.onDisconnect().cancel();
        await entryRef.remove();
      }
    } on FirebaseException {
      // クリーンアップ失敗は次回起動時の再登録で上書きする。
    }

    _matchmakingStartedAt = null;
    _activeMatchmakingPath = null;
    _matchmakingCompleter = null;
    _isMatchmakingAttemptInProgress = false;
  }

  Future<void> saveActiveSession({
    required bool isArenaMode,
    Map<String, dynamic>? snapshot,
  }) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final session = SavedOnlineSession(
      roomId: roomId,
      roleId: roleId,
      isRankedMode: isRankedMode || (currentRoom?.isRanked ?? false),
      isArenaMode: isArenaMode,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      snapshot: snapshot,
    );
    await prefs.setString(_savedSessionPrefsKey, jsonEncode(session.toJson()));
  }

  Future<void> saveRankedBotActiveSession({
    required int opponentRating,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final session = SavedOnlineSession(
      roomId: rankedBotRoomId,
      roleId: 'host',
      isRankedMode: true,
      isArenaMode: false,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      snapshot: {
        'opponentRating': opponentRating,
        'opponentName': 'プレイヤー',
        'opponentIconId': rankedBotIconId,
        'opponentFrameId': rankedBotFrameId,
        if (rankedBotSeasonId != null) 'seasonId': rankedBotSeasonId,
        if (rankedBotSeasonEndsAt != null)
          'seasonEndsAt': rankedBotSeasonEndsAt,
      },
    );
    await prefs.setString(_savedSessionPrefsKey, jsonEncode(session.toJson()));
  }

  Future<SavedOnlineSession?> loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final legacyKey in _legacySavedSessionPrefsKeys) {
        if (prefs.containsKey(legacyKey)) {
          await prefs.remove(legacyKey);
        }
      }
      final raw = prefs.getString(_savedSessionPrefsKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final session = SavedOnlineSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (session.roomId.isEmpty || session.roleId.isEmpty) {
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedSessionPrefsKey);
    for (final legacyKey in _legacySavedSessionPrefsKeys) {
      await prefs.remove(legacyKey);
    }
  }

  Future<void> markSavedSessionResultKnown({
    required bool isWin,
  }) async {
    final session = await loadSavedSession();
    if (session == null || !session.isRankedMode || session.isArenaMode) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final snapshot = Map<String, dynamic>.from(session.snapshot ?? const {});
    snapshot['resultKnown'] = true;
    snapshot['isWin'] = isWin;
    snapshot['resultKnownAt'] = DateTime.now().millisecondsSinceEpoch;
    final nextSession = SavedOnlineSession(
      roomId: session.roomId,
      roleId: session.roleId,
      isRankedMode: session.isRankedMode,
      isArenaMode: session.isArenaMode,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      snapshot: snapshot,
    );
    await prefs.setString(
        _savedSessionPrefsKey, jsonEncode(nextSession.toJson()));
  }

  Future<SavedSessionResolution?> inspectSavedSession() async {
    final session = await loadSavedSession();
    if (session == null) {
      return null;
    }

    if (session.roomId == rankedBotRoomId && session.isRankedMode) {
      return _resolveAbandonedRankedBotSession(session);
    }

    try {
      final snapshot = await _db.child('rooms/${session.roomId}').get();
      if (!snapshot.exists) {
        return SavedSessionResolution(
          session: session,
          isResolved: true,
          newRating: await _loadLatestUserRating(),
        );
      }

      final room = MultiplayerRoom.fromSnapshot(session.roomId, snapshot.value);
      final myRoleId = session.roleId;
      final opponentRoleId = myRoleId == 'host' ? 'guest' : 'host';
      final myStatus = room.players[myRoleId]?.status;
      final opponent = room.players[opponentRoleId];
      final opponentStatus = opponent?.status;
      final resultSnapshot =
          await _db.child('rooms/${session.roomId}/results').get();
      final resultsMap = resultSnapshot.value is Map
          ? resultSnapshot.value as Map<dynamic, dynamic>
          : null;
      Map<dynamic, dynamic>? resultData = resultsMap?[myRoleId] is Map
          ? resultsMap![myRoleId] as Map<dynamic, dynamic>
          : null;
      final opponentResultData = resultsMap?[opponentRoleId] is Map
          ? resultsMap![opponentRoleId] as Map<dynamic, dynamic>
          : null;
      final mirroredIsWin = opponentResultData == null
          ? null
          : opponentResultData['isWin'] != true;
      final startedMatch = room.status == 'playing' ||
          room.status == 'game_over' ||
          session.snapshot != null ||
          resultData != null ||
          opponentResultData != null;
      final sessionSnapshot = session.snapshot;
      final wasOfflineDisconnect =
          sessionSnapshot?['abandonReason'] == 'offline';
      final abandonedByMe = startedMatch && myStatus == 'left';
      final bool? resultKnownIsWin;
      if (sessionSnapshot?['resultKnown'] == true) {
        resultKnownIsWin = sessionSnapshot?['isWin'] == true;
      } else {
        resultKnownIsWin = null;
      }
      final explicitIsWin = resultData == null
          ? (mirroredIsWin ?? resultKnownIsWin)
          : resultData['isWin'] == true;
      final statusInferredIsWin = abandonedByMe
          ? false
          : myStatus == 'dead'
              ? false
              : opponentStatus == 'left' && startedMatch
                  ? true
                  : opponentStatus == 'dead'
                      ? true
                      : null;
      final inferredIsWin = explicitIsWin ?? statusInferredIsWin;
      if (session.isRankedMode &&
          !session.isArenaMode &&
          inferredIsWin != null &&
          resultData == null) {
        resultData = await _ensureRankedResultRecorded(
          room: room,
          myRoleId: myRoleId,
          isWin: inferredIsWin,
          existingOpponentResult: opponentResultData,
        );
      }
      final resolvedResultData = resultData;
      final oldRating = resolvedResultData == null
          ? null
          : _intValue(resolvedResultData['oldRating']) ??
              (() {
                final newRating = _intValue(resolvedResultData['newRating']);
                final delta = _intValue(resolvedResultData['delta']);
                if (newRating == null || delta == null) {
                  return null;
                }
                return newRating - delta;
              })();
      final newRating = resultData == null
          ? await _loadLatestUserRating()
          : _intValue(resultData['newRating']) ?? await _loadLatestUserRating();
      final ratingDelta =
          resultData == null ? null : _intValue(resultData['delta']);
      final isResolved =
          !startedMatch || room.status == 'game_over' || inferredIsWin != null;

      return SavedSessionResolution(
        session: session,
        isResolved: isResolved,
        isWin: inferredIsWin,
        oldRating: oldRating,
        newRating: newRating,
        ratingDelta: ratingDelta,
        opponentName: opponent?.name,
        wasAbandoned: abandonedByMe,
        wasOfflineDisconnect: wasOfflineDisconnect,
      );
    } catch (_) {
      return SavedSessionResolution(session: session, isResolved: true);
    }
  }

  Future<SavedSessionResolution> _resolveAbandonedRankedBotSession(
    SavedOnlineSession session,
  ) async {
    final opponentRating = _intValue(session.snapshot?['opponentRating']) ??
        rankedBotMinimumMaxRating;
    final opponentName =
        session.snapshot?['opponentName']?.toString().trim().isNotEmpty == true
            ? session.snapshot!['opponentName'].toString().trim()
            : 'プレイヤー';
    final uid = myUid ?? await _loadAuthenticatedUid();
    myUid = uid;

    final oldRating = await _loadLatestUserRating();
    final sessionSeasonId = session.snapshot?['seasonId']?.toString();
    final currentSeasonId = await _currentSeasonId(forceRefresh: true);
    final seasonExpired = sessionSeasonId != null &&
        sessionSeasonId.isNotEmpty &&
        sessionSeasonId != currentSeasonId;
    final resultKnown = session.snapshot?['resultKnown'] == true;
    final isWin = resultKnown ? (session.snapshot?['isWin'] == true) : false;
    final newRating = seasonExpired
        ? oldRating
        : calculateNewRating(oldRating, opponentRating, isWin);
    final delta = newRating - oldRating;
    currentRating = newRating;

    try {
      await _db.child('users/$uid').update({
        'name': displayPlayerName,
        'publicId': PlayerDataManager.instance.playerId,
        'rating': newRating,
        'updatedAt': ServerValue.timestamp,
      });
    } on FirebaseException {
      // 次回の通常ユーザー更新で同期されるため、起動は止めない。
    }

    return SavedSessionResolution(
      session: session,
      isResolved: true,
      isWin: isWin,
      oldRating: oldRating,
      newRating: newRating,
      ratingDelta: delta,
      opponentName: opponentName,
      wasAbandoned: !resultKnown,
      wasOfflineDisconnect: session.snapshot?['abandonReason'] == 'offline',
    );
  }

  Future<Map<dynamic, dynamic>?> _ensureRankedResultRecorded({
    required MultiplayerRoom room,
    required String myRoleId,
    required bool isWin,
    Map<dynamic, dynamic>? existingOpponentResult,
    String? reason,
  }) async {
    final roomId = room.roomId;
    final opponentRoleId = myRoleId == 'host' ? 'guest' : 'host';
    final myPlayer = room.players[myRoleId];
    final opponentPlayer = room.players[opponentRoleId];
    if (myPlayer == null) {
      return null;
    }

    final myUidValue = myPlayer.uid ?? myUid ?? await _loadAuthenticatedUid();
    myUid = myUidValue;
    final myOldRating = myPlayer.rating ?? await _loadLatestUserRating();
    final opponentOldRating = opponentPlayer?.rating ?? myOldRating;
    final seasonExpired = await _rankedRoomSeasonExpired(room);
    final myNewRating = seasonExpired
        ? myOldRating
        : calculateNewRating(
            myOldRating,
            opponentOldRating,
            isWin,
          );
    final myDelta = myNewRating - myOldRating;

    final myResult = <String, Object?>{
      'uid': myUidValue,
      'isWin': isWin,
      'oldRating': myOldRating,
      'newRating': myNewRating,
      'delta': myDelta,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (seasonExpired) 'seasonExpired': true,
      if (room.seasonId != null) 'seasonId': room.seasonId,
      'resolvedBy': myUidValue,
      'timestamp': ServerValue.timestamp,
    };

    await _db.child('users/$myUidValue').update({
      'name': displayPlayerName,
      'publicId': PlayerDataManager.instance.playerId,
      'rating': myNewRating,
      'updatedAt': ServerValue.timestamp,
    });
    await _db.child('rooms/$roomId/results/$myRoleId').set(myResult);

    if (existingOpponentResult == null &&
        opponentPlayer?.uid != null &&
        opponentPlayer?.rating != null) {
      final opponentUidValue = opponentPlayer!.uid!;
      final opponentNewRating = seasonExpired
          ? opponentPlayer.rating!
          : calculateNewRating(
              opponentPlayer.rating!,
              myOldRating,
              !isWin,
            );
      final opponentDelta = opponentNewRating - opponentPlayer.rating!;
      await _db.child('rooms/$roomId/results/$opponentRoleId').set({
        'uid': opponentUidValue,
        'isWin': !isWin,
        'oldRating': opponentPlayer.rating,
        'newRating': opponentNewRating,
        'delta': opponentDelta,
        if (reason != null && reason.isNotEmpty)
          'reason':
              reason == 'opponent_offline_forfeit' ? 'offline_forfeit' : reason,
        if (seasonExpired) 'seasonExpired': true,
        if (room.seasonId != null) 'seasonId': room.seasonId,
        'resolvedBy': myUidValue,
        'timestamp': ServerValue.timestamp,
      });
    }

    unawaited(
      _removeRoomIfFinishedAfterDelay(roomId, const Duration(seconds: 5)),
    );
    return myResult;
  }

  Future<void> restoreSession({
    required String roomId,
    required String roleId,
  }) async {
    await initializeUser();
    final snapshot = await _db.child('rooms/$roomId').get();
    if (!snapshot.exists) {
      throw StateError('ルームが見つかりません。');
    }

    currentRoomId = roomId;
    myRoleId = roleId;
    final room = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
    final previousStatus = room.players[roleId]?.status;
    final restoredStatus = room.status == 'playing'
        ? 'playing'
        : room.status == 'game_over' ||
                previousStatus == 'dead' ||
                previousStatus == 'rematch_ready' ||
                previousStatus == 'ready'
            ? previousStatus
            : 'waiting';
    await _db.child('rooms/$roomId/players/$roleId').update({
      'name': displayPlayerName,
      'uid': myUid,
      'publicId': PlayerDataManager.instance.playerId,
      'badgeIds': await _currentEquippedBadgeIds(),
      'playerIconId': await _currentEquippedPlayerIconId(),
      'playerIconFrameId': await _currentEquippedIconFrameId(),
      'ballSkinId': await _currentEquippedBallSkinId(),
      'formationEffectId': await _currentEquippedFormationEffectId(),
      'ojamaEffectId': await _currentEquippedOjamaEffectId(),
      'readySfxId': await _currentReadySfxId(),
      'sfxSelectionIds': await _currentSfxSelectionIds(),
      if (restoredStatus != null) 'status': restoredStatus,
      'reconnectedAt': ServerValue.timestamp,
    });
    final refreshedSnapshot = await _db.child('rooms/$roomId').get();
    currentRoom = MultiplayerRoom.fromSnapshot(roomId, refreshedSnapshot.value);
    isRankedMode = currentRoom?.isRanked ?? false;
    _lastRoomStatus = currentRoom!.status;
    _hadOpponentPresent = currentRoom!.players.containsKey(opponentRoleId);
    _opponentDisconnectNotified = false;
    _presencePreserveMode = null;
    await _syncPresenceMode();
    _listenRoom();
    _listenGameplayChannels();
    unawaited(_connectRealtimeTransportIfEnabled());
  }

  Future<void> setReady() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId').update({
        'status': 'ready',
      });

      final refreshedSnapshot = await _db.child('rooms/$roomId').get();
      if (!refreshedSnapshot.exists) {
        return;
      }

      final refreshedRoom =
          MultiplayerRoom.fromSnapshot(roomId, refreshedSnapshot.value);
      currentRoom = refreshedRoom;

      if (refreshedRoom.isRanked && refreshedRoom.bothPlayersReady) {
        await _db.child('rooms/$roomId').update({
          'status': 'playing',
          'startedAt': ServerValue.timestamp,
          'updatedAt': ServerValue.timestamp,
        });
      }
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('READY送信', error));
    }
  }

  Future<void> updateFriendHandicapRows({
    required int hostRows,
    required int guestRows,
  }) async {
    final roomId = currentRoomId;
    if (roomId == null || !isHost) {
      throw StateError('ホストのみハンデを設定できます。');
    }
    final normalizedHostRows = hostRows.clamp(3, 12).toInt();
    final normalizedGuestRows = guestRows.clamp(3, 12).toInt();
    try {
      await _db.child('rooms/$roomId').update({
        'handicapRows/host': normalizedHostRows,
        'handicapRows/guest': normalizedGuestRows,
        'updatedAt': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ハンデ設定', error));
    }
  }

  Future<void> startFriendMatchFromLobby() async {
    final roomId = currentRoomId;
    if (roomId == null || !isHost) {
      throw StateError('ホストのみゲームを開始できます。');
    }
    try {
      final snapshot = await _db.child('rooms/$roomId').get();
      if (!snapshot.exists) {
        throw StateError('ルームが見つかりません。');
      }
      final room = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
      currentRoom = room;
      if (room.isRanked) {
        throw StateError('このルームでは使用できません。');
      }
      if (room.status != 'waiting') {
        throw StateError('相手がロビーに戻るまでお待ちください。');
      }
      if (!room.hasGuest) {
        throw StateError('相手の入室を待っています。');
      }
      if (room.players['guest']?.status != 'ready') {
        throw StateError('相手の準備完了を待っています。');
      }
      final newSeed = DateTime.now().microsecondsSinceEpoch;
      await _db.child('rooms/$roomId').update({
        'seed': newSeed,
        'status': 'playing',
        'startedAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
        'players/host/status': 'playing',
        'players/guest/status': 'playing',
        'players/host/board': null,
        'players/guest/board': null,
        'players/host/activePiece': null,
        'players/guest/activePiece': null,
        'players/host/attacks': null,
        'players/guest/attacks': null,
        'players/host/ojamaSpawns': null,
        'players/guest/ojamaSpawns': null,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ゲーム開始', error));
    }
  }

  Future<void> returnFriendRoomToLobby() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }
    try {
      await _db.child('rooms/$roomId').update({
        'status': 'waiting',
        'players/$roleId/status': 'waiting',
        'players/host/board': null,
        'players/guest/board': null,
        'players/host/activePiece': null,
        'players/guest/activePiece': null,
        'players/host/attacks': null,
        'players/guest/attacks': null,
        'players/host/ojamaSpawns': null,
        'players/guest/ojamaSpawns': null,
        'updatedAt': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ロビー復帰', error));
    }
  }

  Future<void> markCurrentPlayerPlayingIfNeeded() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return;
    }
    try {
      final snapshots = await Future.wait([
        _db.child('rooms/$roomId/status').get(),
        _db.child('rooms/$roomId/players/$roleId/status').get(),
      ]);
      final roomStatus = snapshots[0].value?.toString();
      final playerStatus = snapshots[1].value?.toString();
      if (roomStatus == 'game_over' ||
          playerStatus == 'dead' ||
          playerStatus == 'forfeit_win') {
        return;
      }
      await _db.child('rooms/$roomId/players/$roleId').update({
        'status': 'playing',
        'reconnectedAt': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('接続復帰通知', error));
    }
  }

  Future<List<OjamaTask>> consumeQueuedIncomingOjama() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return const [];
    }
    try {
      final queueRef =
          _db.child('rooms/$roomId/players/$roleId/proxyIncomingOjama');
      final snapshot = await queueRef.get();
      final tasks = _dynamicList(snapshot.value)
          .map(_ojamaTaskFromMap)
          .whereType<OjamaTask>()
          .toList(growable: false);
      if (tasks.isNotEmpty) {
        await queueRef.remove();
      }
      return tasks;
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('復帰時妨害取得', error));
    }
  }

  Future<void> sendBoardState(Map<String, dynamic> boardData) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    final payload = Map<String, dynamic>.from(boardData);
    if (await _sendRealtimeGameplayPrimary('board', payload)) {
      return;
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId/board').set(boardData);
      _sendRealtimeGameplayShadow('board', payload);
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('盤面送信', error));
    }
  }

  Future<Map<String, dynamic>?> loadRoomBattleSnapshot({
    required String roomId,
    required String roleId,
  }) async {
    try {
      final playerEvent =
          await _db.child('rooms/$roomId/players/$roleId').get();
      final playerData = playerEvent.value is Map
          ? playerEvent.value as Map<dynamic, dynamic>
          : null;
      final snapshotEvent =
          await _db.child('rooms/$roomId/players/$roleId/snapshot').get();
      Map<String, dynamic>? resolvedSnapshot;
      if (snapshotEvent.value is Map) {
        resolvedSnapshot = Map<String, dynamic>.from(
            snapshotEvent.value as Map<dynamic, dynamic>);
      } else if (playerData != null) {
        final board = playerData['board'];
        final activePiece = playerData['activePiece'];
        resolvedSnapshot = {
          if (board is Map) 'board': _stringDynamicMap(board),
          if (activePiece is Map) 'activePiece': _stringDynamicMap(activePiece),
          if (activePiece is Map && activePiece['nextColors'] != null)
            'nextColors': _dynamicList(activePiece['nextColors']),
        };
      }

      if (playerData != null) {
        final mergedSnapshot = Map<String, dynamic>.from(
          resolvedSnapshot ?? const {},
        );
        final board = playerData['board'];
        final boardMap = board is Map ? _stringDynamicMap(board) : null;
        final snapshotBoard = mergedSnapshot['board'];
        final snapshotBoardMap =
            snapshotBoard is Map ? _stringDynamicMap(snapshotBoard) : null;
        if (boardMap != null &&
            (boardMap.isNotEmpty ||
                snapshotBoardMap == null ||
                snapshotBoardMap.isEmpty)) {
          mergedSnapshot['board'] = boardMap;
        }

        final activePiece = playerData['activePiece'];
        if (activePiece is Map) {
          mergedSnapshot['activePiece'] = _stringDynamicMap(activePiece);
          if (activePiece['nextColors'] != null) {
            mergedSnapshot['nextColors'] =
                _dynamicList(activePiece['nextColors']);
          }
        }

        final proxyControlledBy = playerData['proxyControlledBy'];
        if (proxyControlledBy != null && '$proxyControlledBy'.isNotEmpty) {
          mergedSnapshot['proxyControlledBy'] = '$proxyControlledBy';
        }

        resolvedSnapshot = mergedSnapshot;
      }

      final proxyQueueEvent = await _db
          .child('rooms/$roomId/players/$roleId/proxyIncomingOjama')
          .get();
      final queuedTasks = _dynamicList(proxyQueueEvent.value)
          .map(_ojamaTaskFromMap)
          .whereType<OjamaTask>()
          .toList();
      if (queuedTasks.isEmpty &&
          (resolvedSnapshot == null || resolvedSnapshot.isEmpty)) {
        return null;
      }
      if (queuedTasks.isEmpty) {
        return resolvedSnapshot;
      }

      final baseSnapshot =
          Map<String, dynamic>.from(resolvedSnapshot ?? const {});
      final incoming = <Map<String, dynamic>>[];
      final existingIncoming = baseSnapshot['incomingOjama'];
      if (existingIncoming is List) {
        incoming.addAll(
          existingIncoming.whereType<Map>().map(
                (item) => Map<String, dynamic>.from(item),
              ),
        );
      }
      incoming.addAll(queuedTasks.map(_ojamaTaskToMap));
      baseSnapshot['incomingOjama'] = incoming;
      return baseSnapshot;
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('復帰用データ取得', error));
    }
  }

  Future<void> sendActivePiece(
    double x,
    double y,
    int rotation,
    List<BallColor> colors,
    String action,
    int dropSeed,
    int pieceId,
    int eventSeq,
    List<int> nextColors,
    bool movingLeft,
    bool movingRight,
    double contactSlideDirection,
    double relativeX,
    double relativeY,
    String ballSkinId,
    List<Map<String, dynamic>>? lockedCells,
  ) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    final includesTransform = switch (action) {
      'spawn' ||
      'rotate_left' ||
      'rotate_right' ||
      'set_x' ||
      'start_left' ||
      'stop_left' ||
      'start_right' ||
      'stop_right' ||
      'contact_slide' ||
      'move' ||
      'hard_drop' ||
      'lock' =>
        true,
      _ => false,
    };
    final payload = includesTransform
        ? <String, dynamic>{
            'action': action,
            'rotation': rotation,
            'colors': colors.map((color) => color.index).toList(),
            'dropSeed': dropSeed,
            'pieceId': pieceId,
            'eventSeq': eventSeq,
            'nextColors': nextColors,
            'movingLeft': movingLeft,
            'movingRight': movingRight,
            'contactSlideDirection': contactSlideDirection,
            'ballSkinId': ballSkinId,
            'x': x,
            'y': y,
            'relativeX': relativeX,
            'relativeY': relativeY,
            if (lockedCells != null && lockedCells.isNotEmpty)
              'lockedCells': lockedCells,
          }
        : <String, dynamic>{
            'action': action,
            'pieceId': pieceId,
            'eventSeq': eventSeq,
            'movingLeft': movingLeft,
            'movingRight': movingRight,
            if (contactSlideDirection != 0)
              'contactSlideDirection': contactSlideDirection,
          };
    if (await _sendRealtimeGameplayPrimary('activePiece', payload)) {
      return;
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId/activePiece').set({
        ...payload,
        'timestamp': ServerValue.timestamp,
      });
      _sendRealtimeGameplayShadow('activePiece', payload);
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ピース同期送信', error));
    }
  }

  Future<void> sendAttack(OjamaTask task) async {
    final roomId = currentRoomId;
    if (roomId == null || myRoleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    final attackRef =
        _db.child('rooms/$roomId/players/$opponentRoleId/attacks').push();
    final realtimePayload = <String, dynamic>{
      'type': task.type.name,
      'startColor': task.startColor?.index,
      'presetColors': task.presetColors?.map((color) => color.index).toList(),
      'ballSkinId': task.ballSkinId,
      'effectSkinId': task.effectSkinId,
    };

    final payload = {
      ...realtimePayload,
      'timestamp': ServerValue.timestamp,
    };
    try {
      await attackRef.set(payload);
      _sendRealtimeGameplayShadow('attack', realtimePayload);
    } on FirebaseException catch (error) {
      final reconnected = await RealtimeConnectionGuard.waitForConnected(
        timeout: const Duration(milliseconds: 500),
      );
      if (!reconnected) {
        throw StateError(_firebaseErrorMessage('攻撃送信', error));
      }
      try {
        await attackRef.set(payload);
        _sendRealtimeGameplayShadow('attack', realtimePayload);
      } on FirebaseException catch (retryError) {
        throw StateError(_firebaseErrorMessage('攻撃送信', retryError));
      }
    }
  }

  Future<void> queueDisconnectedOpponentAttack(OjamaTask task) async {
    final roomId = currentRoomId;
    if (roomId == null || myRoleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db
          .child('rooms/$roomId/players/$opponentRoleId/proxyIncomingOjama')
          .push()
          .set({
        ..._ojamaTaskToMap(task),
        'queuedBy': myUid,
        'timestamp': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('切断相手への攻撃保存', error));
    }
  }

  Future<bool> queueOpponentAttackIfDisconnected(OjamaTask task) async {
    final roomId = currentRoomId;
    if (roomId == null || myRoleId == null) {
      return false;
    }
    try {
      final opponentRole = opponentRoleId;
      final statusSnapshot =
          await _db.child('rooms/$roomId/players/$opponentRole/status').get();
      if (statusSnapshot.value?.toString() == 'left') {
        await queueDisconnectedOpponentAttack(task);
        return true;
      }
    } on FirebaseException {
      // 待避キューは切断復帰用の補助なので、通常の攻撃送信は止めない。
    }
    return false;
  }

  Future<void> sendStamp(String stampId, {int level = 1}) async {
    final roomId = currentRoomId;
    if (roomId == null || myRoleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    final payload = <String, dynamic>{
      'id': stampId,
      'level': level.clamp(1, 4),
    };
    if (await _sendRealtimeGameplayPrimary('stamp', payload)) {
      return;
    }

    try {
      await _db
          .child('rooms/$roomId/players/$opponentRoleId/stamps')
          .push()
          .set({
        'id': stampId,
        'level': level.clamp(1, 4),
        'timestamp': ServerValue.timestamp,
      });
      _sendRealtimeGameplayShadow('stamp', payload);
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('スタンプ送信', error));
    }
  }

  Future<void> sendOjamaSpawn(List<dynamic> ojamaData, int dropSeed) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    final payload = <String, dynamic>{
      'items': ojamaData,
      'dropSeed': dropSeed,
    };
    if (await _sendRealtimeGameplayPrimary('ojamaSpawn', payload)) {
      return;
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId/ojamaSpawns').push().set({
        'items': ojamaData,
        'dropSeed': dropSeed,
        'timestamp': ServerValue.timestamp,
      });
      _sendRealtimeGameplayShadow('ojamaSpawn', payload);
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('妨害同期送信', error));
    }
  }

  Future<void> declareGameOver({
    Map<String, dynamic>? finalBoard,
  }) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId').update({
        'status': 'dead',
        if (finalBoard != null) 'finalBoard': finalBoard,
      });
      await _db.child('rooms/$roomId').update({
        'status': 'game_over',
        'endedAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });
      unawaited(_realtimeTransportClient.sendRelay('gameOver', {
        'roleId': roleId,
        if (finalBoard != null) 'finalBoard': finalBoard,
      }));
      if (isRankedMode || (currentRoom?.isRanked ?? false)) {
        unawaited(
          _removeRoomIfFinishedAfterDelay(
            roomId,
            const Duration(seconds: 5),
          ),
        );
      }
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ゲーム終了送信', error));
    }
  }

  Future<void> forceOpponentGameOver() async {
    final room = currentRoom;
    final roomId = currentRoomId;
    final roleId = myRoleId;
    final opponentRole = myRoleId == 'host' ? 'guest' : 'host';
    if (room == null || roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      if (isRankedMode || room.isRanked) {
        await _ensureRankedResultRecorded(
          room: room,
          myRoleId: roleId,
          isWin: true,
          reason: 'opponent_offline_forfeit',
        );
      } else {
        await _db.child('rooms/$roomId/results/$roleId').set({
          'uid': myUid,
          'isWin': true,
          'reason': 'opponent_offline_forfeit',
          'resolvedBy': myUid,
          'timestamp': ServerValue.timestamp,
        });
        await _db.child('rooms/$roomId/results/$opponentRole').set({
          'isWin': false,
          'reason': 'offline_forfeit',
          'resolvedBy': myUid,
          'timestamp': ServerValue.timestamp,
        });
      }
      await _db.child('rooms/$roomId/players/$roleId').update({
        'status': 'forfeit_win',
        'finishReason': 'opponent_offline_forfeit',
        'resolvedAt': ServerValue.timestamp,
      });
      await _db.child('rooms/$roomId/players/$opponentRole').update({
        'status': 'dead',
        'resolvedBy': myUid,
        'finishReason': 'offline_forfeit',
        'resolvedAt': ServerValue.timestamp,
      });
      await _db.child('rooms/$roomId').update({
        'status': 'game_over',
        'endedAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
        'finishReason': 'offline_forfeit',
        'forfeitLoserRole': opponentRole,
        'forfeitWinnerRole': roleId,
      });
      if (isRankedMode || (currentRoom?.isRanked ?? false)) {
        unawaited(
          _removeRoomIfFinishedAfterDelay(
            roomId,
            const Duration(seconds: 5),
          ),
        );
      }
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('相手側ゲーム終了確定', error));
    }
  }

  Future<bool> recordOfflineForfeitLoss() async {
    final room = currentRoom;
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (room == null || roomId == null || roleId == null) {
      return false;
    }

    final opponentRole = roleId == 'host' ? 'guest' : 'host';
    try {
      if (isRankedMode || room.isRanked) {
        await _ensureRankedResultRecorded(
          room: room,
          myRoleId: roleId,
          isWin: false,
          reason: 'offline_forfeit',
        );
      } else {
        await _db.child('rooms/$roomId/results/$roleId').set({
          'uid': myUid,
          'isWin': false,
          'reason': 'offline_forfeit',
          'resolvedBy': myUid,
          'timestamp': ServerValue.timestamp,
        });
        await _db.child('rooms/$roomId/results/$opponentRole').set({
          'isWin': true,
          'reason': 'opponent_offline_forfeit',
          'resolvedBy': myUid,
          'timestamp': ServerValue.timestamp,
        });
      }

      await _db.child('rooms/$roomId').update({
        'status': 'game_over',
        'endedAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
        'finishReason': 'offline_forfeit',
        'forfeitLoserRole': roleId,
        'forfeitWinnerRole': opponentRole,
      });
      await _db.child('rooms/$roomId/players/$roleId').update({
        'status': 'dead',
        'finishReason': 'offline_forfeit',
        'resolvedAt': ServerValue.timestamp,
      });
      await _db.child('rooms/$roomId/players/$opponentRole').update({
        'status': 'forfeit_win',
        'finishReason': 'opponent_offline_forfeit',
        'resolvedAt': ServerValue.timestamp,
      });
      unawaited(_realtimeTransportClient.sendRelay('gameOver', {
        'roleId': roleId,
        'reason': 'offline_forfeit',
      }));
      unawaited(
        _removeRoomIfFinishedAfterDelay(roomId, const Duration(seconds: 8)),
      );
      return true;
    } on FirebaseException {
      return false;
    }
  }

  Future<bool?> loadCurrentRoomResultIsWin() async {
    final result = await loadCurrentRoomResult();
    return result?.isWin;
  }

  Future<RoomResultSnapshot?> loadCurrentRoomResult() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return null;
    }
    try {
      final snapshot = await _db.child('rooms/$roomId/results/$roleId').get();
      final value = snapshot.value;
      if (value is Map) {
        return RoomResultSnapshot(
          isWin: value['isWin'] == true,
          reason: value['reason']?.toString() ?? '',
        );
      }
    } on FirebaseException {
      return null;
    }
    return null;
  }

  Future<void> removeCurrentRoomIfFinished({
    Duration delay = Duration.zero,
  }) async {
    final roomId = currentRoomId;
    if (roomId == null) {
      return;
    }
    await _removeRoomIfFinishedAfterDelay(roomId, delay);
  }

  Future<void> _removeRoomIfFinishedAfterDelay(
    String roomId,
    Duration delay,
  ) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    try {
      final roomRef = _db.child('rooms/$roomId');
      final snapshot = await roomRef.get();
      if (_roomValueLooksFinished(snapshot.value)) {
        await roomRef.remove();
      }
    } on FirebaseException {
      // 終了済みルームの掃除失敗は次回の退出やメンテナンスで再試行する。
    }
  }

  bool _roomValueLooksFinished(Object? value) {
    if (value is! Map) {
      return false;
    }
    final status = value['status']?.toString();
    if (status == 'game_over') {
      return true;
    }
    final results = value['results'];
    if (results is Map && results.isNotEmpty) {
      return true;
    }
    final players = value['players'];
    if (players is! Map || players.isEmpty) {
      return false;
    }
    return players.values.every((player) {
      if (player is! Map) {
        return false;
      }
      final playerStatus = player['status']?.toString();
      return playerStatus == 'left' || playerStatus == 'dead';
    });
  }

  Future<void> syncDisconnectedOpponentSnapshot(
    Map<String, dynamic> snapshot, {
    bool clearQueuedOjama = true,
  }) async {
    final roomId = currentRoomId;
    if (roomId == null || myRoleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    final opponentRole = myRoleId == 'host' ? 'guest' : 'host';
    final updatePayload = <String, Object?>{
      'players/$opponentRole/snapshot': Map<String, dynamic>.from(snapshot)
        ..['savedAt'] = ServerValue.timestamp
        ..['proxyControlledBy'] = myUid,
      'players/$opponentRole/board': snapshot['board'],
      'players/$opponentRole/proxyControlledBy': myUid,
      'players/$opponentRole/proxyUpdatedAt': ServerValue.timestamp,
    };

    if (snapshot['activePiece'] is Map) {
      updatePayload['players/$opponentRole/activePiece'] =
          Map<String, dynamic>.from(snapshot['activePiece'] as Map);
    } else {
      updatePayload['players/$opponentRole/activePiece'] = null;
    }
    if (clearQueuedOjama) {
      updatePayload['players/$opponentRole/proxyIncomingOjama'] = null;
    }

    try {
      await _db.child('rooms/$roomId').update(updatePayload);
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('切断相手の状態同期', error));
    }
  }

  Future<void> clearQueuedProxyOjamaForSelf() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return;
    }

    try {
      await _db
          .child('rooms/$roomId/players/$roleId/proxyIncomingOjama')
          .remove();
    } on FirebaseException {
      // 復帰用補助キューの削除失敗は対戦継続を優先する。
    }
  }

  Future<void> requestRematch() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId').update({
        'status': 'rematch_ready',
      });
      unawaited(_realtimeTransportClient.sendRelay('rematchRequest', {
        'roleId': roleId,
      }));
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('再戦準備', error));
    }
  }

  void _listenRoom() {
    _roomSubscription?.cancel();
    _roomStatusSubscription?.cancel();
    _myStatusSubscription?.cancel();

    final roomId = currentRoomId;
    if (roomId == null) {
      return;
    }

    _roomSubscription = _db.child('rooms/$roomId').onValue.listen((event) {
      if (event.snapshot.value == null) {
        if (_hadOpponentPresent) {
          _notifyOpponentDisconnected();
        }
        currentRoom = null;
        _lastRoomStatus = null;
        _lastRoomUiSignature = null;
        _hadOpponentPresent = false;
        return;
      }

      final room = MultiplayerRoom.fromSnapshot(roomId, event.snapshot.value);
      final opponentPresent = room.players.containsKey(opponentRoleId);
      final opponentLeft = room.players[opponentRoleId]?.status == 'left';
      if (_hadOpponentPresent && (!opponentPresent || opponentLeft)) {
        _notifyOpponentDisconnected();
      } else if (opponentPresent && !opponentLeft) {
        _opponentDisconnectNotified = false;
      }
      _hadOpponentPresent = opponentPresent;

      if (room.bothPlayersRematchReady &&
          isHost &&
          room.status == 'game_over' &&
          !_isLaunchingRematch) {
        _isLaunchingRematch = true;
        unawaited(_startRematch(roomId));
      }

      if (_lastRoomStatus == 'game_over' && room.status == 'playing') {
        onRematchStarted?.call(room.seed);
      }

      currentRoom = room;
      _lastRoomStatus = room.status;
      unawaited(_refreshPresenceModeIfNeeded());
      final nextRoomUiSignature = _roomUiSignature(room);
      if (_lastRoomUiSignature != nextRoomUiSignature) {
        _lastRoomUiSignature = nextRoomUiSignature;
        onRoomUpdated?.call(room);
      }
      if (room.status == 'playing') {
        _switchToLightweightRoomListeners();
      }
    });
  }

  void _switchToLightweightRoomListeners() {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return;
    }
    _roomSubscription?.cancel();
    _roomSubscription = null;
    _roomStatusSubscription?.cancel();
    _myStatusSubscription?.cancel();

    _roomStatusSubscription =
        _db.child('rooms/$roomId/status').onValue.listen((event) {
      final status = event.snapshot.value?.toString();
      if (status == null || status.isEmpty) {
        _handleRoomDeleted();
        return;
      }
      _applyRoomStatusUpdate(status);
    });

    _myStatusSubscription =
        _db.child('rooms/$roomId/players/$roleId/status').onValue.listen(
      (event) {
        final status = event.snapshot.value?.toString();
        if (status != null && status.isNotEmpty) {
          _applyPlayerStatusUpdate(roleId, status);
        }
      },
    );
  }

  void _handleRoomDeleted() {
    if (_hadOpponentPresent) {
      _notifyOpponentDisconnected();
    }
    currentRoom = null;
    _lastRoomStatus = null;
    _lastRoomUiSignature = null;
    _hadOpponentPresent = false;
  }

  void _applyRoomStatusUpdate(String status) {
    final previousStatus = _lastRoomStatus;
    final room = currentRoom;
    if (room == null) {
      _lastRoomStatus = status;
      return;
    }
    final nextRoom = MultiplayerRoom(
      roomId: room.roomId,
      status: status,
      seed: room.seed,
      players: room.players,
      isRanked: room.isRanked,
      seasonId: room.seasonId,
      seasonEndsAt: room.seasonEndsAt,
      hostBoardRows: room.hostBoardRows,
      guestBoardRows: room.guestBoardRows,
    );
    currentRoom = nextRoom;
    _lastRoomStatus = status;
    unawaited(_refreshPresenceModeIfNeeded());
    if (previousStatus == 'game_over' && status == 'playing') {
      unawaited(_notifyRematchStartedWithLatestSeed(nextRoom.roomId));
    }
    final nextRoomUiSignature = _roomUiSignature(nextRoom);
    if (_lastRoomUiSignature != nextRoomUiSignature) {
      _lastRoomUiSignature = nextRoomUiSignature;
      onRoomUpdated?.call(nextRoom);
    }
    if (status == 'game_over' && !isRankedMode && !(nextRoom.isRanked)) {
      _listenRoom();
    }
  }

  void _applyPlayerStatusUpdate(String roleId, String status) {
    final room = currentRoom;
    if (room == null) {
      return;
    }
    final previousPlayer = room.players[roleId];
    if (previousPlayer == null || previousPlayer.status == status) {
      return;
    }
    final players = Map<String, MultiplayerPlayer>.from(room.players);
    players[roleId] = MultiplayerPlayer(
      status: status,
      name: previousPlayer.name,
      uid: previousPlayer.uid,
      publicId: previousPlayer.publicId,
      rating: previousPlayer.rating,
      badgeIds: previousPlayer.badgeIds,
      playerIconId: previousPlayer.playerIconId,
      playerIconFrameId: previousPlayer.playerIconFrameId,
      ballSkinId: previousPlayer.ballSkinId,
      formationEffectId: previousPlayer.formationEffectId,
      ojamaEffectId: previousPlayer.ojamaEffectId,
      readySfxId: previousPlayer.readySfxId,
      sfxSelectionIds: previousPlayer.sfxSelectionIds,
    );
    final nextRoom = MultiplayerRoom(
      roomId: room.roomId,
      status: room.status,
      seed: room.seed,
      players: players,
      isRanked: room.isRanked,
      seasonId: room.seasonId,
      seasonEndsAt: room.seasonEndsAt,
      hostBoardRows: room.hostBoardRows,
      guestBoardRows: room.guestBoardRows,
    );
    currentRoom = nextRoom;
    final opponentPresent = nextRoom.players.containsKey(opponentRoleId);
    final opponentLeft = nextRoom.players[opponentRoleId]?.status == 'left';
    if (_hadOpponentPresent && (!opponentPresent || opponentLeft)) {
      _notifyOpponentDisconnected();
    } else if (opponentPresent && !opponentLeft) {
      _opponentDisconnectNotified = false;
    }
    _hadOpponentPresent = opponentPresent;

    if (nextRoom.bothPlayersRematchReady &&
        isHost &&
        nextRoom.status == 'game_over' &&
        !_isLaunchingRematch) {
      _isLaunchingRematch = true;
      unawaited(_startRematch(nextRoom.roomId));
    }

    final nextRoomUiSignature = _roomUiSignature(nextRoom);
    if (_lastRoomUiSignature != nextRoomUiSignature) {
      _lastRoomUiSignature = nextRoomUiSignature;
      onRoomUpdated?.call(nextRoom);
    }
  }

  Future<void> _notifyRematchStartedWithLatestSeed(String roomId) async {
    try {
      final seedSnapshot = await _db.child('rooms/$roomId/seed').get();
      final seed = _globalIntValue(seedSnapshot.value) ??
          currentRoom?.seed ??
          DateTime.now().millisecondsSinceEpoch;
      final room = currentRoom;
      if (room != null) {
        currentRoom = MultiplayerRoom(
          roomId: room.roomId,
          status: room.status,
          seed: seed,
          players: room.players,
          isRanked: room.isRanked,
          seasonId: room.seasonId,
          seasonEndsAt: room.seasonEndsAt,
          hostBoardRows: room.hostBoardRows,
          guestBoardRows: room.guestBoardRows,
        );
      }
      onRematchStarted?.call(seed);
    } catch (_) {
      onRematchStarted?.call(
        currentRoom?.seed ?? DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  String _roomUiSignature(MultiplayerRoom room) {
    final buffer = StringBuffer()
      ..write(room.status)
      ..write('|')
      ..write(room.seed)
      ..write('|')
      ..write(room.isRanked)
      ..write('|')
      ..write(room.seasonId ?? '')
      ..write('|')
      ..write(room.seasonEndsAt ?? '')
      ..write('|')
      ..write(room.hostBoardRows)
      ..write('|')
      ..write(room.guestBoardRows);

    final roles = room.players.keys.toList()..sort();
    for (final role in roles) {
      final player = room.players[role]!;
      buffer
        ..write('|')
        ..write(role)
        ..write(':')
        ..write(player.status)
        ..write(':')
        ..write(player.name)
        ..write(':')
        ..write(player.uid ?? '')
        ..write(':')
        ..write(player.rating ?? '')
        ..write(':')
        ..write(player.playerIconId)
        ..write(':')
        ..write(player.playerIconFrameId)
        ..write(':')
        ..write(player.ballSkinId)
        ..write(':')
        ..write(player.formationEffectId)
        ..write(':')
        ..write(player.ojamaEffectId)
        ..write(':')
        ..write(player.readySfxId)
        ..write(':')
        ..write(player.sfxSelectionIds.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(','))
        ..write(':')
        ..write(player.badgeIds.join(','));
    }
    return buffer.toString();
  }

  void _listenGameplayChannels() {
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _stampSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
    _stampSubscription = null;
    _opponentOjamaSpawnSubscription = null;
    _opponentStatusSubscription = null;

    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return;
    }

    if (!_realtimeTransportClient.useAsPrimaryGameplayTransport) {
      _opponentBoardSubscription = _db
          .child('rooms/$roomId/players/$opponentRoleId/board')
          .onValue
          .listen((event) {
        final value = event.snapshot.value;
        if (value is Map<dynamic, dynamic>) {
          onOpponentBoardUpdated?.call(_stringDynamicMap(value));
        }
      });

      _opponentPieceSubscription = _db
          .child('rooms/$roomId/players/$opponentRoleId/activePiece')
          .onValue
          .listen((event) {
        final value = event.snapshot.value;
        if (value is Map<dynamic, dynamic>) {
          onOpponentPieceUpdated?.call(_stringDynamicMap(value));
        }
      });

      _stampSubscription = _db
          .child('rooms/$roomId/players/$roleId/stamps')
          .onChildAdded
          .listen((event) async {
        final value = event.snapshot.value;
        if (value is Map<dynamic, dynamic>) {
          final stampId = value['id'] as String?;
          if (stampId != null) {
            onOpponentStampReceived?.call(
              stampId,
              (_intValue(value['level']) ?? 1).clamp(1, 4),
            );
          }
        }
        if (event.snapshot.key != null) {
          await event.snapshot.ref.remove();
        }
      });

      _opponentOjamaSpawnSubscription = _db
          .child('rooms/$roomId/players/$opponentRoleId/ojamaSpawns')
          .onChildAdded
          .listen((event) async {
        final value = event.snapshot.value;
        if (value is Map<dynamic, dynamic>) {
          final items = _dynamicList(value['items']);
          final dropSeed = (value['dropSeed'] as num?)?.toInt();
          if (items.isNotEmpty) {
            onOpponentOjamaSpawned?.call(
              items,
              dropSeed ?? DateTime.now().microsecondsSinceEpoch,
            );
          }
        }

        if (event.snapshot.key != null) {
          await event.snapshot.ref.remove();
        }
      });
    }

    _attackSubscription = _db
        .child('rooms/$roomId/players/$roleId/attacks')
        .onChildAdded
        .listen((event) async {
      final task = _ojamaTaskFromMap(event.snapshot.value);
      if (task != null) {
        onAttackReceived?.call(task);
      }

      if (event.snapshot.key != null) {
        await event.snapshot.ref.remove();
      }
    });

    _opponentStatusSubscription = _db
        .child('rooms/$roomId/players/$opponentRoleId/status')
        .onValue
        .listen((event) async {
      final status = event.snapshot.value as String?;
      if (status != null && status.isNotEmpty) {
        _applyPlayerStatusUpdate(opponentRoleId, status);
      }
      if (status == 'dead') {
        Map<String, dynamic>? finalBoard;
        String? finishReason;
        try {
          final playerSnapshot =
              await _db.child('rooms/$roomId/players/$opponentRoleId').get();
          final playerValue = playerSnapshot.value;
          if (playerValue is Map) {
            finishReason = playerValue['finishReason']?.toString();
          }
          final finalBoardSnapshot = playerValue is Map
              ? playerValue['finalBoard']
              : (await _db
                      .child('rooms/$roomId/players/$opponentRoleId/finalBoard')
                      .get())
                  .value;
          if (finalBoardSnapshot is Map) {
            finalBoard = _stringDynamicMap(
              finalBoardSnapshot,
            );
          }
        } on FirebaseException {
          // finalBoardは補助情報なので、取得失敗時も従来通り処理する。
        }
        onOpponentGameOver?.call(
          finalBoard: finalBoard,
          reason: finishReason ?? status,
        );
      } else if (status == 'left') {
        _notifyOpponentDisconnected();
      }
    });
  }

  Future<bool> _sendRealtimeGameplayPrimary(
    String type,
    Map<String, dynamic> payload,
  ) async {
    if (!_realtimeTransportClient.useAsPrimaryGameplayTransport) {
      return false;
    }
    return _realtimeTransportClient.sendRelay(type, payload);
  }

  void reportRealtimeMetric(
    String name, {
    num value = 1,
    Map<String, dynamic>? payload,
  }) {
    unawaited(
      _realtimeTransportClient.sendMetric(
        name,
        value: value,
        payload: payload,
      ),
    );
  }

  void _sendRealtimeGameplayShadow(
    String type,
    Map<String, dynamic> payload,
  ) {
    if (_realtimeTransportClient.useAsPrimaryGameplayTransport) {
      return;
    }
    unawaited(_realtimeTransportClient.sendRelay(type, payload));
  }

  void _handleRealtimeRelay(
    String messageType,
    Map<String, dynamic> payload,
  ) {
    switch (messageType) {
      case 'board':
        onOpponentBoardUpdated?.call(payload);
        break;
      case 'activePiece':
        onOpponentPieceUpdated?.call(payload);
        break;
      case 'attack':
        final task = _ojamaTaskFromMap(payload);
        if (task != null) {
          onAttackReceived?.call(task);
        }
        break;
      case 'stamp':
        final stampId = payload['id']?.toString();
        if (stampId != null && stampId.isNotEmpty) {
          onOpponentStampReceived?.call(
            stampId,
            (_intValue(payload['level']) ?? 1).clamp(1, 4),
          );
        }
        break;
      case 'ojamaSpawn':
        final items = _dynamicList(payload['items']);
        if (items.isNotEmpty) {
          onOpponentOjamaSpawned?.call(
            items,
            _intValue(payload['dropSeed']) ??
                DateTime.now().microsecondsSinceEpoch,
          );
        }
        break;
      case 'gameOver':
        final finalBoard = payload['finalBoard'];
        onOpponentGameOver?.call(
          finalBoard:
              finalBoard is Map ? Map<String, dynamic>.from(finalBoard) : null,
          reason: payload['reason']?.toString(),
        );
        break;
      case 'rematchRequest':
      case 'rematchReady':
      case 'snapshotRequest':
      case 'snapshot':
      case 'resultCommit':
        break;
    }
  }

  void _notifyOpponentDisconnected() {
    if (_opponentDisconnectNotified) {
      return;
    }
    _opponentDisconnectNotified = true;
    onOpponentDisconnected?.call();
  }

  Future<void> cancelLobby() => leaveRoom(forceRemove: true);

  Future<void> suspendActiveSession() async {
    _roomSubscription?.cancel();
    _roomStatusSubscription?.cancel();
    _myStatusSubscription?.cancel();
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _stampSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _roomSubscription = null;
    _roomStatusSubscription = null;
    _myStatusSubscription = null;
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
    _stampSubscription = null;
    _opponentOjamaSpawnSubscription = null;
    _opponentStatusSubscription = null;
    _realtimeTransportClient.onRelay = null;
    _realtimeTransportClient.onPresence = null;
    _realtimeTransportClient.onReady = null;
    _realtimeTransportClient.onDisconnected = null;
    await _realtimeTransportClient.disconnect();
    onRoomUpdated = null;
    onOpponentBoardUpdated = null;
    onOpponentPieceUpdated = null;
    onAttackReceived = null;
    onOpponentOjamaSpawned = null;
    onOpponentStampReceived = null;
    onOpponentGameOver = null;
    onOpponentDisconnected = null;
    onRematchStarted = null;
  }

  Future<void> leaveRoom({bool forceRemove = false}) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    final preserveRoom = forceRemove ? false : _shouldPreserveRoomOnDisconnect;

    _roomSubscription?.cancel();
    _roomStatusSubscription?.cancel();
    _myStatusSubscription?.cancel();
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _stampSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _roomSubscription = null;
    _roomStatusSubscription = null;
    _myStatusSubscription = null;
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
    _stampSubscription = null;
    _opponentOjamaSpawnSubscription = null;
    _opponentStatusSubscription = null;
    _realtimeTransportClient.onRelay = null;
    _realtimeTransportClient.onPresence = null;
    _realtimeTransportClient.onReady = null;
    _realtimeTransportClient.onDisconnected = null;
    await _realtimeTransportClient.disconnect();

    try {
      if (roomId != null && roleId != null) {
        final roomRef = _db.child('rooms/$roomId');
        await roomRef.child('players/$roleId').onDisconnect().cancel();
        await roomRef.onDisconnect().cancel();

        final currentSnapshot = await roomRef.get();
        if (_roomValueLooksFinished(currentSnapshot.value)) {
          await roomRef.remove();
        } else if (preserveRoom) {
          await roomRef.child('players/$roleId').update({
            'status': 'left',
            'disconnectedAt': ServerValue.timestamp,
          });
          final refreshedSnapshot = await roomRef.get();
          if (_roomValueLooksFinished(refreshedSnapshot.value)) {
            await roomRef.remove();
          }
        } else if (roleId == 'host') {
          await roomRef.remove();
        } else {
          await roomRef.child('players/$roleId').remove();
          await roomRef.update({'status': 'waiting'});
        }
      }
    } on FirebaseException {
      // 退出処理の失敗は画面遷移を止めない。
    }

    currentRoomId = null;
    myRoleId = null;
    currentRoom = null;
    isRankedMode = false;
    _lastRoomStatus = null;
    _lastRoomUiSignature = null;
    _hadOpponentPresent = false;
    _isLaunchingRematch = false;
    _opponentDisconnectNotified = false;
    _presencePreserveMode = null;
    onRoomUpdated = null;
    onOpponentBoardUpdated = null;
    onOpponentPieceUpdated = null;
    onAttackReceived = null;
    onOpponentOjamaSpawned = null;
    onOpponentStampReceived = null;
    onOpponentGameOver = null;
    onOpponentDisconnected = null;
    onRematchStarted = null;
  }

  Future<void> _connectRealtimeTransportIfEnabled() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null || roomId == rankedBotRoomId) {
      _realtimeTransportClient.onRelay = null;
      _realtimeTransportClient.onPresence = null;
      _realtimeTransportClient.onReady = null;
      _realtimeTransportClient.onDisconnected = null;
      await _realtimeTransportClient.disconnect();
      return;
    }
    _realtimeTransportClient.onRelay = _handleRealtimeRelay;
    _realtimeTransportClient.onPresence = _handleRealtimePresence;
    _realtimeTransportClient.onReady = _listenGameplayChannels;
    _realtimeTransportClient.onDisconnected = _listenGameplayChannels;
    await _realtimeTransportClient.connectIfEnabled(
      roomId: roomId,
      roleId: roleId,
      mode: _currentTransportMode,
      displayName: displayPlayerName,
    );
  }

  String get _currentTransportMode {
    final room = currentRoom;
    if (room?.isRanked == true || isRankedMode) {
      return 'ranked';
    }
    return 'friend';
  }

  void _handleRealtimePresence(List<Map<String, dynamic>> players) {
    final roleId = myRoleId;
    final room = currentRoom;
    if (roleId == null) {
      return;
    }
    final opponentRole = opponentRoleId;
    final opponentPresent = players.any(
      (player) => player['role']?.toString() == opponentRole,
    );
    final roomIsPlaying =
        room?.status == 'playing' || _lastRoomStatus == 'playing';
    if (roomIsPlaying && !opponentPresent) {
      _notifyOpponentDisconnected();
      return;
    }
    if (opponentPresent) {
      _hadOpponentPresent = true;
      _opponentDisconnectNotified = false;
    }
  }

  Future<int> _loadLatestUserRating() async {
    final uid = myUid ?? await _loadAuthenticatedUid();
    myUid = uid;
    try {
      final snapshot = await _db.child('users/$uid/rating').get();
      final latest = _intValue(snapshot.value);
      if (latest != null) {
        currentRating = latest;
        return latest;
      }
    } catch (_) {
      // 読み出し失敗時は手元の値をそのまま使う。
    }
    return currentRating;
  }

  String _firebaseErrorMessage(String action, FirebaseException error) {
    if (_isOfflineFirebaseError(error)) {
      return RealtimeConnectionGuard.offlineMessage;
    }
    final parts = <String>['$actionに失敗しました。'];
    if (error.code.isNotEmpty) {
      parts.add('code: ${error.code}');
    }
    if (error.message != null && error.message!.isNotEmpty) {
      parts.add(error.message!);
    }
    if (error.code == 'permission-denied') {
      final projectId = AppFirebaseDatabase.app.options.projectId;
      parts.add(
        '接続先Firebaseプロジェクト: $projectId\n'
        'Realtime Database Rules が対象プロジェクトへデプロイ済みか、'
        'App Check を有効にしている場合は現在のビルドを許可しているか確認してください。',
      );
    }
    return parts.join('\n');
  }

  bool _isOfflineFirebaseError(FirebaseException error) {
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    return code == 'disconnected' ||
        code == 'network-error' ||
        code == 'network-request-failed' ||
        code == 'unavailable' ||
        message.contains('network') ||
        message.contains('offline') ||
        message.contains('disconnected');
  }

  Map<String, dynamic> _stringDynamicMap(Map<dynamic, dynamic> data) {
    return {
      for (final entry in data.entries) entry.key.toString(): entry.value,
    };
  }

  Future<String> _loadAuthenticatedUid() async {
    final uid = await AuthManager.instance.ensureSignedIn();
    myUid = uid;
    return uid;
  }

  int? _intValue(Object? value) {
    return _globalIntValue(value);
  }

  Future<void> _refreshPresenceModeIfNeeded() async {
    try {
      await _syncPresenceMode();
    } catch (_) {
      // 接続設定の再同期失敗は次のルーム更新で再試行する。
    }
  }

  Future<void> _syncPresenceMode() async {
    final preserveRoom = _shouldPreserveRoomOnDisconnect;
    if (_presencePreserveMode == preserveRoom) {
      return;
    }
    await _configurePresenceHandlers(preserveRoom: preserveRoom);
  }

  Future<void> _configurePresenceHandlers({
    required bool preserveRoom,
  }) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return;
    }

    final roomRef = _db.child('rooms/$roomId');
    final playerRef = roomRef.child('players/$roleId');
    await playerRef.onDisconnect().cancel();
    await roomRef.onDisconnect().cancel();
    if (preserveRoom) {
      await playerRef.onDisconnect().update({
        'status': 'left',
        'disconnectedAt': ServerValue.timestamp,
      });
    } else {
      if (roleId == 'host') {
        await roomRef.onDisconnect().remove();
      } else {
        await playerRef.onDisconnect().remove();
        await roomRef.onDisconnect().update({'status': 'waiting'});
      }
    }
    _presencePreserveMode = preserveRoom;
  }

  bool get _shouldPreserveRoomOnDisconnect {
    final room = currentRoom;
    return isRankedMode ||
        (room?.isRanked ?? false) ||
        (room?.hasGuest ?? false) ||
        room?.status == 'playing' ||
        room?.status == 'game_over';
  }

  Future<void> _startRematch(String roomId) async {
    try {
      final newSeed = DateTime.now().microsecondsSinceEpoch;
      await _db.child('rooms/$roomId').update({
        'seed': newSeed,
        'status': 'playing',
        'players/host/status': 'playing',
        'players/guest/status': 'playing',
        'players/host/board': null,
        'players/guest/board': null,
        'players/host/activePiece': null,
        'players/guest/activePiece': null,
        'players/host/attacks': null,
        'players/guest/attacks': null,
        'players/host/ojamaSpawns': null,
        'players/guest/ojamaSpawns': null,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('再戦開始', error));
    } finally {
      _isLaunchingRematch = false;
    }
  }

  List<dynamic> _dynamicList(Object? data) {
    if (data is List) {
      return data;
    }
    if (data is Map<dynamic, dynamic>) {
      final entries = data.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return entries.map((entry) => entry.value).toList();
    }
    return const [];
  }

  Map<String, dynamic> _ojamaTaskToMap(OjamaTask task) {
    return {
      'type': task.type.name,
      if (task.startColor != null) 'startColor': task.startColor!.index,
      if (task.presetColors != null)
        'presetColors': task.presetColors!.map((color) => color.index).toList(),
      if (task.ballSkinId != 'default') 'ballSkinId': task.ballSkinId,
      if (task.effectSkinId != task.ballSkinId)
        'effectSkinId': task.effectSkinId,
    };
  }

  OjamaTask? _ojamaTaskFromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }

    final data = Map<String, dynamic>.from(raw);
    final typeName = data['type']?.toString();
    if (typeName == null || typeName.isEmpty) {
      return null;
    }

    OjamaType? type;
    for (final candidate in OjamaType.values) {
      if (candidate.name == typeName) {
        type = candidate;
        break;
      }
    }
    if (type == null) {
      return null;
    }

    final startColorIndex = _intValue(data['startColor']);
    final rawPresetColors = data['presetColors'];
    final presetColors = rawPresetColors is List
        ? rawPresetColors
            .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
            .whereType<int>()
            .where((index) => index >= 0 && index < BallColor.values.length)
            .map((index) => BallColor.values[index])
            .toList()
        : null;

    return OjamaTask(
      type,
      startColor: startColorIndex != null &&
              startColorIndex >= 0 &&
              startColorIndex < BallColor.values.length
          ? BallColor.values[startColorIndex]
          : null,
      presetColors: presetColors,
      ballSkinId: data['ballSkinId']?.toString() ?? 'default',
      effectSkinId: data['effectSkinId']?.toString(),
    );
  }
}
