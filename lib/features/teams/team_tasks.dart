import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../app.dart' show errorText;
import '../tasks/presentation/workspace.dart' show dateLabel;

const teamStatuses = {'todo': 'Новая', 'inProgress': 'В работе', 'done': 'Выполнена'};
String memberLabel(Map<String, String> members, String uid, String currentUid) {
  final name = members[uid]?.trim() ?? '';
  final short = uid.length > 6 ? '${uid.substring(0, 6)}…' : uid;
  if (name.isEmpty) return uid == currentUid ? 'Я' : 'Участник $short';
  final duplicate = members.values.where((value) => value.trim().toLowerCase() == name.toLowerCase()).length > 1;
  return '$name${uid == currentUid ? ' (я)' : ''}${duplicate ? ' · $short' : ''}';
}
bool teamTaskIsOverdue(Map<String, dynamic> data, DateTime now) {
  final stamp = data['deadline'];
  return data['status'] != 'done' && stamp is Timestamp && DateUtils.dateOnly(stamp.toDate()).isBefore(DateUtils.dateOnly(now));
}
bool teamTaskMatches(Map<String, dynamic> data, {String search = '', String status = '', String assignee = '', bool overdueOnly = false, required DateTime now}) {
  final text = search.trim().toLowerCase();
  if (text.isNotEmpty && !'${data['title'] ?? ''} ${data['description'] ?? ''}'.toLowerCase().contains(text)) return false;
  if (status.isNotEmpty && data['status'] != status) return false;
  if (assignee.isNotEmpty && data['assignedTo'] != assignee) return false;
  return !overdueOnly || teamTaskIsOverdue(data, now);
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
  final search = TextEditingController();
  String statusFilter = '';
  String assigneeFilter = '';
  bool overdueOnly = false;
  String? error;
  Stream<QuerySnapshot<Map<String, dynamic>>> watch() {
    Query<Map<String, dynamic>> query = widget.team.collection('tasks');
    if (!widget.owner) query = query.where('assignedTo', isEqualTo: widget.uid);
    return query.snapshots();
  }
  @override
  void initState() { super.initState(); stream = watch(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  @override
  void didUpdateWidget(covariant TeamTaskPanel old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid || old.owner != widget.owner || old.team.path != widget.team.path) { stream = watch(); assigneeFilter = ''; }
  }
  Future<void> change(QueryDocumentSnapshot<Map<String, dynamic>> doc, String status) async {
    if (pending.contains(doc.id)) return;
    setState(() { pending.add(doc.id); error = null; });
    try { await doc.reference.update({'status': status, 'updatedAt': FieldValue.serverTimestamp()}); }
    catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => pending.remove(doc.id)); }
  }
  void edit([QueryDocumentSnapshot<Map<String, dynamic>>? doc]) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamTaskEditor(team: widget.team, uid: widget.uid, members: widget.members, task: doc?.reference, initial: doc?.data())));
  }
  @override
  Widget build(BuildContext context) {
    final assignee = widget.owner && widget.members.containsKey(assigneeFilter) ? assigneeFilter : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(), Text(widget.owner ? 'Задачи команды' : 'Назначенные мне задачи', style: Theme.of(context).textTheme.titleLarge),
      if (widget.owner) FilledButton.icon(icon: const Icon(Icons.add_task), label: const Text('Назначить задачу'), onPressed: widget.members.isEmpty ? null : () => edit()),
      TextField(controller: search, decoration: InputDecoration(labelText: 'Поиск по названию и описанию', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(tooltip: 'Очистить поиск', onPressed: () => setState(() => search.clear()), icon: const Icon(Icons.clear))), onChanged: (_) => setState(() {})),
      DropdownButton<String>(value: statusFilter, isExpanded: true, items: [const DropdownMenuItem(value: '', child: Text('Все статусы')), ...teamStatuses.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))], onChanged: (value) => setState(() => statusFilter = value ?? '')),
      if (widget.owner) DropdownButton<String>(value: assignee, isExpanded: true, items: [const DropdownMenuItem(value: '', child: Text('Все исполнители')), ...widget.members.keys.map((id) => DropdownMenuItem(value: id, child: Text(memberLabel(widget.members, id, widget.uid), overflow: TextOverflow.ellipsis)))], onChanged: (value) => setState(() => assigneeFilter = value ?? '')),
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [FilterChip(label: const Text('Только просроченные'), selected: overdueOnly, onSelected: (value) => setState(() => overdueOnly = value)), TextButton(onPressed: () => setState(() { search.clear(); statusFilter = ''; assigneeFilter = ''; overdueOnly = false; }), child: const Text('Сбросить фильтры'))]),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, snapshot) {
        if (snapshot.hasError) return Column(children: [Text(errorText(snapshot.error!)), TextButton(onPressed: () => setState(() => stream = watch()), child: const Text('Повторить'))]);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final all = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(snapshot.data!.docs);
        final now = DateTime.now();
        final done = all.where((doc) => doc.data()['status'] == 'done').length;
        final overdue = all.where((doc) => teamTaskIsOverdue(doc.data(), now)).length;
        final docs = all.where((doc) => teamTaskMatches(doc.data(), search: search.text, status: statusFilter, assignee: assignee, overdueOnly: overdueOnly, now: now)).toList();
        docs.sort((a, b) {
          final aDone = a.data()['status'] == 'done'; final bDone = b.data()['status'] == 'done';
          if (aDone != bDone) return aDone ? 1 : -1;
          final aDate = a.data()['deadline']; final bDate = b.data()['deadline'];
          final dateOrder = (aDate is Timestamp ? aDate.millisecondsSinceEpoch : 0x7fffffffffffffff).compareTo(bDate is Timestamp ? bDate.millisecondsSinceEpoch : 0x7fffffffffffffff);
          return dateOrder != 0 ? dateOrder : a.id.compareTo(b.id);
        });
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 12), const Text('Сводка по доступным задачам — до применения фильтров'),
          Wrap(spacing: 8, children: [Chip(label: Text('Всего: ${all.length}')), Chip(label: Text('Активные: ${all.length - done}')), Chip(label: Text('Выполнены: $done')), Chip(label: Text('Просрочены: $overdue'))]),
          if (all.isNotEmpty) ...[LinearProgressIndicator(value: done / all.length), Text('Выполнено $done из ${all.length}')],
          const SizedBox(height: 12), Text('Показано: ${docs.length}'),
          if (docs.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(all.isEmpty ? 'Командных задач пока нет.' : 'По выбранным условиям ничего не найдено. Сбросьте фильтры.')),
          ...docs.map((doc) {
            final data = doc.data(); final stamp = data['deadline']; final deadline = stamp is Timestamp ? stamp.toDate() : null;
            final status = data['status'] as String? ?? 'todo'; final late = teamTaskIsOverdue(data, now);
            return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['title'] as String? ?? '', style: Theme.of(context).textTheme.titleMedium?.copyWith(decoration: status == 'done' ? TextDecoration.lineThrough : null)),
              if ((data['description'] as String? ?? '').isNotEmpty) Text(data['description'] as String),
              Text('Исполнитель: ${memberLabel(widget.members, data['assignedTo'] as String? ?? '', widget.uid)}'),
              Text(deadline == null ? 'Без срока' : 'Срок: ${dateLabel(deadline)}${late ? ' — просрочена' : ''}', style: late ? TextStyle(color: Theme.of(context).colorScheme.error) : null),
              Row(children: [Expanded(child: PopupMenuButton<String>(enabled: !pending.contains(doc.id), onSelected: (value) => change(doc, value), itemBuilder: (_) => teamStatuses.entries.map((entry) => PopupMenuItem(value: entry.key, child: Text(entry.value))).toList(), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(pending.contains(doc.id) ? 'Сохранение…' : '${teamStatuses[status] ?? status} ▾')))),
                if (widget.owner) IconButton(tooltip: 'Редактировать', icon: const Icon(Icons.edit_outlined), onPressed: pending.contains(doc.id) ? null : () => edit(doc)),
              ]),
            ])));
          }),
        ]);
      }),
    ]);
  }
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
    final initial = widget.initial ?? const <String, dynamic>{};
    title = TextEditingController(text: initial['title'] as String? ?? '');
    description = TextEditingController(text: initial['description'] as String? ?? '');
    reference = widget.task ?? widget.team.collection('tasks').doc();
    final stamp = initial['deadline']; deadline = stamp is Timestamp ? stamp.toDate() : null;
    final previous = initial['assignedTo'] as String?;
    assignee = previous != null && widget.members.containsKey(previous) ? previous : widget.members.containsKey(widget.uid) ? widget.uid : widget.members.isNotEmpty ? widget.members.keys.first : widget.uid;
  }
  @override
  void dispose() { title.dispose(); description.dispose(); super.dispose(); }
  Future<void> pickDate() async {
    final first = DateTime(1900); final last = DateTime(2200);
    final value = deadline ?? DateTime.now();
    final initial = value.isBefore(first) ? first : value.isAfter(last) ? last : value;
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
    if (date != null && mounted) setState(() => deadline = date);
  }
  Future<void> save() async {
    if (busy || widget.members.isEmpty || !form.currentState!.validate()) return;
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
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(appBar: AppBar(title: Text(editing ? 'Редактировать задачу' : 'Командная задача')), body: widget.members.isEmpty ? const Center(child: Text('Нет доступных исполнителей. Откройте команду заново.')) : Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
    TextFormField(controller: title, enabled: !busy, maxLength: 200, decoration: const InputDecoration(labelText: 'Название'), validator: (value) => value == null || value.trim().isEmpty ? 'Введите название' : null),
    TextFormField(controller: description, enabled: !busy, maxLength: 5000, maxLines: 4, decoration: const InputDecoration(labelText: 'Описание')),
    DropdownButtonFormField<String>(value: widget.members.containsKey(assignee) ? assignee : null, isExpanded: true, decoration: const InputDecoration(labelText: 'Исполнитель'), items: widget.members.keys.map((id) => DropdownMenuItem(value: id, child: Text(memberLabel(widget.members, id, widget.uid), overflow: TextOverflow.ellipsis))).toList(), onChanged: busy ? null : (value) => setState(() => assignee = value ?? assignee), validator: (value) => value == null || !widget.members.containsKey(value) ? 'Выберите исполнителя' : null),
    OutlinedButton.icon(onPressed: busy ? null : pickDate, icon: const Icon(Icons.event), label: Text(deadline == null ? 'Выбрать срок' : dateLabel(deadline!))),
    if (deadline != null) TextButton(onPressed: busy ? null : () => setState(() => deadline = null), child: const Text('Убрать срок')),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const SizedBox(height: 16), FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Сохранение…' : (editing ? 'Сохранить' : 'Назначить'))),
  ]))));
}
