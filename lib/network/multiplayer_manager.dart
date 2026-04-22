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

class RatingChange {
  const RatingChange({
    required this.oldRating,
    required this.newRating,
  });

  final int oldRating;
  final int newRating;

  int get delta => newRating - oldRating;
}

class RandomMatchResult {
  const RandomMatchResult({
    required this.roomId,
    required this.isHost,
  });

  final String roomId;
  final bool isHost;
}

class _MatchCandidate {
  const _MatchCandidate({
    required this.userId,
    required this.name,
    required this.rating,
  });

  final String userId;
  final String name;
  final int rating;
}

class MultiplayerPlayer {
  const MultiplayerPlayer({required this.status, this.name = 'Player'});

  final String status;
  final String name;

  factory MultiplayerPlayer.fromMap(Map<dynamic, dynamic>? data) {
    return MultiplayerPlayer(
      status: (data?['status'] as String?) ?? 'waiting',
      name: _normalizePlayerName(data?['name'] as String?),
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

  String? currentRoomId;
  String? myRoleId;
  String? myUid;
  MultiplayerRoom? currentRoom;
  String playerName = 'Player';

  StreamSubscription<DatabaseEvent>? _roomSubscription;
  StreamSubscription<DatabaseEvent>? _opponentBoardSubscription;
  StreamSubscription<DatabaseEvent>? _opponentPieceSubscription;
  StreamSubscription<DatabaseEvent>? _attackSubscription;
  StreamSubscription<DatabaseEvent>? _opponentOjamaSpawnSubscription;
  StreamSubscription<DatabaseEvent>? _opponentStatusSubscription;
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

  bool get isHost => myRoleId == 'host';
  bool get isGuest => myRoleId == 'guest';
  String get opponentRoleId => myRoleId == 'host' ? 'guest' : 'host';
  String get displayPlayerName =>
      playerName.trim().isEmpty ? 'Player' : playerName.trim();

  void setPlayerName(String name) {
    final nextName = name.trim();
    playerName = nextName.isEmpty ? 'Player' : nextName;
  }

  Future<void> initializeUser({String? name}) async {
    if (name != null) {
      setPlayerName(name);
    }

    final id = await _loadOrCreateUserId();
    userId = id;

    final userRef = _db.child('users/$id');
    final snapshot = await userRef.get();
    if (snapshot.value is Map<dynamic, dynamic>) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      final remoteName = data['name'] as String?;
      playerRating = (data['rating'] as num?)?.toInt() ?? initialRating;
      if ((remoteName == null || remoteName.trim().isEmpty) ||
          data['rating'] == null ||
          remoteName != displayPlayerName) {
        await userRef.update({
          'name': displayPlayerName,
          'rating': playerRating,
        });
      }
      return;
    }

    playerRating = initialRating;
    await userRef.set({
      'name': displayPlayerName,
      'rating': playerRating,
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<void> syncUserName() async {
    final id = userId;
    if (id == null) {
      return;
    }
    await _db.child('users/$id/name').set(displayPlayerName);
  }

  Future<int> refreshMyRating() async {
    final id = userId ?? await _loadOrCreateUserId();
    userId = id;
    final snapshot = await _db.child('users/$id/rating').get();
    playerRating = (snapshot.value as num?)?.toInt() ?? initialRating;
    return playerRating;
  }

  int calculateNewRating(
    int myRating,
    int opponentRating,
    bool isWin,
  ) {
    final expected = 1 / (1 + pow(10, (opponentRating - myRating) / 400));
    var delta = (100 * ((isWin ? 1 : 0) - expected)).round();
    if (isWin) {
      delta = delta.clamp(5, 95).toInt();
    } else {
      delta = delta.clamp(-95, -5).toInt();
    }
    return myRating + delta;
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
      final syncedRating = _intValue(userData?['rating']) ?? initialRating;

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
      isRankedMode = false;

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
              'userId': userId,
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
              userId: userId,
            ),
          },
        );
        _lastRoomStatus = currentRoom!.status;
        _hadOpponentPresent = false;
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
      isRankedMode = false;

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
      });

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
          ),
        },
      );
      _lastRoomStatus = currentRoom!.status;
      _hadOpponentPresent = currentRoom!.players.containsKey(opponentRoleId);
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
    _matchmakingStartedAt = DateTime.now();
    final completer = Completer<String?>();
    _matchmakingCompleter = completer;

    final entryRef = _db.child('matchmaking/$uid');

    try {
      await entryRef.onDisconnect().remove();
      await entryRef.set({
        'rating': myRating,
        'roomId': null,
        'name': displayPlayerName,
        'timestamp': ServerValue.timestamp,
      });

      _matchmakingInviteSubscription = entryRef.child('roomId').onValue.listen(
        (event) {
          final invitedRoomId = event.snapshot.value;
          if (invitedRoomId is! String || invitedRoomId.isEmpty) {
            return;
          }
          unawaited(_acceptRandomMatchAsGuest(invitedRoomId, myRating));
        },
        onError: (Object error, StackTrace stackTrace) {
          _completeMatchmakingError(error, stackTrace);
        },
      );

      unawaited(_pollForRandomMatch(myRating));
      _matchmakingPollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_pollForRandomMatch(myRating)),
      );

      return await completer.future;
    } finally {
      await _cleanupMatchmaking();
    }
  }

  Future<void> cancelMatchmaking() async {
    _isMatchFound = true;
    final completer = _matchmakingCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    await _cleanupMatchmaking();
  }

  Future<void> _acceptRandomMatchAsGuest(
    String roomId,
    int myRating,
  ) async {
    if (_isMatchFound) {
      return;
    }
    _isMatchFound = true;
    _matchmakingPollTimer?.cancel();

    try {
      currentRating = myRating;
      final joined = await _joinRoomWhenReady(roomId);
      if (!joined) {
        throw StateError('ランダムマッチの部屋に参加できませんでした。');
      }
      _completeMatchmaking(roomId);
    } catch (error, stackTrace) {
      _completeMatchmakingError(error, stackTrace);
    }
  }

  Future<void> _pollForRandomMatch(int myRating) async {
    final uid = myUid;
    final completer = _matchmakingCompleter;
    if (uid == null ||
        completer == null ||
        completer.isCompleted ||
        _isMatchFound) {
      return;
    }

    try {
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

        if (!_isFreshMatchmakingEntry(data)) {
          continue;
        }

        final roomId = data['roomId'];
        if (roomId != null && '$roomId'.isNotEmpty) {
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
            timestamp: _intValue(data['timestamp']) ?? 0,
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

        // 同時に待機した2人が互いを取り合わないよう、UID順で
        // どちらがホストとして確保処理を行うかを一意に決める。
        if (!_shouldHostRandomMatch(uid, candidate.uid)) {
          continue;
        }

        final newRoomId = await _generateUniqueRoomId();
        final invited = await _inviteOpponent(candidate.uid, newRoomId);
        if (!invited) {
          continue;
        }

        if (_isMatchFound || completer.isCompleted) {
          return;
        }
        _isMatchFound = true;
        _matchmakingPollTimer?.cancel();

        await _createRankedRoom(
          roomId: newRoomId,
          myRating: myRating,
          opponentUid: candidate.uid,
        );
        _completeMatchmaking(newRoomId);
        return;
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
    await _setupPresence();
    _listenRoom();
    _listenGameplayChannels();
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

  Future<bool> _inviteOpponent(String opponentUid, String roomId) async {
    final uid = myUid;
    if (uid == null) {
      return false;
    }

    final inviteResult = await _db
        .child('matchmaking/$opponentUid')
        .runTransaction((currentValue) {
      if (currentValue is! Map) {
        return Transaction.abort();
      }

      final currentRoomId = currentValue['roomId'];
      if (currentRoomId != null && '$currentRoomId'.isNotEmpty) {
        return Transaction.abort();
      }

      final nextValue = Map<Object?, Object?>.from(currentValue)
        ..['roomId'] = roomId
        ..['claimedBy'] = uid
        ..['claimedAt'] = DateTime.now().millisecondsSinceEpoch;
      return Transaction.success(nextValue);
    });
    return inviteResult.committed;
  }

  int _currentMatchmakingRange() {
    final startedAt = _matchmakingStartedAt;
    if (startedAt == null) {
      return 100;
    }
    return DateTime.now().difference(startedAt).inSeconds >= 15 ? 300 : 100;
  }

  bool _isFreshMatchmakingEntry(Map data) {
    final timestamp = _intValue(data['timestamp']);
    if (timestamp == null) {
      return true;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return now - timestamp < 60000 && timestamp - now < 10000;
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
    final room = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
    isRankedMode = room.isRanked;
    await _db.child('rooms/$roomId/players/$roleId').update({
      'name': displayPlayerName,
      'userId': userId,
    });
    currentRoom = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
    _lastRoomStatus = currentRoom!.status;
    _hadOpponentPresent = currentRoom!.players.containsKey(opponentRoleId);
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
    if (isRankedMode) {
      throw StateError('ランクマッチでは再戦できません。');
    }

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

  Future<RandomMatchResult> startRandomMatch() async {
    try {
      await initializeUser();
      await cancelRandomMatch();
      isRankedMode = true;

      final id = userId;
      if (id == null) {
        throw StateError('ユーザーIDを生成できませんでした。');
      }

      final completer = Completer<RandomMatchResult>();
      _matchmakingStartedAt = DateTime.now();
      await _registerInMatchmaking();
      _listenForRandomMatchInvite(completer);

      _matchmakingPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_pollForRandomMatchOpponent(completer));
      });
      unawaited(_pollForRandomMatchOpponent(completer));

      return await completer.future;
    } on FirebaseException catch (error) {
      await cancelRandomMatch();
      throw StateError(_firebaseErrorMessage('ランダムマッチ', error));
    }
  }

  Future<void> cancelRandomMatch() async {
    _matchmakingPollTimer?.cancel();
    _matchmakingPollTimer = null;
    _matchmakingSubscription?.cancel();
    _matchmakingSubscription = null;
    _isMatchmakingPolling = false;
    _matchmakingStartedAt = null;
    final id = userId;
    if (id != null) {
      try {
        await _db.child('matchmaking/$id').onDisconnect().cancel();
        await _db.child('matchmaking/$id').remove();
      } on FirebaseException {
        // キャンセル失敗は画面遷移を止めない。
      }
    }
  }

  Future<RatingChange?> finalizeRankedMatch({
    required bool isWin,
  }) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (!isRankedMode || roomId == null || roleId == null) {
      return null;
    }

    final roomSnapshot = await _db.child('rooms/$roomId').get();
    if (!roomSnapshot.exists) {
      return null;
    }

    final room = MultiplayerRoom.fromSnapshot(roomId, roomSnapshot.value);
    currentRoom = room;
    final myPlayer = room.players[roleId];
    final opponentPlayer = room.players[opponentRoleId];
    if (myPlayer == null || opponentPlayer == null) {
      return null;
    }

    final myOldRating = myPlayer.rating ?? playerRating;
    final opponentOldRating = opponentPlayer.rating ?? initialRating;
    final myNewRating = calculateNewRating(
      myOldRating,
      opponentOldRating,
      isWin,
    );
    final opponentNewRating = calculateNewRating(
      opponentOldRating,
      myOldRating,
      !isWin,
    );
    final winnerRole = isWin ? roleId : opponentRoleId;

    final resultRef = _db.child('rooms/$roomId/rankedResult');
    final transactionResult = await resultRef.runTransaction((current) {
      if (current != null) {
        return Transaction.abort();
      }
      return Transaction.success({
        'winnerRole': winnerRole,
        'createdBy': roleId,
        'createdAt': ServerValue.timestamp,
        'ratings': {
          roleId: {
            'userId': myPlayer.userId,
            'old': myOldRating,
            'new': myNewRating,
            'delta': myNewRating - myOldRating,
          },
          opponentRoleId: {
            'userId': opponentPlayer.userId,
            'old': opponentOldRating,
            'new': opponentNewRating,
            'delta': opponentNewRating - opponentOldRating,
          },
        },
      });
    }, applyLocally: false);

    final resultData = transactionResult.committed
        ? transactionResult.snapshot.value
        : (await resultRef.get()).value;
    final change = _ratingChangeFromResult(resultData, roleId);

    if (transactionResult.committed) {
      await _applyRankedRatingsFromResult(resultData);
    }

    if (change != null) {
      playerRating = change.newRating;
    } else {
      await refreshMyRating();
    }
    return change;
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
          onOpponentDisconnected?.call();
        }
        currentRoom = null;
        _lastRoomStatus = null;
        _hadOpponentPresent = false;
        return;
      }

      final room = MultiplayerRoom.fromSnapshot(roomId, event.snapshot.value);
      final opponentPresent = room.players.containsKey(opponentRoleId);
      if (_hadOpponentPresent && !opponentPresent) {
        onOpponentDisconnected?.call();
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
      }
    });
  }

  void _listenForRandomMatchInvite(Completer<RandomMatchResult> completer) {
    final id = userId;
    if (id == null) {
      return;
    }

    _matchmakingSubscription?.cancel();
    _matchmakingSubscription =
        _db.child('matchmaking/$id/roomId').onValue.listen((event) async {
      final rawRoomId = event.snapshot.value;
      final roomId = rawRoomId == null ? null : '$rawRoomId';
      if (roomId == null || roomId.isEmpty || completer.isCompleted) {
        return;
      }

      _matchmakingPollTimer?.cancel();
      _matchmakingPollTimer = null;

      try {
        final result = await _joinRankedRoomAsGuest(roomId);
        await _cleanupMatchmakingEntry();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        await cancelRandomMatch();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
  }

  Future<void> _pollForRandomMatchOpponent(
    Completer<RandomMatchResult> completer,
  ) async {
    if (completer.isCompleted || _isMatchmakingPolling) {
      return;
    }

    final id = userId;
    if (id == null) {
      return;
    }

    _isMatchmakingPolling = true;
    try {
      final myEntrySnapshot = await _db.child('matchmaking/$id/roomId').get();
      if (myEntrySnapshot.value != null) {
        return;
      }

      final ratingRange = _currentRandomMatchRatingRange();
      final snapshot = await _db.child('matchmaking').get();
      final candidate = _findCandidateFromMatchmakingSnapshot(
        snapshot.value,
        ratingRange,
      );
      if (candidate == null || completer.isCompleted) {
        return;
      }

      _matchmakingPollTimer?.cancel();
      _matchmakingPollTimer = null;

      final result = await _inviteCandidateAsRankedHost(
        candidate,
        ratingRange,
      );
      if (result == null) {
        _restartRandomMatchPolling(completer);
        return;
      }

      await _cleanupMatchmakingEntry();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    } catch (error, stackTrace) {
      _restartRandomMatchPolling(completer);
      if (error is FirebaseException && !completer.isCompleted) {
        await cancelRandomMatch();
        completer.completeError(
          StateError(_firebaseErrorMessage('ランダムマッチ検索', error)),
          stackTrace,
        );
      }
    } finally {
      _isMatchmakingPolling = false;
    }
  }

  int _currentRandomMatchRatingRange() {
    final startedAt = _matchmakingStartedAt;
    if (startedAt == null) {
      return 100;
    }
    final elapsed = DateTime.now().difference(startedAt);
    return elapsed >= const Duration(seconds: 15) ? 300 : 100;
  }

  _MatchCandidate? _findCandidateFromMatchmakingSnapshot(
    Object? value,
    int ratingRange,
  ) {
    final id = userId;
    if (id == null) {
      return null;
    }

    if (value is! Map<dynamic, dynamic>) {
      return null;
    }

    final candidates = <_MatchCandidate>[];
    for (final entry in value.entries) {
      final candidateId = entry.key.toString();
      if (candidateId == id || entry.value is! Map<dynamic, dynamic>) {
        continue;
      }

      // Deterministic host election prevents two equally timed clients from
      // reserving each other and both becoming hosts.
      if (candidateId.compareTo(id) <= 0) {
        continue;
      }

      final data = entry.value as Map<dynamic, dynamic>;
      if (data['roomId'] != null) {
        continue;
      }

      final rating = (data['rating'] as num?)?.toInt();
      if (rating == null || (rating - playerRating).abs() > ratingRange) {
        continue;
      }

      candidates.add(
        _MatchCandidate(
          userId: candidateId,
          name: MultiplayerPlayer._normalizePlayerName(data['name'] as String?),
          rating: rating,
        ),
      );
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) {
      final ratingCompare = (a.rating - playerRating)
          .abs()
          .compareTo((b.rating - playerRating).abs());
      if (ratingCompare != 0) {
        return ratingCompare;
      }
      return a.userId.compareTo(b.userId);
    });
    return candidates.first;
  }

  Future<RandomMatchResult?> _inviteCandidateAsRankedHost(
    _MatchCandidate candidate,
    int ratingRange,
  ) async {
    final roomId = await _generateRankedRoomId();
    final candidateRef = _db.child('matchmaking/${candidate.userId}');
    final transaction = await candidateRef.runTransaction((current) {
      if (current is! Map<dynamic, dynamic>) {
        return Transaction.abort();
      }
      if (current['roomId'] != null) {
        return Transaction.abort();
      }
      final latestRating = (current['rating'] as num?)?.toInt();
      if (latestRating == null ||
          (latestRating - playerRating).abs() > ratingRange) {
        return Transaction.abort();
      }
      return Transaction.success({
        ...current,
        'roomId': roomId,
        'matchedAt': ServerValue.timestamp,
      });
    }, applyLocally: false);

    if (!transaction.committed) {
      return null;
    }

    try {
      await _createRankedRoomAsHost(roomId, candidate);
    } catch (_) {
      await candidateRef.update({
        'roomId': null,
        'matchedAt': null,
      });
      rethrow;
    }
    return RandomMatchResult(roomId: roomId, isHost: true);
  }

  Future<void> _registerInMatchmaking() async {
    final id = userId;
    if (id == null) {
      throw StateError('ユーザーIDを生成できませんでした。');
    }

    final entryRef = _db.child('matchmaking/$id');
    await entryRef.set({
      'name': displayPlayerName,
      'rating': playerRating,
      'roomId': null,
      'timestamp': ServerValue.timestamp,
    });
    await entryRef.onDisconnect().remove();
  }

  Future<String> _generateRankedRoomId() async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final roomId = (_random.nextInt(9000) + 1000).toString();
      final existing = await _db.child('rooms/$roomId').get();
      if (!existing.exists) {
        return roomId;
      }
    }
    throw StateError('ルームIDの生成に失敗しました。もう一度お試しください。');
  }

  Future<void> _createRankedRoomAsHost(
    String roomId,
    _MatchCandidate candidate,
  ) async {
    final id = userId;
    if (id == null) {
      throw StateError('ユーザーIDを生成できませんでした。');
    }

    final seed = DateTime.now().millisecondsSinceEpoch;
    await _db.child('rooms/$roomId').set({
      'status': 'waiting',
      'seed': seed,
      'mode': 'ranked',
      'createdAt': ServerValue.timestamp,
      'players': {
        'host': {
          'status': 'waiting',
          'name': displayPlayerName,
          'userId': id,
          'rating': playerRating,
        },
        'guest': {
          'status': 'waiting',
          'name': candidate.name,
          'userId': candidate.userId,
          'rating': candidate.rating,
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
          userId: id,
          rating: playerRating,
        ),
        'guest': MultiplayerPlayer(
          status: 'waiting',
          name: candidate.name,
          userId: candidate.userId,
          rating: candidate.rating,
        ),
      },
    );
    _lastRoomStatus = currentRoom!.status;
    _hadOpponentPresent = true;
    await _setupPresence();
    _listenRoom();
    _listenGameplayChannels();
  }

  Future<RandomMatchResult> _joinRankedRoomAsGuest(String roomId) async {
    final id = userId;
    if (id == null) {
      throw StateError('ユーザーIDを生成できませんでした。');
    }

    DataSnapshot? roomSnapshot;
    for (var attempt = 0; attempt < 20; attempt++) {
      final snapshot = await _db.child('rooms/$roomId').get();
      if (snapshot.exists) {
        roomSnapshot = snapshot;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    if (roomSnapshot == null || !roomSnapshot.exists) {
      throw StateError('マッチしたルームが見つかりません。');
    }

    final room = MultiplayerRoom.fromSnapshot(roomId, roomSnapshot.value);
    if (room.status != 'waiting') {
      throw StateError('マッチしたルームはすでに開始されています。');
    }

    await _db.child('rooms/$roomId/players/guest').update({
      'status': 'waiting',
      'name': displayPlayerName,
      'userId': id,
      'rating': playerRating,
    });

    currentRoomId = roomId;
    myRoleId = 'guest';
    isRankedMode = true;
    currentRoom = MultiplayerRoom(
      roomId: room.roomId,
      status: room.status,
      seed: room.seed,
      isRanked: true,
      players: {
        ...room.players,
        'guest': MultiplayerPlayer(
          status: 'waiting',
          name: displayPlayerName,
          userId: id,
          rating: playerRating,
        ),
      },
    );
    _lastRoomStatus = currentRoom!.status;
    _hadOpponentPresent = currentRoom!.players.containsKey(opponentRoleId);
    await _setupPresence();
    _listenRoom();
    _listenGameplayChannels();
    return RandomMatchResult(roomId: roomId, isHost: false);
  }

  void _restartRandomMatchPolling(Completer<RandomMatchResult> completer) {
    if (completer.isCompleted || _matchmakingPollTimer != null) {
      return;
    }
    _matchmakingPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollForRandomMatchOpponent(completer));
    });
  }

  Future<void> _cleanupMatchmakingEntry() async {
    _matchmakingPollTimer?.cancel();
    _matchmakingPollTimer = null;
    await _matchmakingSubscription?.cancel();
    _matchmakingSubscription = null;
    _isMatchmakingPolling = false;
    _matchmakingStartedAt = null;
    final id = userId;
    if (id == null) {
      return;
    }
    try {
      await _db.child('matchmaking/$id').onDisconnect().cancel();
      await _db.child('matchmaking/$id').remove();
    } on FirebaseException {
      // マッチ成立後の掃除失敗は対戦開始を止めない。
    }
  }

  Future<void> leaveRoom() async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    final wasRanked = isRankedMode;
    final shouldForfeitRanked = wasRanked &&
        roomId != null &&
        roleId != null &&
        currentRoom?.status == 'playing' &&
        currentRoom?.statusFor(roleId) != 'dead';

    _roomSubscription?.cancel();
    _opponentBoardSubscription?.cancel();
    _opponentPieceSubscription?.cancel();
    _attackSubscription?.cancel();
    _opponentOjamaSpawnSubscription?.cancel();
    _opponentStatusSubscription?.cancel();
    _matchmakingSubscription?.cancel();
    _roomSubscription = null;
    _opponentBoardSubscription = null;
    _opponentPieceSubscription = null;
    _attackSubscription = null;
    _opponentOjamaSpawnSubscription = null;
    _opponentStatusSubscription = null;
    _matchmakingSubscription = null;

    try {
      if (roomId != null && roleId != null) {
        final roomRef = _db.child('rooms/$roomId');
        await roomRef.child('players/$roleId').onDisconnect().cancel();
        await roomRef.child('players/$roleId/status').onDisconnect().cancel();
        await roomRef.child('status').onDisconnect().cancel();

        if (shouldForfeitRanked) {
          await roomRef.child('players/$roleId/status').set('dead');
          await roomRef.update({'status': 'game_over'});
        } else if (wasRanked) {
          await roomRef.child('players/$roleId/status').set('left');
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

    await cancelRandomMatch();
    currentRoomId = null;
    myRoleId = null;
    currentRoom = null;
    isRankedMode = false;
    _lastRoomStatus = null;
    _hadOpponentPresent = false;
    _isLaunchingRematch = false;
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
      await prefs.setString(_userIdPrefsKey, newUid);
      return newUid;
    } on MissingPluginException {
      return _generateUuidV4();
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

    if (isRankedMode) {
      await _db
          .child('rooms/$roomId/players/$roleId/status')
          .onDisconnect()
          .set('dead');
      await _db.child('rooms/$roomId/status').onDisconnect().set('game_over');
      return;
    }

    await _db.child('rooms/$roomId/players/$roleId').onDisconnect().remove();
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

  Future<String> _loadOrCreateUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_userIdKey);
      if (saved != null && saved.isNotEmpty) {
        return saved;
      }
      final created = _createUuidV4();
      await prefs.setString(_userIdKey, created);
      return created;
    } on MissingPluginException {
      userId ??= _createUuidV4();
      return userId!;
    }
  }

  String _createUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  RatingChange? _ratingChangeFromResult(Object? resultData, String roleId) {
    if (resultData is! Map<dynamic, dynamic>) {
      return null;
    }
    final ratings = resultData['ratings'];
    if (ratings is! Map<dynamic, dynamic>) {
      return null;
    }
    final roleRating = ratings[roleId];
    if (roleRating is! Map<dynamic, dynamic>) {
      return null;
    }
    final oldRating = (roleRating['old'] as num?)?.toInt();
    final newRating = (roleRating['new'] as num?)?.toInt();
    if (oldRating == null || newRating == null) {
      return null;
    }
    return RatingChange(oldRating: oldRating, newRating: newRating);
  }

  Future<void> _applyRankedRatingsFromResult(Object? resultData) async {
    if (resultData is! Map<dynamic, dynamic>) {
      return;
    }
    final ratings = resultData['ratings'];
    if (ratings is! Map<dynamic, dynamic>) {
      return;
    }

    final updates = <String, Object?>{};
    for (final entry in ratings.entries) {
      if (entry.value is! Map<dynamic, dynamic>) {
        continue;
      }
      final ratingData = entry.value as Map<dynamic, dynamic>;
      final targetUserId = ratingData['userId'] as String?;
      final newRating = (ratingData['new'] as num?)?.toInt();
      if (targetUserId == null || newRating == null) {
        continue;
      }
      updates['users/$targetUserId/rating'] = newRating;
      updates['users/$targetUserId/name'] = entry.key == myRoleId
          ? displayPlayerName
          : currentRoom?.players[entry.key.toString()]?.name ?? 'Player';
    }

    if (updates.isNotEmpty) {
      await _db.update(updates);
    }
  }
}
