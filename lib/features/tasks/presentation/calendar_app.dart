import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../app.dart' show AccountScreen, errorText;
import '../../../core/theme/app_theme.dart';
import 'workspace.dart' show Workspace, TaskEditor, dateLabel;

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
  Widget build(BuildContext context) => MaterialApp(
    title: 'TaskFlow', debugShowCheckedModeBanner: false,
    theme: AppTheme.light, darkTheme: AppTheme.dark,
    home: StreamBuilder<User?>(stream: auth, builder: (context, s) {
      if (s.hasError) return Scaffold(body: Center(child: Text(errorText(s.error!))));
      if (s.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return s.data == null ? const AccountScreen() : TaskShell(key: ValueKey(s.data!.uid), uid: s.data!.uid);
    }),
  );
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
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: index, children: [Workspace(uid: widget.uid), TaskCalendar(uid: widget.uid)]),
    bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'),
      NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календарь'),
    ]),
  );
}

class TaskCalendar extends StatefulWidget {
  const TaskCalendar({super.key, required this.uid});
  final String uid;
  @override
  State<TaskCalendar> createState() => _TaskCalendarState();
}
class _TaskCalendarState extends State<TaskCalendar> {
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  late final CollectionReference<Map<String, dynamic>> tasks;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  @override
  void initState() {
    super.initState();
    tasks = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('tasks');
    stream = tasks.orderBy('createdAt', descending: true).snapshots(includeMetadataChanges: true);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Календарь задач'), actions: [
      TextButton(onPressed: () => setState(() => selected = DateUtils.dateOnly(DateTime.now())), child: const Text('Сегодня')),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      CalendarDatePicker(key: ValueKey(selected), initialDate: selected,
        firstDate: DateTime(1900), lastDate: DateTime(2200),
        onDateChanged: (v) => setState(() => selected = DateUtils.dateOnly(v))),
      const Divider(),
      Text('Задачи на ${dateLabel(selected)}', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, s) {
        if (s.hasError) return Text(errorText(s.error!));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs.where((doc) {
          final stamp = doc.data()['deadline'];
          return stamp is Timestamp && DateUtils.isSameDay(stamp.toDate(), selected);
        }).toList();
        if (docs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('На этот день задач со сроком нет. Задачи без срока доступны во вкладке «Задачи».'));
        return Column(children: docs.map((doc) {
          final data = doc.data(); final done = data['status'] == 'done';
          return ListTile(
            leading: Icon(done ? Icons.check_circle_outline : Icons.radio_button_unchecked),
            title: Text(data['title'] as String? ?? '', style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
            subtitle: Text(data['description'] as String? ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskEditor(reference: doc.reference, initial: data))),
          );
        }).toList());
      }),
    ]),
  );
}
