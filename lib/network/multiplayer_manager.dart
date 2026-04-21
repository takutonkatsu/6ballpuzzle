import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';
import '../game/game_models.dart';

typedef RoomUpdateCallback = void Function(MultiplayerRoom room);
typedef OpponentBoardUpdateCallback = void Function(Map<String, dynamic> board);
typedef OpponentPieceUpdateCallback = void Function(Map<String, dynamic> piece);
typedef AttackReceivedCallback = void Function(OjamaTask task);
typedef OpponentOjamaSpawnedCallback = void Function(List<dynamic> ojamaData);
typedef OpponentGameOverCallback = void Function();
typedef OpponentDisconnectedCallback = void Function();
typedef RematchStartedCallback = void Function(int newSeed);

class MultiplayerPlayer {
  const MultiplayerPlayer({required this.status});

  final String status;

  factory MultiplayerPlayer.fromMap(Map<dynamic, dynamic>? data) {
    return MultiplayerPlayer(
      status: (data?['status'] as String?) ?? 'waiting',
    );
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
            'host': {'status': 'waiting'},
          },
        });

        currentRoomId = roomId;
        myRoleId = 'host';
        currentRoom = MultiplayerRoom(
          roomId: roomId,
          status: 'waiting',
          seed: seed,
          players: const {
            'host': MultiplayerPlayer(status: 'waiting'),
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

      final roomRef = _db.child('rooms/$roomId');
      final snapshot = await roomRef.get();
      if (!snapshot.exists) {
        return false;
      }

      final room = MultiplayerRoom.fromSnapshot(roomId, snapshot.value);
      if (room.status != 'waiting' || room.hasGuest) {
        return false;
      }

      await roomRef.child('players/guest').set({'status': 'waiting'});

      currentRoomId = roomId;
      myRoleId = 'guest';
      currentRoom = MultiplayerRoom(
        roomId: room.roomId,
        status: room.status,
        seed: room.seed,
        players: {
          ...room.players,
          'guest': const MultiplayerPlayer(status: 'waiting'),
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

  Future<void> sendOjamaSpawn(List<dynamic> ojamaData) async {
    final roomId = currentRoomId;
    final roleId = myRoleId;
    if (roomId == null || roleId == null) {
      throw StateError('参加中のルームがありません。');
    }

    try {
      await _db.child('rooms/$roomId/players/$roleId/ojamaSpawns').push().set({
        'items': ojamaData,
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
        if (items.isNotEmpty) {
          onOpponentOjamaSpawned?.call(items);
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
}
