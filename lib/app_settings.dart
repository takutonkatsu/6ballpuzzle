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
  static const String _adsRemovedKey = 'settings_ads_removed';

  final ValueNotifier<double> musicVolume = ValueNotifier(1.0);
  final ValueNotifier<double> sfxVolume = ValueNotifier(1.0);
  final ValueNotifier<bool> adsRemoved = ValueNotifier(false);
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
    adsRemoved.value = prefs.getBool(_adsRemovedKey) ?? false;
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

  Future<void> setAdsRemoved(bool value) async {
    adsRemoved.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adsRemovedKey, value);
  }

  Future<bool> redeemAdRemovalGiftCode({
    required String code,
    required String playerId,
  }) async {
    if (isValidAdRemovalGiftCode(code: code, playerId: playerId)) {
      await setAdsRemoved(true);
      return true;
    }
    return false;
  }

  String generateAdRemovalGiftCode(String playerId) {
    final normalizedId = _normalizeGiftPlayerId(playerId);
    if (normalizedId.isEmpty) {
      return '';
    }
    return 'ADFREE-$normalizedId-${_giftChecksum(normalizedId)}';
  }

  bool isValidAdRemovalGiftCode({
    required String code,
    required String playerId,
  }) {
    final normalizedId = _normalizeGiftPlayerId(playerId);
    final normalizedCode = code.trim().toUpperCase().replaceAll(' ', '');
    return normalizedId.isNotEmpty &&
        normalizedCode == generateAdRemovalGiftCode(normalizedId);
  }

  String _normalizeGiftPlayerId(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  String _giftChecksum(String normalizedPlayerId) {
    var hash = 0x45D9F3B;
    for (final unit in '6BALL_AD_FREE_$normalizedPlayerId'.codeUnits) {
      hash = (hash ^ unit) * 16777619;
      hash &= 0x7fffffff;
    }
    return hash.toRadixString(36).toUpperCase().padLeft(6, '0').substring(0, 6);
  }
}
