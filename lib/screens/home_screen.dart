import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../providers/todo_provider.dart';
import '../services/firestore_service.dart';
import '../services/offline_queue.dart';
import '../services/voice_service.dart';
import '../services/tts_service.dart';
import '../utils/parser.dart';
import '../models/todo.dart';

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
    // Show recording indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.mic, color: Colors.white),
            SizedBox(width: 8),
            Text('Listening...'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.teal,
      ),
    );
    
    final result = await voice.listen();
    if (result != null && result.isNotEmpty) {
      // Show what was heard
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('I heard: "$result"'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = connectivityResult != ConnectivityResult.none;
      
      if (isConnected) {
        // Online mode - try to parse and upload directly
        final todo = parseCommand(result);
        if (todo != null) {
          // Show confirmation dialog
          final confirmed = await _showConfirmationDialog(
            'Add Task', 
            'Do you want to add the task: "${todo.title}"?'
          );
          
          if (confirmed) {
            try {
              await FirestoreService().uploadTodo(todo);
              await tts.speak("Task added: ${todo.title}");
              
              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Task added: ${todo.title}'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              // If upload fails, save to offline queue
              queue.addCommand(result);
              await tts.speak("Network error. Saved offline: ${todo.title}");
              
              // Show offline save message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.cloud_off, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Network error. Saved offline: ${todo.title}'),
                    ],
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } else {
          // Could not parse the command - ask for clarification
          final clarifiedCommand = await _showClarificationDialog(result);
          if (clarifiedCommand != null && clarifiedCommand.isNotEmpty) {
            final clarifiedTodo = parseCommand('add $clarifiedCommand');
            if (clarifiedTodo != null) {
              try {
                await FirestoreService().uploadTodo(clarifiedTodo);
                await tts.speak("Task added: ${clarifiedTodo.title}");
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Task added: ${clarifiedTodo.title}'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                queue.addCommand('add $clarifiedCommand');
                await tts.speak("Network error. Saved offline: ${clarifiedTodo.title}");
              }
            }
          } else {
            // User canceled clarification, save original command offline
            queue.addCommand(result);
            await tts.speak("Saved offline: $result");
          }
        }
      } else {
        // Offline mode - save to queue
        queue.addCommand(result);
        await tts.speak("Offline mode. Saved: $result");
        
        // Show offline save message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.white),
                SizedBox(width: 8),
                Text('Offline mode. Command saved locally.'),
              ],
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      // Refresh UI to show updated offline count
      setState(() {});
    }
  }
  
  // Show confirmation dialog for task actions
  Future<bool> _showConfirmationDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('CONFIRM'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
  
  // Show clarification dialog when command can't be parsed
  Future<String?> _showClarificationDialog(String originalCommand) async {
    final TextEditingController taskController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clarify Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'I couldn\'t understand "$originalCommand".',
              style: TextStyle(color: Colors.red.shade700),
            ),
            SizedBox(height: 16),
            Text('Please enter your task description:'),
            SizedBox(height: 8),
            TextField(
              controller: taskController,
              decoration: InputDecoration(
                hintText: 'Enter task description',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, taskController.text.trim()),
            child: Text('ADD TASK'),
          ),
        ],
      ),
    );
  }
  
  void _showAddTaskDialog() {
    final TextEditingController taskController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add New Task'),
        content: TextField(
          controller: taskController,
          decoration: InputDecoration(
            hintText: 'Enter task description',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final taskText = taskController.text.trim();
              if (taskText.isEmpty) return;
              
              // Create a command string like the voice command would
              final commandText = 'add $taskText';
              
              // Check connectivity
              final connectivityResult = await Connectivity().checkConnectivity();
              final isConnected = connectivityResult != ConnectivityResult.none;
              
              if (isConnected) {
                // Online mode - try to parse and upload directly
                final todo = parseCommand(commandText);
                if (todo != null) {
                  try {
                    await FirestoreService().uploadTodo(todo);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Task added: ${todo.title}')),
                    );
                  } catch (e) {
                    // If upload fails, save to offline queue
                    queue.addCommand(commandText);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Network error. Saved offline.')),
                    );
                  }
                }
              } else {
                // Offline mode - save to queue
                queue.addCommand(commandText);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Offline mode. Task saved locally.')),
                );
              }
              
              Navigator.pop(context);
              setState(() {}); // Refresh UI to show offline count
            },
            child: Text('ADD TASK'),
          ),
        ],
      ),
    );
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
          // Filter tabs
          Container(
            color: Colors.teal.shade50,
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: Icon(Icons.list),
                    label: Text('All'),
                    onPressed: () => setState(() {}),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.teal.shade100,
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: Icon(Icons.check_box_outline_blank),
                    label: Text('Active'),
                    onPressed: () => setState(() {}),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: Icon(Icons.check_box),
                    label: Text('Done'),
                    onPressed: () => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: todoList.when(
              data: (todos) => todos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.task, size: 64, color: Colors.grey.shade400),
                          SizedBox(height: 16),
                          Text(
                            'No tasks yet',
                            style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Tap the mic to add one with voice\nor use the + button to type',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: todos.length,
                      itemBuilder: (context, index) {
                        final todo = todos[index];
                        return Dismissible(
                          key: Key(todo.id),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: EdgeInsets.only(right: 20),
                            child: Icon(Icons.delete, color: Colors.white),
                          ),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (direction) async {
                            return await _showConfirmationDialog(
                              'Delete Task',
                              'Are you sure you want to delete "${todo.title}"?',
                            );
                          },
                          onDismissed: (direction) async {
                            try {
                              await FirestoreService().deleteTodo(todo.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Task deleted'),
                                  action: SnackBarAction(
                                    label: 'UNDO',
                                    onPressed: () {
                                      FirestoreService().uploadTodo(todo);
                                    },
                                  ),
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error deleting task')),
                              );
                            }
                          },
                          child: Card(
                            elevation: 1,
                            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListTile(
                              title: Text(
                                todo.title,
                                style: TextStyle(
                                  decoration: todo.isDone ? TextDecoration.lineThrough : null,
                                  color: todo.isDone ? Colors.grey : null,
                                ),
                              ),
                              leading: Checkbox(
                                value: todo.isDone,
                                activeColor: Colors.teal,
                                onChanged: (value) async {
                                  if (value != null) {
                                    try {
                                      await FirestoreService().updateTodoStatus(todo.id, value);
                                      if (value) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.check_circle, color: Colors.white),
                                                SizedBox(width: 8),
                                                Text('Task completed'),
                                              ],
                                            ),
                                            backgroundColor: Colors.green,
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error updating task')),
                                      );
                                    }
                                  }
                                },
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatDate(todo.createdAt),
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.more_vert),
                                    onPressed: () => _showTaskOptions(todo),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red),
                    SizedBox(height: 16),
                    Text("Error: $e", textAlign: TextAlign.center),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      child: Text('Retry'),
                    ),
                  ],
                ),
              ),
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
  
  // Format date for display in task list
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today ${DateFormat.jm().format(date)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${DateFormat.jm().format(date)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat.yMMMd().format(date);
    }
  }
  
  // Show options menu for a task
  void _showTaskOptions(Todo todo) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(todo.isDone ? Icons.check_box_outline_blank : Icons.check_box),
            title: Text(todo.isDone ? 'Mark as incomplete' : 'Mark as complete'),
            onTap: () async {
              Navigator.pop(context);
              await FirestoreService().updateTodoStatus(todo.id, !todo.isDone);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Delete task'),
            onTap: () async {
              Navigator.pop(context);
              final confirm = await _showConfirmationDialog(
                'Delete Task',
                'Are you sure you want to delete "${todo.title}"?',
              );
              if (confirm) {
                await FirestoreService().deleteTodo(todo.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Task deleted'),
                    action: SnackBarAction(
                      label: 'UNDO',
                      onPressed: () {
                        FirestoreService().uploadTodo(todo);
                      },
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
