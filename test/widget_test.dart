import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme/app_theme.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('TaskFlow theme renders in ${mode.name} mode', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: Scaffold(
          appBar: AppBar(title: const Text('TaskFlow')),
          body: Builder(builder: (context) => Text(
            Theme.of(context).brightness == Brightness.dark
                ? 'Dark theme'
                : 'Light theme',
          )),
        ),
      ));
      expect(find.text('TaskFlow'), findsOneWidget);
      expect(find.text(mode == ThemeMode.dark ? 'Dark theme' : 'Light theme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
