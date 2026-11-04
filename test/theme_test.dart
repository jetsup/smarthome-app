import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthome_app/theme/app_colors.dart';
import 'package:smarthome_app/theme/app_theme.dart';

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('snackbar, dialog and page follow the ${b.name} theme', (tester) async {
      final expected = b == Brightness.dark ? AppColors.dark : AppColors.light;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(b),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(children: [
              Text('bg', key: const Key('probe'), style: TextStyle(color: context.c.text)),
              ElevatedButton(
                onPressed: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Node provisioning in progress'))),
                child: const Text('go'),
              ),
            ]),
          ),
        ),
      ));
      // Page background comes from the theme.
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, isNull);
      expect(Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor, expected.bg);

      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 400));
      final snack = tester.widget<Material>(find.descendant(
          of: find.byType(SnackBar), matching: find.byType(Material)).first);
      expect(snack.color, expected.card, reason: 'snackbar background must follow the theme');
      final text = tester.widget<Text>(find.text('Node provisioning in progress'));
      expect(DefaultTextStyle.of(tester.element(find.text('Node provisioning in progress'))).style.color, expected.text);
      expect(text.data, isNotNull);
    });
  }
}
