import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_database_provider.dart';

class RealtimeTransportConfig {
  const RealtimeTransportConfig({
    required this.enabled,
    required this.shadowEnabled,
    required this.receiveEnabled,
    required this.endpointUrl,
    required this.allowInsecureEndpoint,
    required this.friendEnabled,
    required this.rankedEnabled,
    required this.arenaEnabled,
  });

  static const disabled = RealtimeTransportConfig(
    enabled: false,
    shadowEnabled: false,
    receiveEnabled: false,
    endpointUrl: '',
    allowInsecureEndpoint: false,
    friendEnabled: false,
    rankedEnabled: false,
    arenaEnabled: false,
  );

  final bool enabled;
  final bool shadowEnabled;
  final bool receiveEnabled;
  final String endpointUrl;
  final bool allowInsecureEndpoint;
  final bool friendEnabled;
  final bool rankedEnabled;
  final bool arenaEnabled;

  bool enabledForMode(String mode) {
    if (!enabled || !shadowEnabled || !_isEndpointAllowed(endpointUrl)) {
      return false;
    }
    switch (mode) {
      case 'friend':
        return friendEnabled;
      case 'ranked':
        return rankedEnabled;
      case 'arena':
        return arenaEnabled;
      default:
        return false;
    }
  }

  factory RealtimeTransportConfig.fromMap(Map<dynamic, dynamic>? data) {
    if (data == null) {
      return disabled;
    }
    final modes = data['modes'] is Map ? data['modes'] as Map : const {};
    final endpointUrl = data['url']?.toString().trim() ?? '';
    final allowInsecureEndpoint = _boolValue(data['allowInsecureEndpoint']);
    return RealtimeTransportConfig(
      enabled: _boolValue(data['enabled']),
      shadowEnabled: _boolValue(data['shadowEnabled']),
      receiveEnabled: _boolValue(data['receiveEnabled']),
      endpointUrl: endpointUrl,
      allowInsecureEndpoint: allowInsecureEndpoint,
      friendEnabled: _boolValue(modes['friend']),
      rankedEnabled: _boolValue(modes['ranked']),
      arenaEnabled: _boolValue(modes['arena']),
    );
  }

  static bool _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = value?.toString().toLowerCase().trim();
    return text == 'true' || text == '1' || text == 'yes' || text == 'on';
  }

  bool _isEndpointAllowed(String url) {
    if (url.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    if (uri.scheme == 'wss') {
      return true;
    }
    if (uri.scheme == 'ws') {
      return kDebugMode || allowInsecureEndpoint;
    }
    return false;
  }
}

class RealtimeTransportConfigManager {
  RealtimeTransportConfigManager._();

  static final RealtimeTransportConfigManager instance =
      RealtimeTransportConfigManager._();

  static const Duration _cacheTtl = Duration(seconds: 30);

  RealtimeTransportConfig? _cache;
  DateTime? _cacheAt;

  Future<RealtimeTransportConfig> load({bool forceRefresh = false}) async {
    final cache = _cache;
    final cacheAt = _cacheAt;
    if (!forceRefresh &&
        cache != null &&
        cacheAt != null &&
        DateTime.now().difference(cacheAt) < _cacheTtl) {
      return cache;
    }

    try {
      final snapshot = await AppFirebaseDatabase.ref()
          .child('appConfig/realtimeTransport')
          .get()
          .timeout(const Duration(seconds: 2));
      final config = RealtimeTransportConfig.fromMap(
        snapshot.value is Map ? snapshot.value as Map<dynamic, dynamic> : null,
      );
      _cache = config;
      _cacheAt = DateTime.now();
      return config;
    } on FirebaseException {
      return cache ?? RealtimeTransportConfig.disabled;
    } on TimeoutException {
      return cache ?? RealtimeTransportConfig.disabled;
    } catch (_) {
      return cache ?? RealtimeTransportConfig.disabled;
    }
  }
}
