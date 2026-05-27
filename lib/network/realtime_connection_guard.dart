import '../firebase_database_provider.dart';

class RealtimeConnectionGuard {
  RealtimeConnectionGuard._();

  static const String offlineMessage = 'データ通信に接続できません。通信状況を確認してください。';

  static Stream<bool> connectedChanges() {
    return AppFirebaseDatabase.ref()
        .child('.info/connected')
        .onValue
        .map((event) => event.snapshot.value == true);
  }

  static Future<bool?> currentConnected({
    Duration timeout = const Duration(milliseconds: 250),
  }) async {
    try {
      return await connectedChanges().first.timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> waitForConnected({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      return await connectedChanges()
          .firstWhere((connected) => connected)
          .timeout(timeout);
    } catch (_) {
      return false;
    }
  }
}
