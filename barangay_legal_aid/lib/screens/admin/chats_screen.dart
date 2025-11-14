import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class AdminChatsScreen extends StatefulWidget {
  const AdminChatsScreen({super.key});

  @override
  _AdminChatsScreenState createState() => _AdminChatsScreenState();
}

class _AdminChatsScreenState extends State<AdminChatsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final chats = await _apiService.getChats();
      setState(() {
        _chats = chats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _getChatColor(Map<String, dynamic> chat) {
    if (chat['is_bot'] == true) {
      return Color(0xFF36454F);
    }
    return Color(0xFF99272D);
  }

  IconData _getChatIcon(Map<String, dynamic> chat) {
    if (chat['is_bot'] == true) {
      return Icons.smart_toy;
    }
    return Icons.person;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chats Monitoring'),
        backgroundColor: Color(0xFF99272D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadChats,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Color(0xFF99272D)),
                      SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Color(0xFF36454F))),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadChats,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _chats.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No chats found', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadChats,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _chats.length,
                        itemBuilder: (context, index) {
                          final chat = _chats[index];
                          final color = _getChatColor(chat);
                          final icon = _getChatIcon(chat);
                          
                          return Card(
                            margin: EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color,
                                child: Icon(icon, color: Colors.white),
                              ),
                              title: Text(
                                chat['is_bot'] == true ? 'Bot Response' : 'User Message',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 4),
                                  Text(
                                    chat['message'] ?? 'No message',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Sender ID: ${chat['sender_id']} | Receiver ID: ${chat['receiver_id']}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  if (chat['created_at'] != null)
                                    Text(
                                      'Date: ${chat['created_at']}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

