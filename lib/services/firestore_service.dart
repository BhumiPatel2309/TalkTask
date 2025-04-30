import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/todo.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  Future<void> uploadTodo(Todo todo) async {
    await _db.collection('todos').doc(todo.id).set(todo.toMap());
  }
  
  // Update a todo's completion status
  Future<void> updateTodoStatus(String id, bool isDone) async {
    await _db.collection('todos').doc(id).update({'isDone': isDone});
  }
  
  // Delete a todo
  Future<void> deleteTodo(String id) async {
    await _db.collection('todos').doc(id).delete();
  }

  Stream<List<Todo>> getTodos() {
    return _db
        .collection('todos')
        .orderBy('createdAt', descending: true) // Show newest first
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => Todo.fromMap(doc.data())).toList(),
        );
  }
  
  // Get completed todos
  Stream<List<Todo>> getCompletedTodos() {
    return _db
        .collection('todos')
        .where('isDone', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => Todo.fromMap(doc.data())).toList(),
        );
  }
  
  // Get incomplete todos
  Stream<List<Todo>> getIncompleteTodos() {
    return _db
        .collection('todos')
        .where('isDone', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => Todo.fromMap(doc.data())).toList(),
        );
  }
}
