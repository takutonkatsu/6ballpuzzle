import 'dart:async' show runZonedGuarded;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin/admin_app.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('Admin runtime error: ${details.exception}');
        if (details.stack != null) {
          debugPrintStack(stackTrace: details.stack);
        }
      };
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      runApp(const AdminApp());
    },
    (error, stackTrace) {
      debugPrint('Uncaught admin error: $error');
      debugPrintStack(stackTrace: stackTrace);
    },
  );
}
