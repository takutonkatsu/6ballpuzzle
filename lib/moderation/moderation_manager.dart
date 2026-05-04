import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../firebase_database_provider.dart';

class ModerationManager {
  ModerationManager._();

  static final ModerationManager instance = ModerationManager._();

  static const String _blockedUsersKey = 'moderation_blocked_user_ids';
  static const List<String> _blockedTerms = [
    'fuck',
    'shit',
    'bitch',
    'cunt',
    '死ね',
    'ころす',
    '殺す',
    'ばか',
    'バカ',
    'アホ',
  ];

  String sanitizePlayerName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final clipped = String.fromCharCodes(trimmed.runes.take(10));
    final normalized = clipped.toLowerCase();
    for (final term in _blockedTerms) {
      if (normalized.contains(term.toLowerCase())) {
        throw StateError('この名前は使用できません。別の名前を入力してください。');
      }
    }
    return clipped;
  }

  Future<bool> isBlocked(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_blockedUsersKey) ?? const []).contains(uid);
  }

  Future<void> blockUser(String uid) async {
    if (uid.trim().isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final blocked = (prefs.getStringList(_blockedUsersKey) ?? const [])
        .where((item) => item.isNotEmpty)
        .toSet()
      ..add(uid);
    await prefs.setStringList(_blockedUsersKey, blocked.toList()..sort());
  }

  Future<void> reportUser({
    required String reportedUid,
    required String reportedName,
    required String reason,
    String? roomId,
  }) async {
    final reporterUid = await AuthManager.instance.ensureSignedIn();
    await AppFirebaseDatabase.ref().child('reports').push().set({
      'reporterUid': reporterUid,
      'reportedUid': reportedUid,
      'reportedName': reportedName,
      'reason': reason.trim().isEmpty ? 'unspecified' : reason.trim(),
      if (roomId != null) 'roomId': roomId,
      'createdAt': ServerValue.timestamp,
    });
  }
}
