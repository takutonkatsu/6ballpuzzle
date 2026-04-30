import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
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
      // macOS debug builds can lack Keychain Sharing signing. Keep local
      // development usable by falling back to a stable local-only identifier.
      if (Platform.isMacOS && error.code == 'keychain-error') {
        return _loadOrCreateFallbackUid();
      }
      rethrow;
    }
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
