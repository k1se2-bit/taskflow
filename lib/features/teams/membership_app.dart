import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app.dart' show AccountScreen, errorText;
import '../../core/theme/app_theme.dart';
import '../notifications/reminders_app.dart' show ReminderEngine, ReminderPage;
import '../tasks/presentation/workspace.dart' show Workspace;
import '../tasks/presentation/calendar_app.dart' show TaskCalendar;
import 'teams_app.dart' show CreateTeamPage;
import 'team_tasks.dart';

class MembershipApp extends StatefulWidget {
  const MembershipApp({super.key});
  @override
  State<MembershipApp> createState() => _MembershipAppState();
}
class _MembershipAppState extends State<MembershipApp> {
  late final Stream<User?> auth;
  StreamSubscription<User?>? subscription;
  @override
  void initState() { super.initState(); auth = FirebaseAuth.instance.authStateChanges(); subscription = auth.listen((u) => ReminderEngine.instance.bind(u?.uid)); }
  @override
  void dispose() { subscription?.cancel(); ReminderEngine.instance.bind(null); super.dispose(); }
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'TaskFlow', debugShowCheckedModeBanner: false, theme: AppTheme.light, darkTheme: AppTheme.dark,
    home: StreamBuilder<User?>(stream: auth, builder: (context, s) {
      if (s.hasError) return Scaffold(body: Center(child: Text(errorText(s.error!))));
      if (s.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return s.data == null ? const AccountScreen() : MembershipShell(key: ValueKey(s.data!.uid), uid: s.data!.uid);
    }));
}
class MembershipShell extends StatefulWidget {
  const MembershipShell({super.key, required this.uid});
  final String uid;
  @override
  State<MembershipShell> createState() => _MembershipShellState();
}
class _MembershipShellState extends State<MembershipShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(body: IndexedStack(index: index, children: [Workspace(uid: widget.uid), TaskCalendar(uid: widget.uid), ReminderPage(uid: widget.uid), MembershipTeams(uid: widget.uid)]),
    bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'), NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календарь'), NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Уведомления'), NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Команды')]));
}
class MembershipTeams extends StatefulWidget {
  const MembershipTeams({super.key, required this.uid});
  final String uid;
  @override
  State<MembershipTeams> createState() => _MembershipTeamsState();
}
class _MembershipTeamsState extends State<MembershipTeams> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final teamId = TextEditingController();
  final name = TextEditingController();
  bool busy = false;
  String? message;
  Stream<QuerySnapshot<Map<String, dynamic>>> watch() => FirebaseFirestore.instance.collection('organizations').where('memberIds', arrayContains: widget.uid).snapshots();
  @override
  void initState() { super.initState(); stream = watch(); }
  @override
  void dispose() { teamId.dispose(); name.dispose(); super.dispose(); }
  Future<void> join() async {
    final id = teamId.text.trim(); final label = name.text.trim();
    if (busy) return;
    if (!RegExp(r'^[a-zA-Z0-9]{20}$').hasMatch(id) || label.isEmpty || label.length > 80) { setState(() => message = 'Введите ID команды (20 символов) и ваше имя.'); return; }
    setState(() { busy = true; message = null; });
    try {
      final ref = FirebaseFirestore.instance.collection('organizations').doc(id).collection('joinRequests').doc(widget.uid);
      final existing = await ref.get();
      if (!existing.exists) await ref.set({'uid': widget.uid, 'name': label, 'createdAt': FieldValue.serverTimestamp()});
      if (mounted) setState(() => message = existing.exists ? 'Заявка уже отправлена. Ожидайте решения владельца.' : 'Заявка отправлена. Доступ появится после одобрения владельцем.');
    } catch (e) { if (mounted) setState(() => message = '${errorText(e)} Проверьте ID, публикацию правил и не состоите ли вы уже в команде.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Команды')),
    floatingActionButton: FloatingActionButton(tooltip: 'Создать команду', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CreateTeamPage(uid: widget.uid))), child: const Icon(Icons.group_add_outlined)),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
      ExpansionTile(title: const Text('Подать заявку в команду'), children: [
        TextField(controller: teamId, enabled: !busy, decoration: const InputDecoration(labelText: 'ID команды от владельца')),
        TextField(controller: name, enabled: !busy, maxLength: 80, decoration: const InputDecoration(labelText: 'Ваше имя для заявки')),
        FilledButton(onPressed: busy ? null : join, child: Text(busy ? 'Отправка…' : 'Отправить заявку')),
        if (message != null) Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
      ]),
      const SizedBox(height: 16),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, s) {
        if (s.hasError) return Column(children: [Text('${errorText(s.error!)} Опубликуйте обновлённый firestore.rules.'), TextButton(onPressed: () => setState(() => stream = watch()), child: const Text('Повторить'))]);
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.docs.isEmpty) return const Text('Доступных команд пока нет. Создайте команду или отправьте заявку.');
        return Column(children: s.data!.docs.map((doc) => ListTile(title: Text(doc.data()['name'] as String? ?? ''), subtitle: Text(doc.data()['ownerId'] == widget.uid ? 'Владелец' : 'Участник'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MembershipDetails(uid: widget.uid, reference: doc.reference))))).toList());
      }),
    ]));
}
class MembershipDetails extends StatefulWidget {
  const MembershipDetails({super.key, required this.uid, required this.reference});
  final String uid;
  final DocumentReference<Map<String, dynamic>> reference;
  @override
  State<MembershipDetails> createState() => _MembershipDetailsState();
}
class _MembershipDetailsState extends State<MembershipDetails> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> teamStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> requests;
  bool busy = false;
  String? error;
  @override
  void initState() { super.initState(); teamStream = widget.reference.snapshots(); requests = widget.reference.collection('joinRequests').snapshots(); }
  Map<String, String> names(Map<String, dynamic>? data) {
    final raw = data?['memberNames'];
    if (raw is Map) return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
    return {};
  }
  Future<void> decide(QueryDocumentSnapshot<Map<String, dynamic>> doc, bool accept) async {
    if (busy) return;
    final label = doc.data()['name'] as String? ?? '';
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(accept ? 'Принять участника?' : 'Отклонить заявку?'), content: Text('$label\nUID: ${doc.id}\nИмя указано самим заявителем. Убедитесь, что это нужный человек.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Подтвердить'))]));
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; error = null; });
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final team = await transaction.get(widget.reference); final request = await transaction.get(doc.reference);
        if (!request.exists || team.data()?['ownerId'] != widget.uid) throw StateError('Заявка недоступна или нет прав владельца');
        if (accept) {
          final currentNames = names(team.data());
          currentNames[doc.id] = label.isEmpty ? 'Участник' : label;
          transaction.update(widget.reference, {'memberIds': FieldValue.arrayUnion([doc.id]), 'memberNames': currentNames});
        }
        transaction.delete(doc.reference);
      });
    } catch (e) { if (mounted) setState(() => error = '${errorText(e)} Максимум 50 участников в этой версии.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> copyId() async {
    try { await Clipboard.setData(ClipboardData(text: widget.reference.id)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID команды скопирован'))); }
    catch (e) { if (mounted) setState(() => error = errorText(e)); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Команда')), body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: teamStream, builder: (context, s) {
    if (s.hasError) return Center(child: Text(errorText(s.error!)));
    if (!s.hasData) return const Center(child: CircularProgressIndicator());
    final data = s.data!.data(); if (data == null) return const Center(child: Text('Команда недоступна'));
    final owner = data['ownerId'] == widget.uid;
    final memberIds = List<String>.from(data['memberIds'] as List);
    final memberNames = names(data);
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(data['name'] as String? ?? '', style: Theme.of(context).textTheme.headlineSmall),
      Text(owner ? 'Ваша роль: владелец' : 'Ваша роль: участник'), Text('Участников: ${memberIds.length}'),
      const SizedBox(height: 8), const Text('Участники'),
      ...memberIds.map((id) => ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.person_outline), title: Text(memberLabel(memberNames, id, widget.uid)), subtitle: data['ownerId'] == id ? const Text('Владелец') : null)),
      if (owner) ...[const SizedBox(height: 16), SelectableText('ID: ${widget.reference.id}'), OutlinedButton.icon(onPressed: copyId, icon: const Icon(Icons.copy), label: const Text('Скопировать ID для заявки')), const Text('Передайте ID нужному человеку. Сам ID не даёт доступ к команде — требуется ваше одобрение.')],
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (busy) const LinearProgressIndicator(),
      if (owner) ...[const Divider(), const Text('Заявки на вступление'), StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: requests, builder: (context, r) {
        if (r.hasError) return Text(errorText(r.error!)); if (!r.hasData) return const CircularProgressIndicator();
        if (r.data!.docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Заявок пока нет'));
        return Column(children: r.data!.docs.map((doc) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(doc.data()['name'] as String? ?? ''), SelectableText('UID: ${doc.id}'), Wrap(spacing: 8, children: [FilledButton(onPressed: busy ? null : () => decide(doc, true), child: const Text('Принять')), TextButton(onPressed: busy ? null : () => decide(doc, false), child: const Text('Отклонить'))])])))).toList());
      })],
      const SizedBox(height: 16),
      TeamTaskPanel(uid: widget.uid, team: widget.reference, owner: owner, members: memberNames),
    ]);
  }));
}
