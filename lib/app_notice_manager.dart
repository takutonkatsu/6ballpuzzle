import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_database_provider.dart';
import 'network/server_time_manager.dart';

class AppNotice {
  const AppNotice({
    required this.id,
    required this.title,
    required this.message,
    required this.publishedAtText,
    required this.sortAt,
  });

  final String id;
  final String title;
  final String message;
  final String publishedAtText;
  final int sortAt;
}

class AppNoticeManager {
  AppNoticeManager._();

  static const Duration _fetchTimeout = Duration(seconds: 4);

  static Future<AppNotice?> fetchLatest() async {
    final notices = await fetchActiveNotices();
    return notices.isEmpty ? null : notices.first;
  }

  static Future<List<AppNotice>> fetchActiveNotices() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final platform = Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : 'other';
      final now = await _now();
      final snapshots = await Future.wait([
        AppFirebaseDatabase.ref()
            .child('appConfig/notices')
            .get()
            .timeout(_fetchTimeout),
        AppFirebaseDatabase.ref()
            .child('appConfig/notice')
            .get()
            .timeout(_fetchTimeout),
      ]);

      final rawNotices = <Map<dynamic, dynamic>>[];
      final noticesRaw = snapshots[0].value;
      if (noticesRaw is Map) {
        for (final entry in noticesRaw.entries) {
          if (entry.value is Map) {
            rawNotices.add({
              'id': entry.key.toString(),
              ...Map<dynamic, dynamic>.from(entry.value as Map),
            });
          }
        }
      }
      final legacyRaw = snapshots[1].value;
      if (legacyRaw is Map && legacyRaw['enabled'] == true) {
        rawNotices.add(Map<dynamic, dynamic>.from(legacyRaw));
      }

      final notices = rawNotices
          .map(
            (data) => _noticeFromData(
              data: data,
              currentBuild: currentBuild,
              platform: platform,
              now: now,
            ),
          )
          .whereType<AppNotice>()
          .toList()
        ..sort((a, b) => b.sortAt.compareTo(a.sortAt));
      return notices;
    } catch (_) {
      return const [];
    }
  }

  static AppNotice? _noticeFromData({
    required Map<dynamic, dynamic> data,
    required int currentBuild,
    required String platform,
    required DateTime now,
  }) {
    if (data['enabled'] != true) {
      return null;
    }

    final minBuild = _intValue(data['minBuild']) ?? 0;
    final maxBuild = _intValue(data['maxBuild']);
    if (currentBuild < minBuild) {
      return null;
    }
    if (maxBuild != null && currentBuild > maxBuild) {
      return null;
    }

    final targetPlatforms = _stringListValue(data['platforms']);
    if (targetPlatforms.isNotEmpty &&
        !targetPlatforms.contains(platform) &&
        !targetPlatforms.contains('all')) {
      return null;
    }

    final startsAt = _dateTimeValue(data['startsAt'] ?? data['startAt']);
    final endsAt = _dateTimeValue(data['endsAt'] ?? data['endAt']);
    if (startsAt != null && now.isBefore(startsAt)) {
      return null;
    }
    if (endsAt != null && !now.isBefore(endsAt)) {
      return null;
    }

    final message = _stringValue(data['message']);
    if (message == null) {
      return null;
    }
    final title = _stringValue(data['title']) ?? 'お知らせ';
    final publishedAt =
        _dateTimeValue(data['publishedAt'] ?? data['createdAt']);
    final sortAt =
        (publishedAt ?? startsAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .millisecondsSinceEpoch;
    return AppNotice(
      id: _stringValue(data['id']) ?? '${message.hashCode}_$title',
      title: title,
      message: message,
      publishedAtText: _dateText(publishedAt ?? startsAt),
      sortAt: sortAt,
    );
  }

  static Future<DateTime> _now() async {
    try {
      return await ServerTimeManager.instance.nowJst();
    } catch (_) {
      return DateTime.now();
    }
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return DateTime.tryParse(value.toString().trim());
  }

  static String _dateText(DateTime? value) {
    if (value == null) {
      return '';
    }
    final jst = value.toUtc().add(const Duration(hours: 9));
    return '${jst.year}/${jst.month.toString().padLeft(2, '0')}/'
        '${jst.day.toString().padLeft(2, '0')}';
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

  static List<String> _stringListValue(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final text = _stringValue(value);
    if (text == null) {
      return const [];
    }
    return text
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
