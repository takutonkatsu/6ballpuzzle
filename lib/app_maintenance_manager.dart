import 'firebase_database_provider.dart';
import 'network/endless_season_manager.dart';
import 'network/ranked_season_manager.dart';
import 'network/server_time_manager.dart';

enum MaintenanceMode {
  ranked,
  endless,
  friend,
  cpu,
  arena,
}

class MaintenanceNotice {
  const MaintenanceNotice({
    required this.enabled,
    required this.title,
    required this.message,
    this.expectedEndAt,
  });

  final bool enabled;
  final String title;
  final String message;
  final DateTime? expectedEndAt;

  bool get hasExpectedEndAt => expectedEndAt != null;

  static const MaintenanceNotice disabled = MaintenanceNotice(
    enabled: false,
    title: '',
    message: '',
  );

  factory MaintenanceNotice.fromMap(
    Object? raw, {
    required String defaultTitle,
    required String defaultMessage,
  }) {
    if (raw is! Map) {
      return disabled;
    }
    final data = Map<dynamic, dynamic>.from(raw);
    final enabled =
        _boolValue(data['enabled']) || _boolValue(data['matchmakingDisabled']);
    if (!enabled) {
      return disabled;
    }
    final startsAt = _dateTimeValue(data['startsAt']);
    if (startsAt != null && DateTime.now().isBefore(startsAt)) {
      return disabled;
    }
    return MaintenanceNotice(
      enabled: true,
      title: _stringValue(data['title']) ?? defaultTitle,
      message: _stringValue(data['message']) ?? defaultMessage,
      expectedEndAt: _dateTimeValue(data['expectedEndAt']),
    );
  }

  static bool _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is num) {
      final millis = value.toInt();
      if (millis <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final millis = int.tryParse(text);
    if (millis != null && millis > 0) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return DateTime.tryParse(text);
  }
}

class AppMaintenanceManager {
  AppMaintenanceManager._();

  static const Duration _fetchTimeout = Duration(seconds: 4);
  static const Duration modeTransitionLockDuration = Duration(minutes: 30);

  static Future<MaintenanceNotice> fetchGlobalMaintenance() async {
    try {
      final snapshot = await AppFirebaseDatabase.ref()
          .child('appConfig/maintenance/global')
          .get()
          .timeout(_fetchTimeout);
      return MaintenanceNotice.fromMap(
        snapshot.value,
        defaultTitle: 'メンテナンス中',
        defaultMessage: '現在メンテナンス中です。しばらく時間をおいてから再度お試しください。',
      );
    } catch (_) {
      return MaintenanceNotice.disabled;
    }
  }

  static Future<MaintenanceNotice> checkModeAvailability(
    MaintenanceMode mode,
  ) async {
    final manual = await _fetchModeMaintenance(mode);
    if (manual.enabled) {
      return manual;
    }

    try {
      final nowJst = await ServerTimeManager.instance.nowJst();
      switch (mode) {
        case MaintenanceMode.ranked:
          if (RankedSeasonManager.isTransitionLocked(
            nowJstOverride: nowJst,
          )) {
            return const MaintenanceNotice(
              enabled: true,
              title: 'シーズン集計中',
              message: 'ランキングとレートを集計しています。21:30ごろ再開予定です。',
            );
          }
        case MaintenanceMode.endless:
          if (EndlessSeasonManager.isTransitionLocked(
            nowJstOverride: nowJst,
          )) {
            return const MaintenanceNotice(
              enabled: true,
              title: 'ランキング集計中',
              message: 'エンドレスランキングを集計しています。しばらくお待ちください。',
            );
          }
        case MaintenanceMode.friend:
        case MaintenanceMode.cpu:
        case MaintenanceMode.arena:
          break;
      }
    } catch (_) {
      return MaintenanceNotice.disabled;
    }
    return MaintenanceNotice.disabled;
  }

  static Future<MaintenanceNotice> _fetchModeMaintenance(
    MaintenanceMode mode,
  ) async {
    try {
      final snapshot = await AppFirebaseDatabase.ref()
          .child('appConfig/maintenance/modes/${mode.name}')
          .get()
          .timeout(_fetchTimeout);
      return MaintenanceNotice.fromMap(
        snapshot.value,
        defaultTitle: 'メンテナンス中',
        defaultMessage: switch (mode) {
          MaintenanceMode.ranked => '現在ランク戦はメンテナンス中です。完了までしばらくお待ちください。',
          MaintenanceMode.endless => '現在エンドレスはメンテナンス中です。完了までしばらくお待ちください。',
          MaintenanceMode.friend => '現在フレンド対戦はメンテナンス中です。完了までしばらくお待ちください。',
          MaintenanceMode.cpu => '現在コンピュータ対戦はメンテナンス中です。完了までしばらくお待ちください。',
          MaintenanceMode.arena => '現在アリーナはメンテナンス中です。完了までしばらくお待ちください。',
        },
      );
    } catch (_) {
      return MaintenanceNotice.disabled;
    }
  }
}
