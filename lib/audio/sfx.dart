import 'dart:async';

import '../app_settings.dart';
import 'sfx_player.dart';

class AppSfx {
  AppSfx._();
  static const double _boostMultiplier = 1.3;

  static const String win = 'jingle_22_勝利時01.mp3';
  static const String lose = 'jingle_24_敗北時.mp3';
  static const String uiTap = '決定ボタンを押す44_ボタン音01.mp3';
  static const String matched = '完了1_マッチング01.mp3';

  static Future<void> play(
    String fileName, {
    double volume = 1.0,
  }) async {
    try {
      final master = AppSettings.instance.sfxVolume.value;
      await SfxPlayer.play(
        fileName,
        volume: (volume * _boostMultiplier * master).clamp(0.0, 1.0),
      );
    } catch (_) {
      // SE再生失敗で画面遷移や進行を止めない。
    }
  }

  static void playUiTap({double volume = 0.72}) {
    unawaited(play(uiTap, volume: volume));
  }

  static void playMatched({double volume = 0.85}) {
    unawaited(play(matched, volume: volume));
  }

  static void playWin({double volume = 0.92}) {
    unawaited(play(win, volume: volume));
  }

  static void playLose({double volume = 0.92}) {
    unawaited(play(lose, volume: volume));
  }
}
