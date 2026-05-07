import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'firebase_options_dev.dart' as firebase_dev;
import 'firebase_options_prod.dart' as firebase_prod;

class AppFirebaseDatabase {
  AppFirebaseDatabase._();

  static FirebaseApp? _activeApp;

  static FirebaseApp get app {
    final activeApp = _activeApp;
    if (activeApp == null) {
      throw StateError(
          'Firebase has not been initialized for the active flavor.');
    }
    return activeApp;
  }

  static void useApp(FirebaseApp app) {
    _activeApp = app;
  }

  static FirebaseDatabase instance() {
    return FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: databaseUrl,
    );
  }

  static DatabaseReference ref() => instance().ref();

  static String get databaseUrl {
    final runtimeUrl = app.options.databaseURL;
    if (runtimeUrl != null && runtimeUrl.isNotEmpty) {
      return runtimeUrl;
    }

    const isReleaseBuild = bool.fromEnvironment('dart.vm.product');
    const flavor = String.fromEnvironment(
      'FLAVOR',
      defaultValue: isReleaseBuild ? 'prod' : 'dev',
    );
    final configuredUrl = flavor == 'prod'
        ? firebase_prod.DefaultFirebaseOptions.currentPlatform.databaseURL
        : firebase_dev.DefaultFirebaseOptions.currentPlatform.databaseURL;
    if (configuredUrl == null || configuredUrl.isEmpty) {
      throw StateError('Firebase Realtime Database URL is not configured.');
    }
    return configuredUrl;
  }
}
