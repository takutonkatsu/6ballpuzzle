import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FriendDeepLinkService {
  FriendDeepLinkService._();

  static final FriendDeepLinkService instance = FriendDeepLinkService._();

  final StreamController<Uri> _controller = StreamController<Uri>.broadcast();
  static const MethodChannel _nativeChannel = MethodChannel(
    'hexagon/deep_link',
  );
  StreamSubscription<Uri>? _subscription;
  Uri? _pendingUri;
  bool _started = false;

  Stream<Uri> get stream => _controller.stream;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _nativeChannel.setMethodCallHandler(_handleNativeMethodCall);
    unawaited(_readNativeInitialLink());
    final appLinks = AppLinks();
    unawaited(
      appLinks.getInitialLink().then((uri) {
        if (uri != null) {
          _emit(uri);
        }
      }).catchError((Object error, StackTrace stackTrace) {
        debugPrint('Initial friend link read failed: $error');
      }),
    );
    _subscription = appLinks.uriLinkStream.listen(
      _emit,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Friend link stream failed: $error');
      },
    );
  }

  Future<void> _readNativeInitialLink() async {
    try {
      final raw = await _nativeChannel.invokeMethod<String>(
        'getInitialFriendLink',
      );
      if (raw != null && raw.trim().isNotEmpty) {
        _emitRaw(raw);
      }
    } catch (error, stackTrace) {
      debugPrint('Native initial friend link read failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method != 'onFriendLink') {
      return;
    }
    final raw = call.arguments?.toString() ?? '';
    _emitRaw(raw);
  }

  void _emitRaw(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) {
      return;
    }
    _emit(uri);
  }

  Uri? consumePendingUri() {
    final uri = _pendingUri;
    _pendingUri = null;
    return uri;
  }

  void _emit(Uri uri) {
    if (!_isFriendUri(uri)) {
      return;
    }
    _pendingUri = uri;
    if (!_controller.isClosed) {
      _controller.add(uri);
    }
  }

  bool _isFriendUri(Uri uri) {
    if (uri.scheme.toLowerCase() == 'hexagon' &&
        uri.host.toLowerCase() == 'friend') {
      return true;
    }
    final host = uri.host.toLowerCase();
    if (host != 'takutonkatsu.com' && host != 'www.takutonkatsu.com') {
      return false;
    }
    final normalizedPath = uri.path.toLowerCase();
    return normalizedPath == '/hexagon/friend' ||
        normalizedPath == '/hexagon/friend/' ||
        normalizedPath == '/hexagon/friend.html';
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}
