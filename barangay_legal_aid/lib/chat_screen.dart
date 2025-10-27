import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/chat_model.dart';
import 'package:barangay_legal_aid/chat_provider.dart';
import 'package:barangay_legal_aid/models/user_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  final ChatProvider chatProvider;
  final User currentUser;

  const ChatScreen({
    super.key,
    required this.chatProvider,
    required this.currentUser,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    widget.chatProvider.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.chatProvider.removeListener(_refresh);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;

    widget.chatProvider.addMessage(message, true);
    _messageController.clear();

    setState(() {
      _isSending = true;
    });

    try {
      final url = Uri.parse('http://127.0.0.1:8000/chats/ai'); 

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender_id': widget.currentUser.id,
          'receiver_id': 1, // Use 1 for bot user
          'message': message,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final botReply = data['message'] ?? "Sorry, I couldn't understand that.";

        widget.chatProvider.addMessage(botReply, false);
      } else {
        print('Error status code: ${response.statusCode}');
        print('Error response: ${response.body}');
        final errorMsg = "Error ${response.statusCode}: Could not reach chatbot. ${response.body}";
        widget.chatProvider.addMessage(errorMsg, false);
      }
    } catch (e) {
      print('Error: $e');
      widget.chatProvider
          .addMessage("Error: Could not connect to server. Details: $e", false);
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = widget.chatProvider.currentSession;

    return Container(
      color: Color(0xFFFFFFFF),
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFF99272D),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    'BOT',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  currentSession?.title ?? 'New Chat',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(
            child: currentSession == null || currentSession.messages.isEmpty
                ? Center(
                    child: Text('Start a new conversation'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(16),
                    itemCount: currentSession.messages.length,
                    itemBuilder: (context, index) {
                      final message = currentSession.messages[index];
                      return ChatBubble(message: message);
                    },
                  ),
          ),

          // Input
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFFFFFFFF),
              border: Border(
                top: BorderSide(color: Color(0xFF36454F).withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                            color: Color(0xFF36454F).withOpacity(0.3)),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Color(0xFF99272D),
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser)
            CircleAvatar(
              backgroundColor: Color(0xFF99272D),
              child: Text('BOT', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          if (!message.isUser) SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isUser ? Color(0xFF99272D) : Color(0xFF36454F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message.content,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          if (message.isUser) SizedBox(width: 8),
          if (message.isUser)
            CircleAvatar(
              backgroundColor: Color(0xFF99272D),
              child: Text('YOU', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
        ],
      ),
    );
  }
}
