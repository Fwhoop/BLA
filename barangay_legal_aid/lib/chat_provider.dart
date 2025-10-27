import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'chat_model.dart';
import '../models/user_model.dart';

class ChatProvider with ChangeNotifier {
  List<ChatSession> _chatSessions = [];
  ChatSession? _currentSession;

  List<ChatSession> get chatSessions => _chatSessions;
  ChatSession? get currentSession => _currentSession;

  ChatProvider() {
    _loadSessions();
  }

  void _loadSessions() {
    _chatSessions = [
      ChatSession(
        id: '1',
        title: 'Welcome Chat',
        createdAt: DateTime.now().subtract(Duration(hours: 2)),
        messages: [
          ChatMessage(
            id: '1-1',
            content: 'Hello! How can I help you today?',
            isUser: false,
            timestamp: DateTime.now().subtract(Duration(hours: 2)),
          ),
        ],
      ),
    ];
    _currentSession = _chatSessions.first;
    notifyListeners();
  }

  void createNewSession() {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New Chat',
      createdAt: DateTime.now(),
      messages: [],
    );
    _chatSessions.insert(0, newSession);
    _currentSession = newSession;
    notifyListeners();
  }

  void selectSession(String sessionId) {
    _currentSession = _chatSessions.firstWhere(
      (session) => session.id == sessionId,
      orElse: () => _chatSessions.first,
    );
    notifyListeners();
  }

  void addMessage(String content, bool isUser) {
    if (_currentSession == null) {
      createNewSession();
    }

    final message = ChatMessage(
      id: '${_currentSession!.id}-${_currentSession!.messages.length + 1}',
      content: content,
      isUser: isUser,
      timestamp: DateTime.now(),
    );

    _currentSession!.messages.add(message);

    if (_currentSession!.messages.length == 1 && isUser) {
      _currentSession!.title =
          content.length > 30 ? '${content.substring(0, 30)}...' : content;
      final index = _chatSessions.indexWhere((s) => s.id == _currentSession!.id);
      if (index != -1) _chatSessions[index] = _currentSession!;
    }

    notifyListeners();
  }

  void deleteSession(String sessionId) {
    _chatSessions.removeWhere((session) => session.id == sessionId);
    if (_currentSession?.id == sessionId) {
      _currentSession = _chatSessions.isNotEmpty ? _chatSessions.first : null;
    }
    notifyListeners();
  }

  
  Future<void> sendMessageToBot(String content, User currentUser) async {
    if (_currentSession == null) createNewSession();

    addMessage(content, true);

    try {
      final url = Uri.parse('http://127.0.0.1:8000/chats/ai');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender_id': currentUser.id,
          'receiver_id': 1,
          'message': content,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final aiMessage = data['message'] as String;

        addMessage(aiMessage, false);
      } else {
        print('Error status code: ${response.statusCode}');
        print('Error response: ${response.body}');
        addMessage('Failed to get AI response', false);
      }
    } catch (e) {
      print('Error: $e');
      addMessage('Error connecting to AI: $e', false);
    }
  }
}
