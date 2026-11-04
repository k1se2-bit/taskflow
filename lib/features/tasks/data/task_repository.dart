import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/task.dart';

class TaskRepository {
  TaskRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not authenticated');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _db.collection('users').doc(_uid).collection('tasks');

  Stream<List<Task>> watchTasks() {
    return _tasks.orderBy('createdAt', descending: true).snapshots().map(
          (snapshot) => snapshot.docs.map(Task.fromDoc).toList(),
        );
  }

  Future<void> createTask(Task task) async {
    await _tasks.doc(task.id).set(task.toMap());
  }

  Future<void> updateTask(Task task) async {
    await _tasks.doc(task.id).update(task.toMap());
  }

  Future<void> deleteTask(String taskId) async {
    await _tasks.doc(taskId).delete();
  }
}
