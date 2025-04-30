import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../providers/todo_provider.dart';
import '../services/firestore_service.dart';
import '../services/offline_queue.dart';
import '../services/voice_service.dart';
import '../services/tts_service.dart';
import '../services/voice_history_service.dart';
import 'voice_history_screen.dart';
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
  final voiceHistory = VoiceHistoryService();
  
  // Track the current filter tab
  String _currentFilter = 'all'; // 'all', 'active', or 'done'

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
    // For web, we need to ensure microphone permissions are granted
    // Show a message to the user about allowing microphone access
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Please allow microphone access when prompted'),
        duration: Duration(seconds: 3),
        backgroundColor: Colors.blue,
      ),
    );
    
    // Initialize speech recognition
    await voice.init();
    
    // Get device locale for better recognition
    String? deviceLocale;
    try {
      final locales = await voice.getAvailableLocales();
      if (locales.isNotEmpty) {
        // Try to find a locale matching the device language
        deviceLocale = locales.first.localeId;
      }
    } catch (e) {
      print('Error getting locales: $e');
    }
    
    // Show recording indicator with animation
    final snackBar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.mic, color: Colors.white),
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            Text('Listening... Speak your task'),
          ],
        ),
        duration: Duration(seconds: 20), // Longer duration for the listening process
        backgroundColor: Colors.teal,
      ),
    );
    
    // Start voice recognition with the device locale
    String? result;
    try {
      result = await voice.listen(locale: deviceLocale);
      print('Voice recognition result: $result');
    } catch (e) {
      print('Error during voice recognition: $e');
      result = null;
    }
    
    // Dismiss the listening indicator
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    // Determine the task text to use
    String taskText;
    bool isDefaultTask = false;
    
    if (result == null || result.isEmpty) {
      // If nothing was spoken, use default tasks
      final defaultTasks = [
        'Nothing to do',
        'Default task',
        'Remember to add tasks',
        'Tap to add details'
      ];
      // Pick a random default task
      taskText = defaultTasks[DateTime.now().second % defaultTasks.length];
      isDefaultTask = true;
      
      // Store the default task in voice history
      await voiceHistory.addCommand(taskText, wasProcessed: false);
      
      // Show message about using default task
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No speech detected. Using default task.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Use the spoken text
      taskText = result;
      
      // Store the spoken command in voice history
      await voiceHistory.addCommand(taskText, wasProcessed: true);
      
      // Show what was heard with confirmation
      await _showRecognitionResult(taskText);
    }
    
    // Create a task from the determined text
    final todo = parseCommand(taskText);
    
    // Check connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    final isConnected = connectivityResult != ConnectivityResult.none;
    
    if (isConnected) {
      // Online mode - upload directly
      try {
        await FirestoreService().uploadTodo(todo!);
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
        queue.addCommand(taskText);
        await tts.speak("Network error. Saved offline: $taskText");
        
        // Show offline save message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.white),
                SizedBox(width: 8),
                Text('Network error. Saved offline: $taskText'),
              ],
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      // Offline mode - save to queue
      queue.addCommand(taskText);
      await tts.speak("Offline mode. Saved: $taskText");
      
      // Show offline save message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.cloud_off, color: Colors.white),
              SizedBox(width: 8),
              Text('Offline mode. Task saved locally.'),
            ],
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
    
    // Refresh UI to show updated offline count
    setState(() {});
  }
  
  // Show what was recognized with visual feedback
  Future<void> _showRecognitionResult(String recognizedText) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.mic, color: Colors.teal),
              SizedBox(width: 8),
              Text('Voice Recognized'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('I heard:'),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '"$recognizedText"',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(height: 16),
                Text('This will be added as a task.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('EDIT'),
              onPressed: () {
                Navigator.of(context).pop();
                _showEditRecognizedTextDialog(recognizedText);
              },
            ),
            ElevatedButton(
              child: Text('CONFIRM'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
  
  // Allow editing the recognized text
  Future<String?> _showEditRecognizedTextDialog(String originalText) async {
    final TextEditingController textController = TextEditingController(text: originalText);
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Task Text'),
        content: TextField(
          controller: textController,
          decoration: InputDecoration(
            hintText: 'Edit your task text',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, textController.text.trim()),
            child: Text('SAVE'),
          ),
        ],
      ),
    );
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
          // Voice history button
          IconButton(
            icon: Icon(Icons.history),
            onPressed: () => _openVoiceHistoryScreen(),
            tooltip: 'Voice command history',
          ),
          // Sync button with badge
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
                    onPressed: () => setState(() => _currentFilter = 'all'),
                    style: TextButton.styleFrom(
                      backgroundColor: _currentFilter == 'all' ? Colors.teal.shade100 : null,
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: Icon(Icons.check_box_outline_blank),
                    label: Text('Active'),
                    onPressed: () => setState(() => _currentFilter = 'active'),
                    style: TextButton.styleFrom(
                      backgroundColor: _currentFilter == 'active' ? Colors.teal.shade100 : null,
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: Icon(Icons.check_box),
                    label: Text('Done'),
                    onPressed: () => setState(() => _currentFilter = 'done'),
                    style: TextButton.styleFrom(
                      backgroundColor: _currentFilter == 'done' ? Colors.teal.shade100 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildTaskList(),
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
  
  // Build the task list based on the current filter
  Widget _buildTaskList() {
    // Choose the appropriate provider based on the filter
    final taskProvider = _currentFilter == 'active'
        ? activeTodoStreamProvider
        : _currentFilter == 'done'
            ? completedTodoStreamProvider
            : todoStreamProvider;
    
    // Get the appropriate filter name for empty state message
    final filterName = _currentFilter == 'active'
        ? 'active'
        : _currentFilter == 'done'
            ? 'completed'
            : '';
    
    return ref.watch(taskProvider).when(
      data: (todos) => todos.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task, size: 64, color: Colors.grey.shade400),
                  SizedBox(height: 16),
                  Text(
                    filterName.isNotEmpty
                        ? 'No $filterName tasks'
                        : 'No tasks yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    filterName.isNotEmpty
                        ? _currentFilter == 'active'
                            ? 'Tasks you complete will no longer appear here'
                            : 'Complete some tasks to see them here'
                        : 'Tap the mic to add one with voice\nor use the + button to type',
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
  
  // Open voice history screen
  Future<void> _openVoiceHistoryScreen() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => VoiceHistoryScreen()),
    );
    
    // If a command was selected from history, create a task from it
    if (result != null && result.isNotEmpty) {
      final todo = parseCommand(result);
      if (todo != null) {
        try {
          await FirestoreService().uploadTodo(todo);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Task created from history: ${todo.title}'),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating task from history')),
          );
        }
      }
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
