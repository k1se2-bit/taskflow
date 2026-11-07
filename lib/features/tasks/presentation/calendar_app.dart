import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../app.dart' show AccountScreen, errorText;
import '../../../core/theme/app_theme.dart';
import '../../teams/team_tasks.dart' show TeamTaskEditor, teamStatuses;
import 'workspace.dart' show Workspace, dateLabel;
import 'task_details_page.dart' show TaskDetailsPage;

class CalendarApp extends StatefulWidget {
  const CalendarApp({super.key});
  @override
  State<CalendarApp> createState() => _CalendarAppState();
}
class _CalendarAppState extends State<CalendarApp> {
  late final Stream<User?> auth;
  @override
  void initState() { super.initState(); auth = FirebaseAuth.instance.authStateChanges(); }
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'TaskFlow', debugShowCheckedModeBanner: false, theme: AppTheme.light, darkTheme: AppTheme.dark,
    home: StreamBuilder<User?>(stream: auth, builder: (context, s) {
      if (s.hasError) return Scaffold(body: Center(child: Text(errorText(s.error!))));
      if (s.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return s.data == null ? const AccountScreen() : TaskShell(key: ValueKey(s.data!.uid), uid: s.data!.uid);
    }));
}
class TaskShell extends StatefulWidget {
  const TaskShell({super.key, required this.uid});
  final String uid;
  @override
  State<TaskShell> createState() => _TaskShellState();
}
class _TaskShellState extends State<TaskShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(body: IndexedStack(index: index, children: [Workspace(uid: widget.uid), TaskCalendar(uid: widget.uid)]),
    bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'), NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календарь')]));
}

bool calendarMatches(Map<String, dynamic> data, DateTime day, String filter, bool overdue) {
  final stamp = data['deadline'];
  if (stamp is! Timestamp) return false;
  final date = DateUtils.dateOnly(stamp.toDate());
  final done = data['status'] == 'done';
  if (overdue) {
    if (done || !date.isBefore(DateUtils.dateOnly(DateTime.now()))) return false;
  } else if (!DateUtils.isSameDay(date, day)) { return false; }
  return filter == 'all' || (filter == 'active' ? !done : done);
}
class TaskCalendar extends StatefulWidget {
  const TaskCalendar({super.key, required this.uid});
  final String uid;
  @override
  State<TaskCalendar> createState() => _TaskCalendarState();
}
class _TaskCalendarState extends State<TaskCalendar> {
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  bool teamMode = false;
  bool overdue = false;
  String filter = 'all';
  String? teamId;
  late Stream<QuerySnapshot<Map<String, dynamic>>> personal;
  late Stream<QuerySnapshot<Map<String, dynamic>>> teams;
  void bind() {
    personal = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('tasks').orderBy('createdAt', descending: true).snapshots(includeMetadataChanges: true);
    teams = FirebaseFirestore.instance.collection('organizations').where('memberIds', arrayContains: widget.uid).snapshots();
  }
  @override
  void initState() { super.initState(); bind(); }
  @override
  void didUpdateWidget(covariant TaskCalendar old) { super.didUpdateWidget(old); if (old.uid != widget.uid) { teamId = null; bind(); } }
  Widget failure(Object error) => Column(children: [Text(errorText(error)), TextButton(onPressed: () => setState(bind), child: const Text('Повторить'))]);
  Widget personalTasks() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: personal, builder: (context, s) {
    if (s.hasError) return failure(s.error!);
    if (!s.hasData) return const Center(child: CircularProgressIndicator());
    final docs = s.data!.docs.where((d) => calendarMatches(d.data(), selected, filter, overdue)).toList();
    if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Личных задач по выбранным условиям нет. Задачи без срока доступны на «Сегодня» и в полном личном списке.'));
    return Column(children: docs.map((doc) {
      final data = doc.data(); final done = data['status'] == 'done';
      return Card(child: ListTile(leading: Icon(done ? Icons.check_circle_outline : Icons.radio_button_unchecked),
        title: Text(data['title'] as String? ?? '', style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
        subtitle: Text('${dateLabel((data['deadline'] as Timestamp).toDate())} · Личная\n${data['description'] ?? ''}'), trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskDetailsPage(uid: widget.uid, reference: doc.reference)))));
    }).toList());
  });
  Widget teamTasks() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: teams, builder: (context, s) {
    if (s.hasError) return failure(s.error!);
    if (!s.hasData) return const Center(child: CircularProgressIndicator());
    final docs = s.data!.docs.toList()..sort((a, b) => (a.data()['name'] as String? ?? '').compareTo(b.data()['name'] as String? ?? ''));
    if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Доступных команд нет. Создайте команду или дождитесь одобрения заявки во вкладке «Команды».'));
    QueryDocumentSnapshot<Map<String, dynamic>> selectedTeam = docs.first;
    for (final doc in docs) {
      if (doc.id == teamId) { selectedTeam = doc; break; }
    }
    final owner = selectedTeam.data()['ownerId'] == widget.uid;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButton<String>(value: selectedTeam.id, isExpanded: true, items: docs.map((d) => DropdownMenuItem(value: d.id, child: Text(d.data()['name'] as String? ?? d.id, overflow: TextOverflow.ellipsis))).toList(), onChanged: (id) => setState(() => teamId = id)),
      Text(owner ? 'Все задачи выбранной команды' : 'Только назначенные мне задачи'),
      TeamCalendarTasks(key: ValueKey('${widget.uid}:${selectedTeam.id}:$owner'), uid: widget.uid, team: selectedTeam, day: selected, filter: filter, overdue: overdue),
    ]);
  });
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Календарь задач'), actions: [TextButton(onPressed: () => setState(() { selected = DateUtils.dateOnly(DateTime.now()); overdue = false; }), child: const Text('Сегодня'))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, children: [ChoiceChip(label: const Text('Личные'), selected: !teamMode, onSelected: (_) => setState(() => teamMode = false)), ChoiceChip(label: const Text('Командные'), selected: teamMode, onSelected: (_) => setState(() => teamMode = true))]),
      CalendarDatePicker(key: ValueKey(selected), initialDate: selected, firstDate: DateTime(1900), lastDate: DateTime(2200), onDateChanged: (day) => setState(() { selected = DateUtils.dateOnly(day); overdue = false; })),
      Wrap(spacing: 8, children: [for (final entry in const {'all': 'Все', 'active': 'Активные', 'done': 'Выполненные'}.entries) ChoiceChip(label: Text(entry.value), selected: filter == entry.key, onSelected: (_) => setState(() { filter = entry.key; if (filter == 'done') overdue = false; }))]),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Все просроченные'), subtitle: const Text('Незавершённые задачи со сроком до сегодняшнего дня'), value: overdue, onChanged: (value) => setState(() { overdue = value; if (value) filter = 'active'; })),
      const Divider(), Text(overdue ? 'Просроченные задачи' : 'Задачи на ${dateLabel(selected)}', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12),
      if (teamMode) teamTasks() else personalTasks(),
    ]));
}

class TeamCalendarTasks extends StatefulWidget {
  const TeamCalendarTasks({super.key, required this.uid, required this.team, required this.day, required this.filter, required this.overdue});
  final String uid;
  final QueryDocumentSnapshot<Map<String, dynamic>> team;
  final DateTime day;
  final String filter;
  final bool overdue;
  @override
  State<TeamCalendarTasks> createState() => _TeamCalendarTasksState();
}
class _TeamCalendarTasksState extends State<TeamCalendarTasks> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final pending = <String>{};
  String? error;
  bool get owner => widget.team.data()['ownerId'] == widget.uid;
  Stream<QuerySnapshot<Map<String, dynamic>>> watch() {
    Query<Map<String, dynamic>> query = widget.team.reference.collection('tasks');
    if (!owner) query = query.where('assignedTo', isEqualTo: widget.uid);
    return query.snapshots();
  }
  @override
  void initState() { super.initState(); stream = watch(); }
  Map<String, String> members() {
    final data = widget.team.data(); final raw = data['memberNames'];
    return {for (final id in List<String>.from(data['memberIds'] as List)) id: raw is Map && raw[id] is String ? raw[id] as String : (data['ownerId'] == id ? 'Владелец' : '')};
  }
  String label(String id) {
    final name = members()[id];
    final short = id.length > 6 ? '${id.substring(0, 6)}…' : id;
    return '${name == null || name.isEmpty ? 'Участник' : name}${id == widget.uid ? ' (я)' : ''} · $short';
  }
  Future<void> change(QueryDocumentSnapshot<Map<String, dynamic>> doc, String value) async {
    if (!pending.add(doc.id)) return;
    setState(() => error = null);
    try { await doc.reference.update({'status': value, 'updatedAt': FieldValue.serverTimestamp()}); }
    catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => pending.remove(doc.id)); }
  }
  void details(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskDetailsPage(uid: widget.uid, reference: doc.reference, teamId: widget.team.id)));
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, s) {
      if (s.hasError) return Column(children: [Text(errorText(s.error!)), TextButton(onPressed: () => setState(() => stream = watch()), child: const Text('Повторить'))]);
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final docs = s.data!.docs.where((d) => calendarMatches(d.data(), widget.day, widget.filter, widget.overdue)).toList()..sort((a, b) => (a.data()['deadline'] as Timestamp).compareTo(b.data()['deadline'] as Timestamp));
      if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Командных задач по выбранным условиям нет. Задачи без срока доступны внутри команды.'));
      return Column(children: docs.map((doc) {
        final data = doc.data(); final done = data['status'] == 'done'; final status = data['status'] as String? ?? 'todo';
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(done ? Icons.check_circle_outline : Icons.groups_outlined), title: Text(data['title'] as String? ?? '', style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
            subtitle: Text('${widget.team.data()['name']}\n${label(data['assignedTo'] as String? ?? '')}\nСрок: ${dateLabel((data['deadline'] as Timestamp).toDate())}'), onTap: pending.contains(doc.id) ? null : () => details(doc),
            trailing: owner ? IconButton(tooltip: 'Редактировать', icon: const Icon(Icons.edit_outlined), onPressed: pending.contains(doc.id) ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamTaskEditor(team: widget.team.reference, uid: widget.uid, members: members(), task: doc.reference, initial: data)))) : null),
          PopupMenuButton<String>(enabled: !pending.contains(doc.id), onSelected: (value) => change(doc, value), itemBuilder: (_) => teamStatuses.entries.map((e) => PopupMenuItem(value: e.key, child: Text(e.value))).toList(), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(pending.contains(doc.id) ? 'Сохранение…' : '${teamStatuses[status] ?? status} ▾'))),
        ])));
      }).toList());
    }),
  ]);
}
