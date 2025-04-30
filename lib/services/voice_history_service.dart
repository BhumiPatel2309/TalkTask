import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

class VoiceHistoryService {
  final _box = Hive.box('voiceHistory');
  
  // Add a voice command to history
  Future<void> addCommand(String command, {bool wasProcessed = true}) async {
    final timestamp = DateTime.now().toIso8601String();
    final entry = {
      'command': command,
      'timestamp': timestamp,
      'processed': wasProcessed,
    };
    await _box.add(jsonEncode(entry));
  }
  
  // Get all voice commands history
  List<Map<String, dynamic>> getAllCommands() {
    final commands = <Map<String, dynamic>>[];
    for (int i = 0; i < _box.length; i++) {
      final entry = jsonDecode(_box.getAt(i));
      entry['id'] = i;
      commands.add(entry);
    }
    // Sort by timestamp (newest first)
    commands.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    return commands;
  }
  
  // Get the most recent commands (limited by count)
  List<Map<String, dynamic>> getRecentCommands({int count = 10}) {
    final commands = getAllCommands();
    return commands.take(count).toList();
  }
  
  // Delete a specific command by ID
  Future<void> deleteCommand(int id) async {
    await _box.deleteAt(id);
  }
  
  // Clear all history
  Future<void> clearHistory() async {
    await _box.clear();
  }
  
  // Get the count of stored commands
  int getCommandCount() {
    return _box.length;
  }
}
