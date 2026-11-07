import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../app.dart' show AccountScreen, errorText;
import '../../../core/theme/app_theme.dart';
import '../../teams/membership_app.dart' show MembershipTeams;
import '../../teams/team_tasks.dart' show teamStatuses;
import '../../notifications/reminders_app.dart' show ReminderEngine, ReminderPage;
import 'calendar_app.dart' show TaskCalendar;
import 'workspace.dart' show Workspace, TaskEditor, dateLabel;
import 'task_details_page.dart';

const todaySections = {'overdue': 'Просроченные', 'today': 'Сегодня', 'upcoming': 'Предстоящие', 'noDate': 'Без срока'};
String? todaySection(Map<String, dynamic> data, DateTime now) {
  if (data['status'] == 'done') return null;
  final stamp = data['deadline'];
  if (stamp is! Timestamp) return 'noDate';
  final day = DateUtils.dateOnly(stamp.toDate());
  final today = DateUtils.dateOnly(now);
  if (day.isBefore(today)) return 'overdue';
  return day == today ? 'today' : 'upcoming';
}
bool todaySearchMatches(Map<String, dynamic> data, String source, String query) => '${data['title'] ?? ''} ${data['description'] ?? ''} $source'.toLowerCase().contains(query.trim().toLowerCase());

class TodayApp extends StatefulWidget {
  const TodayApp({super.key});
  @override
  State<TodayApp> createState() => _TodayAppState();
}
class _TodayAppState extends State<TodayApp> {
  late final Stream<User?> auth;
  StreamSubscription<User?>? subscription;
  @override
  void initState() { super.initState(); auth = FirebaseAuth.instance.authStateChanges(); subscription = auth.listen((user) => ReminderEngine.instance.bind(user?.uid)); }
  @override
  void dispose() { subscription?.cancel(); ReminderEngine.instance.bind(null); super.dispose(); }
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'TaskFlow', debugShowCheckedModeBanner: false, theme: AppTheme.light, darkTheme: AppTheme.dark, home: StreamBuilder<User?>(stream: auth, builder: (context, snapshot) {
    if (snapshot.hasError) return Scaffold(body: Center(child: Text(errorText(snapshot.error!))));
    if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return snapshot.data == null ? const AccountScreen() : TodayShell(key: ValueKey(snapshot.data!.uid), uid: snapshot.data!.uid);
  }));
}
class TodayShell extends StatefulWidget {
  const TodayShell({super.key, required this.uid});
  final String uid;
  @override
  State<TodayShell> createState() => _TodayShellState();
}
class _TodayShellState extends State<TodayShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(body: IndexedStack(index: index, children: [TodayPage(uid: widget.uid), TaskCalendar(uid: widget.uid), ReminderPage(uid: widget.uid), MembershipTeams(uid: widget.uid)]), bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (value) => setState(() => index = value), destinations: const [
    NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Сегодня'), NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календарь'), NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Уведомления'), NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Команды'),
  ]));
}
class _TodayItem {
  const _TodayItem(this.doc, {this.teamId, this.teamData});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String? teamId;
  final Map<String, dynamic>? teamData;
  String get source => teamId == null ? 'Личная' : teamData?['name'] as String? ?? 'Команда';
}
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.uid});
  final String uid;
  @override
  State<TodayPage> createState() => _TodayPageState();
}
class _TodayPageState extends State<TodayPage> with WidgetsBindingObserver {
  final subscriptions = <StreamSubscription<dynamic>>[];
  final teamSubscriptions = <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final teams = <String, Map<String, dynamic>>{};
  final teamTasks = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  final loadingTeams = <String>{};
  final errors = <String, String>{};
  final pending = <String>{};
  final search = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> personal = [];
  bool personalLoaded = false;
  bool teamsLoaded = false;
  bool signingOut = false;
  int generation = 0;
  Timer? clock;
  void stopListeners() {
    for (final sub in subscriptions) { unawaited(sub.cancel()); }
    subscriptions.clear();
    for (final sub in teamSubscriptions.values) { unawaited(sub.cancel()); }
    teamSubscriptions.clear();
  }
  void bind() {
    final token = ++generation; stopListeners();
    personal = []; teams.clear(); teamTasks.clear(); loadingTeams.clear(); errors.clear(); personalLoaded = false; teamsLoaded = false;
    subscriptions.add(FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('tasks').snapshots(includeMetadataChanges: true).listen((snapshot) {
      if (!mounted || token != generation) return;
      setState(() { personal = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(snapshot.docs); personalLoaded = true; errors.remove('personal'); });
    }, onError: (Object error) { if (mounted && token == generation) setState(() { personal = []; personalLoaded = true; errors['personal'] = errorText(error); }); }));
    subscriptions.add(FirebaseFirestore.instance.collection('organizations').where('memberIds', arrayContains: widget.uid).snapshots().listen((snapshot) {
      if (!mounted || token != generation) return;
      setState(() {
        teamsLoaded = true; errors.remove('teams');
        final ids = snapshot.docs.map((doc) => doc.id).toSet();
        for (final id in teams.keys.toList()) {
          if (!ids.contains(id)) { final sub = teamSubscriptions.remove(id); if (sub != null) unawaited(sub.cancel()); teams.remove(id); teamTasks.remove(id); loadingTeams.remove(id); errors.remove(id); }
        }
        for (final doc in snapshot.docs) {
          final id = doc.id; teams[id] = doc.data();
          if (teamSubscriptions.containsKey(id)) continue;
          loadingTeams.add(id);
          teamSubscriptions[id] = doc.reference.collection('tasks').where('assignedTo', isEqualTo: widget.uid).snapshots(includeMetadataChanges: true).listen((tasks) {
            if (!mounted || token != generation || !teams.containsKey(id)) return;
            setState(() { teamTasks[id] = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(tasks.docs); loadingTeams.remove(id); errors.remove(id); });
          }, onError: (Object error) { if (mounted && token == generation && teams.containsKey(id)) setState(() { teamTasks.remove(id); loadingTeams.remove(id); errors[id] = errorText(error); }); });
        }
      });
    }, onError: (Object error) {
      if (!mounted || token != generation) return;
      setState(() {
        for (final sub in teamSubscriptions.values) { unawaited(sub.cancel()); }
        teamSubscriptions.clear(); teams.clear(); teamTasks.clear(); loadingTeams.clear(); teamsLoaded = true; errors['teams'] = errorText(error);
      });
    }));
  }
  void startClock() { clock?.cancel(); clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); }); }
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); bind(); final state = WidgetsBinding.instance.lifecycleState; if (state == null || state == AppLifecycleState.resumed) startClock(); }
  @override
  void didUpdateWidget(covariant TodayPage old) { super.didUpdateWidget(old); if (old.uid != widget.uid) { search.clear(); bind(); } }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) { startClock(); if (mounted) setState(() {}); } else { clock?.cancel(); } }
  @override
  void dispose() { generation++; stopListeners(); clock?.cancel(); search.dispose(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  Future<void> change(_TodayItem item, String status) async {
    final key = item.doc.reference.path;
    if (pending.contains(key)) return;
    setState(() { pending.add(key); errors.remove('write'); });
    try {
      if (FirebaseAuth.instance.currentUser?.uid != widget.uid) throw StateError('Аккаунт изменился');
      await item.doc.reference.update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (error) { if (mounted) setState(() => errors['write'] = errorText(error)); }
    finally { if (mounted) setState(() => pending.remove(key)); }
  }
  void createPersonalTask() {
    final reference = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('tasks').doc();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskEditor(reference: reference)));
  }
  void open(_TodayItem item) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskDetailsPage(uid: widget.uid, reference: item.doc.reference, teamId: item.teamId)));
  }
  Future<void> logout() async {
    if (signingOut) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Выйти из аккаунта?'), content: const Text('Запланированные напоминания на этом устройстве будут отменены.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти'))]));
    if (confirmed != true || !mounted) return;
    setState(() => signingOut = true);
    try { await FirebaseAuth.instance.signOut(); }
    catch (error) { if (mounted) setState(() => errors['logout'] = errorText(error)); }
    finally { if (mounted) setState(() => signingOut = false); }
  }
  Widget tile(_TodayItem item) {
    final data = item.doc.data(); final stamp = data['deadline']; final busy = pending.contains(item.doc.reference.path);
    final statuses = item.teamId == null ? const {'todo': 'Новая', 'done': 'Выполнена'} : teamStatuses;
    return Card(child: ListTile(leading: Checkbox(value: false, onChanged: busy ? null : (_) { unawaited(change(item, 'done')); }), title: Text(data['title'] as String? ?? ''),
      subtitle: Text('${item.source}${stamp is Timestamp ? ' · ${dateLabel(stamp.toDate())}' : ''}\n${busy || item.doc.metadata.hasPendingWrites ? 'Синхронизация…' : teamStatuses[data['status']] ?? 'Новая'}'),
      onTap: busy ? null : () => open(item), trailing: PopupMenuButton<String>(enabled: !busy, tooltip: 'Изменить статус', onSelected: (value) { unawaited(change(item, value)); }, itemBuilder: (_) => statuses.entries.map((entry) => PopupMenuItem(value: entry.key, child: Text(entry.value))).toList())));
  }
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = <_TodayItem>[for (final doc in personal) _TodayItem(doc), for (final entry in teamTasks.entries) if (teams.containsKey(entry.key)) for (final doc in entry.value) if (doc.data()['assignedTo'] == widget.uid) _TodayItem(doc, teamId: entry.key, teamData: teams[entry.key])];
    final groups = <String, List<_TodayItem>>{for (final key in todaySections.keys) key: []};
    var active = 0; var todayCount = 0; var overdueCount = 0;
    for (final item in items) {
      final section = todaySection(item.doc.data(), now); if (section == null) continue;
      active++; if (section == 'today') todayCount++; if (section == 'overdue') overdueCount++;
      if (todaySearchMatches(item.doc.data(), item.source, search.text)) groups[section]!.add(item);
    }
    for (final group in groups.values) {
      group.sort((a, b) { final ad = a.doc.data()['deadline']; final bd = b.doc.data()['deadline']; final order = (ad is Timestamp ? ad.millisecondsSinceEpoch : 0).compareTo(bd is Timestamp ? bd.millisecondsSinceEpoch : 0); return order != 0 ? order : a.doc.reference.path.compareTo(b.doc.reference.path); });
    }
    final loading = !personalLoaded || !teamsLoaded || loadingTeams.isNotEmpty;
    final found = groups.values.fold<int>(0, (sum, group) => sum + group.length);
    return Scaffold(appBar: AppBar(title: const Text('Сегодня'), actions: [
      IconButton(tooltip: 'Все личные задачи', icon: const Icon(Icons.list_alt), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Workspace(uid: widget.uid)))),
      IconButton(tooltip: 'Обновить подключения', icon: const Icon(Icons.refresh), onPressed: () => setState(bind)),
      IconButton(tooltip: 'Выйти', icon: const Icon(Icons.logout), onPressed: signingOut ? null : logout),
    ]), floatingActionButton: FloatingActionButton.extended(onPressed: createPersonalTask, icon: const Icon(Icons.add), label: const Text('Личная задача')), body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
      Text(dateLabel(now), style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8),
      Text('На сегодня: $todayCount · Просрочено: $overdueCount · Всего активных: $active'),
      const Text('Личные задачи и мои назначения из всех команд. Завершённые задачи доступны в личном списке и внутри команды.'),
      const SizedBox(height: 12),
      TextField(controller: search, decoration: InputDecoration(labelText: 'Найти задачу или команду', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(tooltip: 'Очистить поиск', onPressed: () => setState(search.clear), icon: const Icon(Icons.clear))), onChanged: (_) => setState(() {})),
      if (loading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
      for (final error in errors.entries) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('${error.key == 'personal' ? 'Личные задачи' : error.key == 'teams' ? 'Команды' : teams[error.key]?['name'] ?? 'Действие'}: ${error.value}', style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (!loading && errors.isEmpty && found == 0) Padding(padding: const EdgeInsets.all(24), child: Text(search.text.trim().isEmpty ? 'Активных задач пока нет. Создайте личную задачу или откройте «Команды».' : 'Ничего не найдено. Измените запрос.')),
      if (!loading && search.text.trim().isEmpty && todayCount == 0 && active > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('На сегодня задач нет. Остальные задачи — в разделах ниже.')),
      for (final section in todaySections.entries) if (groups[section.key]!.isNotEmpty) ExpansionTile(key: ValueKey('${section.key}:${search.text.trim().isNotEmpty}'), initiallyExpanded: search.text.trim().isNotEmpty || section.key == 'today' || section.key == 'overdue', title: Text(section.value), trailing: Text('${groups[section.key]!.length}'), children: groups[section.key]!.map(tile).toList()),
    ]));
  }
}
