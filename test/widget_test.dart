import 'package:flutter_test/flutter_test.dart';
import 'package:plating_simulator/main.dart';

void main() {
  testWidgets('PlatingSimulatorApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PlatingSimulatorApp());
    expect(find.byType(PlatingSimulatorApp), findsOneWidget);
  });
}
