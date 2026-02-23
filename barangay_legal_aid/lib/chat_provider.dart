import 'package:flutter/foundation.dart';
import 'chat_model.dart';
import 'package:barangay_legal_aid/models/user_model.dart';
import 'package:barangay_legal_aid/services/api_service.dart';

class ChatProvider with ChangeNotifier {
  List<ChatSession> _chatSessions = [];
  ChatSession? _currentSession;
  final ApiService? _apiService;

  List<ChatSession> get chatSessions => _chatSessions;
  ChatSession? get currentSession => _currentSession;

  ChatProvider({ApiService? apiService}) : _apiService = apiService {
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

    if (_apiService == null) {
      addMessage('Chat service not available. Please sign in again.', false);
      return;
    }
    try {
      final aiMessage = await _apiService.sendChatMessage(content, currentUser.id);
      addMessage(aiMessage, false);
    } catch (e) {
      final msg = e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Unable to reach chatbot. Please try again.';
      addMessage(msg, false);
    }
  }
}
