import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';

String errorText(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied': return 'Нет доступа. Проверьте правила Firestore.';
      case 'invalid-email': return 'Проверьте адрес электронной почты.';
      case 'email-already-in-use': return 'Этот адрес уже зарегистрирован.';
      case 'weak-password': return 'Пароль слишком простой. Используйте не менее 6 символов.';
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password': return 'Неверная почта или пароль.';
      case 'network-request-failed':
      case 'unavailable': return 'Не удалось связаться с сервером. Проверьте интернет.';
      case 'too-many-requests': return 'Слишком много попыток. Попробуйте позже.';
      default: return 'Ошибка сервиса: ${error.code}';
    }
  }
  return 'Не удалось выполнить действие. Попробуйте ещё раз.';
}

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TaskFlow', debugShowCheckedModeBanner: false,
    theme: AppTheme.light, darkTheme: AppTheme.dark,
    home: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text(errorText(snapshot.error!))));
        }
        final user = snapshot.data;
        return user == null ? const AccountScreen() : TasksScreen(key: ValueKey(user.uid), user: user);
      },
    ),
  );
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_register) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TaskFlow')),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Form(
        key: _form,
        child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_register ? 'Создать аккаунт' : 'Вход', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          TextFormField(controller: _email, enabled: !_busy, keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Электронная почта'),
            validator: (v) => v == null || !v.trim().contains('@') ? 'Введите электронную почту' : null),
          const SizedBox(height: 16),
          TextFormField(controller: _password, enabled: !_busy, obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль'),
            validator: (v) => v == null || v.isEmpty ? 'Введите пароль' : (_register && v.length < 6 ? 'Минимум 6 символов' : null)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Подождите…' : (_register ? 'Зарегистрироваться' : 'Войти'))),
          TextButton(onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; }),
            child: Text(_register ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Зарегистрироваться')),
        ])),
      )),
    )),
  );
}

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.user});
  final User user;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final CollectionReference<Map<String, dynamic>> _tasks;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  final Set<String> _pending = {};
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _tasks = FirebaseFirestore.instance.collection('users').doc(widget.user.uid).collection('tasks');
    _stream = _tasks.orderBy('createdAt', descending: true).snapshots();
  }

  void _showError(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
  }

  Future<void> _logout() async {
    setState(() => _signingOut = true);
    try { await FirebaseAuth.instance.signOut(); } catch (e) { _showError(e); }
    finally { if (mounted) setState(() => _signingOut = false); }
  }

  Future<void> _toggle(String id, bool done) async {
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    try { await _tasks.doc(id).update({'status': done ? 'done' : 'todo', 'updatedAt': FieldValue.serverTimestamp()}); }
    catch (e) { _showError(e); }
    finally { if (mounted) setState(() => _pending.remove(id)); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мои задачи'), actions: [
      IconButton(tooltip: 'Выйти', onPressed: _signingOut ? null : _logout, icon: const Icon(Icons.logout)),
    ]),
    floatingActionButton: FloatingActionButton(
      tooltip: 'Новая задача',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NewTaskScreen(tasks: _tasks))),
      child: const Icon(Icons.add)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(errorText(snapshot.error!))));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('Задач пока нет. Нажмите +, чтобы создать первую.'));
        return ListView.builder(itemCount: docs.length, itemBuilder: (context, index) {
          final doc = docs[index];
          final data = doc.data();
          final done = data['status'] == 'done';
          return CheckboxListTile(
            value: done, onChanged: _pending.contains(doc.id) ? null : (v) => _toggle(doc.id, v ?? false),
            title: Text(data['title'] as String? ?? '', style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
            subtitle: Text(doc.metadata.hasPendingWrites ? 'Синхронизация…' : (data['description'] as String? ?? '')),
          );
        });
      },
    ),
  );
}

class NewTaskScreen extends StatefulWidget {
  const NewTaskScreen({super.key, required this.tasks});
  final CollectionReference<Map<String, dynamic>> tasks;
  @override
  State<NewTaskScreen> createState() => _NewTaskScreenState();
}

class _NewTaskScreenState extends State<NewTaskScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  late final DocumentReference<Map<String, dynamic>> _document;
  DateTime? _deadline;
  bool _busy = false;
  String? _error;

  @override
  void initState() { super.initState(); _document = widget.tasks.doc(); }
  @override
  void dispose() { _title.dispose(); _description.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: _deadline ?? now,
      firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 5));
    if (date != null && mounted) setState(() => _deadline = date);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _document.set({
        'title': _title.text.trim(), 'description': _description.text.trim(),
        'status': 'todo', 'priority': 'medium', 'category': '',
        'deadline': _deadline == null ? null : Timestamp.fromDate(_deadline!),
        'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Новая задача')),
      body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [
        TextFormField(controller: _title, enabled: !_busy, maxLength: 200,
          decoration: const InputDecoration(labelText: 'Название'),
          validator: (v) => v == null || v.trim().isEmpty ? 'Введите название задачи' : null),
        const SizedBox(height: 16),
        TextFormField(controller: _description, enabled: !_busy, maxLines: 4, maxLength: 5000,
          decoration: const InputDecoration(labelText: 'Описание')),
        OutlinedButton.icon(onPressed: _busy ? null : _pickDate, icon: const Icon(Icons.event),
          label: Text(_deadline == null ? 'Выбрать срок' : 'Срок: ${_deadline!.day}.${_deadline!.month}.${_deadline!.year}')),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Сохранение…' : 'Сохранить')),
      ])),
    ),
  );
}
