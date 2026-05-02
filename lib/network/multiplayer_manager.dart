import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../data/player_data_manager.dart';
import '../game/game_models.dart';
import '../moderation/moderation_manager.dart';

typedef RoomUpdateCallback = void Function(MultiplayerRoom room);
typedef OpponentBoardUpdateCallback = void Function(Map<String, dynamic> board);
typedef OpponentPieceUpdateCallback = void Function(Map<String, dynamic> piece);
typedef AttackReceivedCallback = void Function(OjamaTask task);
typedef OpponentOjamaSpawnedCallback = void Function(
  List<dynamic> ojamaData,
  int dropSeed,
);
typedef OpponentStampReceivedCallback = void Function(String stampId);
typedef OpponentGameOverCallback = void Function();
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
    this.rating,
    this.badgeIds = const [],
    this.playerIconId = 'default',
  });

  final String status;
  final String name;
  final String? uid;
  final int? rating;
  final List<String> badgeIds;
  final String playerIconId;

  factory MultiplayerPlayer.fromMap(Map<dynamic, dynamic>? data) {
    return MultiplayerPlayer(
      status: (data?['status'] as String?) ?? 'waiting',
      name: _normalizePlayerName(data?['name'] as String?),
      uid: data?['uid'] as String?,
      rating: _intValue(data?['rating']),
      badgeIds: _stringList(data?['badgeIds']),
      playerIconId:
          ((data?['playerIconId']?.toString() ?? '').trim()).isNotEmpty
              ? data!['playerIconId'].toString().trim()
              : 'default',
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
}

class MultiplayerRoom {
  const MultiplayerRoom({
    required this.roomId,
    required this.status,
    required this.seed,
    required this.players,
    this.isRanked = false,
  });

  final String roomId;
  final String status;
  final int seed;
  final Map<String, MultiplayerPlayer> players;
  final bool isRanked;

  bool get hasHost => players.containsKey('host');
  bool get hasGuest => players.containsKey('guest');
  bool get bothPlayersJoined => hasHost && hasGuest;
  bool get bothPlayersReady =>
      players['host']?.status == 'ready' && players['guest']?.status == 'ready';
  bool get bothPlayersRematchReady =>
      players['host']?.status == 'rematch_ready' &&
      players['guest']?.status == 'rematch_ready';
  String? statusFor(String roleId) => players[roleId]?.status;

  factory MultiplayerRoom.fromSnapshot(String roomId, Object? value) {
    final map = value is Map<dynamic, dynamic> ? value : <dynamic, dynamic>{};
    final playersRaw = map['players'] as Map<dynamic, dynamic>? ?? {};

    return MultiplayerRoom(
      roomId: roomId,
      status: (map['status'] as String?) ?? 'waiting',
      seed: (map['seed'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      isRanked: map['mode'] == 'ranked' ||
          map['mode'] == 'arena' ||
          map['ranked'] == true,
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
  });

  final SavedOnlineSession session;
  final bool isResolved;
  final bool? isWin;
  final int? oldRating;
  final int? newRating;
  final int? ratingDelta;
  final String? opponentName;
  final bool wasAbandoned;
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

class MultiplayerManager {
  MultiplayerManager._internal();

  static final MultiplayerManager _instance = MultiplayerManager._internal();

  factory MultiplayerManager() => _instance;

  static MultiplayerManager get instance => _instance;

  static const int initialRating = 1000;
  static const String _savedSessionPrefsKey = 'multiplayer_saved_session_v2';
  static const List<String> _legacySavedSessionPrefsKeys = [
    'multiplayer_saved_session_v1',
  ];

  final Random _random = Random();

  String? currentRoomId;
  String? myRoleId;
  String? myUid;
  MultiplayerRoom? currentRoom;
  String playerName = 'Player';
  int currentRating = initialRating;
  bool isRankedMode = false;

  StreamSubscription<DatabaseEvent>? _roomSubscription;
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
  bool _hadOpponentPresent = false;
  bool _isLaunchingRematch = false;
  bool _isMatchFound = false;
  bool _isMatchmakingAttemptInProgress = false;
  bool _opponentDisconnectNotified = false;
  bool? _presencePreserveMode;
  DateTime? _matchmakingStartedAt;
  String? _activeMatchmakingPath;

  bool get isHost => myRoleId == 'host';
  bool get isGuest => myRoleId == 'guest';
  String get opponentRoleId => myRoleId == 'host' ? 'guest' : 'host';
  String get displayPlayerName =>
      playerName.trim().isEmpty ? 'Player' : playerName.trim();

  void setPlayerName(String name) {
    final nextName = ModerationManager.instance.sanitizePlayerName(name);
    playerName = nextName.isEmpty ? 'Player' : nextName;
  }

  DatabaseReference get _db {
    final app = Firebase.app();
    final database = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: app.options.databaseURL,
    );
    return database.ref();
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

  Future<Map<String, Object?>> _buildPlayerPayload({
    required String status,
    int? rating,
  }) async {
    final badgeIds = await _currentEquippedBadgeIds();
    final playerIconId = await _currentEquippedPlayerIconId();
    return {
      'status': status,
      'name': displayPlayerName,
      'uid': myUid,
      if (rating != null) 'rating': rating,
      'badgeIds': badgeIds,
      'playerIconId': playerIconId,
    };
  }

  Future<int> initializeUser({String? name}) async {
    if (name != null) {
      setPlayerName(name);
    }

    final uid = await _loadAuthenticatedUid();
    myUid = uid;

    try {
      final userRef = _db.child('users/$uid');
      final snapshot = await userRef.get();
      final userData = snapshot.value is Map ? snapshot.value as Map : null;
      final syncedRating = _intValue(userData?['rating']) ?? currentRating;
      currentRating = syncedRating;
      final badgeIds = await _currentEquippedBadgeIds();
      final playerIconId = await _currentEquippedPlayerIconId();
      await userRef.update({
        'name': displayPlayerName,
        'rating': syncedRating,
        'badgeIds': badgeIds,
        'playerIconId': playerIconId,
        'updatedAt': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ユーザー情報の同期', error));
    }

    return currentRating;
  }

  Future<void> updateUserName(String name) async {
    setPlayerName(name);
    final uid = myUid;
    if (uid == null) {
      return;
    }

    try {
      final badgeIds = await _currentEquippedBadgeIds();
      final playerIconId = await _currentEquippedPlayerIconId();
      await _db.child('users/$uid').update({
        'name': displayPlayerName,
        'badgeIds': badgeIds,
        'playerIconId': playerIconId,
        'updatedAt': ServerValue.timestamp,
      });
      final roomId = currentRoomId;
      final roleId = myRoleId;
      if (roomId != null && roleId != null) {
        await _db.child('rooms/$roomId/players/$roleId').update({
          'name': displayPlayerName,
          'badgeIds': badgeIds,
          'playerIconId': playerIconId,
          'updatedAt': ServerValue.timestamp,
        });
      }
    } on FirebaseException {
      // 名前のオンライン同期失敗はローカル保存と画面操作を止めない。
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
  }) async {
    if (!isRankedMode) {
      return null;
    }

    final uid = myUid ?? await _loadAuthenticatedUid();
    myUid = uid;

    final oldRating = currentRating;
    final opponentRating =
        currentRoom?.players[opponentRoleId]?.rating ?? oldRating;
    final newRating = calculateNewRating(oldRating, opponentRating, isWin);
    final delta = newRating - oldRating;

    currentRating = newRating;

    try {
      final badgeIds = await _currentEquippedBadgeIds();
      final playerIconId = await _currentEquippedPlayerIconId();
      await _db.child('users/$uid').update({
        'name': displayPlayerName,
        'rating': newRating,
        'badgeIds': badgeIds,
        'playerIconId': playerIconId,
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
          'timestamp': ServerValue.timestamp,
        });

        if (applyOpponentResult) {
          await _applyOpponentRankedResult(
            roomId: roomId,
            myOldRating: oldRating,
            opponentWon: !isWin,
          );
        }
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

  Future<void> _applyOpponentRankedResult({
    required String roomId,
    required int myOldRating,
    required bool opponentWon,
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

    final opponentNewRating = calculateNewRating(
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
      'resolvedBy': myUid,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<String> createRoom() async {
    try {
      await leaveRoom();
      await initializeUser();

      for (int attempt = 0; attempt < 10; attempt++) {
        final hostData = await _buildPlayerPayload(status: 'waiting');
        final roomId = (_random.nextInt(9000) + 1000).toString();
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
      return true;
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ルーム参加', error));
    }
  }

  Future<String?> startRandomMatch(int myRating) async {
    await cancelMatchmaking();
    await initializeUser();
    await leaveRoom();

    final uid = myUid;
    if (uid == null) {
      throw StateError('ユーザーIDの初期化に失敗しました。');
    }

    currentRating = myRating;
    _isMatchFound = false;
    _isMatchmakingAttemptInProgress = false;
    _matchmakingStartedAt = DateTime.now();
    _activeMatchmakingPath = 'matchmaking';
    final completer = Completer<String?>();
    _matchmakingCompleter = completer;

    final entryRef = _db.child('matchmaking/$uid');

    try {
      await entryRef.onDisconnect().remove();
      await _writeWaitingMatchmakingEntry(uid, myRating);

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
        const Duration(seconds: 2),
        (_) => unawaited(_tryRandomMatch(myRating)),
      );

      return await completer.future;
    } finally {
      await _cleanupMatchmaking();
    }
  }

  Future<String?> startArenaMatch(int currentWins) async {
    await cancelMatchmaking();
    await initializeUser();
    await leaveRoom();

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
      await _cleanupMatchmaking();
    }
  }

  Future<void> cancelMatchmaking() async {
    _isMatchFound = true;
    _isMatchmakingAttemptInProgress = false;
    final completer = _matchmakingCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    await _cleanupMatchmaking();
  }

  Future<void> cancelArenaMatchmaking() => cancelMatchmaking();

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

      final snapshot = await _db.child('matchmaking').get();
      final rawPlayers = snapshot.value;
      if (rawPlayers is! Map) {
        return;
      }

      final range = _currentMatchmakingRange();
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

        final rating = _intValue(data['rating']);
        if (rating == null || (rating - myRating).abs() > range) {
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
    final playerIconId = await _currentEquippedPlayerIconId();
    await _db.child('matchmaking/$uid').set({
      'status': 'waiting',
      'rating': myRating,
      'roomId': null,
      'role': null,
      'name': displayPlayerName,
      'playerIconId': playerIconId,
      'joinedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _writeWaitingArenaMatchmakingEntry(
    String uid,
    int currentWins,
  ) async {
    final playerIconId = await _currentEquippedPlayerIconId();
    await _db.child('arena_matchmaking/$uid').set({
      'status': 'waiting',
      'wins': currentWins,
      'roomId': null,
      'role': null,
      'name': displayPlayerName,
      'playerIconId': playerIconId,
      'joinedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _refreshWaitingMatchmakingEntry(
    String uid,
    int myRating,
  ) async {
    try {
      final playerIconId = await _currentEquippedPlayerIconId();
      await _db.child('matchmaking/$uid').update({
        'rating': myRating,
        'name': displayPlayerName,
        'playerIconId': playerIconId,
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
      await _db.child('arena_matchmaking/$uid').update({
        'wins': currentWins,
        'name': displayPlayerName,
        'playerIconId': playerIconId,
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
      if (opponentRating == null || (opponentRating - myRating).abs() > range) {
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

    final playerIconId = await _currentEquippedPlayerIconId();
    await _db.child('matchmaking/$uid').set({
      'status': 'waiting',
      'rating': myRating,
      'roomId': null,
      'role': null,
      'name': displayPlayerName,
      'playerIconId': playerIconId,
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
    await _db.child('arena_matchmaking/$uid').set({
      'status': 'waiting',
      'wins': currentWins,
      'roomId': null,
      'role': null,
      'name': displayPlayerName,
      'playerIconId': playerIconId,
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
    final roomRef = _db.child('rooms/$roomId');
    await roomRef.set({
      'mode': 'ranked',
      'ranked': true,
      'status': 'waiting',
      'seed': seed,
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
      final roomId = (_random.nextInt(9000) + 1000).toString();
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
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _stampSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _roomSubscription = null;
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
    _lastRoomStatus = null;
    _hadOpponentPresent = false;
    _isLaunchingRematch = false;
    _opponentDisconnectNotified = false;
    _presencePreserveMode = null;
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
      return 100;
    }
    final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
    if (elapsedSeconds >= 10) {
      return 1 << 30;
    }
    return 100 + (elapsedSeconds * 100);
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

  Future<void> saveBattleSnapshot(Map<String, dynamic> snapshot) async {
    final existing = await loadSavedSession();
    if (existing == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final updated = SavedOnlineSession(
      roomId: existing.roomId,
      roleId: existing.roleId,
      isRankedMode: existing.isRankedMode,
      isArenaMode: existing.isArenaMode,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      snapshot: snapshot,
    );
    await prefs.setString(_savedSessionPrefsKey, jsonEncode(updated.toJson()));
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

  Future<SavedSessionResolution?> inspectSavedSession() async {
    final session = await loadSavedSession();
    if (session == null) {
      return null;
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
      final abandonedByMe = startedMatch && myStatus == 'left';
      final explicitIsWin =
          resultData == null ? mirroredIsWin : resultData['isWin'] == true;
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
      );
    } catch (_) {
      return SavedSessionResolution(session: session, isResolved: true);
    }
  }

  Future<Map<dynamic, dynamic>?> _ensureRankedResultRecorded({
    required MultiplayerRoom room,
    required String myRoleId,
    required bool isWin,
    Map<dynamic, dynamic>? existingOpponentResult,
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
    final myNewRating = calculateNewRating(
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
      'resolvedBy': myUidValue,
      'timestamp': ServerValue.timestamp,
    };

    await _db.child('users/$myUidValue').update({
      'rating': myNewRating,
      'updatedAt': ServerValue.timestamp,
    });
    await _db.child('rooms/$roomId/results/$myRoleId').set(myResult);

    if (existingOpponentResult == null &&
        opponentPlayer?.uid != null &&
        opponentPlayer?.rating != null) {
      final opponentUidValue = opponentPlayer!.uid!;
      final opponentNewRating = calculateNewRating(
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
        'resolvedBy': myUidValue,
        'timestamp': ServerValue.timestamp,
      });
    }

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
      'badgeIds': await _currentEquippedBadgeIds(),
      'playerIconId': await _currentEquippedPlayerIconId(),
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

      if (refreshedRoom.bothPlayersReady) {
        await _db.child('rooms/$roomId').update({'status': 'playing'});
      }
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('READY送信', error));
    }
  }

  Future<void> sendBoardState(Map<String, dynamic> boardData) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId/board').set(boardData);
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('盤面送信', error));
    }
  }

  Future<void> sendBattleSnapshot(Map<String, dynamic> snapshot) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    final payload = Map<String, dynamic>.from(snapshot)
      ..['savedAt'] = ServerValue.timestamp;

    try {
      await _db.child('rooms/$roomId/players/$roleId/snapshot').set(payload);
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('対戦状態の保存', error));
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
    List<int> nextColors,
  ) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId/activePiece').set({
        'action': action,
        'x': x,
        'y': y,
        'rotation': rotation,
        'colors': colors.map((color) => color.index).toList(),
        'dropSeed': dropSeed,
        'nextColors': nextColors,
        'timestamp': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ピース同期送信', error));
    }
  }

  Future<void> sendAttack(OjamaTask task) async {
    final roomId = currentRoomId;
    if (roomId == null || myRoleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db
          .child('rooms/$roomId/players/$opponentRoleId/attacks')
          .push()
          .set({
        'type': task.type.name,
        'startColor': task.startColor?.index,
        'presetColors': task.presetColors?.map((color) => color.index).toList(),
        'timestamp': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('攻撃送信', error));
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

  Future<void> sendStamp(String stampId) async {
    final roomId = currentRoomId;
    if (roomId == null || myRoleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db
          .child('rooms/$roomId/players/$opponentRoleId/stamps')
          .push()
          .set({
        'id': stampId,
        'timestamp': ServerValue.timestamp,
      });
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

    try {
      await _db.child('rooms/$roomId/players/$roleId/ojamaSpawns').push().set({
        'items': ojamaData,
        'dropSeed': dropSeed,
        'timestamp': ServerValue.timestamp,
      });
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('おじゃま同期送信', error));
    }
  }

  Future<void> declareGameOver() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId').update({
        'status': 'dead',
      });
      await _db.child('rooms/$roomId').update({'status': 'game_over'});
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('ゲーム終了送信', error));
    }
  }

  Future<void> forceOpponentGameOver() async {
    final roomId = currentRoomId;
    final opponentRole = myRoleId == 'host' ? 'guest' : 'host';
    if (roomId == null || myRoleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db.child('rooms/$roomId/players/$opponentRole').update({
        'status': 'dead',
        'resolvedBy': myUid,
        'resolvedAt': ServerValue.timestamp,
      });
      await _db.child('rooms/$roomId').update({'status': 'game_over'});
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('相手側ゲーム終了確定', error));
    }
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
    } on FirebaseException catch (error) {
      throw StateError(_firebaseErrorMessage('再戦準備', error));
    }
  }

  void _listenRoom() {
    _roomSubscription?.cancel();

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
      onRoomUpdated?.call(room);
    });
  }

  void _listenGameplayChannels() {
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();

    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return;
    }

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

    _attackSubscription = _db
        .child('rooms/$roomId/players/$roleId/attacks')
        .onChildAdded
        .listen((event) async {
      final value = event.snapshot.value;
      OjamaTask? task;
      if (value is Map<dynamic, dynamic>) {
        final typeName = value['type'] as String?;
        OjamaType? type;
        for (final candidate in OjamaType.values) {
          if (candidate.name == typeName) {
            type = candidate;
            break;
          }
        }
        if (type != null) {
          final startColorIndex = (value['startColor'] as num?)?.toInt();
          final rawPresetColors = value['presetColors'];
          final presetColors = rawPresetColors is List
              ? rawPresetColors
                  .map((item) =>
                      item is num ? item.toInt() : int.tryParse('$item'))
                  .whereType<int>()
                  .where(
                      (index) => index >= 0 && index < BallColor.values.length)
                  .map((index) => BallColor.values[index])
                  .toList()
              : null;
          task = OjamaTask(
            type,
            startColor: startColorIndex != null &&
                    startColorIndex >= 0 &&
                    startColorIndex < BallColor.values.length
                ? BallColor.values[startColorIndex]
                : null,
            presetColors: presetColors,
          );
        }
      }

      if (task != null) {
        onAttackReceived?.call(task);
      }

      if (event.snapshot.key != null) {
        await event.snapshot.ref.remove();
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
          onOpponentStampReceived?.call(stampId);
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

    _opponentStatusSubscription = _db
        .child('rooms/$roomId/players/$opponentRoleId/status')
        .onValue
        .listen((event) {
      final status = event.snapshot.value as String?;
      if (status == 'dead') {
        onOpponentGameOver?.call();
      } else if (status == 'left') {
        _notifyOpponentDisconnected();
      }
    });
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
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _stampSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _roomSubscription = null;
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
    _stampSubscription = null;
    _opponentOjamaSpawnSubscription = null;
    _opponentStatusSubscription = null;
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
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _stampSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _roomSubscription = null;
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
    _stampSubscription = null;
    _opponentOjamaSpawnSubscription = null;
    _opponentStatusSubscription = null;

    try {
      if (roomId != null && roleId != null) {
        final roomRef = _db.child('rooms/$roomId');
        await roomRef.child('players/$roleId').onDisconnect().cancel();
        await roomRef.onDisconnect().cancel();

        if (preserveRoom) {
          await roomRef.child('players/$roleId').update({
            'status': 'left',
            'disconnectedAt': ServerValue.timestamp,
          });
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
    final parts = <String>['$actionに失敗しました。'];
    if (error.code.isNotEmpty) {
      parts.add('code: ${error.code}');
    }
    if (error.message != null && error.message!.isNotEmpty) {
      parts.add(error.message!);
    }
    if (error.code == 'permission-denied') {
      final projectId = Firebase.app().options.projectId;
      parts.add(
        '接続先Firebaseプロジェクト: $projectId\n'
        'Realtime Database Rules が対象プロジェクトへデプロイ済みか、'
        'App Check を有効にしている場合は現在のビルドを許可しているか確認してください。',
      );
    }
    return parts.join('\n');
  }

  Map<String, dynamic> _stringDynamicMap(Map<dynamic, dynamic> data) {
    return {
      for (final entry in data.entries) entry.key.toString(): entry.value,
    };
  }

  Future<String> _loadAuthenticatedUid() async {
    if (myUid != null) {
      return myUid!;
    }
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
        'players/host/status': 'waiting',
        'players/guest/status': 'waiting',
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
    );
  }
}
