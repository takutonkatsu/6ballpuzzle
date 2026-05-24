import 'package:flutter_test/flutter_test.dart';
import 'package:six_ball_puzzle/network/ranking_manager.dart';

void main() {
  group('RankingManager', () {
    test('formats daily remaining time until midnight JST', () {
      expect(
        RankingManager.dailyRemainingLabel(
          nowJstOverride: DateTime(2026, 5, 19, 16, 37, 52),
        ),
        '残り7時間',
      );
      expect(
        RankingManager.dailyRemainingLabel(
          nowJstOverride: DateTime(2026, 5, 19, 23, 59, 30),
        ),
        '残り30秒',
      );
      expect(
        RankingManager.dailyRemainingLabel(
          nowJstOverride: DateTime(2026, 5, 20),
        ),
        '残り24時間',
      );
    });
  });
}
