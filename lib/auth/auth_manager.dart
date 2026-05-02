import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthManager {
  AuthManager._internal();

  static final AuthManager instance = AuthManager._internal();
  static const String _fallbackUidPrefsKey = 'auth_fallback_uid';

  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get currentUid => _auth.currentUser?.uid;

  Future<String> ensureSignedIn() async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      return currentUser.uid;
    }

    try {
      final credential = await _auth.signInAnonymously();
      final user = credential.user;
      if (user == null) {
        throw StateError('Firebase匿名認証に失敗しました。');
      }
      return user.uid;
    } on FirebaseAuthException catch (error) {
      // Keep the app bootable even when platform auth configuration is
      // unavailable on a specific device/build. Online features may still
      // fail later, but the home screen should not black-screen on launch.
      if (_shouldUseFallbackUid(error)) {
        debugPrint(
          'Falling back to local auth uid because FirebaseAuth '
          'signInAnonymously failed: code=${error.code} message=${error.message}',
        );
        return _loadOrCreateFallbackUid();
      }
      rethrow;
    }
  }

  bool _shouldUseFallbackUid(FirebaseAuthException error) {
    if (Platform.isMacOS && error.code == 'keychain-error') {
      return true;
    }

    final message = (error.message ?? '').toUpperCase();
    return error.code == 'unknown' &&
        (message.contains('CONFIGURATION_NOT_FOUND') ||
            message.contains('INTERNAL ERROR HAS OCCURRED'));
  }

  Future<String> _loadOrCreateFallbackUid() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUid = prefs.getString(_fallbackUidPrefsKey);
    if (savedUid != null && savedUid.isNotEmpty) {
      return savedUid;
    }

    final fallbackUid = 'macos-dev-${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_fallbackUidPrefsKey, fallbackUid);
    return fallbackUid;
  }
}
