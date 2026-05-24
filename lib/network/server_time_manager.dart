import 'package:firebase_database/firebase_database.dart';

import '../auth/auth_manager.dart';
import '../firebase_database_provider.dart';

class ServerTimeManager {
  ServerTimeManager._internal();

  static final ServerTimeManager instance = ServerTimeManager._internal();

  static const Duration _anchorTtl = Duration(minutes: 15);
  static const Duration _minRefreshInterval = Duration(seconds: 20);

  int? _anchorServerMillis;
  final Stopwatch _anchorStopwatch = Stopwatch();
  DateTime? _lastRefreshAttemptAt;

  DatabaseReference get _db => AppFirebaseDatabase.ref();

  Future<DateTime> nowUtc({bool forceRefresh = false}) async {
    if (_hasFreshAnchor && (!forceRefresh || !_canRefreshNow)) {
      return _anchoredNowUtc();
    }
    if (!forceRefresh && _hasAnchor) {
      return _anchoredNowUtc();
    }
    return refreshNowUtc();
  }

  Future<DateTime> nowJst({bool forceRefresh = false}) async {
    final utc = await nowUtc(forceRefresh: forceRefresh);
    return utc.add(const Duration(hours: 9));
  }

  DateTime? cachedNowJst() {
    if (!_hasAnchor) {
      return null;
    }
    return _anchoredNowUtc().add(const Duration(hours: 9));
  }

  Future<DateTime> refreshNowUtc() async {
    _lastRefreshAttemptAt = DateTime.now();
    final uid = await AuthManager.instance.ensureSignedIn();
    final ref = _db.child('serverTimePings/$uid/current');
    await ref.set({
      'timestamp': ServerValue.timestamp,
    });
    final snapshot = await ref.child('timestamp').get();
    final millis = _intValue(snapshot.value);
    if (millis == null) {
      throw StateError('サーバー時刻を取得できませんでした。');
    }
    _anchorServerMillis = millis;
    _anchorStopwatch
      ..reset()
      ..start();
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  bool get _hasAnchor => _anchorServerMillis != null;

  bool get _hasFreshAnchor =>
      _hasAnchor && _anchorStopwatch.elapsed <= _anchorTtl;

  bool get _canRefreshNow {
    final last = _lastRefreshAttemptAt;
    return last == null ||
        DateTime.now().difference(last) >= _minRefreshInterval;
  }

  DateTime _anchoredNowUtc() {
    final anchor = _anchorServerMillis;
    if (anchor == null) {
      throw StateError('サーバー時刻が初期化されていません。');
    }
    return DateTime.fromMillisecondsSinceEpoch(
      anchor + _anchorStopwatch.elapsedMilliseconds,
      isUtc: true,
    );
  }

  int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }
}
