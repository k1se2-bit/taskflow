import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/task_repository.dart';
import '../domain/task.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

final tasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchTasks();
});
