import 'dart:async';

import '../app_settings.dart';
import 'audio_selection_manager.dart';
import 'sfx_player.dart';

class AppSfx {
  AppSfx._();
  static const double _boostMultiplier = 1.3;

  static const String win = 'winner01_jingle_22.mp3';
  static const String lose = 'loser01_jingle_24.mp3';
  static const String uiTap = 'buttonTap01_決定ボタンを押す44.mp3';
  static const String matched = 'matching01_完了1.mp3';

  static Future<void> play(
    String fileName, {
    double volume = 1.0,
  }) async {
    try {
      final master = AppSettings.instance.sfxVolume.value;
      final itemMultiplier =
          AudioSelectionManager.volumeMultiplierForFileName(fileName);
      await SfxPlayer.play(
        fileName,
        volume: (volume * itemMultiplier * _boostMultiplier * master)
            .clamp(0.0, 1.0),
      );
    } catch (_) {
      // SE再生失敗で画面遷移や進行を止めない。
    }
  }

  static void playUiTap({double volume = 1.44}) {
    unawaited(_playSelected('button', uiTap, volume: volume));
  }

  static void playMatched({double volume = 0.85}) {
    unawaited(_playSelected('matching', matched, volume: volume));
  }

  static void playWin({double volume = 0.92}) {
    unawaited(_playSelected('winner', win, volume: volume));
  }

  static void playLose({double volume = 0.92}) {
    unawaited(_playSelected('loser', lose, volume: volume));
  }

  static Future<void> _playSelected(
    String sectionId,
    String defaultFileName, {
    double volume = 1.0,
  }) async {
    final fileName = await AudioSelectionManager.selectedSfxFile(
      sectionId,
      defaultFileName,
    );
    await play(fileName, volume: volume);
  }
}
