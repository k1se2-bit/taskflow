import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PersonalTaskDraft {
  const PersonalTaskDraft({required this.taskId, required this.title, required this.description, required this.priority, this.deadline});
  final String taskId;
  final String title;
  final String description;
  final String priority;
  final DateTime? deadline;
  bool get isEmpty => title.isEmpty && description.isEmpty && priority == 'medium' && deadline == null;
  Map<String, dynamic> toMap() => {'version': 1, 'taskId': taskId, 'title': title, 'description': description, 'priority': priority, 'deadline': deadline?.toIso8601String()};
  factory PersonalTaskDraft.fromMap(Map<String, dynamic> value) {
    final id = value['taskId']; final date = value['deadline'];
    if (value['version'] != 1 || id is! String || !RegExp(r'^[a-zA-Z0-9]{20}$').hasMatch(id) || value['title'] is! String || value['description'] is! String || !['low', 'medium', 'high'].contains(value['priority']) || (date != null && (date is! String || DateTime.tryParse(date) == null))) throw const FormatException('Invalid personal task draft');
    return PersonalTaskDraft(taskId: id, title: value['title'] as String, description: value['description'] as String, priority: value['priority'] as String, deadline: date == null ? null : DateTime.parse(date as String));
  }
}

class PersonalTaskDraftStore {
  PersonalTaskDraftStore({Future<Directory> Function()? directory}) : directory = directory ?? getApplicationSupportDirectory;
  static final instance = PersonalTaskDraftStore();
  final Future<Directory> Function() directory;
  Future<void> queue = Future<void>.value();
  Future<T> serial<T>(Future<T> Function() action) {
    final result = queue.then((_) => action());
    queue = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }
  Future<File> file(String uid) async {
    if (uid.isEmpty) throw ArgumentError('UID is required');
    final root = await directory();
    final folder = Directory('${root.path}${Platform.pathSeparator}taskflow_drafts');
    await folder.create(recursive: true);
    final key = base64Url.encode(utf8.encode(uid)).replaceAll('=', '');
    return File('${folder.path}${Platform.pathSeparator}$key.json');
  }
  Future<PersonalTaskDraft> decode(File value) async {
    final data = jsonDecode(await value.readAsString());
    if (data is! Map) throw const FormatException('Invalid draft document');
    return PersonalTaskDraft.fromMap(Map<String, dynamic>.from(data));
  }
  Future<PersonalTaskDraft?> load(String uid) => serial(() async {
    final target = await file(uid); final temporary = File('${target.path}.tmp');
    if (await temporary.exists()) {
      try { return await decode(temporary); } on FormatException { /* Keep the previous complete file. */ }
    }
    return await target.exists() ? await decode(target) : null;
  });
  Future<void> save(String uid, PersonalTaskDraft value) => serial(() async {
    PersonalTaskDraft.fromMap(value.toMap());
    final target = await file(uid); final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(value.toMap()), flush: true);
    await temporary.rename(target.path);
  });
  Future<void> clear(String uid) => serial(() async {
    final target = await file(uid);
    for (final candidate in [target, File('${target.path}.tmp')]) { if (await candidate.exists()) await candidate.delete(); }
  });
}
