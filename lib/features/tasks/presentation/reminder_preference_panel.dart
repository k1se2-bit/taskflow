import 'dart:async';
import 'package:flutter/material.dart';

dynamic readReminderPreference(Map<String, dynamic>? data, String key) {
  final values = data?['teamReminders'];
  final value = values is Map ? values[key] : null;
  return value is Map ? value['remindAt'] : null;
}

class ReminderPreferencePanel extends StatefulWidget {
  const ReminderPreferencePanel({super.key, required this.stream, required this.preferenceKey, required this.builder, this.errorFormatter, this.waitLimit = const Duration(seconds: 8)});
  final Stream<Map<String, dynamic>?> stream;
  final String preferenceKey;
  final Widget Function(dynamic stamp) builder;
  final String Function(Object error)? errorFormatter;
  final Duration waitLimit;
  @override
  State<ReminderPreferencePanel> createState() => _ReminderPreferencePanelState();
}
class _ReminderPreferencePanelState extends State<ReminderPreferencePanel> {
  StreamSubscription<Map<String, dynamic>?>? subscription;
  Timer? timer;
  int generation = 0;
  bool loaded = false;
  bool timedOut = false;
  Object? error;
  Map<String, dynamic>? data;
  void listen() {
    final token = ++generation;
    final old = subscription;
    if (old != null) unawaited(old.cancel());
    timer?.cancel(); loaded = false; timedOut = false; error = null; data = null;
    timer = Timer(widget.waitLimit, () {
      if (mounted && token == generation && !loaded && error == null) setState(() => timedOut = true);
    });
    subscription = widget.stream.listen((value) {
      if (!mounted || token != generation) return;
      timer?.cancel();
      setState(() { data = value; loaded = true; timedOut = false; error = null; });
    }, onError: (Object value) {
      if (!mounted || token != generation) return;
      timer?.cancel();
      setState(() { loaded = false; error = value; timedOut = false; });
    }, onDone: () {
      if (!mounted || token != generation || loaded || error != null) return;
      timer?.cancel(); setState(() => timedOut = true);
    });
  }
  @override
  void initState() { super.initState(); listen(); }
  @override
  void didUpdateWidget(covariant ReminderPreferencePanel old) {
    super.didUpdateWidget(old);
    if (old.stream != widget.stream || old.preferenceKey != widget.preferenceKey || old.waitLimit != widget.waitLimit) listen();
  }
  @override
  void dispose() { generation++; timer?.cancel(); final sub = subscription; if (sub != null) unawaited(sub.cancel()); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (error != null || timedOut) {
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Моё напоминание', style: Theme.of(context).textTheme.titleMedium),
        Text(error == null ? 'Настройки пока не получены. Проверьте соединение и повторите загрузку. Существующее напоминание не изменено.' : widget.errorFormatter?.call(error!) ?? 'Не удалось загрузить настройки напоминания.'),
        TextButton.icon(onPressed: () => setState(listen), icon: const Icon(Icons.refresh), label: const Text('Повторить загрузку')),
      ])));
    }
    if (loaded) return widget.builder(readReminderPreference(data, widget.preferenceKey));
    return const Padding(padding: EdgeInsets.all(16), child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Загружаем личное напоминание…')]));
  }
}
