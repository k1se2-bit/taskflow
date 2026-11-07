import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../app.dart' show errorText;
import '../../notifications/reminders_app.dart' show ReminderEngine, reminderKey, reminderTime;
import '../../teams/team_tasks.dart' show TeamTaskEditor, teamStatuses, memberLabel;
import 'workspace.dart' show TaskEditor, dateLabel, priorities;
import 'reminder_preference_panel.dart';

bool detailsCanEdit(String uid, {String? personalOwner, Map<String, dynamic>? team}) => personalOwner != null ? uid == personalOwner : team?['ownerId'] == uid && (team?['memberIds'] is List && (team!['memberIds'] as List).contains(uid));
bool detailsCanChangeStatus(String uid, Map<String, dynamic> task, {String? personalOwner, Map<String, dynamic>? team}) => detailsCanEdit(uid, personalOwner: personalOwner, team: team) || (personalOwner == null && team?['memberIds'] is List && (team!['memberIds'] as List).contains(uid) && task['assignedTo'] == uid);
bool detailsCanRemind(String uid, Map<String, dynamic> task, {String? personalOwner, Map<String, dynamic>? team}) => personalOwner != null ? personalOwner == uid : team?['memberIds'] is List && (team!['memberIds'] as List).contains(uid) && task['assignedTo'] == uid;

class TaskDetailsPage extends StatefulWidget {
  const TaskDetailsPage({super.key, required this.uid, required this.reference, this.teamId});
  final String uid;
  final DocumentReference<Map<String, dynamic>> reference;
  final String? teamId;
  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}
class _TaskDetailsPageState extends State<TaskDetailsPage> {
  late final Stream<User?> auth;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> taskStream;
  late final DocumentReference<Map<String, dynamic>> user;
  late final Stream<Map<String, dynamic>?> preferences;
  DocumentReference<Map<String, dynamic>>? teamReference;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? teamStream;
  bool busy = false;
  String? message;
  String? get personalOwner => widget.teamId == null ? widget.uid : null;
  bool get validPath => widget.reference.path == (widget.teamId == null ? 'users/${widget.uid}/tasks/${widget.reference.id}' : 'organizations/${widget.teamId}/tasks/${widget.reference.id}');
  @override
  void initState() {
    super.initState(); auth = FirebaseAuth.instance.authStateChanges();
    taskStream = widget.reference.snapshots(includeMetadataChanges: true);
    user = FirebaseFirestore.instance.collection('users').doc(widget.uid);
    preferences = user.snapshots().map((snapshot) => snapshot.data());
    if (widget.teamId != null) { teamReference = FirebaseFirestore.instance.collection('organizations').doc(widget.teamId!); teamStream = teamReference!.snapshots(); }
  }
  void checkAccount() { if (FirebaseAuth.instance.currentUser?.uid != widget.uid) throw StateError('Аккаунт изменился. Откройте задачу заново.'); }
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try { checkAccount(); await action(); }
    catch (error) { if (mounted) setState(() => message = error is StateError ? error.message.toString() : errorText(error)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> chooseReminder() => perform(() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now, firstDate: DateUtils.dateOnly(now), lastDate: DateTime(now.year + 5));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))));
    if (time == null || !mounted) return;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(DateTime.now())) throw StateError('Выберите время в будущем.');
    checkAccount();
    final latest = await widget.reference.get(const GetOptions(source: Source.server));
    final team = teamReference == null ? null : (await teamReference!.get(const GetOptions(source: Source.server))).data();
    final data = latest.data();
    if (data == null || data['status'] == 'done' || !detailsCanRemind(widget.uid, data, personalOwner: personalOwner, team: team)) throw StateError('Задача недоступна, выполнена или назначена другому участнику.');
    await ReminderEngine.instance.permission(); checkAccount();
    if (widget.teamId == null) { await widget.reference.update({'remindAt': Timestamp.fromDate(when), 'updatedAt': FieldValue.serverTimestamp()}); }
    else { await user.set({'teamReminders': {reminderKey(widget.teamId!, widget.reference.id): {'teamId': widget.teamId, 'taskId': widget.reference.id, 'remindAt': Timestamp.fromDate(when)}}}, SetOptions(merge: true)); }
    await ReminderEngine.instance.refresh();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Время напоминания сохранено')));
  });
  Future<void> cancelReminder() => perform(() async {
    if (widget.teamId == null) { await widget.reference.update({'remindAt': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()}); }
    else { await user.update({'teamReminders.${reminderKey(widget.teamId!, widget.reference.id)}': FieldValue.delete()}); }
    await ReminderEngine.instance.refresh();
  });
  Future<void> setArchived(bool value) => perform(() async {
    final latest = await widget.reference.get(const GetOptions(source: Source.server));
    final data = latest.data();
    if (data == null || widget.teamId != null || !detailsCanEdit(widget.uid, personalOwner: personalOwner, team: null)) throw StateError('Архивировать может только владелец личной задачи.');
    final previous = data['archived'] == true;
    if (previous == value) return;
    await widget.reference.update({'archived': value, 'archivedAt': value ? FieldValue.serverTimestamp() : FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value ? 'Задача в архиве' : 'Задача возвращена из архива'), action: SnackBarAction(label: 'Отменить', onPressed: () { widget.reference.update({'archived': previous, 'archivedAt': previous ? FieldValue.serverTimestamp() : FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()}); })));
  });
  void edit(Map<String, dynamic> data, Map<String, dynamic>? team) {
    if (!detailsCanEdit(widget.uid, personalOwner: personalOwner, team: team)) return;
    if (widget.teamId == null) { Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskEditor(reference: widget.reference, initial: data))); return; }
    final raw = team!['memberNames'];
    final members = <String, String>{for (final id in List<String>.from(team['memberIds'] as List)) id: raw is Map && raw[id] is String ? raw[id] as String : (team['ownerId'] == id ? 'Владелец' : '')};
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamTaskEditor(team: teamReference!, uid: widget.uid, members: members, task: widget.reference, initial: data)));
  }
  Widget reminderControls(dynamic stamp, bool done) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Моё напоминание', style: Theme.of(context).textTheme.titleMedium), Text(reminderTime(stamp)),
    const Text('Настройка только для вас. Android может задерживать показ; изменения с других устройств учитываются после синхронизации.'),
    if (!done) OutlinedButton.icon(onPressed: busy ? null : () { chooseReminder(); }, icon: const Icon(Icons.add_alarm), label: Text(stamp is Timestamp ? 'Изменить время' : 'Напомнить мне')),
    if (stamp is Timestamp) TextButton.icon(onPressed: busy ? null : () { cancelReminder(); }, icon: const Icon(Icons.alarm_off), label: const Text('Отменить напоминание')),
    if (done) const Text('Для выполненной задачи новое напоминание не планируется.'),
  ])));
  Widget taskBody(Map<String, dynamic>? team) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(key: ValueKey('task:${widget.reference.path}'), stream: taskStream, builder: (context, snapshot) {
    if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(errorText(snapshot.error!))));
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final data = snapshot.data!.data();
    if (data == null) return const Center(child: Text('Задача удалена или недоступна.'));
    final canEdit = detailsCanEdit(widget.uid, personalOwner: personalOwner, team: team);
    final canStatus = detailsCanChangeStatus(widget.uid, data, personalOwner: personalOwner, team: team);
    final canRemind = detailsCanRemind(widget.uid, data, personalOwner: personalOwner, team: team);
    final archived = data['archived'] == true;
    final stamp = data['deadline']; final status = data['status'] as String? ?? 'todo';
    final statuses = widget.teamId == null ? const {'todo': 'Новая', 'done': 'Выполнена'} : teamStatuses;
    final raw = team?['memberNames']; final names = raw is Map ? raw.map((key, value) => MapEntry(key.toString(), value.toString())) : <String, String>{};
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(data['title'] as String? ?? '', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 12),
      Text(widget.teamId == null ? 'Личная задача' : 'Команда: ${team?['name'] ?? ''}'),
      if (widget.teamId != null) Text('Исполнитель: ${memberLabel(names, data['assignedTo'] as String? ?? '', widget.uid)}'),
      Text(stamp is Timestamp ? 'Срок: ${dateLabel(stamp.toDate())}' : 'Без срока'),
      if (widget.teamId == null) Text('Приоритет: ${priorities[data['priority']] ?? 'Обычный'}'),
      if (archived) const Text('Задача в архиве'),
      const SizedBox(height: 12), SelectableText((data['description'] as String? ?? '').isEmpty ? 'Без описания' : data['description'] as String),
      const SizedBox(height: 16), Text('Статус: ${teamStatuses[status] ?? status}'),
      if (canStatus && !archived) PopupMenuButton<String>(enabled: !busy, onSelected: (value) { perform(() async { await widget.reference.update({'status': value, 'updatedAt': FieldValue.serverTimestamp()}); }); }, itemBuilder: (_) => statuses.entries.map((entry) => PopupMenuItem(value: entry.key, child: Text(entry.value))).toList(), child: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Изменить статус ▾'))),
      if (canEdit) FilledButton.icon(onPressed: busy ? null : () => edit(data, team), icon: const Icon(Icons.edit_outlined), label: const Text('Редактировать')),
      if (widget.teamId == null) OutlinedButton.icon(onPressed: busy ? null : () => setArchived(!archived), icon: Icon(archived ? Icons.unarchive_outlined : Icons.archive_outlined), label: Text(archived ? 'Вернуть из архива' : 'В архив')),
      if (snapshot.data!.metadata.hasPendingWrites) const Text('Есть несинхронизированные изменения.'),
      if (snapshot.data!.metadata.isFromCache) const Text('Показаны данные из локального кэша.'),
      if (busy) const LinearProgressIndicator(),
      if (message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(message!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      if (canRemind && widget.teamId == null) reminderControls(data['remindAt'], status == 'done'),
      if (canRemind && widget.teamId != null) ReminderPreferencePanel(
        key: ValueKey('reminder:${widget.uid}:${widget.reference.path}'),
        stream: preferences, preferenceKey: reminderKey(widget.teamId!, widget.reference.id), errorFormatter: errorText,
        builder: (value) => reminderControls(value, status == 'done'),
      ),
      if (!canRemind) const Text('Личное напоминание доступно только текущему исполнителю.'),
    ]);
  });
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(appBar: AppBar(title: const Text('Задача')), body: StreamBuilder<User?>(stream: auth, builder: (context, account) {
    if (account.hasError) return Center(child: Text(errorText(account.error!)));
    if (account.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (account.data?.uid != widget.uid || !validPath) return const Center(child: Text('Задача недоступна. Вернитесь к списку.'));
    if (teamStream == null) return taskBody(null);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: teamStream, builder: (context, team) {
      if (team.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(errorText(team.error!))));
      if (!team.hasData) return const Center(child: CircularProgressIndicator());
      final data = team.data!.data();
      if (data == null || data['memberIds'] is! List || !(data['memberIds'] as List).contains(widget.uid)) return const Center(child: Text('Команда недоступна.'));
      return taskBody(data);
    });
  })));
}
