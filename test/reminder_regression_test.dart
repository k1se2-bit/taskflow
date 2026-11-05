import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/features/notifications/reminders_app.dart' show ReminderEngine, reminderKey, reminderTime;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('test callback has the Future<void> function signature', () {
    final Future<void> Function() callback = ReminderEngine.instance.test;
    expect(callback, isNotNull);
  });
  test('counter refresh has the Future<void> function signature', () {
    final Future<void> Function() callback = ReminderEngine.instance.updatePendingCount;
    expect(callback, isNotNull);
  });
  test('notification identifiers are deterministic and nonzero', () {
    final engine = ReminderEngine.instance;
    final first = engine.identifier('users/u/tasks/task1', false);
    expect(first, engine.identifier('users/u/tasks/task1', false));
    expect(first, greaterThan(0));
    expect(first, lessThan(0x40000000));
  });
  test('personal and team notification ID ranges do not overlap', () {
    final engine = ReminderEngine.instance;
    final personal = engine.identifier('same-path', false);
    final team = engine.identifier('same-path', true);
    expect(team, isNot(personal));
    expect(team, greaterThanOrEqualTo(0x40000000));
    expect(team, lessThanOrEqualTo(0x7fffffff));
  });
  test('same task ID in different teams has different preference keys', () {
    expect(reminderKey('teamA', 'task1'), isNot(reminderKey('teamB', 'task1')));
  });
  test('missing reminder timestamp is displayed safely', () {
    expect(reminderTime(null), 'Напоминание не задано');
    expect(reminderTime('invalid'), 'Напоминание не задано');
  });
}
