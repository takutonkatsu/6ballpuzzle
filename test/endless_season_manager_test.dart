import 'package:flutter_test/flutter_test.dart';
import 'package:six_ball_puzzle/network/endless_season_manager.dart';

void main() {
  group('EndlessSeasonManager', () {
    test('uses Monday 21:00 JST as the weekly boundary', () {
      expect(
        EndlessSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 6, 22, 20, 59, 59),
        ),
        '2026-W25',
      );
      expect(
        EndlessSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 6, 22, 21),
        ),
        '2026-W26',
      );
      expect(
        EndlessSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 6, 29, 20, 59, 59),
        ),
        '2026-W26',
      );
      expect(
        EndlessSeasonManager.currentSeasonId(
          nowJstOverride: DateTime(2026, 6, 29, 21),
        ),
        '2026-W27',
      );
    });

    test('formats remaining time until the next endless season boundary', () {
      expect(
        EndlessSeasonManager.remainingLabel(
          nowJstOverride: DateTime(2026, 6, 28, 20, 59, 59),
        ),
        '残り1日',
      );
      expect(
        EndlessSeasonManager.remainingLabel(
          nowJstOverride: DateTime(2026, 6, 29, 20, 30),
        ),
        '残り30分',
      );
      expect(
        EndlessSeasonManager.remainingLabel(
          nowJstOverride: DateTime(2026, 6, 29, 20, 59, 30),
        ),
        '残り30秒',
      );
    });

    test('uses a weekly date range label for the endless season name', () {
      expect(
        EndlessSeasonManager.seasonName('2026-W26'),
        '2026年6/22-6/29期',
      );
      expect(
        EndlessSeasonManager.seasonName('2026-W53'),
        '2026年12/28-2027年1/4期',
      );
    });

    test('locks endless for 30 minutes after the boundary', () {
      expect(
        EndlessSeasonManager.isTransitionLocked(
          nowJstOverride: DateTime(2026, 6, 22, 20, 59, 59),
        ),
        isFalse,
      );
      expect(
        EndlessSeasonManager.isTransitionLocked(
          nowJstOverride: DateTime(2026, 6, 22, 21, 29, 59),
        ),
        isTrue,
      );
      expect(
        EndlessSeasonManager.isTransitionLocked(
          nowJstOverride: DateTime(2026, 6, 22, 21, 30),
        ),
        isFalse,
      );
    });
  });
}
