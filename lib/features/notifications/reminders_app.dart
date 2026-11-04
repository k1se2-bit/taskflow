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

class ReminderEngine {
  static final instance = ReminderEngine();
  final plugin = FlutterLocalNotificationsPlugin();
  final status = ValueNotifier<String>('Подключение напоминаний…');
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
  Future<void> queue = Future<void>.value();
  String? uid;
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
  void bind(String? next) {
    uid = next;
    subscription?.cancel();
    enqueue(() async { await initialize(); await plugin.cancelAll(); plans.clear(); });
    if (next == null) return;
    subscription = FirebaseFirestore.instance.collection('users').doc(next).collection('tasks').snapshots().listen((snapshot) {
      enqueue(() async { if (uid == next) await reconcile(snapshot.docs); });
    }, onError: (Object e) { if (uid == next) status.value = errorText(e); });
  }
  int identifier(String id) {
    var hash = 2166136261;
    for (final c in id.codeUnits) { hash = ((hash ^ c) * 16777619) & 0x7fffffff; }
    return hash == 0 ? 1 : hash;
  }
  Future<void> reconcile(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final desired = <int, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final data = doc.data(); final stamp = data['remindAt'];
      if (data['status'] == 'done' || stamp is! Timestamp || !stamp.toDate().isAfter(DateTime.now())) continue;
      final id = identifier(doc.id);
      if (desired.containsKey(id)) throw StateError('Конфликт идентификаторов напоминаний');
      desired[id] = doc;
    }
    for (final id in plans.keys.toList()) {
      if (!desired.containsKey(id)) { await plugin.cancel(id); plans.remove(id); }
    }
    final enabled = await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
    if (enabled == false) { status.value = 'Уведомления запрещены. Нажмите «Разрешить и проверить».'; return; }
    for (final entry in desired.entries) {
      final data = entry.value.data(); final time = (data['remindAt'] as Timestamp).toDate();
      final title = data['title'] as String? ?? 'Задача';
      final signature = '${entry.value.id}|${time.millisecondsSinceEpoch}|$title';
      if (plans[entry.key] == signature || !time.isAfter(DateTime.now())) continue;
      await plugin.zonedSchedule(entry.key, 'TaskFlow: $title', 'Пора заняться задачей', tz.TZDateTime.from(time.toUtc(), tz.UTC), details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: entry.value.id);
      plans[entry.key] = signature;
    }
    status.value = 'Запланировано на этом устройстве: ${plans.length}. Android может задерживать неточные уведомления.';
  }
  Future<void> refresh() async {
    final current = uid;
    if (current == null) return;
    final result = await FirebaseFirestore.instance.collection('users').doc(current).collection('tasks').get();
    enqueue(() async { if (uid == current) await reconcile(result.docs); });
    await queue;
  }
  Future<void> test() async {
    await initialize();
    final allowed = await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    if (allowed == false) throw StateError('Разрешите уведомления в настройках Android');
    await plugin.show(0, 'TaskFlow', 'Уведомления включены', details);
    await refresh();
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
  void initState() {
    super.initState(); auth = FirebaseAuth.instance.authStateChanges();
    subscription = auth.listen((user) => ReminderEngine.instance.bind(user?.uid));
  }
  @override
  void dispose() { subscription?.cancel(); ReminderEngine.instance.bind(null); super.dispose(); }
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'TaskFlow', debugShowCheckedModeBanner: false, theme: AppTheme.light, darkTheme: AppTheme.dark,
    home: StreamBuilder<User?>(stream: auth, builder: (context, s) {
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
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: index, children: [Workspace(uid: widget.uid), TaskCalendar(uid: widget.uid), ReminderPage(uid: widget.uid)]),
    bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'), NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календарь'), NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Уведомления')]),
  );
}
class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key, required this.uid});
  final String uid;
  @override
  State<ReminderPage> createState() => _ReminderPageState();
}
class _ReminderPageState extends State<ReminderPage> {
  late final CollectionReference<Map<String, dynamic>> tasks;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState(); tasks = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('tasks');
    stream = tasks.orderBy('createdAt', descending: true).snapshots();
  }
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try { await action(); } catch (e) { if (mounted) setState(() => message = 'Не удалось выполнить действие: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> choose(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final now = DateTime.now(); final first = DateUtils.dateOnly(now);
    final date = await showDatePicker(context: context, initialDate: now, firstDate: first, lastDate: DateTime(now.year + 5));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))));
    if (time == null || !mounted) return;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(DateTime.now())) { setState(() => message = 'Выберите время в будущем.'); return; }
    await perform(() async {
      final android = ReminderEngine.instance;
      await android.initialize();
      final allowed = await android.plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      if (allowed == false) throw StateError('Уведомления запрещены в настройках Android');
      await doc.reference.update({'remindAt': Timestamp.fromDate(when), 'updatedAt': FieldValue.serverTimestamp()});
      await android.refresh();
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Напоминания')), body: ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Одно напоминание на задачу. Время выбирается по часам устройства. Это неточное расписание: Android может задерживать показ. Изменения с других устройств применяются здесь после синхронизации приложения.'),
    const SizedBox(height: 12),
    FilledButton(onPressed: busy ? null : () => perform(ReminderEngine.instance.test), child: const Text('Разрешить и проверить')),
    ValueListenableBuilder<String>(valueListenable: ReminderEngine.instance.status, builder: (_, value, __) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(value))),
    if (message != null) Text(message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    if (busy) const LinearProgressIndicator(),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, s) {
      if (s.hasError) return Text(errorText(s.error!));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final docs = s.data!.docs.where((d) => d.data()['status'] != 'done').toList();
      if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Создайте активную задачу во вкладке «Задачи».'));
      return Column(children: docs.map((doc) {
        final stamp = doc.data()['remindAt']; final date = stamp is Timestamp ? stamp.toDate() : null;
        final label = date == null ? 'Напоминание не задано' : '${dateLabel(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}${date.isBefore(DateTime.now()) ? ' — время прошло' : ''}';
        return ListTile(title: Text(doc.data()['title'] as String? ?? ''), subtitle: Text(label),
          onTap: busy ? null : () => choose(doc),
          trailing: date == null ? const Icon(Icons.add_alarm) : IconButton(tooltip: 'Отменить напоминание', onPressed: busy ? null : () => perform(() async {
            await doc.reference.update({'remindAt': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()}); await ReminderEngine.instance.refresh();
          }), icon: const Icon(Icons.alarm_off)));
      }).toList());
    }),
  ]));
}
