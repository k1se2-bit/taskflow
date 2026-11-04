import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../app.dart' show AccountScreen, errorText;
import '../../core/theme/app_theme.dart';
import '../tasks/presentation/calendar_app.dart' show TaskCalendar;
import '../tasks/presentation/workspace.dart' show Workspace;

class NotificationsApp extends StatefulWidget {
  const NotificationsApp({super.key});
  @override
  State<NotificationsApp> createState() => _NotificationsAppState();
}
class _NotificationsAppState extends State<NotificationsApp> {
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
      return s.data == null ? const AccountScreen() : NotificationShell(key: ValueKey(s.data!.uid), uid: s.data!.uid);
    }),
  );
}
class NotificationShell extends StatefulWidget {
  const NotificationShell({super.key, required this.uid});
  final String uid;
  @override
  State<NotificationShell> createState() => _NotificationShellState();
}
class _NotificationShellState extends State<NotificationShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: index, children: [Workspace(uid: widget.uid), TaskCalendar(uid: widget.uid), const NotificationCheck()]),
    bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'),
      NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календарь'),
      NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Уведомления'),
    ]),
  );
}
class NotificationCheck extends StatefulWidget {
  const NotificationCheck({super.key});
  @override
  State<NotificationCheck> createState() => _NotificationCheckState();
}
class _NotificationCheckState extends State<NotificationCheck> {
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  bool busy = false;
  String message = 'Сначала проверим разрешение Android и показ обычного уведомления. Напоминания по времени пока не подключены.';
  Future<void> test() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        setState(() => message = 'Эта проверка предназначена для Android.');
        return;
      }
      if (!initialized) {
        final ok = await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
        if (ok != true) throw StateError('Не удалось инициализировать уведомления');
        initialized = true;
      }
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      if (!mounted) return;
      if (granted == false) {
        setState(() => message = 'Разрешение не выдано. Откройте настройки Android → Приложения → TaskFlow → Уведомления и разрешите показ, затем повторите проверку.');
        return;
      }
      await plugin.show(0, 'TaskFlow', 'Тестовое уведомление. Показ уведомлений подключён.', const NotificationDetails(
        android: AndroidNotificationDetails('taskflow_reminders', 'Напоминания о задачах', channelDescription: 'Уведомления TaskFlow', importance: Importance.high, priority: Priority.high),
      ));
      if (mounted) setState(() => message = 'Команда показа отправлена. Потяните шторку Android сверху вниз и проверьте уведомление TaskFlow. Если его нет, проверьте разрешение и режим «Не беспокоить».');
    } catch (e) {
      if (mounted) setState(() => message = 'Проверка не удалась: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Уведомления')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Text('Проверка уведомлений', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16), Text(message), const SizedBox(height: 24),
      FilledButton.icon(onPressed: busy ? null : test, icon: const Icon(Icons.notifications_active_outlined), label: Text(busy ? 'Подождите…' : 'Тестовое уведомление')),
    ]),
  );
}
