import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_review_config.dart';
import 'firebase_database_provider.dart';

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
  static const String _interstitialSkipUntilKey =
      'settings_interstitial_skip_until';
  static const String _usedAdGiftCodesKey = 'settings_used_ad_gift_codes';
  static const String _onboardingSeenKey = 'settings_onboarding_seen';
  static const String _hintGuideEnabledKey = 'settings_hint_guide_enabled';
  static const String _hapticsEnabledKey = 'settings_haptics_enabled';
  static const String _serverAdsConfigPath = 'appConfig/ads';

  final ValueNotifier<double> musicVolume = ValueNotifier(1.0);
  final ValueNotifier<double> sfxVolume = ValueNotifier(1.0);
  final ValueNotifier<bool> adsRemoved = ValueNotifier(false);
  final ValueNotifier<bool> serverAdsGloballyDisabled = ValueNotifier(false);
  final ValueNotifier<DateTime?> interstitialSkipUntil = ValueNotifier(null);
  final ValueNotifier<bool> onboardingSeen = ValueNotifier(false);
  final ValueNotifier<bool> hintGuideEnabled = ValueNotifier(true);
  final ValueNotifier<bool> hapticsEnabled = ValueNotifier(true);
  final ValueNotifier<ControlLayoutPreset> controlLayout =
      ValueNotifier(ControlLayoutPreset.rotateMoveMoveRotate);

  bool _loaded = false;
  StreamSubscription<DatabaseEvent>? _serverAdsConfigSubscription;

  bool get _androidAdsRemovedBenefitsEnabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get canRequestAds => !serverAdsGloballyDisabled.value;

  bool get canRequestRewardedAds => !serverAdsGloballyDisabled.value;

  bool get canShowAdRemovalUi => !serverAdsGloballyDisabled.value;

  bool get adRemovalBenefitsEnabled =>
      adsRemoved.value || serverAdsGloballyDisabled.value;

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    musicVolume.value =
        (prefs.getDouble(_musicVolumeKey) ?? 1.0).clamp(0.0, 1.0);
    sfxVolume.value = (prefs.getDouble(_sfxVolumeKey) ?? 1.0).clamp(0.0, 1.0);
    adsRemoved.value = _androidAdsRemovedBenefitsEnabled ||
        (prefs.getBool(_adsRemovedKey) ?? false);
    final skipUntilMs = prefs.getInt(_interstitialSkipUntilKey) ?? 0;
    interstitialSkipUntil.value =
        skipUntilMs > DateTime.now().millisecondsSinceEpoch
            ? DateTime.fromMillisecondsSinceEpoch(skipUntilMs)
            : null;
    onboardingSeen.value = prefs.getBool(_onboardingSeenKey) ?? false;
    hintGuideEnabled.value = prefs.getBool(_hintGuideEnabledKey) ?? true;
    hapticsEnabled.value = prefs.getBool(_hapticsEnabledKey) ?? true;
    final defaultLayout = ControlLayoutPreset.rotateMoveMoveRotate.index;
    final rawLayout = prefs.getInt(_controlLayoutKey) ?? defaultLayout;
    controlLayout.value = ControlLayoutPreset
        .values[rawLayout.clamp(0, ControlLayoutPreset.values.length - 1)];
    _loaded = true;
    await startServerAdsConfigListener();
  }

  Future<void> startServerAdsConfigListener() async {
    if (_serverAdsConfigSubscription != null) {
      return;
    }
    try {
      final ref = AppFirebaseDatabase.ref().child(_serverAdsConfigPath);
      final snapshot = await ref.get().timeout(const Duration(seconds: 4));
      _applyServerAdsConfig(snapshot.value);
      _serverAdsConfigSubscription = ref.onValue.listen(
        (event) => _applyServerAdsConfig(event.snapshot.value),
        onError: (_) {},
      );
    } catch (_) {
      serverAdsGloballyDisabled.value = false;
    }
  }

  void _applyServerAdsConfig(Object? raw) {
    if (raw is! Map) {
      serverAdsGloballyDisabled.value = false;
      return;
    }
    final data = Map<dynamic, dynamic>.from(raw);
    serverAdsGloballyDisabled.value = _boolValue(data['globallyDisabled']) ||
        _boolValue(data['disabled']) ||
        _boolValue(data['hideAllAds']);
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
    final next = _androidAdsRemovedBenefitsEnabled || value;
    adsRemoved.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adsRemovedKey, next);
  }

  bool get isInterstitialSkipActive {
    final until = interstitialSkipUntil.value;
    if (until == null) {
      return false;
    }
    if (DateTime.now().isBefore(until)) {
      return true;
    }
    unawaited(clearInterstitialSkipIfExpired());
    return false;
  }

  Duration get remainingInterstitialSkip {
    final until = interstitialSkipUntil.value;
    if (until == null) {
      return Duration.zero;
    }
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> activateInterstitialSkip(Duration duration) async {
    final base = interstitialSkipUntil.value != null &&
            DateTime.now().isBefore(interstitialSkipUntil.value!)
        ? interstitialSkipUntil.value!
        : DateTime.now();
    final until = base.add(duration);
    interstitialSkipUntil.value = until;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _interstitialSkipUntilKey,
      until.millisecondsSinceEpoch,
    );
  }

  Future<void> clearInterstitialSkipIfExpired() async {
    final until = interstitialSkipUntil.value;
    if (until == null || DateTime.now().isBefore(until)) {
      return;
    }
    interstitialSkipUntil.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_interstitialSkipUntilKey);
  }

  Future<void> setOnboardingSeen(bool value) async {
    onboardingSeen.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, value);
  }

  Future<void> setHintGuideEnabled(bool value) async {
    hintGuideEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hintGuideEnabledKey, value);
  }

  Future<void> setHapticsEnabled(bool value) async {
    hapticsEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticsEnabledKey, value);
  }

  bool _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes' || text == 'on';
  }

  String text(String ja, String en) => ja;

  String translate(String value) => value;

  Future<bool> redeemAdRemovalGiftCode({
    required String code,
  }) async {
    if (!AppReviewConfig.adRemovalGiftCodeEnabled) {
      return false;
    }
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
    if (!AppReviewConfig.adRemovalGiftCodeIssuerEnabled) {
      return '';
    }
    final millis = DateTime.now().millisecondsSinceEpoch;
    final payload = millis.toRadixString(36).toUpperCase().padLeft(8, '0');
    return 'ADFREE-$payload-${_giftChecksum(payload)}';
  }

  bool isValidAdRemovalGiftCode({required String code}) {
    if (!AppReviewConfig.adRemovalGiftCodeEnabled) {
      return false;
    }
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
      final ref = AppFirebaseDatabase.ref().child(
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
