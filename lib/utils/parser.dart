import '../models/todo.dart';

Todo? parseCommand(String command) {
  if (command.toLowerCase().startsWith("add ")) {
    final task = command.substring(4);
    return Todo(
      id: DateTime.now().toIso8601String(),
      title: task,
      isDone: false,
      createdAt: DateTime.now(),
    );
  }
  return null;
}
