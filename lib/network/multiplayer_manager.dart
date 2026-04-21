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
  const MultiplayerPlayer({
    required this.status,
    this.name = 'Player',
    this.userId,
    this.rating,
  });

  final String status;
  final String name;
  final String? userId;
  final int? rating;

  factory MultiplayerPlayer.fromMap(Map<dynamic, dynamic>? data) {
    return MultiplayerPlayer(
      status: (data?['status'] as String?) ?? 'waiting',
      name: _normalizePlayerName(data?['name'] as String?),
      userId: data?['userId'] as String?,
      rating: (data?['rating'] as num?)?.toInt(),
    );
  }

  static String _normalizePlayerName(String? value) {
    final name = value?.trim() ?? '';
    return name.isEmpty ? 'Player' : name;
  }
}

class MultiplayerRoom {
  const MultiplayerRoom({
    required this.roomId,
    required this.status,
    required this.seed,
    required this.players,
  });

  final String roomId;
  final String status;
  final int seed;
  final Map<String, MultiplayerPlayer> players;

  bool get hasHost => players.containsKey('host');
  bool get hasGuest => players.containsKey('guest');
  bool get isRanked => roomId.startsWith('ranked_');
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
            entry.value as Map<dynamic, dynamic>?,
          ),
      },
    );
  }
}

class MultiplayerManager {
  MultiplayerManager._internal();

  static final MultiplayerManager _instance = MultiplayerManager._internal();

  factory MultiplayerManager() => _instance;

  final Random _random = Random();

  String? currentRoomId;
  String? myRoleId;
  MultiplayerRoom? currentRoom;
  String playerName = 'Player';
  String? userId;
  int playerRating = 1000;
  bool isRankedMode = false;

  StreamSubscription<DatabaseEvent>? _roomSubscription;
  StreamSubscription<DatabaseEvent>? _opponentBoardSubscription;
  StreamSubscription<DatabaseEvent>? _opponentPieceSubscription;
  StreamSubscription<DatabaseEvent>? _attackSubscription;
  StreamSubscription<DatabaseEvent>? _opponentOjamaSpawnSubscription;
  StreamSubscription<DatabaseEvent>? _opponentStatusSubscription;
  StreamSubscription<DatabaseEvent>? _matchmakingSubscription;
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

  static const int initialRating = 1000;
  static const String _userIdKey = 'user_id';

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
        currentRoom = MultiplayerRoom(
          roomId: roomId,
          status: 'waiting',
          seed: seed,
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

      await roomRef.child('players/guest').set({
        'status': 'waiting',
        'name': displayPlayerName,
        'userId': userId,
      });

      currentRoomId = roomId;
      myRoleId = 'guest';
      currentRoom = MultiplayerRoom(
        roomId: room.roomId,
        status: room.status,
        seed: room.seed,
        players: {
          ...room.players,
          'guest': MultiplayerPlayer(
            status: 'waiting',
            name: displayPlayerName,
            userId: userId,
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
    isRankedMode = roomId.startsWith('ranked_');
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
      await leaveRoom();
      isRankedMode = true;

      final narrow = await _findOrWaitForMatch(
        ratingRange: 100,
        waitDuration: const Duration(seconds: 10),
      );
      if (narrow != null) {
        return narrow;
      }

      final wide = await _findOrWaitForMatch(
        ratingRange: 300,
        waitDuration: const Duration(seconds: 5),
      );
      if (wide != null) {
        return wide;
      }

      await cancelRandomMatch();
      throw StateError('条件に合う相手が見つかりませんでした。');
    } on FirebaseException catch (error) {
      await cancelRandomMatch();
      throw StateError(_firebaseErrorMessage('ランダムマッチ', error));
    }
  }

  Future<void> cancelRandomMatch() async {
    _matchmakingSubscription?.cancel();
    _matchmakingSubscription = null;
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

  Future<RandomMatchResult?> _findOrWaitForMatch({
    required int ratingRange,
    required Duration waitDuration,
  }) async {
    final candidate = await _findCandidate(ratingRange);
    if (candidate != null) {
      final result = await _tryInviteCandidate(candidate, ratingRange);
      if (result != null) {
        return result;
      }
    }

    await _registerInMatchmaking(ratingRange);
    return _waitForMatchInvite(waitDuration);
  }

  Future<_MatchCandidate?> _findCandidate(int ratingRange) async {
    final id = userId;
    if (id == null) {
      return null;
    }

    final snapshot = await _db.child('matchmaking').get();
    final value = snapshot.value;
    if (value is! Map<dynamic, dynamic>) {
      return null;
    }

    final candidates = <_MatchCandidate>[];
    for (final entry in value.entries) {
      final candidateId = entry.key.toString();
      if (candidateId == id || entry.value is! Map<dynamic, dynamic>) {
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

  Future<RandomMatchResult?> _tryInviteCandidate(
    _MatchCandidate candidate,
    int ratingRange,
  ) async {
    final id = userId;
    if (id == null) {
      return null;
    }

    final roomRef = _db.child('rooms').push();
    final roomId = 'ranked_${roomRef.key}';
    final rankedRoomRef = _db.child('rooms/$roomId');
    final seed = DateTime.now().millisecondsSinceEpoch;

    await rankedRoomRef.set({
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
        'roleId': 'guest',
        'matchedAt': ServerValue.timestamp,
      });
    }, applyLocally: false);

    if (!transaction.committed) {
      await rankedRoomRef.remove();
      return null;
    }

    currentRoomId = roomId;
    myRoleId = 'host';
    currentRoom = MultiplayerRoom(
      roomId: roomId,
      status: 'waiting',
      seed: seed,
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
    await cancelRandomMatch();
    await _setupPresence();
    _listenRoom();
    _listenGameplayChannels();
    return RandomMatchResult(roomId: roomId, isHost: true);
  }

  Future<void> _registerInMatchmaking(int ratingRange) async {
    final id = userId;
    if (id == null) {
      throw StateError('ユーザーIDを生成できませんでした。');
    }

    final entryRef = _db.child('matchmaking/$id');
    await entryRef.set({
      'name': displayPlayerName,
      'rating': playerRating,
      'range': ratingRange,
      'createdAt': ServerValue.timestamp,
    });
    await entryRef.onDisconnect().remove();
  }

  Future<RandomMatchResult?> _waitForMatchInvite(Duration timeout) async {
    final id = userId;
    if (id == null) {
      return null;
    }

    final completer = Completer<RandomMatchResult?>();
    Timer? timeoutTimer;

    _matchmakingSubscription?.cancel();
    _matchmakingSubscription =
        _db.child('matchmaking/$id').onValue.listen((event) async {
      final value = event.snapshot.value;
      if (value is! Map<dynamic, dynamic>) {
        return;
      }
      final roomId = value['roomId'] as String?;
      final roleId = value['roleId'] as String? ?? 'guest';
      if (roomId == null || roomId.isEmpty || completer.isCompleted) {
        return;
      }

      timeoutTimer?.cancel();
      await _matchmakingSubscription?.cancel();
      _matchmakingSubscription = null;
      await _db.child('matchmaking/$id').onDisconnect().cancel();
      await _db.child('matchmaking/$id').remove();

      currentRoomId = roomId;
      myRoleId = roleId;
      isRankedMode = true;
      final roomSnapshot = await _db.child('rooms/$roomId').get();
      if (!roomSnapshot.exists) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        return;
      }
      currentRoom = MultiplayerRoom.fromSnapshot(roomId, roomSnapshot.value);
      _lastRoomStatus = currentRoom!.status;
      _hadOpponentPresent = currentRoom!.players.containsKey(opponentRoleId);
      await _setupPresence();
      _listenRoom();
      _listenGameplayChannels();
      if (!completer.isCompleted) {
        completer.complete(
          RandomMatchResult(roomId: roomId, isHost: roleId == 'host'),
        );
      }
    });

    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    final result = await completer.future;
    timeoutTimer.cancel();
    if (result == null) {
      await _matchmakingSubscription?.cancel();
      _matchmakingSubscription = null;
    }
    return result;
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
