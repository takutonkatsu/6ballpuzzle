import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

class SfxPlayer {
  SfxPlayer._();

  static final Set<AudioPlayer> _activePlayers = <AudioPlayer>{};
  static final Map<AudioPlayer, StreamSubscription<void>> _subscriptions =
      <AudioPlayer, StreamSubscription<void>>{};
  static final Map<AudioPlayer, Timer> _fallbackTimers = <AudioPlayer, Timer>{};

  static Future<void> play(String fileName, {double volume = 1.0}) async {
    final player = await FlameAudio.play(fileName, volume: volume);
    _track(player);
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

  static Future<void> resetTransientAudio() async {
    final players = List<AudioPlayer>.from(_activePlayers);
    for (final player in players) {
      await _disposePlayer(player);
    }
    try {
      await FlameAudio.audioCache.clearAll();
    } catch (_) {
      // 一時音声キャッシュの削除失敗で画面遷移を止めない。
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
}
