import 'package:hive_flutter/hive_flutter.dart';

class OfflineQueue {
  final _box = Hive.box('taskQueue');

  void addCommand(String command) {
    _box.add(command);
  }

  List<String> getCommands() {
    return _box.values.cast<String>().toList();
  }

  void clearQueue() {
    _box.clear();
  }
}
