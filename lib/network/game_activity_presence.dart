import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_manager.dart';
import '../data/player_data_manager.dart';
import '../firebase_database_provider.dart';

enum GameActivityMode {
  endless,
  cpu,
  ranked,
  arena,
  friend,
}

extension GameActivityModePayload on GameActivityMode {
  String get key {
    switch (this) {
      case GameActivityMode.endless:
        return 'endless';
      case GameActivityMode.cpu:
        return 'cpu';
      case GameActivityMode.ranked:
        return 'ranked';
      case GameActivityMode.arena:
        return 'arena';
      case GameActivityMode.friend:
        return 'friend';
    }
  }
}

class GameActivityPresence {
  GameActivityPresence._();

  static final GameActivityPresence instance = GameActivityPresence._();

  DatabaseReference? _entryRef;
  String? _sessionId;
  GameActivityMode? _mode;
  String? _roomId;
  bool _active = false;
  Timer? _heartbeatTimer;
  int _generation = 0;

  Future<void> enter({
    required GameActivityMode mode,
    String? roomId,
  }) async {
    final generation = ++_generation;
    _heartbeatTimer?.cancel();
    try {
      final uid = await AuthManager.instance.ensureSignedIn();
      await PlayerDataManager.instance.load();
      if (generation != _generation) {
        return;
      }
      final sessionId = '${DateTime.now().microsecondsSinceEpoch}';
      final entryRef = AppFirebaseDatabase.ref().child(
        'realtimeGameActivity/$uid',
      );
      final playerData = PlayerDataManager.instance;

      _entryRef = entryRef;
      _sessionId = sessionId;
      _mode = mode;
      _roomId = roomId;
      _active = true;

      final payload = {
        'uid': uid,
        'publicId': playerData.playerId,
        'displayName': playerData.displayPlayerName,
        'mode': mode.key,
        if (roomId != null && roomId.isNotEmpty) 'roomId': roomId,
        'sessionId': sessionId,
        'enteredAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
        'clientUpdatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      await entryRef.set(payload);
      if (generation != _generation) {
        await _removeIfSameSession(entryRef, sessionId);
        return;
      }
      unawaited(_registerDisconnectRemoval(entryRef));
      _startHeartbeat(generation);
    } catch (error, stackTrace) {
      // プレイ本体を止めないため、プレゼンス送信失敗は握りつぶす。
      debugPrint('Game activity presence enter failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> refresh() async {
    await _refresh(_generation);
  }

  Future<void> _refresh(int generation) async {
    final entryRef = _entryRef;
    final mode = _mode;
    final sessionId = _sessionId;
    if (!_active ||
        generation != _generation ||
        entryRef == null ||
        mode == null ||
        sessionId == null) {
      return;
    }
    try {
      final playerData = PlayerDataManager.instance;
      await entryRef.update({
        'displayName': playerData.displayPlayerName,
        'publicId': playerData.playerId,
        'mode': mode.key,
        if (_roomId != null && _roomId!.isNotEmpty) 'roomId': _roomId,
        'sessionId': sessionId,
        'updatedAt': ServerValue.timestamp,
        'clientUpdatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (error, stackTrace) {
      // プレイ本体を止めない。
      debugPrint('Game activity presence refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _registerDisconnectRemoval(DatabaseReference entryRef) async {
    try {
      await entryRef.onDisconnect().remove();
    } catch (error, stackTrace) {
      debugPrint(
          'Game activity presence onDisconnect registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> exit() async {
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final entryRef = _entryRef;
    _active = false;
    _entryRef = null;
    _sessionId = null;
    _mode = null;
    _roomId = null;
    if (entryRef == null) {
      return;
    }
    try {
      await entryRef.onDisconnect().cancel();
      await entryRef.remove();
    } catch (error, stackTrace) {
      // 終了時の掃除失敗で画面遷移を止めない。
      debugPrint('Game activity presence exit failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _removeIfSameSession(
    DatabaseReference entryRef,
    String sessionId,
  ) async {
    try {
      final snapshot = await entryRef.get();
      if (snapshot.value is! Map) {
        return;
      }
      final data = snapshot.value as Map;
      if (data['sessionId']?.toString() == sessionId) {
        await entryRef.remove();
      }
    } catch (error, stackTrace) {
      debugPrint('Game activity presence stale cleanup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _startHeartbeat(int generation) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refresh(generation));
    });
  }
}
