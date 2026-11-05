import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../app.dart' show errorText;
import '../tasks/presentation/workspace.dart' show dateLabel;

const teamStatuses = {'todo': 'Новая', 'inProgress': 'В работе', 'done': 'Выполнена'};
String memberLabel(Map<String, String> members, String uid, String currentUid) {
  final name = members[uid];
  if (uid == currentUid) return name == null || name.isEmpty ? 'Я' : '$name (я)';
  return name == null || name.isEmpty ? 'Участник ${uid.substring(0, 6)}…' : name;
}
class TeamTaskPanel extends StatefulWidget {
  const TeamTaskPanel({super.key, required this.uid, required this.team, required this.owner, required this.members});
  final String uid;
  final DocumentReference<Map<String, dynamic>> team;
  final bool owner;
  final Map<String, String> members;
  @override
  State<TeamTaskPanel> createState() => _TeamTaskPanelState();
}
class _TeamTaskPanelState extends State<TeamTaskPanel> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final pending = <String>{};
  String? error;
  Stream<QuerySnapshot<Map<String, dynamic>>> watch() {
    Query<Map<String, dynamic>> query = widget.team.collection('tasks');
    if (!widget.owner) query = query.where('assignedTo', isEqualTo: widget.uid);
    return query.snapshots();
  }
  @override
  void initState() { super.initState(); stream = watch(); }
  @override
  void didUpdateWidget(covariant TeamTaskPanel old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid || old.owner != widget.owner || old.team.path != widget.team.path) stream = watch();
  }
  Future<void> change(QueryDocumentSnapshot<Map<String, dynamic>> doc, String status) async {
    if (pending.contains(doc.id)) return;
    setState(() { pending.add(doc.id); error = null; });
    try { await doc.reference.update({'status': status, 'updatedAt': FieldValue.serverTimestamp()}); }
    catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => pending.remove(doc.id)); }
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Divider(), Text(widget.owner ? 'Задачи команды' : 'Назначенные мне задачи', style: Theme.of(context).textTheme.titleLarge),
    if (widget.owner) FilledButton.icon(icon: const Icon(Icons.add_task), label: const Text('Назначить задачу'), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamTaskEditor(team: widget.team, uid: widget.uid, members: widget.members)))),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, snapshot) {
      if (snapshot.hasError) return Column(children: [Text('${errorText(snapshot.error!)} Проверьте публикацию обновлённых правил.'), TextButton(onPressed: () => setState(() => stream = watch()), child: const Text('Повторить'))]);
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snapshot.data!.docs.toList()..sort((a, b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
      if (docs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Командных задач пока нет.'));
      return Column(children: docs.map((doc) {
        final data = doc.data(); final stamp = data['deadline']; final deadline = stamp is Timestamp ? stamp.toDate() : null;
        final status = data['status'] as String? ?? 'todo';
        final assignee = data['assignedTo'] as String? ?? '';
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data['title'] as String? ?? '', style: Theme.of(context).textTheme.titleMedium),
          if ((data['description'] as String? ?? '').isNotEmpty) Text(data['description'] as String),
          Text('Исполнитель: ${memberLabel(widget.members, assignee, widget.uid)}'),
          Text(deadline == null ? 'Без срока' : 'Срок: ${dateLabel(deadline)}'),
          Row(children: [
            Expanded(child: PopupMenuButton<String>(enabled: !pending.contains(doc.id), onSelected: (v) => change(doc, v), itemBuilder: (_) => teamStatuses.entries.map((e) => PopupMenuItem(value: e.key, child: Text(e.value))).toList(), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(pending.contains(doc.id) ? 'Сохранение…' : '${teamStatuses[status] ?? status} ▾')))),
            if (widget.owner) IconButton(tooltip: 'Редактировать', icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamTaskEditor(team: widget.team, uid: widget.uid, members: widget.members, task: doc.reference, initial: data)))),
          ]),
        ])));
      }).toList());
    }),
  ]);
}
class TeamTaskEditor extends StatefulWidget {
  const TeamTaskEditor({super.key, required this.team, required this.uid, required this.members, this.task, this.initial});
  final DocumentReference<Map<String, dynamic>> team;
  final String uid;
  final Map<String, String> members;
  final DocumentReference<Map<String, dynamic>>? task;
  final Map<String, dynamic>? initial;
  @override
  State<TeamTaskEditor> createState() => _TeamTaskEditorState();
}
class _TeamTaskEditorState extends State<TeamTaskEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController description;
  late final DocumentReference<Map<String, dynamic>> reference;
  late String assignee;
  DateTime? deadline;
  bool busy = false;
  String? error;
  bool get editing => widget.task != null;
  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const {};
    title = TextEditingController(text: initial['title'] as String? ?? '');
    description = TextEditingController(text: initial['description'] as String? ?? '');
    reference = widget.task ?? widget.team.collection('tasks').doc();
    final stamp = initial['deadline'];
    deadline = stamp is Timestamp ? stamp.toDate() : null;
    assignee = initial['assignedTo'] as String? ?? (widget.members.containsKey(widget.uid) ? widget.uid : widget.members.keys.first);
  }
  @override
  void dispose() { title.dispose(); description.dispose(); super.dispose(); }
  Future<void> pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: deadline ?? now, firstDate: DateUtils.dateOnly(now), lastDate: DateTime(now.year + 5));
    if (date != null && mounted) setState(() => deadline = date);
  }
  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    var success = false;
    try {
      final values = {'title': title.text.trim(), 'description': description.text.trim(), 'assignedTo': assignee, 'deadline': deadline == null ? null : Timestamp.fromDate(deadline!), 'updatedAt': FieldValue.serverTimestamp()};
      if (editing) { await reference.update(values); }
      else { await reference.set({...values, 'creatorId': widget.uid, 'status': 'todo', 'createdAt': FieldValue.serverTimestamp()}); }
      success = true;
    } catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(appBar: AppBar(title: Text(editing ? 'Редактировать задачу' : 'Командная задача')), body: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
    TextFormField(controller: title, enabled: !busy, maxLength: 200, decoration: const InputDecoration(labelText: 'Название'), validator: (v) => v == null || v.trim().isEmpty ? 'Введите название' : null),
    TextFormField(controller: description, enabled: !busy, maxLength: 5000, maxLines: 4, decoration: const InputDecoration(labelText: 'Описание')),
    DropdownButtonFormField<String>(value: assignee, isExpanded: true, decoration: const InputDecoration(labelText: 'Исполнитель'), items: widget.members.keys.map((id) => DropdownMenuItem(value: id, child: Text(memberLabel(widget.members, id, widget.uid), overflow: TextOverflow.ellipsis))).toList(), onChanged: busy ? null : (v) => setState(() => assignee = v ?? assignee)),
    OutlinedButton.icon(onPressed: busy ? null : pickDate, icon: const Icon(Icons.event), label: Text(deadline == null ? 'Выбрать срок' : dateLabel(deadline!))),
    if (deadline != null) TextButton(onPressed: busy ? null : () => setState(() => deadline = null), child: const Text('Убрать срок')),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const SizedBox(height: 16), FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Сохранение…' : (editing ? 'Сохранить' : 'Назначить'))),
  ]))));
}
