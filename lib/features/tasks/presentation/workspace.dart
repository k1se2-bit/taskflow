import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../app.dart' show AccountScreen, errorText;
import '../../../core/theme/app_theme.dart';
import '../data/personal_task_draft.dart';
import 'task_details_page.dart' show TaskDetailsPage;

const priorities = {'low': 'Низкий', 'medium': 'Обычный', 'high': 'Высокий'};
String dateLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class WorkspaceApp extends StatelessWidget {
  const WorkspaceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'TaskFlow', debugShowCheckedModeBanner: false, theme: AppTheme.light, darkTheme: AppTheme.dark, home: StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges(), builder: (context, s) {
    if (s.hasError) return Scaffold(body: Center(child: Text(errorText(s.error!))));
    if (s.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return s.data == null ? const AccountScreen() : Workspace(key: ValueKey(s.data!.uid), uid: s.data!.uid);
  }));
}
class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.uid});
  final String uid;
  @override
  State<Workspace> createState() => _WorkspaceState();
}
class _WorkspaceState extends State<Workspace> {
  late final CollectionReference<Map<String, dynamic>> tasks;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final pending = <String>{};
  String query = ''; int filter = 0; bool signingOut = false;
  @override
  void initState() { super.initState(); tasks = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('tasks'); stream = tasks.orderBy('createdAt', descending: true).snapshots(includeMetadataChanges: true); }
  void report(Object error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(error)))); }
  Future<void> toggle(String id, bool done) async {
    if (pending.contains(id)) return;
    setState(() => pending.add(id));
    String? previous;
    try {
      final snapshot = await tasks.doc(id).get();
      previous = snapshot.data()?['status'] as String?;
      await tasks.doc(id).update({'status': done ? 'done' : 'todo', 'updatedAt': FieldValue.serverTimestamp()});
      if (mounted && previous != null && previous != (done ? 'done' : 'todo')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Статус изменён'), action: SnackBarAction(label: 'Отменить', onPressed: () { tasks.doc(id).update({'status': previous!, 'updatedAt': FieldValue.serverTimestamp()}); })));
      }
    }
    catch (error) { report(error); }
    finally { if (mounted) setState(() => pending.remove(id)); }
  }
  Future<void> logout() async {
    setState(() => signingOut = true);
    try { await FirebaseAuth.instance.signOut(); } catch (error) { report(error); }
    finally { if (mounted) setState(() => signingOut = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Мои задачи'), actions: [IconButton(tooltip: 'Выйти', onPressed: signingOut ? null : logout, icon: const Icon(Icons.logout))]),
    floatingActionButton: FloatingActionButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskEditor(reference: tasks.doc()))), child: const Icon(Icons.add)),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(decoration: const InputDecoration(labelText: 'Поиск по названию и описанию', prefixIcon: Icon(Icons.search)), onChanged: (value) => setState(() => query = value.trim().toLowerCase()))),
      Wrap(spacing: 8, children: List.generate(4, (i) => ChoiceChip(label: Text(['Все', 'Активные', 'Выполненные', 'Архив'][i]), selected: filter == i, onSelected: (_) => setState(() => filter = i)))),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(errorText(snapshot.error!)));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data(); final done = data['status'] == 'done'; final archived = data['archived'] == true;
          if (filter == 3 ? !archived : archived) return false;
          if (filter == 1 && done) return false;
          if (filter == 2 && !done) return false;
          return '${data['title'] ?? ''} ${data['description'] ?? ''}'.toLowerCase().contains(query);
        }).toList();
        if (docs.isEmpty) return Center(child: Text(filter == 3 ? 'Архив пуст' : 'Задач не найдено'));
        return ListView.builder(padding: const EdgeInsets.only(bottom: 88), itemCount: docs.length, itemBuilder: (context, index) {
          final doc = docs[index]; final data = doc.data(); final done = data['status'] == 'done'; final deadline = (data['deadline'] as Timestamp?)?.toDate(); final now = DateTime.now();
          final overdue = !done && deadline != null && deadline.isBefore(DateTime(now.year, now.month, now.day));
          return ListTile(leading: Checkbox(value: done, onChanged: pending.contains(doc.id) ? null : (value) => toggle(doc.id, value ?? false)), title: Text(data['title'] as String? ?? '', style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
            subtitle: Text('${priorities[data['priority']] ?? 'Обычный'}${deadline == null ? '' : ' • ${dateLabel(deadline)}'}${overdue ? ' • Просрочено' : ''}${doc.metadata.hasPendingWrites ? ' • Синхронизация…' : ''}', style: TextStyle(color: overdue ? Theme.of(context).colorScheme.error : null)),
            trailing: const Icon(Icons.chevron_right), onTap: pending.contains(doc.id) ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskDetailsPage(uid: widget.uid, reference: doc.reference))));
        });
      })),
    ]));
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.reference, this.initial});
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic>? initial;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}
class _TaskEditorState extends State<TaskEditor> with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  final drafts = PersonalTaskDraftStore.instance;
  late final TextEditingController title;
  late final TextEditingController description;
  late final String uid;
  late final Stream<User?> auth;
  late DocumentReference<Map<String, dynamic>> reference;
  DateTime? deadline;
  String priority = 'medium';
  bool busy = false; bool closing = false; bool loading = false; bool draftReady = false; bool allowExit = false;
  int revision = 0; Timer? debounce; String? error; String draftStatus = '';
  bool get editing => widget.initial != null;
  bool get validOwnerPath => uid.isNotEmpty && widget.reference.path == 'users/$uid/tasks/${widget.reference.id}';
  PersonalTaskDraft get currentDraft => PersonalTaskDraft(taskId: reference.id, title: title.text, description: description.text, priority: priority, deadline: deadline);
  String friendly(Object value) => value is StateError ? value.message.toString() : errorText(value);
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    uid = widget.reference.parent.parent?.id ?? ''; reference = widget.reference; auth = FirebaseAuth.instance.authStateChanges();
    title = TextEditingController(text: widget.initial?['title'] as String? ?? ''); description = TextEditingController(text: widget.initial?['description'] as String? ?? '');
    deadline = (widget.initial?['deadline'] as Timestamp?)?.toDate(); priority = priorities.containsKey(widget.initial?['priority']) ? widget.initial!['priority'] as String : 'medium';
    title.addListener(changed); description.addListener(changed);
    draftReady = editing; if (!editing && validOwnerPath) unawaited(loadDraft());
  }
  Future<void> loadDraft() async {
    setState(() { loading = true; error = null; });
    try {
      final value = await drafts.load(uid); if (!mounted) return;
      if (value != null) { reference = widget.reference.parent.doc(value.taskId); title.text = value.title; description.text = value.description; priority = value.priority; deadline = value.deadline; }
      setState(() { draftReady = true; draftStatus = value == null ? 'Черновик хранится только на этом устройстве.' : 'Восстановлен локальный черновик.'; });
    } catch (value) { if (mounted) setState(() { draftReady = false; error = 'Не удалось прочитать черновик. Повторите загрузку или явно сбросьте его.'; }); }
    finally { if (mounted) setState(() => loading = false); }
  }
  void changed() {
    if (editing || loading || !draftReady || busy || closing) return;
    revision++; setState(() => draftStatus = 'Сохраняем черновик…'); debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () { unawaited(persistQuietly()); });
  }
  Future<void> persist() async {
    if (editing || !draftReady) return;
    debounce?.cancel(); final version = revision; final value = currentDraft;
    if (value.isEmpty) { await drafts.clear(uid); } else { await drafts.save(uid, value); }
    if (mounted && version == revision) setState(() => draftStatus = value.isEmpty ? 'Черновик пуст.' : 'Черновик записан на устройстве — это ещё не задача на сервере.');
  }
  Future<void> persistQuietly() async {
    try { await persist(); } catch (value) { if (mounted) setState(() => draftStatus = 'Не удалось записать черновик. Не закрывайте форму без повторной попытки.'); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.paused && !editing && draftReady && !busy && !closing) unawaited(persistQuietly()); }
  @override
  void dispose() { debounce?.cancel(); WidgetsBinding.instance.removeObserver(this); title.dispose(); description.dispose(); super.dispose(); }
  void exit() {
    if (!mounted) return;
    setState(() => allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.of(context).pop(); });
  }
  Future<void> close() async {
    if (busy || closing) return;
    if (editing || !draftReady) { exit(); return; }
    setState(() => closing = true);
    try { await persist(); exit(); }
    catch (value) {
      if (!mounted) return;
      final leave = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Черновик не сохранён'), content: const Text('Остаться и попробовать снова или выйти с риском потери последних изменений?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти без сохранения'))]));
      if (leave == true) exit();
    } finally { if (mounted) setState(() => closing = false); }
  }
  Future<void> discardDraft() async {
    if (busy || closing || loading) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Сбросить черновик?'), content: const Text('Введённые данные новой задачи будут удалены с этого устройства. Сохранённые задачи не изменятся.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сбросить'))]));
    if (confirmed != true || !mounted) return;
    debounce?.cancel(); setState(() { loading = true; error = null; });
    try {
      await drafts.clear(uid); if (!mounted) return;
      reference = widget.reference.parent.doc(); title.clear(); description.clear(); priority = 'medium'; deadline = null; revision++;
      setState(() { draftReady = true; draftStatus = 'Черновик сброшен.'; });
    } catch (value) { if (mounted) setState(() => error = 'Не удалось сбросить черновик. Данные формы сохранены.'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> pickDate() async {
    final initial = deadline ?? DateTime.now();
    final value = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(initial.year - 100), lastDate: DateTime(initial.year + 100));
    if (mounted && value != null) { setState(() => deadline = value); changed(); }
  }
  bool sameSavedTask(Map<String, dynamic> data, PersonalTaskDraft value) {
    final stamp = data['deadline'];
    return data['title'] == value.title.trim() && data['description'] == value.description.trim() && data['priority'] == value.priority && (stamp is Timestamp ? stamp.millisecondsSinceEpoch : null) == value.deadline?.millisecondsSinceEpoch;
  }
  Future<void> save() async {
    if (busy || closing || loading || !draftReady || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; }); debounce?.cancel();
    var success = false; String? warning;
    try {
      if (!validOwnerPath || FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Аккаунт изменился. Откройте форму заново.');
      final value = currentDraft;
      final values = <String, dynamic>{'title': value.title.trim(), 'description': value.description.trim(), 'priority': value.priority, 'deadline': value.deadline == null ? null : Timestamp.fromDate(value.deadline!), 'updatedAt': FieldValue.serverTimestamp()};
      if (editing) { await reference.update(values); }
      else {
        await persist();
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final existing = await transaction.get(reference);
          if (existing.exists) {
            if (!sameSavedTask(existing.data()!, value)) throw StateError('Задача этого черновика уже сохранена и изменена. Не перезаписываем её. Проверьте список; для другой задачи сбросьте черновик и создайте новую.');
            return;
          }
          transaction.set(reference, {...values, 'status': 'todo', 'category': '', 'createdAt': FieldValue.serverTimestamp()});
        });
        try { await drafts.clear(uid); } catch (value) { warning = 'Задача сохранена, но локальный черновик не очищен. Повторное сохранение не создаст копию с другим ID.'; }
      }
      success = true;
    } catch (value) { if (mounted) setState(() => error = friendly(value)); }
    finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) { if (warning != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning!))); exit(); }
  }
  Future<void> remove() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Удалить задачу?'), content: Text('«${title.text}» будет удалена без возможности восстановления.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить'))]));
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; error = null; }); var success = false;
    try { if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Аккаунт изменился.'); await reference.delete(); success = true; }
    catch (value) { if (mounted) setState(() => error = friendly(value)); }
    finally { if (mounted) setState(() => busy = false); }
    if (success) exit();
  }
  Widget editorBody() {
    final enabled = !busy && !closing && !loading; final now = DateUtils.dateOnly(DateTime.now());
    if (loading) return const Center(child: CircularProgressIndicator());
    if (!draftReady) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error ?? 'Черновик недоступен.'), TextButton(onPressed: () { loadDraft(); }, child: const Text('Повторить загрузку')), TextButton(onPressed: () { discardDraft(); }, child: const Text('Сбросить черновик'))])));
    return Form(key: form, child: ListView(padding: const EdgeInsets.all(16), children: [
      TextFormField(controller: title, enabled: enabled, autofocus: !editing && title.text.isEmpty, maxLength: 200, decoration: const InputDecoration(labelText: 'Что нужно сделать?'), validator: (value) => value == null || value.trim().isEmpty ? 'Введите название' : null),
      Wrap(spacing: 8, children: [for (final option in [MapEntry('Сегодня', now), MapEntry('Завтра', DateTime(now.year, now.month, now.day + 1))]) ChoiceChip(label: Text(option.key), selected: DateUtils.isSameDay(deadline, option.value), onSelected: enabled ? (_) { setState(() => deadline = option.value); changed(); } : null), ChoiceChip(label: const Text('Без срока'), selected: deadline == null, onSelected: enabled ? (_) { setState(() => deadline = null); changed(); } : null)]),
      OutlinedButton.icon(onPressed: enabled ? pickDate : null, icon: const Icon(Icons.event), label: Text(deadline == null ? 'Другая дата' : dateLabel(deadline!))),
      ExpansionTile(title: const Text('Подробнее'), initiallyExpanded: editing || description.text.isNotEmpty || priority != 'medium', children: [
        TextFormField(controller: description, enabled: enabled, maxLength: 5000, maxLines: 4, decoration: const InputDecoration(labelText: 'Описание')),
        DropdownButtonFormField<String>(value: priority, decoration: const InputDecoration(labelText: 'Приоритет'), items: priorities.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(), onChanged: enabled ? (value) { setState(() => priority = value ?? 'medium'); changed(); } : null),
      ]),
      if (!editing) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(draftStatus)),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      FilledButton(onPressed: enabled ? save : null, child: Text(busy ? 'Сохраняем…' : 'Сохранить задачу')),
      if (!editing) TextButton(onPressed: enabled ? discardDraft : null, child: const Text('Сбросить черновик')),
      if (!editing) const Text('Черновик — локальный. Новая задача появится в списке после подтверждения сервером. Если сети нет, продолжите позже с этого устройства.'),
    ]));
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy && !closing && (editing || allowExit), onPopInvokedWithResult: (didPop, result) { if (!didPop && !busy && !closing) unawaited(close()); }, child: Scaffold(
    appBar: AppBar(leading: BackButton(onPressed: () { close(); }), title: Text(editing ? 'Редактирование задачи' : 'Новая задача'), actions: [if (editing) IconButton(tooltip: 'Удалить', onPressed: busy ? null : remove, icon: const Icon(Icons.delete_outline))]),
    body: StreamBuilder<User?>(stream: auth, builder: (context, account) {
      if (account.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (!validOwnerPath || account.data?.uid != uid) return const Center(child: Text('Аккаунт изменился. Вернитесь к списку.'));
      return editorBody();
    }),
  ));
}
