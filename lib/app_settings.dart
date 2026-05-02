import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
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
  static const String _usedAdGiftCodesKey = 'settings_used_ad_gift_codes';

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
  }) async {
    final normalizedCode = _normalizeGiftCode(code);
    if (!isValidAdRemovalGiftCode(code: normalizedCode)) {
      return false;
    }
    final globallyAvailable = await _claimGlobalGiftCode(normalizedCode);
    if (!globallyAvailable) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final usedCodes = prefs.getStringList(_usedAdGiftCodesKey) ?? const [];
    if (usedCodes.contains(normalizedCode)) {
      return false;
    }
    await prefs.setStringList(
      _usedAdGiftCodesKey,
      [...usedCodes, normalizedCode],
    );
    await setAdsRemoved(true);
    return true;
  }

  String generateAdRemovalGiftCode() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final payload = millis.toRadixString(36).toUpperCase().padLeft(8, '0');
    return 'ADFREE-$payload-${_giftChecksum(payload)}';
  }

  bool isValidAdRemovalGiftCode({required String code}) {
    final normalizedCode = _normalizeGiftCode(code);
    final parts = normalizedCode.split('-');
    if (parts.length != 3 || parts.first != 'ADFREE') {
      return false;
    }
    return parts[2] == _giftChecksum(parts[1]);
  }

  String _normalizeGiftCode(String value) {
    return value.trim().toUpperCase().replaceAll(' ', '');
  }

  Future<bool> _claimGlobalGiftCode(String normalizedCode) async {
    try {
      final app = Firebase.app();
      final database = FirebaseDatabase.instanceFor(
        app: app,
        databaseURL: app.options.databaseURL,
      );
      final ref = database.ref(
        'giftCodes/adRemoval/${normalizedCode.replaceAll('-', '_')}',
      );
      final snapshot = await ref.get();
      if (snapshot.exists) {
        return false;
      }
      await ref.set({
        'code': normalizedCode,
        'redeemedAt': ServerValue.timestamp,
      });
      return true;
    } catch (_) {
      return true;
    }
  }

  String _giftChecksum(String payload) {
    var hash = 0x45D9F3B;
    for (final unit in '6BALL_AD_FREE_$payload'.codeUnits) {
      hash = (hash ^ unit) * 16777619;
      hash &= 0x7fffffff;
    }
    return hash.toRadixString(36).toUpperCase().padLeft(6, '0').substring(0, 6);
  }
}
