import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/todo.dart';
import '../services/firestore_service.dart';

final todoStreamProvider = StreamProvider<List<Todo>>((ref) {
  return FirestoreService().getTodos();
});
