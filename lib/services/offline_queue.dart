import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

class OfflineQueue {
  final _box = Hive.box('taskQueue');
  
  // Add a command with timestamp to the queue
  void addCommand(String command) {
    final timestamp = DateTime.now().toIso8601String();
    final entry = {
      'command': command,
      'timestamp': timestamp,
      'processed': false
    };
    _box.add(jsonEncode(entry));
  }
  
  // Get all unprocessed commands
  List<Map<String, dynamic>> getUnprocessedCommands() {
    final commands = <Map<String, dynamic>>[];
    for (int i = 0; i < _box.length; i++) {
      final entry = jsonDecode(_box.getAt(i));
      if (entry['processed'] == false) {
        entry['index'] = i;
        commands.add(entry);
      }
    }
    return commands;
  }
  
  // Get all commands (processed and unprocessed)
  List<Map<String, dynamic>> getAllCommands() {
    final commands = <Map<String, dynamic>>[];
    for (int i = 0; i < _box.length; i++) {
      final entry = jsonDecode(_box.getAt(i));
      entry['index'] = i;
      commands.add(entry);
    }
    return commands;
  }
  
  // Mark a command as processed
  void markAsProcessed(int index) {
    if (index >= 0 && index < _box.length) {
      final entry = jsonDecode(_box.getAt(index));
      entry['processed'] = true;
      _box.putAt(index, jsonEncode(entry));
    }
  }
  
  // Get the count of unprocessed commands
  int getUnprocessedCount() {
    return getUnprocessedCommands().length;
  }
  
  // Clear all processed commands
  void clearProcessedCommands() {
    final keysToDelete = <int>[];
    for (int i = 0; i < _box.length; i++) {
      final entry = jsonDecode(_box.getAt(i));
      if (entry['processed'] == true) {
        keysToDelete.add(i);
      }
    }
    
    // Delete in reverse order to avoid index shifting issues
    for (int i = keysToDelete.length - 1; i >= 0; i--) {
      _box.deleteAt(keysToDelete[i]);
    }
  }
  
  // Clear all commands
  void clearQueue() {
    _box.clear();
  }
}
