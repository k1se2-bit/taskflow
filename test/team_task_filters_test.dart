import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/features/teams/team_tasks.dart' show teamTaskMatches, teamTaskIsOverdue, memberLabel;

void main() {
  final now = DateTime(2026, 11, 5, 12);
  final task = <String, dynamic>{'title': 'Prepare Report', 'description': 'Review team results', 'status': 'inProgress', 'assignedTo': 'alice', 'deadline': Timestamp.fromDate(DateTime(2026, 11, 4))};
  test('search is case insensitive and trims whitespace', () {
    expect(teamTaskMatches(task, search: '  REPORT  ', now: now), isTrue);
  });
  test('search includes descriptions', () {
    expect(teamTaskMatches(task, search: 'team results', now: now), isTrue);
  });
  test('search excludes unmatched text', () {
    expect(teamTaskMatches(task, search: 'absent', now: now), isFalse);
  });
  test('status filter excludes other statuses', () {
    expect(teamTaskMatches(task, status: 'done', now: now), isFalse);
  });
  test('assignee filter uses UID', () {
    expect(teamTaskMatches(task, assignee: 'alice', now: now), isTrue);
    expect(teamTaskMatches(task, assignee: 'bob', now: now), isFalse);
  });
  test('all filters combine', () {
    expect(teamTaskMatches(task, search: 'report', status: 'inProgress', assignee: 'alice', overdueOnly: true, now: now), isTrue);
  });
  test('completed tasks are not overdue', () {
    expect(teamTaskIsOverdue({...task, 'status': 'done'}, now), isFalse);
  });
  test('today is not overdue even if its time has passed', () {
    expect(teamTaskIsOverdue({...task, 'deadline': Timestamp.fromDate(DateTime(2026, 11, 5))}, now), isFalse);
  });
  test('tasks without deadlines are not overdue', () {
    expect(teamTaskIsOverdue({...task, 'deadline': null}, now), isFalse);
  });
  test('short unknown UIDs are handled safely', () {
    expect(memberLabel({}, 'abc', 'owner'), 'Участник abc');
  });
  test('duplicate member names include an identifying suffix', () {
    const names = {'alice001': 'Alex', 'bob00001': 'Alex'};
    expect(memberLabel(names, 'alice001', 'owner'), contains('alice0'));
    expect(memberLabel(names, 'bob00001', 'owner'), contains('bob000'));
  });
  test('current user is marked without a saved name', () {
    expect(memberLabel({}, 'owner', 'owner'), 'Я');
  });
}
