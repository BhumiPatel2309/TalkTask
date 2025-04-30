import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/todo.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  Future<void> uploadTodo(Todo todo) async {
    await _db.collection('todos').doc(todo.id).set(todo.toMap());
  }

  Stream<List<Todo>> getTodos() {
    return _db
        .collection('todos')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => Todo.fromMap(doc.data())).toList(),
        );
  }
}
