import 'package:flutter_test/flutter_test.dart';
import 'package:six_ball_puzzle/main.dart';

void main() {
  testWidgets('home screen shows ranked match entry points', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('6-BALL PUZZLE'), findsOneWidget);
    expect(find.text('Rating: ...'), findsOneWidget);
    expect(find.text('RANDOM MATCH'), findsOneWidget);
  });
}
