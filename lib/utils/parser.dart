import '../models/todo.dart';

Todo? parseCommand(String command) {
  String taskText = command.trim();
  
  // If it starts with "add ", remove it
  if (taskText.toLowerCase().startsWith("add ")) {
    taskText = taskText.substring(4);
  }
  
  // If we have any text, create a task
  if (taskText.isNotEmpty) {
    return Todo(
      id: DateTime.now().toIso8601String(),
      title: taskText,
      isDone: false,
      createdAt: DateTime.now(),
    );
  }
  
  return null;
}
