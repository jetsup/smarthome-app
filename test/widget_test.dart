import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarthome_app/main.dart';

void main() {
  testWidgets('App renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmartHomeApp()));
    await tester.pumpAndSettle();
    expect(find.byType(SmartHomeApp), findsOneWidget);
  });
}
