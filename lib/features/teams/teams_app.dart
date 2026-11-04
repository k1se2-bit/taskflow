import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart' show AccountScreen, errorText;
import '../../core/theme/app_theme.dart';
import '../notifications/reminders_app.dart' show ReminderEngine, ReminderPage;
import '../tasks/presentation/workspace.dart' show Workspace;
import '../tasks/presentation/calendar_app.dart' show TaskCalendar;

class TeamsApp extends StatefulWidget {
  const TeamsApp({super.key});
  @override
  State<TeamsApp> createState() => _TeamsAppState();
}
class _TeamsAppState extends State<TeamsApp> {
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
    home: StreamBuilder<User?>(stream: auth, builder: (context, snapshot) {
      if (snapshot.hasError) return Scaffold(body: Center(child: Text(errorText(snapshot.error!))));
      if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return snapshot.data == null ? const AccountScreen() : TeamsShell(key: ValueKey(snapshot.data!.uid), uid: snapshot.data!.uid);
    }));
}
class TeamsShell extends StatefulWidget {
  const TeamsShell({super.key, required this.uid});
  final String uid;
  @override
  State<TeamsShell> createState() => _TeamsShellState();
}
class _TeamsShellState extends State<TeamsShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: index, children: [Workspace(uid: widget.uid), TaskCalendar(uid: widget.uid), ReminderPage(uid: widget.uid), TeamsPage(uid: widget.uid)]),
    bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'),
      NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календарь'),
      NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Уведомления'),
      NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Команды'),
    ]),
  );
}
class TeamsPage extends StatefulWidget {
  const TeamsPage({super.key, required this.uid});
  final String uid;
  @override
  State<TeamsPage> createState() => _TeamsPageState();
}
class _TeamsPageState extends State<TeamsPage> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  Stream<QuerySnapshot<Map<String, dynamic>>> watch() => FirebaseFirestore.instance.collection('organizations').where('memberIds', arrayContains: widget.uid).snapshots();
  @override
  void initState() { super.initState(); stream = watch(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мои команды')),
    floatingActionButton: FloatingActionButton(tooltip: 'Создать команду', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CreateTeamPage(uid: widget.uid))), child: const Icon(Icons.group_add_outlined)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${errorText(snapshot.error!)} Если вы только обновили приложение, опубликуйте новые правила из firestore.rules в Firebase Console.'),
        TextButton(onPressed: () => setState(() => stream = watch()), child: const Text('Повторить')),
      ])));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snapshot.data!.docs.toList()..sort((a, b) => (a.data()['name'] as String).compareTo(b.data()['name'] as String));
      if (docs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Команд пока нет. Нажмите +, чтобы создать команду. Личные задачи останутся приватными.')));
      return ListView.builder(padding: const EdgeInsets.only(bottom: 88), itemCount: docs.length, itemBuilder: (context, i) {
        final doc = docs[i]; final data = doc.data(); final owner = data['ownerId'] == widget.uid;
        return ListTile(leading: const Icon(Icons.groups_outlined), title: Text(data['name'] as String? ?? ''), subtitle: Text(owner ? 'Ваша роль: владелец' : 'Ваша роль: участник'), trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamDetailsPage(uid: widget.uid, reference: doc.reference))));
      });
    }),
  );
}
class CreateTeamPage extends StatefulWidget {
  const CreateTeamPage({super.key, required this.uid});
  final String uid;
  @override
  State<CreateTeamPage> createState() => _CreateTeamPageState();
}
class _CreateTeamPageState extends State<CreateTeamPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  late final DocumentReference<Map<String, dynamic>> reference;
  bool busy = false;
  String? error;
  @override
  void initState() { super.initState(); reference = FirebaseFirestore.instance.collection('organizations').doc(); }
  @override
  void dispose() { name.dispose(); super.dispose(); }
  Future<void> create() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    var success = false;
    try {
      if (FirebaseAuth.instance.currentUser?.uid != widget.uid) throw StateError('Аккаунт изменился. Откройте приложение заново.');
      await reference.set({'name': name.text.trim(), 'ownerId': widget.uid, 'memberIds': [widget.uid], 'createdAt': FieldValue.serverTimestamp()});
      success = true;
    } catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(appBar: AppBar(title: const Text('Создать команду')),
    body: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
      TextFormField(controller: name, enabled: !busy, maxLength: 100, decoration: const InputDecoration(labelText: 'Название команды'), validator: (v) => v == null || v.trim().isEmpty ? 'Введите название команды' : null),
      const Text('Вы станете владельцем команды. Личные задачи не будут автоматически переданы в команду. Приглашения участников появятся в следующем обновлении.'),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 24), FilledButton(onPressed: busy ? null : create, child: Text(busy ? 'Создание…' : 'Создать')),
    ])),
  ));
}
class TeamDetailsPage extends StatefulWidget {
  const TeamDetailsPage({super.key, required this.uid, required this.reference});
  final String uid;
  final DocumentReference<Map<String, dynamic>> reference;
  @override
  State<TeamDetailsPage> createState() => _TeamDetailsPageState();
}
class _TeamDetailsPageState extends State<TeamDetailsPage> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> stream;
  @override
  void initState() { super.initState(); stream = widget.reference.snapshots(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Команда')), body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, snapshot) {
    if (snapshot.hasError) return Center(child: Text(errorText(snapshot.error!)));
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final data = snapshot.data!.data();
    if (data == null) return const Center(child: Text('Команда недоступна'));
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(data['name'] as String? ?? '', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16), Text(data['ownerId'] == widget.uid ? 'Ваша роль: владелец' : 'Ваша роль: участник'),
      Text('Участников: ${(data['memberIds'] as List).length}'),
      const SizedBox(height: 16), const Text('Это первый этап командного режима. Приглашения, командные задачи и управление участниками пока недоступны.'),
    ]);
  }));
}
