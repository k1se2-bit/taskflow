import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/features/tasks/presentation/today_app.dart' show todaySection, todaySearchMatches;

void main() {
  final now = DateTime(2026, 11, 5, 12);
  Map<String, dynamic> task(DateTime? date, [String status = 'todo']) => {'title': 'Prepare Report', 'description': 'Team results', 'status': status, 'deadline': date == null ? null : Timestamp.fromDate(date)};
  test('unfinished tasks before today are overdue', () {
    expect(todaySection(task(DateTime(2026, 11, 4)), now), 'overdue');
  });
  test('today includes all times of the same calendar day', () {
    expect(todaySection(task(DateTime(2026, 11, 5, 23, 59)), now), 'today');
    expect(todaySection(task(DateTime(2026, 11, 5)), now), 'today');
  });
  test('future tasks are upcoming', () {
    expect(todaySection(task(DateTime(2026, 11, 6)), now), 'upcoming');
  });
  test('tasks without dates have their own section', () {
    expect(todaySection(task(null), now), 'noDate');
  });
  test('invalid deadlines do not crash grouping', () {
    expect(todaySection({'deadline': 'invalid', 'status': 'todo'}, now), 'noDate');
  });
  test('completed tasks are excluded regardless of deadline', () {
    expect(todaySection(task(DateTime(2026, 11, 4), 'done'), now), isNull);
    expect(todaySection(task(null, 'done'), now), isNull);
  });
  test('search matches task text without case or outer whitespace', () {
    expect(todaySearchMatches(task(null), 'Personal', ' REPORT '), isTrue);
    expect(todaySearchMatches(task(null), 'Personal', 'results'), isTrue);
    expect(todaySearchMatches(task(null), 'Personal', 'absent'), isFalse);
  });
  test('search also matches team names', () {
    expect(todaySearchMatches(task(null), 'Design team', 'design'), isTrue);
  });
}
