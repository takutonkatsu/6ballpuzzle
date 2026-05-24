import 'package:flutter_test/flutter_test.dart';
import 'package:six_ball_puzzle/network/ranked_season_manager.dart';

void main() {
  group('RankedSeasonManager', () {
    test('uses month-end 21:00 JST as the season boundary', () {
      expect(
        RankedSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 5, 31, 12),
        ),
        '2026-05',
      );
      expect(
        RankedSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 5, 31, 20, 59, 59),
        ),
        '2026-05',
      );
      expect(
        RankedSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 5, 31, 21),
        ),
        '2026-06',
      );
      expect(
        RankedSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 6, 30, 20, 59, 59),
        ),
        '2026-06',
      );
      expect(
        RankedSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 6, 30, 21),
        ),
        '2026-07',
      );
    });

    test('labels 2026-05 as season 0 and increments monthly', () {
      expect(RankedSeasonManager.seasonName('2026-05'), 'シーズン0');
      expect(RankedSeasonManager.seasonName('2026-06'), 'シーズン1');
      expect(RankedSeasonManager.seasonName('2027-05'), 'シーズン12');
    });

    test('formats remaining time by day, hour, minute, then second', () {
      expect(
        RankedSeasonManager.remainingLabel(
          nowJstOverride: DateTime(2026, 5, 30, 20, 59, 59),
        ),
        '残り1日',
      );
      expect(
        RankedSeasonManager.remainingLabel(
          nowJstOverride: DateTime(2026, 5, 31, 1),
        ),
        '残り20時間',
      );
      expect(
        RankedSeasonManager.remainingLabel(
          nowJstOverride: DateTime(2026, 5, 31, 20, 30),
        ),
        '残り30分',
      );
      expect(
        RankedSeasonManager.remainingLabel(
          nowJstOverride: DateTime(2026, 5, 31, 20, 59, 30),
        ),
        '残り30秒',
      );
    });
  });
}
