import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../game/game_models.dart';

typedef RoomUpdateCallback = void Function(MultiplayerRoom room);
typedef OpponentBoardUpdateCallback = void Function(Map<String, dynamic> board);
typedef OpponentPieceUpdateCallback = void Function(Map<String, dynamic> piece);
typedef AttackReceivedCallback = void Function(OjamaTask task);
typedef OpponentOjamaSpawnedCallback = void Function(
  List<dynamic> ojamaData,
  int dropSeed,
);
typedef OpponentGameOverCallback = void Function();
typedef OpponentDisconnectedCallback = void Function();
typedef RematchStartedCallback = void Function(int newSeed);

class MultiplayerPlayer {
  const MultiplayerPlayer({
    required this.status,
    this.name = 'Player',
    this.uid,
    this.rating,
  });

  final String status;
  final String name;
  final String? uid;
  final int? rating;

  factory MultiplayerPlayer.fromMap(Map<dynamic, dynamic>? data) {
    return MultiplayerPlayer(
      status: (data?['status'] as String?) ?? 'waiting',
      name: _normalizePlayerName(data?['name'] as String?),
      uid: data?['uid'] as String?,
      rating: _intValue(data?['rating']),
    );
  }

  static String _normalizePlayerName(String? value) {
    final name = value?.trim() ?? '';
    return name.isEmpty ? 'Player' : name;
  }

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
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
      isRanked: map['mode'] == 'ranked' || map['ranked'] == true,
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
  static const String _userIdPrefsKey = 'multiplayer_user_id';

  final Random _random = Random();
  bool _didResetRatingForThisRun = false;

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
  OpponentGameOverCallback? onOpponentGameOver;
  OpponentDisconnectedCallback? onOpponentDisconnected;
  RematchStartedCallback? onRematchStarted;

  String? _lastRoomStatus;
  bool _hadOpponentPresent = false;
  bool _isLaunchingRematch = false;
  bool _isMatchFound = false;
  bool _isMatchmakingAttemptInProgress = false;
  bool _opponentDisconnectNotified = false;
  DateTime? _matchmakingStartedAt;

  bool get isHost => myRoleId == 'host';
  bool get isGuest => myRoleId == 'guest';
  String get opponentRoleId => myRoleId == 'host' ? 'guest' : 'host';
  String get displayPlayerName =>
      playerName.trim().isEmpty ? 'Player' : playerName.trim();

  void setPlayerName(String name) {
    final nextName = name.trim();
    playerName = nextName.isEmpty ? 'Player' : nextName;
  }

  DatabaseReference get _db {
    final app = Firebase.app();
    final database = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
    );
    return database.ref();
  }

  Future<int> initializeUser({String? name}) async {
    if (name != null) {
      setPlayerName(name);
    }

    final uid = await _loadOrCreateUid();
    myUid = uid;

    try {
      final userRef = _db.child('users/$uid');
      final snapshot = await userRef.get();
      final userData = snapshot.value is Map ? snapshot.value as Map : null;
      final shouldResetRating = !_didResetRatingForThisRun;
      final syncedRating = shouldResetRating
          ? initialRating
          : _intValue(userData?['rating']) ?? initialRating;

      _didResetRatingForThisRun = true;
      currentRating = syncedRating;
      await userRef.update({
        'name': displayPlayerName,
        'rating': syncedRating,
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
      await _db.child('users/$uid').update({
        'name': displayPlayerName,
        'updatedAt': ServerValue.timestamp,
      });
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
  }) async {
    if (!isRankedMode) {
      return null;
    }

    final uid = myUid ?? await _loadOrCreateUid();
    myUid = uid;

    final oldRating = currentRating;
    final opponentRating =
        currentRoom?.players[opponentRoleId]?.rating ?? oldRating;
    final newRating = calculateNewRating(oldRating, opponentRating, isWin);
    final delta = newRating - oldRating;

    currentRating = newRating;

    try {
      await _db.child('users/$uid').update({
        'name': displayPlayerName,
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
          'timestamp': ServerValue.timestamp,
        });
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

  Future<String> createRoom() async {
    try {
      await leaveRoom();

      for (int attempt = 0; attempt < 10; attempt++) {
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
            'host': {
              'status': 'waiting',
              'name': displayPlayerName,
            },
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
            'host': MultiplayerPlayer(
              status: 'waiting',
              name: displayPlayerName,
            ),
          },
        );
        _lastRoomStatus = currentRoom!.status;
        _hadOpponentPresent = false;
        _opponentDisconnectNotified = false;
        await _setupPresence();
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

      final roomRef = _db.child('rooms/$roomId');
      final snapshot = await roomRef.get();
      if (!snapshot.exists) {
        return false;
      }

      final room = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
      if (room.status != 'waiting' || room.hasGuest) {
        return false;
      }

      final guestData = <String, Object?>{
        'status': 'waiting',
        'name': displayPlayerName,
      };
      if (room.isRanked) {
        guestData['uid'] = myUid;
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
          'guest': MultiplayerPlayer(
            status: 'waiting',
            name: displayPlayerName,
            uid: room.isRanked ? myUid : null,
            rating: room.isRanked ? currentRating : null,
          ),
        },
      );
      _lastRoomStatus = currentRoom!.status;
      _hadOpponentPresent = currentRoom!.players.containsKey(opponentRoleId);
      _opponentDisconnectNotified = false;
      await _setupPresence();
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
        const Duration(seconds: 1),
        (_) => unawaited(_tryRandomMatch(myRating)),
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
        throw StateError('ランダムマッチの部屋に参加できませんでした。');
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
        return a.timestamp.compareTo(b.timestamp);
      });

      for (final candidate in candidates) {
        if (_isMatchFound || completer.isCompleted) {
          return;
        }

        if (!_shouldHostRandomMatch(uid, candidate.uid)) {
          continue;
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
        StateError(_firebaseErrorMessage('ランダムマッチ検索', error)),
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
      'roomId': null,
      'role': null,
      'name': displayPlayerName,
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
        'name': displayPlayerName,
        'timestamp': ServerValue.timestamp,
      });
    } on FirebaseException {
      // 次のポーリングでもう一度更新する。検索自体は既存の待機情報で続ける。
    }
  }

  bool _shouldHostRandomMatch(String uid, String opponentUid) {
    return uid.compareTo(opponentUid) > 0;
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
    final result = await _db
        .child('matchmaking/$opponentUid')
        .runTransaction((currentValue) {
      if (currentValue is! Map ||
          _matchmakingStatus(currentValue) != 'waiting' ||
          _nonEmptyString(currentValue['roomId']) != null ||
          !_isFreshMatchmakingEntry(currentValue)) {
        return Transaction.abort();
      }

      final opponentRating = _intValue(currentValue['rating']);
      if (opponentRating == null || (opponentRating - myRating).abs() > range) {
        return Transaction.abort();
      }

      final nextValue = Map<Object?, Object?>.from(currentValue)
        ..['status'] = 'assigned'
        ..['role'] = 'guest'
        ..['roomId'] = roomId
        ..['hostUid'] = uid
        ..['assignedAt'] = now
        ..['timestamp'] = now;
      return Transaction.success(nextValue);
    });
    return result.committed;
  }

  Future<void> _markOwnMatchAsHost(
    String uid,
    String roomId,
    String opponentUid,
  ) async {
    await _db.child('matchmaking/$uid').update({
      'status': 'assigned',
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
      'roomId': null,
      'role': null,
      'name': displayPlayerName,
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
        'host': {
          'status': 'waiting',
          'name': displayPlayerName,
          'uid': uid,
          'rating': myRating,
        },
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
        'host': MultiplayerPlayer(
          status: 'waiting',
          name: displayPlayerName,
          uid: uid,
          rating: myRating,
        ),
      },
    );
    _lastRoomStatus = currentRoom!.status;
    _hadOpponentPresent = false;
    _opponentDisconnectNotified = false;
    await _setupPresence();
    _listenRoom();
    _listenGameplayChannels();
  }

  Future<bool> _waitForRankedGuest(String roomId) async {
    for (var attempt = 0; attempt < 40; attempt++) {
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
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _roomSubscription = null;
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
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
  }

  Future<void> _clearGuestInvite(String opponentUid, String roomId) async {
    final uid = myUid;
    if (uid == null) {
      return;
    }

    try {
      await _db.child('matchmaking/$opponentUid').runTransaction((
        currentValue,
      ) {
        if (currentValue is! Map) {
          return Transaction.abort();
        }

        if (currentValue['roomId'] != roomId ||
            currentValue['hostUid'] != uid) {
          return Transaction.abort();
        }

        final nextValue = Map<Object?, Object?>.from(currentValue)
          ..['status'] = 'waiting'
          ..remove('roomId')
          ..remove('role')
          ..remove('hostUid')
          ..remove('assignedAt');
        return Transaction.success(nextValue);
      });
    } on FirebaseException {
      // 招待情報は待機エントリの鮮度チェックで自然に無視されるため、失敗しても続行する。
    }
  }

  int _currentMatchmakingRange() {
    final startedAt = _matchmakingStartedAt;
    if (startedAt == null) {
      return 100;
    }
    final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
    return 100 + ((elapsedSeconds ~/ 5) * 100);
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
    try {
      if (uid != null) {
        final entryRef = _db.child('matchmaking/$uid');
        await entryRef.onDisconnect().cancel();
        await entryRef.remove();
      }
    } on FirebaseException {
      // クリーンアップ失敗は次回起動時の再登録で上書きする。
    }

    _matchmakingStartedAt = null;
    _matchmakingCompleter = null;
    _isMatchmakingAttemptInProgress = false;
  }

  Future<void> restoreSession({
    required String roomId,
    required String roleId,
  }) async {
    final snapshot = await _db.child('rooms/$roomId').get();
    if (!snapshot.exists) {
      throw StateError('ルームが見つかりません。');
    }

    currentRoomId = roomId;
    myRoleId = roleId;
    await _db.child('rooms/$roomId/players/$roleId').update({
      'name': displayPlayerName,
    });
    currentRoom = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
    isRankedMode = currentRoom?.isRanked ?? false;
    _lastRoomStatus = currentRoom!.status;
    _hadOpponentPresent = currentRoom!.players.containsKey(opponentRoleId);
    _opponentDisconnectNotified = false;
    await _setupPresence();
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

  Future<void> cancelLobby() => leaveRoom();

  Future<void> leaveRoom() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;

    _roomSubscription?.cancel();
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _roomSubscription = null;
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
    _opponentOjamaSpawnSubscription = null;
    _opponentStatusSubscription = null;

    try {
      if (roomId != null && roleId != null) {
        final roomRef = _db.child('rooms/$roomId');
        await roomRef.child('players/$roleId').onDisconnect().cancel();

        if (roleId == 'host') {
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
    onRoomUpdated = null;
    onOpponentBoardUpdated = null;
    onOpponentPieceUpdated = null;
    onAttackReceived = null;
    onOpponentOjamaSpawned = null;
    onOpponentGameOver = null;
    onOpponentDisconnected = null;
    onRematchStarted = null;
  }

  String _firebaseErrorMessage(String action, FirebaseException error) {
    final parts = <String>['$actionに失敗しました。'];
    if (error.code.isNotEmpty) {
      parts.add('code: ${error.code}');
    }
    if (error.message != null && error.message!.isNotEmpty) {
      parts.add(error.message!);
    }
    return parts.join('\n');
  }

  Map<String, dynamic> _stringDynamicMap(Map<dynamic, dynamic> data) {
    return {
      for (final entry in data.entries) entry.key.toString(): entry.value,
    };
  }

  Future<String> _loadOrCreateUid() async {
    if (myUid != null) {
      return myUid!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUid = prefs.getString(_userIdPrefsKey);
      if (savedUid != null && savedUid.isNotEmpty) {
        return savedUid;
      }

      final newUid = _generateUuidV4();
      final saved = await prefs.setString(_userIdPrefsKey, newUid);
      if (!saved) {
        return newUid;
      }
      final verifiedUid = prefs.getString(_userIdPrefsKey);
      if (verifiedUid == null || verifiedUid.isEmpty) {
        await prefs.reload();
        return prefs.getString(_userIdPrefsKey) ?? newUid;
      }
      return newUid;
    } on MissingPluginException {
      return _generateUuidV4();
    } catch (_) {
      final fallbackUid = _generateUuidV4();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userIdPrefsKey, fallbackUid);
      } catch (_) {
        // 開発中のmacOSビルドなどで永続化できない場合も、現在セッションは継続する。
      }
      return fallbackUid;
    }
  }

  String _generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String byteHex(int index) => bytes[index].toRadixString(16).padLeft(2, '0');
    return '${byteHex(0)}${byteHex(1)}${byteHex(2)}${byteHex(3)}-'
        '${byteHex(4)}${byteHex(5)}-'
        '${byteHex(6)}${byteHex(7)}-'
        '${byteHex(8)}${byteHex(9)}-'
        '${byteHex(10)}${byteHex(11)}${byteHex(12)}${byteHex(13)}'
        '${byteHex(14)}${byteHex(15)}';
  }

  int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  Future<void> _setupPresence() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      return;
    }

    final isRanked = isRankedMode || (currentRoom?.isRanked ?? false);
    final playerRef = _db.child('rooms/$roomId/players/$roleId');
    if (isRanked) {
      await playerRef.onDisconnect().update({
        'status': 'left',
        'disconnectedAt': ServerValue.timestamp,
      });
    } else {
      await playerRef.onDisconnect().remove();
    }
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
}
