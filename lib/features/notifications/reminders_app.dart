import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../app.dart' show AccountScreen, errorText;
import '../../core/theme/app_theme.dart';
import '../tasks/presentation/workspace.dart' show Workspace, dateLabel;
import '../tasks/presentation/calendar_app.dart' show TaskCalendar;

typedef ReminderDoc = QueryDocumentSnapshot<Map<String, dynamic>>;
String reminderKey(String teamId, String taskId) => '${teamId}_$taskId';
String reminderTime(dynamic stamp) {
  if (stamp is! Timestamp) return 'Напоминание не задано';
  final date = stamp.toDate();
  return '${dateLabel(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}${date.isBefore(DateTime.now()) ? ' — время прошло' : ''}';
}
class _ReminderPlan {
  const _ReminderPlan(this.path, this.title, this.body, this.time);
  final String path;
  final String title;
  final String body;
  final DateTime time;
  String get signature => '$path|${time.millisecondsSinceEpoch}|$title|$body';
}
class ReminderEngine {
  static final instance = ReminderEngine();
  final plugin = FlutterLocalNotificationsPlugin();
  final status = ValueNotifier<String>('Подключение напоминаний…');
  final subscriptions = <StreamSubscription<dynamic>>[];
  final teamSubscriptions = <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final teamNames = <String, String>{};
  final teamTasks = <String, List<ReminderDoc>>{};
  List<ReminderDoc> personal = [];
  Map<String, dynamic> preferences = {};
  Future<void> queue = Future<void>.value();
  String? uid;
  int generation = 0;
  bool initialized = false;
  final plans = <int, String>{};
  static const details = NotificationDetails(android: AndroidNotificationDetails('taskflow_reminders', 'Напоминания о задачах', channelDescription: 'Уведомления TaskFlow', importance: Importance.high, priority: Priority.high));
  Future<void> initialize() async {
    if (initialized) return;
    final ok = await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    if (ok != true) throw StateError('Не удалось подключить уведомления');
    initialized = true;
  }
  void enqueue(Future<void> Function() job) {
    queue = queue.then((_) => job()).catchError((Object e) { status.value = 'Ошибка напоминаний: $e'; });
  }
  void schedule(int token) { enqueue(() async { if (token == generation && uid != null) await reconcile(token); }); }
  void setPreferences(Map<String, dynamic>? data) {
    final raw = data?['teamReminders'];
    preferences = raw is Map ? Map<String, dynamic>.from(raw) : {};
  }
  void bind(String? next) {
    final token = ++generation;
    uid = next;
    for (final sub in subscriptions) { unawaited(sub.cancel()); }
    subscriptions.clear();
    for (final sub in teamSubscriptions.values) { unawaited(sub.cancel()); }
    teamSubscriptions.clear(); teamNames.clear(); teamTasks.clear(); personal = []; preferences = {};
    enqueue(() async { await initialize(); await plugin.cancelAll(); plans.clear(); if (token == generation) status.value = next == null ? 'Выполнен выход. Напоминания отменены.' : 'Синхронизация напоминаний…'; });
    if (next == null) return;
    final user = FirebaseFirestore.instance.collection('users').doc(next);
    subscriptions.add(user.collection('tasks').snapshots().listen((snapshot) {
      if (token != generation) return;
      personal = List<ReminderDoc>.of(snapshot.docs); schedule(token);
    }, onError: (Object e) { if (token == generation) { personal = []; schedule(token); status.value = errorText(e); } }));
    subscriptions.add(user.snapshots().listen((snapshot) {
      if (token != generation) return;
      setPreferences(snapshot.data()); schedule(token);
    }, onError: (Object e) { if (token == generation) { preferences = {}; schedule(token); status.value = errorText(e); } }));
    subscriptions.add(FirebaseFirestore.instance.collection('organizations').where('memberIds', arrayContains: next).snapshots().listen((snapshot) {
      if (token != generation) return;
      final ids = snapshot.docs.map((doc) => doc.id).toSet();
      for (final id in teamSubscriptions.keys.toList()) {
        if (!ids.contains(id)) { unawaited(teamSubscriptions.remove(id)!.cancel()); teamNames.remove(id); teamTasks.remove(id); }
      }
      for (final doc in snapshot.docs) {
        teamNames[doc.id] = doc.data()['name'] as String? ?? 'Команда';
        if (teamSubscriptions.containsKey(doc.id)) continue;
        final id = doc.id;
        teamSubscriptions[id] = doc.reference.collection('tasks').where('assignedTo', isEqualTo: next).snapshots().listen((tasks) {
          if (token != generation || !teamNames.containsKey(id)) return;
          teamTasks[id] = List<ReminderDoc>.of(tasks.docs); schedule(token);
        }, onError: (Object e) { if (token == generation) { teamTasks.remove(id); schedule(token); status.value = errorText(e); } });
      }
      schedule(token);
    }, onError: (Object e) {
      if (token != generation) return;
      for (final sub in teamSubscriptions.values) { unawaited(sub.cancel()); }
      teamSubscriptions.clear(); teamNames.clear(); teamTasks.clear(); schedule(token); status.value = errorText(e);
    }));
  }
  int identifier(String path, bool team) {
    var hash = 2166136261;
    for (final c in path.codeUnits) { hash = ((hash ^ c) * 16777619) & 0x3fffffff; }
    final value = hash == 0 ? 1 : hash;
    return team ? value | 0x40000000 : value;
  }
  Future<void> reconcile(int token) async {
    final desired = <int, _ReminderPlan>{};
    void add(ReminderDoc doc, dynamic stamp, String? teamId) {
      if (doc.data()['status'] == 'done' || stamp is! Timestamp || !stamp.toDate().isAfter(DateTime.now())) return;
      final path = doc.reference.path;
      final id = identifier(path, teamId != null);
      if (desired.containsKey(id)) throw StateError('Конфликт идентификаторов напоминаний');
      desired[id] = _ReminderPlan(path, 'TaskFlow: ${doc.data()['title'] ?? 'Задача'}', teamId == null ? 'Пора заняться личной задачей' : 'Команда: ${teamNames[teamId] ?? 'Команда'}', stamp.toDate());
    }
    for (final doc in personal) { add(doc, doc.data()['remindAt'], null); }
    for (final entry in teamTasks.entries) {
      if (!teamNames.containsKey(entry.key)) continue;
      for (final doc in entry.value) {
        if (doc.data()['assignedTo'] != uid) continue;
        final pref = preferences[reminderKey(entry.key, doc.id)];
        if (pref is Map) add(doc, pref['remindAt'], entry.key);
      }
    }
    for (final id in plans.keys.toList()) {
      if (token != generation) return;
      if (!desired.containsKey(id)) { await plugin.cancel(id); plans.remove(id); }
    }
    final enabled = await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
    if (token != generation) return;
    if (enabled == false) { status.value = 'Уведомления запрещены. Нажмите «Разрешить и проверить».'; return; }
    for (final entry in desired.entries) {
      if (token != generation) return;
      final item = entry.value;
      if (plans[entry.key] == item.signature || !item.time.isAfter(DateTime.now())) continue;
      await plugin.zonedSchedule(entry.key, item.title, item.body, tz.TZDateTime.from(item.time.toUtc(), tz.UTC), details, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime, payload: item.path);
      plans[entry.key] = item.signature;
    }
    if (token == generation) await updatePendingCount();
  }
  Future<void> updatePendingCount() async {
    if (!initialized || uid == null) return;
    final token = generation;
    final pending = await plugin.pendingNotificationRequests();
    final enabled = await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
    if (token != generation || uid == null) return;
    if (enabled == false) {
      status.value = 'Уведомления запрещены. Нажмите «Разрешить и проверить».';
      return;
    }
    status.value = 'Ожидают показа на этом устройстве: ${pending.length}. Android может задерживать показ.';
  }
  Future<void> refresh() async {
    final current = uid; final token = generation;
    if (current == null) return;
    final user = FirebaseFirestore.instance.collection('users').doc(current);
    final tasks = await user.collection('tasks').get();
    final profile = await user.get();
    if (token != generation) return;
    personal = List<ReminderDoc>.of(tasks.docs); setPreferences(profile.data()); schedule(token); await queue;
  }
  Future<void> permission() async {
    await initialize();
    final allowed = await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    if (allowed == false) throw StateError('Разрешите уведомления в настройках Android');
  }
  Future<void> test() async {
    await permission();
    await plugin.show(0, 'TaskFlow', 'Уведомления включены', details);
    await refresh();
    await updatePendingCount();
  }
}

class RemindersApp extends StatefulWidget {
  const RemindersApp({super.key});
  @override
  State<RemindersApp> createState() => _RemindersAppState();
}
class _RemindersAppState extends State<RemindersApp> {
  late final Stream<User?> auth;
  StreamSubscription<User?>? subscription;
  @override
  void initState() { super.initState(); auth = FirebaseAuth.instance.authStateChanges(); subscription = auth.listen((user) => ReminderEngine.instance.bind(user?.uid)); }
  @override
  void dispose() { subscription?.cancel(); ReminderEngine.instance.bind(null); super.dispose(); }
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'TaskFlow', debugShowCheckedModeBanner: false, theme: AppTheme.light, darkTheme: AppTheme.dark, home: StreamBuilder<User?>(stream: auth, builder: (context, s) {
    if (s.hasError) return Scaffold(body: Center(child: Text(errorText(s.error!))));
    if (s.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return s.data == null ? const AccountScreen() : ReminderShell(key: ValueKey(s.data!.uid), uid: s.data!.uid);
  }));
}
class ReminderShell extends StatefulWidget {
  const ReminderShell({super.key, required this.uid});
  final String uid;
  @override
  State<ReminderShell> createState() => _ReminderShellState();
}
class _ReminderShellState extends State<ReminderShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(body: IndexedStack(index: index, children: [Workspace(uid: widget.uid), TaskCalendar(uid: widget.uid), ReminderPage(uid: widget.uid)]), bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'), NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календарь'), NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Уведомления')]));
}
class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key, required this.uid});
  final String uid;
  @override
  State<ReminderPage> createState() => _ReminderPageState();
}
class _ReminderPageState extends State<ReminderPage> with WidgetsBindingObserver {
  late final DocumentReference<Map<String, dynamic>> user;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> personal;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> teams;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> settings;
  Timer? counterTimer;
  bool counterBusy = false;
  bool teamMode = false;
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    user = FirebaseFirestore.instance.collection('users').doc(widget.uid);
    personal = user.collection('tasks').orderBy('createdAt', descending: true).snapshots();
    teams = FirebaseFirestore.instance.collection('organizations').where('memberIds', arrayContains: widget.uid).snapshots();
    settings = user.snapshots();
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) startCounter();
  }
  void startCounter() {
    counterTimer?.cancel();
    counterTimer = Timer.periodic(const Duration(seconds: 15), (_) { unawaited(refreshPendingCount()); });
    unawaited(refreshPendingCount());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { startCounter(); }
    else { counterTimer?.cancel(); counterTimer = null; }
  }
  Future<void> refreshPendingCount() async {
    if (counterBusy || !mounted) return;
    counterBusy = true;
    try {
      final engine = ReminderEngine.instance;
      await engine.queue;
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != widget.uid) return;
      await engine.updatePendingCount();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => message = 'Не удалось обновить счётчик: ${errorText(e)}');
    } finally { counterBusy = false; }
  }
  @override
  void dispose() { counterTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try { await action(); } catch (e) { if (mounted) setState(() => message = 'Не удалось выполнить действие: ${errorText(e)}'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> choose(ReminderDoc doc, String? teamId) async {
    if (busy) return;
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now, firstDate: DateUtils.dateOnly(now), lastDate: DateTime(now.year + 5));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))));
    if (time == null || !mounted) return;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(DateTime.now())) { setState(() => message = 'Выберите время в будущем.'); return; }
    await perform(() async {
      if (FirebaseAuth.instance.currentUser?.uid != widget.uid) throw StateError('Аккаунт изменился.');
      await ReminderEngine.instance.permission();
      if (teamId == null) { await doc.reference.update({'remindAt': Timestamp.fromDate(when), 'updatedAt': FieldValue.serverTimestamp()}); }
      else {
        final latest = await doc.reference.get();
        if (latest.data()?['assignedTo'] != widget.uid || latest.data()?['status'] == 'done') throw StateError('Задача выполнена или уже назначена другому участнику.');
        await user.set({'teamReminders': {reminderKey(teamId, doc.id): {'teamId': teamId, 'taskId': doc.id, 'remindAt': Timestamp.fromDate(when)}}}, SetOptions(merge: true));
      }
      await ReminderEngine.instance.refresh();
    });
  }
  Future<void> cancel(ReminderDoc doc, String? teamId) => perform(() async {
    if (FirebaseAuth.instance.currentUser?.uid != widget.uid) throw StateError('Аккаунт изменился.');
    if (teamId == null) { await doc.reference.update({'remindAt': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()}); }
    else { await user.update({'teamReminders.${reminderKey(teamId, doc.id)}': FieldValue.delete()}); }
    await ReminderEngine.instance.refresh();
  });
  Widget taskTile(ReminderDoc doc, dynamic stamp, String? teamId) => ListTile(title: Text(doc.data()['title'] as String? ?? ''), subtitle: Text(reminderTime(stamp)), onTap: busy ? null : () => choose(doc, teamId), trailing: stamp is! Timestamp ? const Icon(Icons.add_alarm) : IconButton(tooltip: 'Отменить напоминание', onPressed: busy ? null : () => cancel(doc, teamId), icon: const Icon(Icons.alarm_off)));
  Widget personalList() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: personal, builder: (context, s) {
    if (s.hasError) return Text(errorText(s.error!));
    if (!s.hasData) return const Center(child: CircularProgressIndicator());
    final docs = s.data!.docs.where((d) => d.data()['status'] != 'done').toList();
    if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Активных личных задач нет.'));
    return Column(children: docs.map((doc) => taskTile(doc, doc.data()['remindAt'], null)).toList());
  });
  Widget teamList() => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: settings, builder: (context, prefs) {
    if (prefs.hasError) return Text(errorText(prefs.error!));
    if (!prefs.hasData) return const Center(child: CircularProgressIndicator());
    final raw = prefs.data!.data()?['teamReminders'];
    final values = raw is Map ? raw : const {};
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: teams, builder: (context, s) {
      if (s.hasError) return Text(errorText(s.error!));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      if (s.data!.docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Доступных команд нет.'));
      return Column(children: s.data!.docs.map((team) => Card(child: ExpansionTile(key: PageStorageKey('reminders:${widget.uid}:${team.id}'), title: Text(team.data()['name'] as String? ?? 'Команда'), subtitle: const Text('Только назначенные мне задачи'), children: [
        AssignedReminderTasks(key: ValueKey('${widget.uid}:${team.id}'), team: team.reference, uid: widget.uid, builder: (doc) {
          final pref = values[reminderKey(team.id, doc.id)];
          return taskTile(doc, pref is Map ? pref['remindAt'] : null, team.id);
        }),
      ]))).toList());
    });
  });
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Напоминания'), actions: [IconButton(tooltip: 'Обновить счётчик', onPressed: () { unawaited(refreshPendingCount()); }, icon: const Icon(Icons.refresh))]), body: ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Одно личное напоминание на задачу. Время — по часам устройства. Android может задерживать показ. Изменения с других устройств, выполнение и переназначение учитываются после синхронизации приложения. На закрытом или отключённом от сети устройстве старое уведомление может ещё сработать.'),
    const SizedBox(height: 12), FilledButton(onPressed: busy ? null : () => perform(() async { await ReminderEngine.instance.test(); }), child: const Text('Разрешить и проверить')),
    ValueListenableBuilder<String>(valueListenable: ReminderEngine.instance.status, builder: (_, value, __) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(value))),
    Wrap(spacing: 8, children: [ChoiceChip(label: const Text('Личные'), selected: !teamMode, onSelected: (_) => setState(() => teamMode = false)), ChoiceChip(label: const Text('Командные'), selected: teamMode, onSelected: (_) => setState(() => teamMode = true))]),
    if (teamMode) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Время командного напоминания видно только вам. Владелец не назначает его за другого исполнителя.')),
    if (message != null) Text(message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    if (busy) const LinearProgressIndicator(),
    if (teamMode) teamList() else personalList(),
  ]));
}
class AssignedReminderTasks extends StatefulWidget {
  const AssignedReminderTasks({super.key, required this.team, required this.uid, required this.builder});
  final DocumentReference<Map<String, dynamic>> team;
  final String uid;
  final Widget Function(ReminderDoc) builder;
  @override
  State<AssignedReminderTasks> createState() => _AssignedReminderTasksState();
}
class _AssignedReminderTasksState extends State<AssignedReminderTasks> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  @override
  void initState() { super.initState(); stream = widget.team.collection('tasks').where('assignedTo', isEqualTo: widget.uid).snapshots(); }
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, s) {
    if (s.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text(errorText(s.error!)));
    if (!s.hasData) return const Center(child: CircularProgressIndicator());
    final docs = s.data!.docs.where((doc) => doc.data()['status'] != 'done').toList();
    if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Назначенных активных задач нет.'));
    return Column(children: docs.map((doc) => widget.builder(doc)).toList());
  });
}
