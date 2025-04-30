import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/todo_provider.dart';
import '../services/firestore_service.dart';
import '../services/offline_queue.dart';
import '../services/voice_service.dart';
import '../services/tts_service.dart';
import '../utils/parser.dart';

class HomeScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final voice = VoiceService();
  final tts = TTSService();
  final queue = OfflineQueue();

  @override
  void initState() {
    super.initState();
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _syncOfflineTasks();
      }
    });
    voice.init();
  }

  Future<void> _syncOfflineTasks() async {
    final commands = queue.getCommands();
    for (final cmd in commands) {
      final todo = parseCommand(cmd);
      if (todo != null) {
        await FirestoreService().uploadTodo(todo);
      }
    }
    queue.clearQueue();
  }

  Future<void> _handleVoiceInput() async {
    final result = await voice.listen();
    if (result != null && result.isNotEmpty) {
      final todo = parseCommand(result);
      if (todo != null) {
        await FirestoreService().uploadTodo(todo);
        await tts.speak("Task added: ${todo.title}");
      } else {
        queue.addCommand(result);
        await tts.speak("Saved offline: $result");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todoList = ref.watch(todoStreamProvider);

    return Scaffold(
      appBar: AppBar(title: Text("Voice To-Do")),
      body: todoList.when(
        data:
            (todos) => ListView(
              children:
                  todos.map((t) => ListTile(title: Text(t.title))).toList(),
            ),
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Error: $e")),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleVoiceInput,
        child: Icon(Icons.mic),
      ),
    );
  }
}
