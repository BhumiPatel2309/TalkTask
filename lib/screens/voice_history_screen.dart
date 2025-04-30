import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/voice_history_service.dart';

class VoiceHistoryScreen extends StatefulWidget {
  @override
  _VoiceHistoryScreenState createState() => _VoiceHistoryScreenState();
}

class _VoiceHistoryScreenState extends State<VoiceHistoryScreen> {
  final VoiceHistoryService _historyService = VoiceHistoryService();
  late List<Map<String, dynamic>> _commands;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCommands();
  }

  void _loadCommands() {
    setState(() {
      _isLoading = true;
    });
    
    _commands = _historyService.getAllCommands();
    
    setState(() {
      _isLoading = false;
    });
  }

  String _formatDate(String timestamp) {
    final date = DateTime.parse(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat.yMMMd().add_jm().format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Voice Command History'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_sweep),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Clear History'),
                  content: Text('Are you sure you want to clear all voice command history?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('CANCEL'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await _historyService.clearHistory();
                        Navigator.pop(context);
                        _loadCommands();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('History cleared')),
                        );
                      },
                      child: Text('CLEAR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Clear history',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _commands.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                      SizedBox(height: 16),
                      Text(
                        'No voice commands yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Your voice command history will appear here',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _commands.length,
                  itemBuilder: (context, index) {
                    final command = _commands[index];
                    final isProcessed = command['processed'] ?? false;
                    
                    return Dismissible(
                      key: Key(command['id'].toString()),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: EdgeInsets.only(right: 20),
                        child: Icon(Icons.delete, color: Colors.white),
                      ),
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) async {
                        await _historyService.deleteCommand(command['id']);
                        setState(() {
                          _commands.removeAt(index);
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Command deleted')),
                        );
                      },
                      child: Card(
                        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(command['command']),
                          subtitle: Text(_formatDate(command['timestamp'])),
                          leading: Icon(
                            isProcessed ? Icons.check_circle : Icons.info_outline,
                            color: isProcessed ? Colors.green : Colors.orange,
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.add_task),
                            onPressed: () {
                              Navigator.pop(context, command['command']);
                            },
                            tooltip: 'Create task from this command',
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
