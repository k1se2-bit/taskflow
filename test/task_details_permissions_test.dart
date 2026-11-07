import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/features/tasks/presentation/task_details_page.dart' show detailsCanEdit, detailsCanChangeStatus, detailsCanRemind;

void main() {
  final team = <String, dynamic>{'ownerId': 'owner', 'memberIds': ['owner', 'member', 'other']};
  final task = <String, dynamic>{'assignedTo': 'member', 'status': 'todo'};
  test('personal owner can edit', () { expect(detailsCanEdit('member', personalOwner: 'member'), isTrue); });
  test('another user cannot edit a personal task', () { expect(detailsCanEdit('other', personalOwner: 'member'), isFalse); });
  test('team owner can edit', () { expect(detailsCanEdit('owner', team: team), isTrue); });
  test('assignee cannot edit team task fields', () { expect(detailsCanEdit('member', team: team), isFalse); });
  test('assignee can change status', () { expect(detailsCanChangeStatus('member', task, team: team), isTrue); });
  test('another team member cannot change status', () { expect(detailsCanChangeStatus('other', task, team: team), isFalse); });
  test('owner cannot set a reminder for another assignee', () { expect(detailsCanRemind('owner', task, team: team), isFalse); });
  test('assignee can configure a personal reminder', () { expect(detailsCanRemind('member', task, team: team), isTrue); });
  test('removed assignee has no reminder control', () { expect(detailsCanRemind('member', task, team: {'ownerId': 'owner', 'memberIds': ['owner']}), isFalse); });
  test('missing team denies team controls', () { expect(detailsCanEdit('member'), isFalse); expect(detailsCanChangeStatus('member', task), isFalse); expect(detailsCanRemind('member', task), isFalse); });
}
