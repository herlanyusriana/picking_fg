import 'package:flutter_test/flutter_test.dart';
import 'package:picking_fg/main.dart';

void main() {
  testWidgets('App loads without error', (WidgetTester tester) async {
    await tester.pumpWidget(const PickingApp());
    expect(find.byType(PickingApp), findsOneWidget);
  });
}
