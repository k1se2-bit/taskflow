import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'task_providers.dart';

class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My tasks')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/tasks/new'),
        child: const Icon(Icons.add),
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks yet'));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return CheckboxListTile(
                value: task.status == TaskStatus.done,
                title: Text(task.title),
                subtitle: Text(task.category.isEmpty ? 'No category' : task.category),
                onChanged: (_) {
                  final updated = task.copyWith(
                    status: task.status == TaskStatus.done
                        ? TaskStatus.todo
                        : TaskStatus.done,
                  );
                  ref.read(taskRepositoryProvider).updateTask(updated);
                },
              );
            },
          );
        },
      ),
    );
  }
}
