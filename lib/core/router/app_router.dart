import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/tasks/presentation/task_list_screen.dart';
import '../../features/tasks/presentation/task_form_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/tasks', builder: (_, __) => const TaskListScreen()),
    GoRoute(path: '/tasks/new', builder: (_, __) => const TaskFormScreen()),
  ],
);
