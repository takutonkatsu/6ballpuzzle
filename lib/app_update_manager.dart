import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_database_provider.dart';

class AppUpdateRequirement {
  const AppUpdateRequirement({
    required this.required,
    required this.currentBuild,
    required this.minSupportedBuild,
    required this.storeUrl,
    required this.message,
  });

  final bool required;
  final int currentBuild;
  final int minSupportedBuild;
  final String storeUrl;
  final String message;
}

class AppUpdateManager {
  AppUpdateManager._();

  static const Duration _fetchTimeout = Duration(seconds: 4);
  static const String _defaultAndroidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.takutonkatsu.hexagon';

  static Future<AppUpdateRequirement> checkRequirement() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    if (!Platform.isAndroid && !Platform.isIOS) {
      return AppUpdateRequirement(
        required: false,
        currentBuild: currentBuild,
        minSupportedBuild: 0,
        storeUrl: '',
        message: _defaultMessage,
      );
    }

    try {
      final snapshot = await AppFirebaseDatabase.ref()
          .child('appConfig')
          .get()
          .timeout(_fetchTimeout);
      final data =
          snapshot.value is Map ? snapshot.value as Map<dynamic, dynamic> : {};
      final platformKey = Platform.isIOS ? 'ios' : 'android';
      final minSupportedBuild = _intValue(
            _mapValue(data['minSupportedBuild'])?[platformKey],
          ) ??
          _intValue(
            _mapValue(data['forceUpdate'])?[platformKey],
          ) ??
          0;
      final storeUrl = _stringValue(
            _mapValue(data['storeUrl'])?[platformKey],
          ) ??
          (Platform.isAndroid ? _defaultAndroidStoreUrl : '');
      final message = _stringValue(data['updateMessage']) ?? _defaultMessage;

      return AppUpdateRequirement(
        required: minSupportedBuild > 0 && currentBuild < minSupportedBuild,
        currentBuild: currentBuild,
        minSupportedBuild: minSupportedBuild,
        storeUrl: storeUrl,
        message: message,
      );
    } catch (_) {
      return AppUpdateRequirement(
        required: false,
        currentBuild: currentBuild,
        minSupportedBuild: 0,
        storeUrl: '',
        message: _defaultMessage,
      );
    }
  }

  static const String _defaultMessage =
      '新しいバージョンが公開されています。\nアップデートしてからプレイしてください。';

  static Map<dynamic, dynamic>? _mapValue(Object? value) {
    return value is Map ? value : null;
  }

  static int? _intValue(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
