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
    // Initialize voice service
    voice.init();
    
    // Check for offline tasks on startup
    _checkConnectivityAndSync();
    
    // Listen for connectivity changes
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _syncOfflineTasks();
      }
    });
  }
  
  Future<void> _checkConnectivityAndSync() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.none) {
      await _syncOfflineTasks();
    }
  }

  Future<void> _syncOfflineTasks() async {
    final commands = queue.getUnprocessedCommands();
    if (commands.isEmpty) return;
    
    int successCount = 0;
    for (final cmd in commands) {
      final todo = parseCommand(cmd['command']);
      if (todo != null) {
        try {
          await FirestoreService().uploadTodo(todo);
          queue.markAsProcessed(cmd['index']);
          successCount++;
        } catch (e) {
          print('Error syncing task: $e');
        }
      } else {
        // Mark as processed even if parsing failed to avoid infinite retries
        queue.markAsProcessed(cmd['index']);
      }
    }
    
    if (successCount > 0) {
      await tts.speak("$successCount offline tasks synchronized");
    }
    
    // Clean up processed commands
    queue.clearProcessedCommands();
  }

  Future<void> _handleVoiceInput() async {
    final result = await voice.listen();
    if (result != null && result.isNotEmpty) {
      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = connectivityResult != ConnectivityResult.none;
      
      if (isConnected) {
        // Online mode - try to parse and upload directly
        final todo = parseCommand(result);
        if (todo != null) {
          try {
            await FirestoreService().uploadTodo(todo);
            await tts.speak("Task added: ${todo.title}");
          } catch (e) {
            // If upload fails, save to offline queue
            queue.addCommand(result);
            await tts.speak("Network error. Saved offline: ${todo.title}");
          }
        } else {
          // Could not parse the command
          queue.addCommand(result);
          await tts.speak("Could not understand. Saved offline: $result");
        }
      } else {
        // Offline mode - save to queue
        queue.addCommand(result);
        await tts.speak("Offline mode. Saved: $result");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todoList = ref.watch(todoStreamProvider);
    final unprocessedCount = queue.getUnprocessedCount();

    return Scaffold(
      appBar: AppBar(
        title: Text("Voice To-Do"),
        actions: [
          if (unprocessedCount > 0)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.cloud_upload),
                  onPressed: () => _syncOfflineTasks(),
                  tooltip: 'Sync offline tasks',
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$unprocessedCount',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (unprocessedCount > 0)
            Container(
              color: Colors.amber.shade100,
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt, color: Colors.amber.shade800),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You have $unprocessedCount offline task(s) waiting to be synced',
                      style: TextStyle(color: Colors.amber.shade900),
                    ),
                  ),
                  TextButton(
                    onPressed: _syncOfflineTasks,
                    child: Text('SYNC NOW'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: todoList.when(
              data: (todos) => todos.isEmpty
                  ? Center(child: Text('No tasks yet. Tap the mic to add one!'))
                  : ListView(
                      children: todos
                          .map((t) => ListTile(
                                title: Text(t.title),
                                leading: Icon(Icons.task_alt),
                              ))
                          .toList(),
                    ),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text("Error: $e")),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FloatingActionButton(
              heroTag: 'manual',
              onPressed: _showAddTaskDialog,
              child: Icon(Icons.add_task),
              tooltip: 'Add task manually',
              backgroundColor: Colors.teal.shade700,
            ),
            FloatingActionButton(
              heroTag: 'voice',
              onPressed: _handleVoiceInput,
              child: Icon(Icons.mic),
              tooltip: 'Add task with voice',
            ),
          ],
        ),
      ),
    );
  }
}
