import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/features/tasks/data/personal_task_draft.dart';

void main() {
  late Directory directory; late PersonalTaskDraftStore store;
  const id = 'abcdefghijklmnopqrst';
  PersonalTaskDraft draft(String title) => PersonalTaskDraft(taskId: id, title: title, description: 'Details', priority: 'high', deadline: DateTime(2026, 11, 7));
  File target(String uid) { final key = base64Url.encode(utf8.encode(uid)).replaceAll('=', ''); return File('${directory.path}${Platform.pathSeparator}taskflow_drafts${Platform.pathSeparator}$key.json'); }
  setUp(() async { directory = await Directory.systemTemp.createTemp('taskflow-draft-test-'); store = PersonalTaskDraftStore(directory: () async => directory); });
  tearDown(() async { await store.queue; await directory.delete(recursive: true); });
  test('draft round trip preserves fields and local deadline', () async {
    await store.save('a', draft('Report')); final value = (await store.load('a'))!;
    expect(value.taskId, id); expect(value.title, 'Report'); expect(value.description, 'Details'); expect(value.priority, 'high'); expect(value.deadline, DateTime(2026, 11, 7));
  });
  test('accounts have separate drafts', () async {
    await store.save('a', draft('A')); await store.save('b', draft('B'));
    expect((await store.load('a'))!.title, 'A'); expect((await store.load('b'))!.title, 'B');
  });
  test('clearing one account does not remove another draft', () async {
    await store.save('a', draft('A')); await store.save('b', draft('B')); await store.clear('a');
    expect(await store.load('a'), isNull); expect((await store.load('b'))!.title, 'B');
  });
  test('queued saves preserve their order', () async {
    final first = store.save('a', draft('First')); final second = store.save('a', draft('Last')); await Future.wait([first, second]);
    expect((await store.load('a'))!.title, 'Last');
  });
  test('clear runs after an already queued save', () async {
    final saved = store.save('a', draft('A')); final cleared = store.clear('a'); await Future.wait([saved, cleared]);
    expect(await store.load('a'), isNull);
  });
  test('corrupt primary draft produces an error instead of silent deletion', () async {
    await store.save('a', draft('A')); await target('a').writeAsString('broken');
    await expectLater(store.load('a'), throwsFormatException); expect(await target('a').exists(), isTrue);
  });
  test('complete temporary file can be recovered after interrupted rename', () async {
    await store.save('a', draft('Old')); await File('${target('a').path}.tmp').writeAsString(jsonEncode(draft('New').toMap()), flush: true);
    expect((await store.load('a'))!.title, 'New');
  });
  test('unsupported version and invalid document ID are rejected', () {
    expect(() => PersonalTaskDraft.fromMap({...draft('A').toMap(), 'version': 99}), throwsFormatException);
    expect(() => PersonalTaskDraft.fromMap({...draft('A').toMap(), 'taskId': '../other'}), throwsFormatException);
  });
}
