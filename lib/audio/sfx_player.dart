import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

import '../game/perf_monitor.dart';

class SfxPlayer {
  SfxPlayer._();

  static const int _maxPlayersPerSound = 4;
  static const Duration _sameSoundCooldown = Duration(milliseconds: 35);
  static const Duration _pooledSoundSafetyStop = Duration(seconds: 12);

  static final Set<AudioPlayer> _activePlayers = <AudioPlayer>{};
  static final Map<AudioPlayer, StreamSubscription<void>> _subscriptions =
      <AudioPlayer, StreamSubscription<void>>{};
  static final Map<AudioPlayer, Timer> _fallbackTimers = <AudioPlayer, Timer>{};
  static final Map<String, AudioPool> _pools = <String, AudioPool>{};
  static final Map<String, Future<AudioPool>> _pendingPools =
      <String, Future<AudioPool>>{};
  static final Map<String, DateTime> _lastPlayedAt = <String, DateTime>{};
  static int _activePoolSounds = 0;
  static Future<void> _operation = Future<void>.value();

  static Future<void> play(String fileName, {double volume = 1.0}) async {
    return _enqueue(() => _playNow(fileName, volume: volume));
  }

  static Future<void> _playNow(
    String fileName, {
    required double volume,
  }) async {
    final now = DateTime.now();
    final lastPlayedAt = _lastPlayedAt[fileName];
    if (lastPlayedAt != null &&
        now.difference(lastPlayedAt) < _sameSoundCooldown) {
      PerfMonitor.logValue('sfx.skipped', fileName);
      return;
    }
    _lastPlayedAt[fileName] = now;

    final stopwatch = PerfMonitor.enabled ? (Stopwatch()..start()) : null;
    try {
      await _startPooledSound(fileName, volume: volume);
      if (stopwatch != null) {
        PerfMonitor.logDuration('sfx.play', stopwatch, warnMs: 4);
      }
    } catch (error) {
      PerfMonitor.logValue('sfx.pool_failed', '$fileName:$error');
      await _evictPool(fileName);
      final player = await FlameAudio.play(fileName, volume: volume);
      _track(player);
    }
  }

  static Future<void> _startPooledSound(
    String fileName, {
    required double volume,
  }) async {
    final pool = await _poolFor(fileName);
    _activePoolSounds++;
    try {
      final stop = await pool.start(volume: volume);
      unawaited(_releasePooledSound(stop));
    } catch (_) {
      _activePoolSounds = (_activePoolSounds - 1).clamp(0, 1 << 30);
      rethrow;
    }
  }

  static Future<AudioPool> _poolFor(String fileName) {
    final existing = _pools[fileName];
    if (existing != null) {
      return Future<AudioPool>.value(existing);
    }
    final pending = _pendingPools[fileName];
    if (pending != null) {
      return pending;
    }
    final created = FlameAudio.createPool(
      fileName,
      minPlayers: 1,
      maxPlayers: _maxPlayersPerSound,
    ).then((pool) {
      _pendingPools.remove(fileName);
      _pools[fileName] = pool;
      return pool;
    });
    _pendingPools[fileName] = created;
    return created;
  }

  static Future<void> _releasePooledSound(StopFunction stop) async {
    try {
      await Future<void>.delayed(_pooledSoundSafetyStop);
      await stop();
    } catch (_) {
      // プール音の停止失敗でゲーム進行を止めない。
    } finally {
      _activePoolSounds = (_activePoolSounds - 1).clamp(0, 1 << 30);
      PerfMonitor.logValue('sfx.activePoolSounds', _activePoolSounds);
    }
  }

  static void _track(AudioPlayer player) {
    _activePlayers.add(player);
    _subscriptions[player] = player.onPlayerComplete.listen((_) {
      unawaited(_disposePlayer(player));
    });
    _fallbackTimers[player] = Timer(const Duration(seconds: 8), () {
      unawaited(_disposePlayer(player));
    });
  }

  static Future<void> resetTransientAudio() {
    return _enqueue(_resetTransientAudioNow);
  }

  static Future<void> _resetTransientAudioNow() async {
    final players = List<AudioPlayer>.from(_activePlayers);
    for (final player in players) {
      await _disposePlayer(player);
    }
    final pools = List<AudioPool>.from(_pools.values);
    _pools.clear();
    _pendingPools.clear();
    _lastPlayedAt.clear();
    _activePoolSounds = 0;
    for (final pool in pools) {
      try {
        await pool.dispose();
      } catch (_) {
        // AudioPool破棄失敗で画面遷移を止めない。
      }
    }
  }

  static Future<void> _disposePlayer(AudioPlayer player) async {
    _activePlayers.remove(player);
    final subscription = _subscriptions.remove(player);
    final timer = _fallbackTimers.remove(player);
    timer?.cancel();
    await subscription?.cancel();
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {
      // Androidのネイティブ側解放タイミング差で例外が出ても無視する。
    }
  }

  static Future<void> _evictPool(String fileName) async {
    final pool = _pools.remove(fileName);
    _pendingPools.remove(fileName);
    if (pool == null) {
      return;
    }
    try {
      await pool.dispose();
    } catch (_) {
      // 壊れたAudioPoolの破棄失敗は、次回作り直しで回復させる。
    }
  }

  static Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operation = _operation.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
