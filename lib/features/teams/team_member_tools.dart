import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../app.dart' show errorText;

class CreateNamedTeamPage extends StatefulWidget {
  const CreateNamedTeamPage({super.key, required this.uid});
  final String uid;
  @override
  State<CreateNamedTeamPage> createState() => _CreateNamedTeamPageState();
}
class _CreateNamedTeamPageState extends State<CreateNamedTeamPage> {
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
      await reference.set({'name': name.text.trim(), 'ownerId': widget.uid, 'memberIds': [widget.uid], 'memberNames': {widget.uid: 'Владелец'}, 'createdAt': FieldValue.serverTimestamp()});
      success = true;
    } catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(appBar: AppBar(title: const Text('Создать команду')), body: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
    TextFormField(controller: name, enabled: !busy, maxLength: 100, decoration: const InputDecoration(labelText: 'Название команды'), validator: (v) => v == null || v.trim().isEmpty ? 'Введите название команды' : null),
    const Text('Вы станете владельцем. Личные задачи останутся приватными. Участники смогут подать заявку по ID команды. Своё имя можно изменить в списке участников.'),
    if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    const SizedBox(height: 24), FilledButton(onPressed: busy ? null : create, child: Text(busy ? 'Создание…' : 'Создать')),
  ])))) ;
}

class TeamMemberTools extends StatefulWidget {
  const TeamMemberTools({super.key, required this.team, required this.uid, required this.owner, required this.members, required this.ownerId});
  final DocumentReference<Map<String, dynamic>> team;
  final String uid;
  final bool owner;
  final Map<String, String> members;
  final String ownerId;
  @override
  State<TeamMemberTools> createState() => _TeamMemberToolsState();
}
class _TeamMemberToolsState extends State<TeamMemberTools> {
  bool busy = false;
  String? error;
  Future<void> rename(String id) async {
    if (busy || !widget.owner) return;
    final key = GlobalKey<FormState>();
    var value = widget.members[id] ?? '';
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Имя участника в команде'),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText('UID: $id'),
        const SizedBox(height: 12),
        TextFormField(initialValue: value, autofocus: true, maxLength: 80, decoration: const InputDecoration(labelText: 'Отображаемое имя'), onChanged: (v) => value = v, validator: (v) => v == null || v.trim().isEmpty ? 'Введите имя' : null),
        const Text('Меняется только имя в этой команде. Аккаунт и назначенные задачи сохраняются.'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')), FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, value.trim()); }, child: const Text('Сохранить'))],
    ));
    if (result == null || !mounted || busy) return;
    setState(() { busy = true; error = null; });
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snapshot = await tx.get(widget.team);
        final data = snapshot.data();
        if (data == null || data['ownerId'] != widget.uid || !(data['memberIds'] as List).contains(id)) throw StateError('Участник недоступен или нет прав владельца.');
        final raw = data['memberNames'];
        final values = <String, dynamic>{if (raw is Map) ...Map<String, dynamic>.from(raw)};
        values[id] = result;
        tx.update(widget.team, {'memberNames': values});
      });
    } catch (e) { if (mounted) setState(() => error = errorText(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SizedBox(height: 8), const Text('Участники'),
    if (busy) const LinearProgressIndicator(),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ...widget.members.entries.map((entry) {
      final id = entry.key;
      final label = entry.value.trim().isNotEmpty ? entry.value : 'Участник';
      return ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_outline),
        title: Text(id == widget.uid ? '$label (я)' : label),
        subtitle: Text('${id == widget.ownerId ? 'Владелец' : 'Участник'}\nUID: $id'), isThreeLine: true,
        trailing: widget.owner ? IconButton(tooltip: 'Изменить имя', icon: const Icon(Icons.edit_outlined), onPressed: busy ? null : () => rename(id)) : null);
    }),
  ]);
}
