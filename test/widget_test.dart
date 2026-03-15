import 'package:flutter_test/flutter_test.dart';
import 'package:realtime/main.dart';

void main() {
  testWidgets('App should show S-LOG splash', (WidgetTester tester) async {
    await tester.pumpWidget(const RealtimeApp());

    expect(find.text('S'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    expect(find.text('Loading Studio'), findsOneWidget);
  });
}
