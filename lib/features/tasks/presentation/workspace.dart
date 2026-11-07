import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../app.dart' show AccountScreen, errorText;
import '../../../core/theme/app_theme.dart';
import 'task_details_page.dart' show TaskDetailsPage;

const priorities = {'low': 'Низкий', 'medium': 'Обычный', 'high': 'Высокий'};
String dateLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class WorkspaceApp extends StatelessWidget {
  const WorkspaceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TaskFlow', debugShowCheckedModeBanner: false,
    theme: AppTheme.light, darkTheme: AppTheme.dark,
    home: StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges(), builder: (context, s) {
      if (s.hasError) return Scaffold(body: Center(child: Text(errorText(s.error!))));
      if (s.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return s.data == null ? const AccountScreen() : Workspace(key: ValueKey(s.data!.uid), uid: s.data!.uid);
    }),
  );
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
  String query = '';
  int filter = 0;
  bool signingOut = false;
  @override
  void initState() {
    super.initState();
    tasks = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('tasks');
    stream = tasks.orderBy('createdAt', descending: true).snapshots(includeMetadataChanges: true);
  }
  void report(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
  }
  Future<void> toggle(String id, bool done) async {
    setState(() => pending.add(id));
    try { await tasks.doc(id).update({'status': done ? 'done' : 'todo', 'updatedAt': FieldValue.serverTimestamp()}); }
    catch (e) { report(e); }
    finally { if (mounted) setState(() => pending.remove(id)); }
  }
  Future<void> logout() async {
    setState(() => signingOut = true);
    try { await FirebaseAuth.instance.signOut(); } catch (e) { report(e); }
    finally { if (mounted) setState(() => signingOut = false); }
  }
  void edit([QueryDocumentSnapshot<Map<String, dynamic>>? doc]) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskEditor(reference: doc?.reference ?? tasks.doc(), initial: doc?.data())));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мои задачи'), actions: [IconButton(tooltip: 'Выйти', onPressed: signingOut ? null : logout, icon: const Icon(Icons.logout))]),
    floatingActionButton: FloatingActionButton(onPressed: () => edit(), child: const Icon(Icons.add)),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(decoration: const InputDecoration(labelText: 'Поиск по названию и описанию', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v.trim().toLowerCase()))),
      Wrap(spacing: 8, children: List.generate(3, (i) => ChoiceChip(label: Text(['Все', 'Активные', 'Выполненные'][i]), selected: filter == i, onSelected: (_) => setState(() => filter = i)))),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, s) {
        if (s.hasError) return Center(child: Text(errorText(s.error!)));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs.where((d) {
          final v = d.data(); final done = v['status'] == 'done';
          return (filter == 0 || (filter == 1 && !done) || (filter == 2 && done)) && '${v['title'] ?? ''} ${v['description'] ?? ''}'.toLowerCase().contains(query);
        }).toList();
        if (docs.isEmpty) return const Center(child: Text('Задач не найдено'));
        return ListView.builder(padding: const EdgeInsets.only(bottom: 88), itemCount: docs.length, itemBuilder: (context, i) {
          final doc = docs[i]; final v = doc.data(); final done = v['status'] == 'done';
          final deadline = (v['deadline'] as Timestamp?)?.toDate();
          final now = DateTime.now();
          final overdue = !done && deadline != null && deadline.isBefore(DateTime(now.year, now.month, now.day));
          final priority = priorities[v['priority']] ?? 'Обычный';
          return ListTile(
            leading: Checkbox(value: done, onChanged: pending.contains(doc.id) ? null : (value) => toggle(doc.id, value ?? false)),
            title: Text(v['title'] as String? ?? '', style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
            subtitle: Text('$priority${deadline == null ? '' : ' • ${dateLabel(deadline)}'}${overdue ? ' • Просрочено' : ''}${doc.metadata.hasPendingWrites ? ' • Синхронизация…' : ''}', style: TextStyle(color: overdue ? Theme.of(context).colorScheme.error : null)),
            trailing: const Icon(Icons.chevron_right), onTap: pending.contains(doc.id) ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskDetailsPage(uid: widget.uid, reference: doc.reference))),
          );
        });
      })),
    ]),
  );
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.reference, this.initial});
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic>? initial;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}
class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController description;
  DateTime? deadline;
  String priority = 'medium';
  bool busy = false;
  String? error;
  bool get editing => widget.initial != null;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.initial?['title'] as String? ?? '');
    description = TextEditingController(text: widget.initial?['description'] as String? ?? '');
    deadline = (widget.initial?['deadline'] as Timestamp?)?.toDate();
    priority = priorities.containsKey(widget.initial?['priority']) ? widget.initial!['priority'] as String : 'medium';
  }
  @override
  void dispose() { title.dispose(); description.dispose(); super.dispose(); }
  Future<void> pickDate() async {
    final initial = deadline ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(initial.year - 100), lastDate: DateTime(initial.year + 100));
    if (mounted && d != null) setState(() => deadline = d);
  }
  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    var success = false;
    try {
      final data = <String, dynamic>{'title': title.text.trim(), 'description': description.text.trim(), 'priority': priority, 'deadline': deadline == null ? null : Timestamp.fromDate(deadline!), 'updatedAt': FieldValue.serverTimestamp()};
      if (editing) { await widget.reference.update(data); }
      else { await widget.reference.set({...data, 'status': 'todo', 'category': '', 'createdAt': FieldValue.serverTimestamp()}); }
      success = true;
    } catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) Navigator.of(context).pop();
  }
  Future<void> remove() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить задачу?'), content: Text('«${title.text}» будет удалена без возможности восстановления.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить'))]));
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; error = null; });
    var success = false;
    try { await widget.reference.delete(); success = true; }
    catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(
    appBar: AppBar(title: Text(editing ? 'Редактирование задачи' : 'Новая задача'), actions: [if (editing) IconButton(tooltip: 'Удалить', onPressed: busy ? null : remove, icon: const Icon(Icons.delete_outline))]),
    body: Form(key: form, child: ListView(padding: const EdgeInsets.all(16), children: [
      TextFormField(controller: title, enabled: !busy, maxLength: 200, decoration: const InputDecoration(labelText: 'Название'), validator: (v) => v == null || v.trim().isEmpty ? 'Введите название' : null),
      TextFormField(controller: description, enabled: !busy, maxLength: 5000, maxLines: 4, decoration: const InputDecoration(labelText: 'Описание')),
      DropdownButtonFormField<String>(value: priority, decoration: const InputDecoration(labelText: 'Приоритет'), items: priorities.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: busy ? null : (v) => setState(() => priority = v ?? 'medium')),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: busy ? null : pickDate, icon: const Icon(Icons.event), label: Text(deadline == null ? 'Выбрать срок' : dateLabel(deadline!))),
      if (deadline != null) TextButton(onPressed: busy ? null : () => setState(() => deadline = null), child: const Text('Убрать срок')),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Подождите…' : 'Сохранить')),
    ])),
  ));
}
