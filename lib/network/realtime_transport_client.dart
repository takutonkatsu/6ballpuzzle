import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../firebase_database_provider.dart';
import 'realtime_transport_config.dart';

typedef RealtimeRelayCallback = void Function(
  String messageType,
  Map<String, dynamic> payload,
);
typedef RealtimePresenceCallback = void Function(
  List<Map<String, dynamic>> players,
);

class RealtimeTransportClient {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  String? _roomId;
  String? _roleId;
  String? _mode;
  bool _connecting = false;
  bool _connected = false;
  bool _receiveEnabled = false;
  int _sequence = 0;
  RealtimeRelayCallback? onRelay;
  RealtimePresenceCallback? onPresence;
  VoidCallback? onReady;
  VoidCallback? onDisconnected;

  bool get isConnected => _connected;
  bool get useAsPrimaryGameplayTransport => _connected && _receiveEnabled;

  Future<void> connectIfEnabled({
    required String roomId,
    required String roleId,
    required String mode,
    required String displayName,
  }) async {
    if (_roomId == roomId &&
        _roleId == roleId &&
        _mode == mode &&
        (_connected || _connecting)) {
      return;
    }

    final config = await RealtimeTransportConfigManager.instance.load();
    if (!config.enabledForMode(mode)) {
      await disconnect();
      return;
    }
    _receiveEnabled = config.receiveEnabled;

    await disconnect();
    _receiveEnabled = config.receiveEnabled;
    _connecting = true;
    _roomId = roomId;
    _roleId = roleId;
    _mode = mode;

    try {
      final token = await FirebaseAuth.instanceFor(
        app: AppFirebaseDatabase.app,
      ).currentUser?.getIdToken();
      final channel = WebSocketChannel.connect(Uri.parse(config.endpointUrl));
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error) {
          debugPrint('Realtime transport error: $error');
          _handleDisconnected();
        },
        onDone: () {
          _handleDisconnected();
        },
        cancelOnError: false,
      );
      channel.sink.add(jsonEncode({
        'type': 'hello',
        'token': token,
        'roomId': roomId,
        'role': roleId,
        'transportVersion': 1,
        'displayName': displayName,
      }));
    } catch (error) {
      debugPrint('Realtime transport connect failed: $error');
      await disconnect();
    } finally {
      _connecting = false;
    }
  }

  Future<bool> sendRelay(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final channel = _channel;
    if (channel == null || (!_connected && !_connecting)) {
      return false;
    }
    try {
      channel.sink.add(jsonEncode({
        'type': type,
        'seq': ++_sequence,
        'sentAt': DateTime.now().millisecondsSinceEpoch,
        'payload': payload,
      }));
      return true;
    } catch (error) {
      debugPrint('Realtime transport send failed: $error');
      return false;
    }
  }

  Future<bool> sendMetric(
    String name, {
    num value = 1,
    Map<String, dynamic>? payload,
  }) async {
    final channel = _channel;
    if (channel == null || (!_connected && !_connecting)) {
      return false;
    }
    try {
      channel.sink.add(jsonEncode({
        'type': 'metric',
        'name': name,
        'value': value,
        'sentAt': DateTime.now().millisecondsSinceEpoch,
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      }));
      return true;
    } catch (error) {
      debugPrint('Realtime transport metric failed: $error');
      return false;
    }
  }

  Future<void> disconnect() async {
    _connected = false;
    _connecting = false;
    _roomId = null;
    _roleId = null;
    _mode = null;
    _receiveEnabled = false;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void _handleDisconnected() {
    final wasPrimary = useAsPrimaryGameplayTransport;
    _connected = false;
    if (wasPrimary) {
      onDisconnected?.call();
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) {
        return;
      }
      final type = decoded['type']?.toString();
      if (type == 'helloAck') {
        _connected = true;
        onReady?.call();
      } else if (type == 'relay') {
        final messageType = decoded['messageType']?.toString();
        final payload = decoded['payload'];
        if (_receiveEnabled && messageType != null && payload is Map) {
          onRelay?.call(messageType, Map<String, dynamic>.from(payload));
        } else {
          debugPrint(
            'Realtime transport relay received: ${decoded['messageType']}',
          );
        }
      } else if (type == 'presence') {
        final rawPlayers = decoded['players'];
        if (rawPlayers is List) {
          final players = rawPlayers
              .whereType<Map>()
              .map((player) => Map<String, dynamic>.from(player))
              .toList(growable: false);
          onPresence?.call(players);
        }
      } else if (type == 'error') {
        debugPrint('Realtime transport server error: ${decoded['code']}');
      }
    } catch (error) {
      debugPrint('Realtime transport decode failed: $error');
    }
  }
}
