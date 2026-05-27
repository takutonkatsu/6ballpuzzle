import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'admin_models.dart';

class AdminDatabaseRepository {
  const AdminDatabaseRepository(this._database);

  final FirebaseDatabase _database;

  DatabaseReference get _root => _database.ref();

  Stream<List<AdminPlayerSummary>> watchPlayerSummaries({int limit = 300}) {
    return _root
        .child('playerRecordSummaries')
        .orderByChild('updatedAt')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      if (value is! Map) {
        return const <AdminPlayerSummary>[];
      }
      final players = value.entries
          .map((entry) =>
              playerSummaryFromEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
      return players;
    });
  }

  Stream<List<AdminRoomSummary>> watchRooms() {
    return _root.child('rooms').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) {
        return const <AdminRoomSummary>[];
      }
      final rooms = value.entries
          .map((entry) =>
              roomSummaryFromEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort(_compareRooms);
      return rooms;
    });
  }

  Stream<AdminRoomDetail?> watchRoom(String roomId) {
    return _root.child('rooms/$roomId').onValue.map((event) {
      if (!event.snapshot.exists) {
        return null;
      }
      final summary = roomSummaryFromEntry(roomId, event.snapshot.value);
      return AdminRoomDetail(
        summary: summary,
        rawJson: prettyJson(event.snapshot.value),
      );
    });
  }

  Stream<Map<String, int>> watchRoomPlayerBoard(String roomId, String role) {
    return _root.child('rooms/$roomId/players/$role/board').onValue.map(
          (event) => boardFromValue(event.snapshot.value),
        );
  }

  Stream<AdminActivePiece?> watchRoomPlayerActivePiece(
    String roomId,
    String role,
  ) {
    return _root.child('rooms/$roomId/players/$role/activePiece').onValue.map(
          (event) => activePieceFromValue(event.snapshot.value),
        );
  }

  Stream<AdminOjamaSpawn> watchRoomPlayerOjamaSpawns(
    String roomId,
    String role,
  ) {
    return _root
        .child('rooms/$roomId/players/$role/ojamaSpawns')
        .onChildAdded
        .map(
      (event) {
        final raw = stringDynamicMap(event.snapshot.value);
        return AdminOjamaSpawn(
          id: event.snapshot.key ?? '',
          items: listValue(raw['items']),
          dropSeed: intValue(raw['dropSeed']),
          timestamp: intValue(raw['timestamp']),
        );
      },
    );
  }

  Future<AdminPlayerSummary?> fetchPlayerSummary(String uid) async {
    final snapshot = await _root.child('playerRecordSummaries/$uid').get();
    if (!snapshot.exists) {
      return null;
    }
    return playerSummaryFromEntry(uid, snapshot.value);
  }

  Stream<List<AdminPlayerSummary>> watchOnlinePlayers({
    int limit = 1000,
    Duration freshness = const Duration(minutes: 20),
  }) {
    return watchPlayerSummaries(limit: limit).map((players) {
      final threshold =
          DateTime.now().millisecondsSinceEpoch - freshness.inMilliseconds;
      return players.where((player) {
        final updatedAt = player.updatedAt;
        return updatedAt != null && updatedAt >= threshold;
      }).toList();
    });
  }

  Stream<List<AdminWaitingPlayer>> watchWaitingPlayers() {
    late final StreamController<List<AdminWaitingPlayer>> controller;
    var matching = const <AdminWaitingPlayer>[];
    var arena = const <AdminWaitingPlayer>[];
    StreamSubscription<List<AdminWaitingPlayer>>? matchingSubscription;
    StreamSubscription<List<AdminWaitingPlayer>>? arenaSubscription;

    void emit() {
      final waiting = [...matching, ...arena]
        ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      if (!controller.isClosed) {
        controller.add(waiting);
      }
    }

    controller = StreamController<List<AdminWaitingPlayer>>.broadcast(
      onListen: () {
        matchingSubscription = _watchWaitingQueue('matchmaking').listen(
          (players) {
            matching = players;
            emit();
          },
          onError: controller.addError,
        );
        arenaSubscription = _watchWaitingQueue('arena_matchmaking').listen(
          (players) {
            arena = players;
            emit();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await matchingSubscription?.cancel();
        await arenaSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<List<AdminGameActivity>> watchGameActivities({
    Duration freshness = const Duration(minutes: 5),
  }) {
    return _root.child('realtimeGameActivity').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) {
        return const <AdminGameActivity>[];
      }
      final threshold =
          DateTime.now().millisecondsSinceEpoch - freshness.inMilliseconds;
      final activities = <AdminGameActivity>[];
      for (final entry in value.entries) {
        final activity = gameActivityFromEntry(
          entry.key.toString(),
          entry.value,
        );
        final activityAt = activity.updatedAt ?? activity.enteredAt;
        if (activityAt != null && activityAt >= threshold) {
          activities.add(activity);
        }
      }
      activities.sort(
        (a, b) => (b.updatedAt ?? b.enteredAt ?? 0)
            .compareTo(a.updatedAt ?? a.enteredAt ?? 0),
      );
      return activities;
    });
  }

  Stream<List<AdminWaitingPlayer>> _watchWaitingQueue(String queue) {
    return _root.child(queue).onValue.map((event) {
      final rawQueue = event.snapshot.value;
      if (rawQueue is! Map) {
        return const <AdminWaitingPlayer>[];
      }
      final waiting = <AdminWaitingPlayer>[];
      for (final entry in rawQueue.entries) {
        final player = waitingPlayerFromEntry(
          entry.key.toString(),
          queue,
          entry.value,
        );
        if (player.status == 'waiting' && _isFresh(player.timestamp)) {
          waiting.add(player);
        }
      }
      waiting.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      return waiting;
    });
  }

  Stream<AdminRealtimeSnapshot> watchRealtimeSnapshot() {
    late final StreamController<AdminRealtimeSnapshot> controller;
    var onlinePlayers = const <AdminPlayerSummary>[];
    var waitingPlayers = const <AdminWaitingPlayer>[];
    var gameActivities = const <AdminGameActivity>[];
    StreamSubscription<List<AdminPlayerSummary>>? onlineSubscription;
    StreamSubscription<List<AdminWaitingPlayer>>? waitingSubscription;
    StreamSubscription<List<AdminGameActivity>>? activitySubscription;

    void emit() {
      if (!controller.isClosed) {
        controller.add(AdminRealtimeSnapshot(
          onlinePlayers: onlinePlayers,
          waitingPlayers: waitingPlayers,
          gameActivities: gameActivities,
        ));
      }
    }

    controller = StreamController<AdminRealtimeSnapshot>.broadcast(
      onListen: () {
        onlineSubscription = watchOnlinePlayers(limit: 1000).listen(
          (players) {
            onlinePlayers = players;
            emit();
          },
          onError: controller.addError,
        );
        waitingSubscription = watchWaitingPlayers().listen(
          (players) {
            waitingPlayers = players;
            emit();
          },
          onError: controller.addError,
        );
        activitySubscription = watchGameActivities().listen(
          (activities) {
            gameActivities = activities;
            emit();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await onlineSubscription?.cancel();
        await waitingSubscription?.cancel();
        await activitySubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<AdminOverallStats> watchOverallStats() {
    return watchPlayerSummaries(limit: 5000).map((players) {
      final today = _todayKeyJst();
      var todayNewPlayers = 0;
      var todayLoginPlayers = 0;
      final modeCounts = <String, int>{};
      for (final player in players) {
        final createdAt =
            _stringAt(player.raw, const ['overall', 'accountCreatedAt']);
        if (_dateKeyFromIso(createdAt) == today) {
          todayNewPlayers++;
        }
        if (player.lastLoginDate == today || player.recordDate == today) {
          todayLoginPlayers++;
        }
        for (final entry in player.modePlayCounts.entries) {
          modeCounts[entry.key] = (modeCounts[entry.key] ?? 0) + entry.value;
        }
      }
      return AdminOverallStats(
        todayKey: today,
        todayNewPlayers: todayNewPlayers,
        todayLoginPlayers: todayLoginPlayers,
        totalPlayers: players.length,
        modePlayCounts: modeCounts,
      );
    });
  }
}

bool _isFresh(int? timestamp,
    {Duration freshness = const Duration(minutes: 2)}) {
  if (timestamp == null) {
    return true;
  }
  final age = DateTime.now().millisecondsSinceEpoch - timestamp;
  return age >= -300000 && age <= freshness.inMilliseconds;
}

int _compareRooms(AdminRoomSummary a, AdminRoomSummary b) {
  final liveCompare = _liveWeight(b).compareTo(_liveWeight(a));
  if (liveCompare != 0) {
    return liveCompare;
  }
  return a.roomId.compareTo(b.roomId);
}

int _liveWeight(AdminRoomSummary room) {
  return switch (room.status) {
    'playing' => 3,
    'waiting' => 2,
    'game_over' => 1,
    _ => 0,
  };
}

String _todayKeyJst() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 9));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

String? _dateKeyFromIso(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return null;
  }
  final jst = parsed.toUtc().add(const Duration(hours: 9));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${jst.year}-${two(jst.month)}-${two(jst.day)}';
}

String? _stringAt(Map<String, dynamic> raw, List<String> path) {
  Object? cursor = raw;
  for (final segment in path) {
    if (cursor is! Map || !cursor.containsKey(segment)) {
      return null;
    }
    cursor = cursor[segment];
  }
  final text = cursor?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
