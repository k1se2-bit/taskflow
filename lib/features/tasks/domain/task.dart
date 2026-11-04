import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskStatus { todo, inProgress, done }

enum TaskPriority { low, medium, high }

class Task {
  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = TaskPriority.medium,
    this.category = '',
    this.deadline,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final TaskPriority priority;
  final String category;
  final DateTime? deadline;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Task copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    String? category,
    DateTime? deadline,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      deadline: deadline ?? this.deadline,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'status': status.name,
        'priority': priority.name,
        'category': category,
        'deadline': deadline != null ? Timestamp.fromDate(deadline!) : null,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory Task.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      status: TaskStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => TaskStatus.todo,
      ),
      priority: TaskPriority.values.firstWhere(
        (e) => e.name == data['priority'],
        orElse: () => TaskPriority.medium,
      ),
      category: data['category'] ?? '',
      deadline: (data['deadline'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
