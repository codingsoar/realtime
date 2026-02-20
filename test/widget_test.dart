import 'package:flutter_test/flutter_test.dart';
import 'package:realtime/main.dart';

void main() {
  testWidgets('App should show splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RealtimeApp());

    expect(find.text('Realtime'), findsOneWidget);
    expect(find.text('Track your focused study time'), findsOneWidget);
  });
}
