import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/todo.dart';
import '../services/firestore_service.dart';

// Provider for all todos
final todoStreamProvider = StreamProvider<List<Todo>>((ref) {
  return FirestoreService().getTodos();
});

// Provider for active (incomplete) todos
final activeTodoStreamProvider = StreamProvider<List<Todo>>((ref) {
  return FirestoreService().getIncompleteTodos();
});

// Provider for completed todos
final completedTodoStreamProvider = StreamProvider<List<Todo>>((ref) {
  return FirestoreService().getCompletedTodos();
});
