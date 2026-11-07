import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/features/tasks/presentation/reminder_preference_panel.dart';

Widget host(Stream<Map<String, dynamic>?> stream) => MaterialApp(home: Scaffold(body: ReminderPreferencePanel(stream: stream, preferenceKey: 'team_task', builder: (value) => Text(value == null ? 'not-set' : 'saved:$value'))));
void main() {
  testWidgets('nonexistent user document is a loaded empty preference', (tester) async {
    await tester.pumpWidget(host(Stream<Map<String, dynamic>?>.value(null)));
    await tester.pumpAndSettle();
    expect(find.text('not-set'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets('missing reminder map is also a loaded preference', (tester) async {
    await tester.pumpWidget(host(Stream<Map<String, dynamic>?>.value({})));
    await tester.pumpAndSettle();
    expect(find.text('not-set'), findsOneWidget);
  });
  testWidgets('saved reminder is rendered', (tester) async {
    await tester.pumpWidget(host(Stream<Map<String, dynamic>?>.value({'teamReminders': {'team_task': {'remindAt': 42}}})));
    await tester.pumpAndSettle();
    expect(find.text('saved:42'), findsOneWidget);
  });
  testWidgets('silent stream stops showing an infinite spinner', (tester) async {
    final controller = StreamController<Map<String, dynamic>?>.broadcast();
    await tester.pumpWidget(host(controller.stream));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Повторить загрузку'), findsOneWidget);
    controller.add({}); await tester.pump();
    expect(find.text('not-set'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await controller.close();
  });
  testWidgets('stream errors show retry instead of a spinner', (tester) async {
    final controller = StreamController<Map<String, dynamic>?>.broadcast();
    await tester.pumpWidget(host(controller.stream));
    controller.addError(StateError('offline')); await tester.pump();
    expect(find.text('Повторить загрузку'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Повторить загрузку')); await tester.pump();
    controller.add({}); await tester.pump();
    expect(find.text('not-set'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await controller.close();
  });
  testWidgets('keyed preference state survives sibling insertion', (tester) async {
    var listens = 0;
    final controller = StreamController<Map<String, dynamic>?>.broadcast(onListen: () { listens++; });
    final extra = ValueNotifier<bool>(false);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<bool>(valueListenable: extra, builder: (_, show, __) => Column(children: [
      if (show) const Text('Other content'),
      ReminderPreferencePanel(key: const ValueKey('stable'), stream: controller.stream, preferenceKey: 'team_task', builder: (value) => Text('value:$value')),
    ])))));
    controller.add({'teamReminders': {'team_task': {'remindAt': 42}}}); await tester.pump();
    extra.value = true; await tester.pump();
    expect(find.text('value:42'), findsOneWidget); expect(listens, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox()); await controller.close(); extra.dispose();
  });
}
