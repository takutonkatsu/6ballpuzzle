class RankedSeasonManager {
  RankedSeasonManager._();

  static const String baseSeasonId = '2026-05';
  static const int baseSeasonNumber = 0;
  static const int seasonEndHourJst = 21;

  static final RegExp _seasonIdPattern = RegExp(r'^(\d{4})-(\d{2})$');

  static String currentSeasonId({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      throw StateError('currentSeasonId requires server based JST time.');
    }
    final end = _seasonEndForMonth(now.year, now.month);
    final seasonMonth = now.isBefore(end) ? now.month : _nextMonth(now.month);
    final seasonYear =
        now.isBefore(end) || now.month < 12 ? now.year : now.year + 1;
    return _formatSeasonId(seasonYear, seasonMonth);
  }

  static String previousSeasonId(String seasonId) {
    final parsed = _parseSeasonId(seasonId);
    if (parsed == null) {
      return baseSeasonId;
    }
    final year = parsed.$1;
    final month = parsed.$2;
    if (month == 1) {
      return _formatSeasonId(year - 1, 12);
    }
    return _formatSeasonId(year, month - 1);
  }

  static String seasonName(String seasonId) {
    final number = seasonNumber(seasonId);
    return 'シーズン$number';
  }

  static int seasonNumber(String seasonId) {
    final base = _parseSeasonId(baseSeasonId);
    final target = _parseSeasonId(seasonId);
    if (base == null || target == null) {
      return baseSeasonNumber;
    }
    final diff = (target.$1 - base.$1) * 12 + (target.$2 - base.$2);
    return baseSeasonNumber + diff;
  }

  static DateTime seasonEndJst(String seasonId) {
    final parsed = _parseSeasonId(seasonId);
    if (parsed == null) {
      return _seasonEndForMonth(2026, 5);
    }
    return _seasonEndForMonth(parsed.$1, parsed.$2);
  }

  static DateTime seasonStartJst(String seasonId) {
    return seasonEndJst(previousSeasonId(seasonId));
  }

  static Duration remaining({DateTime? nowJstOverride}) {
    final now = nowJstOverride;
    if (now == null) {
      throw StateError('remaining requires server based JST time.');
    }
    final end = seasonEndJst(currentSeasonId(nowJstOverride: now));
    final remaining = end.difference(now);
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

  static bool isCurrentSeason(String seasonId, {DateTime? nowJstOverride}) {
    if (nowJstOverride == null) {
      throw StateError('isCurrentSeason requires server based JST time.');
    }
    return seasonId == currentSeasonId(nowJstOverride: nowJstOverride);
  }

  static DateTime _seasonEndForMonth(int year, int month) {
    final nextMonth =
        month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1)).day;
    return DateTime(year, month, lastDay, seasonEndHourJst);
  }

  static int _nextMonth(int month) => month == 12 ? 1 : month + 1;

  static String _formatSeasonId(int year, int month) {
    return '$year-${month.toString().padLeft(2, '0')}';
  }

  static (int, int)? _parseSeasonId(String seasonId) {
    final match = _seasonIdPattern.firstMatch(seasonId);
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    if (year == null || month == null || month < 1 || month > 12) {
      return null;
    }
    return (year, month);
  }
}
