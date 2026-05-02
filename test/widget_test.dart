import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:six_ball_puzzle/ui/home_screen.dart';

void main() {
  testWidgets('home screen shows ranked match entry points', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          bootstrapData: HomeBootstrapData(playerName: '', rating: 1000),
        ),
      ),
    );

    expect(find.text('ランク戦'), findsOneWidget);
  });
}
