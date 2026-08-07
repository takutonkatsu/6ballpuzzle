import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_manager.dart';
import '../firebase_database_provider.dart';

class PlayerNameValidationException implements Exception {
  const PlayerNameValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ModerationManager {
  ModerationManager._();

  static final ModerationManager instance = ModerationManager._();

  static const String _blockedUsersKey = 'moderation_blocked_user_ids';
  static const String _nameRejectedMessage = 'この名前は使用できません。別の名前を入力してください。';
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
  static const List<String> _reservedTerms = [
    '運営',
    '公式',
    '管理者',
    'admin',
    'administrator',
    'official',
    'support',
    'staff',
    'hexagon',
    'ヘキサゴン運営',
    'ヘキサゴン公式',
  ];

  List<String>? _remoteBlockedWords;
  List<String>? _remoteReservedWords;
  List<RegExp>? _remoteRegexes;
  DateTime? _remoteConfigFetchedAt;

  String sanitizePlayerName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final clipped = String.fromCharCodes(trimmed.runes.take(10));
    _validatePlayerNameSync(clipped);
    return clipped;
  }

  Future<String> validateAndSanitizePlayerName(String value) async {
    final sanitized = sanitizePlayerName(value);
    if (sanitized.isEmpty) {
      throw const PlayerNameValidationException('名前を入力してください。');
    }
    await _ensureRemoteNameModerationConfig();
    _validateAgainstTerms(sanitized, _remoteBlockedWords ?? const []);
    _validateAgainstTerms(sanitized, _remoteReservedWords ?? const []);
    final normalized = _normalizeNameForCheck(sanitized);
    for (final regex in _remoteRegexes ?? const <RegExp>[]) {
      if (regex.hasMatch(normalized) || regex.hasMatch(sanitized)) {
        throw const PlayerNameValidationException(_nameRejectedMessage);
      }
    }
    return sanitized;
  }

  void _validatePlayerNameSync(String value) {
    final normalized = _normalizeNameForCheck(value);
    if (normalized.isEmpty) {
      throw const PlayerNameValidationException('名前を入力してください。');
    }
    if (normalized.length < 2) {
      throw const PlayerNameValidationException('名前は2文字以上で入力してください。');
    }
    if (!_containsNameLikeCharacter(value)) {
      throw const PlayerNameValidationException(_nameRejectedMessage);
    }
    if (RegExp(r'(.)\1{5,}', unicode: true).hasMatch(normalized)) {
      throw const PlayerNameValidationException(_nameRejectedMessage);
    }
    _validateAgainstTerms(value, _blockedTerms);
    _validateAgainstTerms(value, _reservedTerms);
  }

  void _validateAgainstTerms(String value, Iterable<String> terms) {
    final normalized = _normalizeNameForCheck(value);
    for (final term in terms) {
      final normalizedTerm = _normalizeNameForCheck(term);
      if (normalizedTerm.isEmpty) {
        continue;
      }
      if (normalized.contains(normalizedTerm)) {
        throw const PlayerNameValidationException(_nameRejectedMessage);
      }
    }
  }

  String _normalizeNameForCheck(String value) {
    const replacements = {
      '０': '0',
      '１': '1',
      '２': '2',
      '３': '3',
      '４': '4',
      '５': '5',
      '６': '6',
      '７': '7',
      '８': '8',
      '９': '9',
      'Ａ': 'a',
      'Ｂ': 'b',
      'Ｃ': 'c',
      'Ｄ': 'd',
      'Ｅ': 'e',
      'Ｆ': 'f',
      'Ｇ': 'g',
      'Ｈ': 'h',
      'Ｉ': 'i',
      'Ｊ': 'j',
      'Ｋ': 'k',
      'Ｌ': 'l',
      'Ｍ': 'm',
      'Ｎ': 'n',
      'Ｏ': 'o',
      'Ｐ': 'p',
      'Ｑ': 'q',
      'Ｒ': 'r',
      'Ｓ': 's',
      'Ｔ': 't',
      'Ｕ': 'u',
      'Ｖ': 'v',
      'Ｗ': 'w',
      'Ｘ': 'x',
      'Ｙ': 'y',
      'Ｚ': 'z',
    };
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(replacements[char] ?? char);
    }
    return buffer.toString().toLowerCase().replaceAll(
        RegExp(
            r'[\s\-_.,!！?？@＠#＃$￥%％&＆*＊+＋=＝/／\\|｜:：;；~〜～「」『』（）()［］\[\]{}｛｝<>＜＞・、。]+'),
        '');
  }

  bool _containsNameLikeCharacter(String value) {
    for (final rune in value.runes) {
      if ((rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          (rune >= 0x3040 && rune <= 0x30FF) ||
          (rune >= 0x3400 && rune <= 0x9FFF) ||
          (rune >= 0xFF10 && rune <= 0xFF19) ||
          (rune >= 0xFF21 && rune <= 0xFF3A) ||
          (rune >= 0xFF41 && rune <= 0xFF5A)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _ensureRemoteNameModerationConfig() async {
    final fetchedAt = _remoteConfigFetchedAt;
    if (fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(minutes: 10)) {
      return;
    }
    _remoteConfigFetchedAt = DateTime.now();
    try {
      final snapshot = await AppFirebaseDatabase.ref()
          .child('appConfig/nameModeration')
          .get()
          .timeout(const Duration(seconds: 2));
      final raw = snapshot.value;
      if (raw is! Map) {
        return;
      }
      _remoteBlockedWords = _stringList(raw['blockedWords']);
      _remoteReservedWords = _stringList(raw['reservedWords']);
      _remoteRegexes = _stringList(raw['regexes'])
          .map((pattern) {
            try {
              return RegExp(pattern, caseSensitive: false, unicode: true);
            } catch (_) {
              return null;
            }
          })
          .whereType<RegExp>()
          .toList();
    } catch (_) {
      // サーバー設定が読めない場合も、ローカルの最低限チェックは維持する。
    }
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item'.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (value is Map) {
      return value.values
          .map((item) => '$item'.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
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
