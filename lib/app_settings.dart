import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ControlLayoutPreset {
  rotateMoveMoveRotate,
  moveMoveRotateRotate,
  rotateRotateMoveMove,
  moveRotateRotateMove,
}

class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _musicVolumeKey = 'settings_music_volume';
  static const String _sfxVolumeKey = 'settings_sfx_volume';
  static const String _controlLayoutKey = 'settings_control_layout';

  final ValueNotifier<double> musicVolume = ValueNotifier(1.0);
  final ValueNotifier<double> sfxVolume = ValueNotifier(1.0);
  final ValueNotifier<ControlLayoutPreset> controlLayout =
      ValueNotifier(ControlLayoutPreset.rotateMoveMoveRotate);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    musicVolume.value =
        (prefs.getDouble(_musicVolumeKey) ?? 1.0).clamp(0.0, 1.0);
    sfxVolume.value = (prefs.getDouble(_sfxVolumeKey) ?? 1.0).clamp(0.0, 1.0);
    final rawLayout = prefs.getInt(_controlLayoutKey) ?? 0;
    controlLayout.value = ControlLayoutPreset
        .values[rawLayout.clamp(0, ControlLayoutPreset.values.length - 1)];
    _loaded = true;
  }

  Future<void> setMusicVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    musicVolume.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_musicVolumeKey, next);
  }

  Future<void> setSfxVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    sfxVolume.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sfxVolumeKey, next);
  }

  Future<void> setControlLayout(ControlLayoutPreset preset) async {
    controlLayout.value = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_controlLayoutKey, preset.index);
  }
}
