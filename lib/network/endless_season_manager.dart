class EndlessSeasonManager {
  EndlessSeasonManager._();

  static const int seasonSwitchWeekdayJst = DateTime.monday;
  static const int seasonSwitchHourJst = 21;
  static const Duration transitionLockDuration = Duration(minutes: 30);

  static final RegExp _seasonIdPattern = RegExp(r'^(\d{4})-W(\d{2})$');

  static String currentSeasonId({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      throw StateError('currentSeasonId requires server based JST time.');
    }
    return _formatSeasonId(_weekStartFor(_wallClockUtc(now)));
  }

  static String previousSeasonId(String seasonId) {
    final start = _startDateForSeasonId(seasonId);
    if (start == null) {
      return '';
    }
    return _formatSeasonId(start.subtract(const Duration(days: 7)));
  }

  static String seasonName(String seasonId) {
    final start = seasonStartJst(seasonId);
    final end = seasonEndJst(seasonId);
    if (start.year == end.year) {
      return '${start.year}年${start.month}/${start.day}-${end.month}/${end.day}期';
    }
    return '${start.year}年${start.month}/${start.day}-${end.year}年${end.month}/${end.day}期';
  }

  static DateTime seasonStartJst(String seasonId) {
    final start = _startDateForSeasonId(seasonId);
    return start == null
        ? DateTime.utc(2026, 6, 22, seasonSwitchHourJst)
        : DateTime.utc(
            start.year,
            start.month,
            start.day,
            seasonSwitchHourJst,
          );
  }

  static DateTime seasonEndJst(String seasonId) {
    return seasonStartJst(seasonId).add(const Duration(days: 7));
  }

  static Duration remaining({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      throw StateError('remaining requires server based JST time.');
    }
    final current = currentSeasonId(nowJstOverride: now);
    final end = seasonEndJst(current);
    final remaining = end.difference(_wallClockUtc(now));
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static String remainingLabel({DateTime? nowJstOverride}) {
    final value = remaining(nowJstOverride: nowJstOverride);
    if (value.inDays >= 1) {
      return '残り${value.inDays}日';
    }
    if (value.inHours >= 1) {
      return '残り${value.inHours}時間';
    }
    if (value.inMinutes >= 1) {
      return '残り${value.inMinutes}分';
    }
    return '残り${value.inSeconds}秒';
  }

  static bool isTransitionLocked({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      throw StateError('isTransitionLocked requires server based JST time.');
    }
    final wallClockNow = _wallClockUtc(now);
    final start = seasonStartJst(currentSeasonId(nowJstOverride: now));
    final elapsed = wallClockNow.difference(start);
    return !elapsed.isNegative && elapsed < transitionLockDuration;
  }

  static DateTime _wallClockUtc(DateTime value) {
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  static DateTime _weekStartFor(DateTime wallClockNow) {
    final dayStart = DateTime.utc(
      wallClockNow.year,
      wallClockNow.month,
      wallClockNow.day,
    );
    final monday = dayStart.subtract(
      Duration(days: dayStart.weekday - seasonSwitchWeekdayJst),
    );
    final switchAt = DateTime.utc(
      monday.year,
      monday.month,
      monday.day,
      seasonSwitchHourJst,
    );
    if (wallClockNow.isBefore(switchAt)) {
      return monday.subtract(const Duration(days: 7));
    }
    return monday;
  }

  static String _formatSeasonId(DateTime weekStart) {
    final weekYear = _isoWeekYear(weekStart);
    final week = _isoWeekNumber(weekStart);
    return '$weekYear-W${week.toString().padLeft(2, '0')}';
  }

  static DateTime? _startDateForSeasonId(String seasonId) {
    final match = _seasonIdPattern.firstMatch(seasonId);
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1) ?? '');
    final week = int.tryParse(match.group(2) ?? '');
    if (year == null || week == null || week < 1 || week > 53) {
      return null;
    }
    final jan4 = DateTime.utc(year, 1, 4);
    final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return week1Monday.add(Duration(days: (week - 1) * 7));
  }

  static int _isoWeekYear(DateTime date) {
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    return thursday.year;
  }

  static int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    final firstThursday = DateTime.utc(thursday.year, 1, 4);
    final diff = thursday.difference(firstThursday).inDays;
    return 1 + ((diff + firstThursday.weekday - 1) ~/ 7);
  }
}
