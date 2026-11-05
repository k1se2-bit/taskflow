import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/features/tasks/presentation/calendar_app.dart' show calendarMatches;

void main() {
  final day = DateTime(2026, 11, 5);
  Map<String, dynamic> task(DateTime? deadline, [String status = 'todo']) => {
    'deadline': deadline == null ? null : Timestamp.fromDate(deadline),
    'status': status,
  };

  group('Calendar date and status filters', () {
    test('includes a task on the selected day regardless of time', () {
      expect(calendarMatches(task(DateTime(2026, 11, 5, 23, 59)), day, 'all', false), isTrue);
    });
    test('excludes a task on another day', () {
      expect(calendarMatches(task(DateTime(2026, 11, 6)), day, 'all', false), isFalse);
    });
    test('excludes a task without a deadline', () {
      expect(calendarMatches(task(null), day, 'all', false), isFalse);
    });
    test('excludes an invalid deadline without throwing', () {
      expect(calendarMatches({'deadline': 'invalid', 'status': 'todo'}, day, 'all', false), isFalse);
    });
    test('active filter includes new and in-progress tasks', () {
      for (final status in ['todo', 'inProgress']) {
        expect(calendarMatches(task(day, status), day, 'active', false), isTrue);
      }
    });
    test('active filter excludes completed tasks', () {
      expect(calendarMatches(task(day, 'done'), day, 'active', false), isFalse);
    });
    test('done filter includes only completed tasks', () {
      expect(calendarMatches(task(day, 'done'), day, 'done', false), isTrue);
      expect(calendarMatches(task(day), day, 'done', false), isFalse);
    });
    test('all filter includes completed tasks', () {
      expect(calendarMatches(task(day, 'done'), day, 'all', false), isTrue);
    });
  });

  group('Overdue filter', () {
    test('includes unfinished tasks from the past regardless of selected day', () {
      expect(calendarMatches(task(DateTime(2000, 1, 1)), day, 'active', true), isTrue);
    });
    test('excludes completed tasks from the past', () {
      expect(calendarMatches(task(DateTime(2000, 1, 1), 'done'), day, 'all', true), isFalse);
    });
    test('excludes tasks with a future deadline', () {
      final now = DateTime.now();
      expect(calendarMatches(task(DateTime(now.year + 1, 1, 1)), day, 'active', true), isFalse);
    });
    test('excludes tasks without a deadline', () {
      expect(calendarMatches(task(null), day, 'active', true), isFalse);
    });
  });
}
