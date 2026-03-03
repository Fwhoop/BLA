import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/chat_model.dart';
import 'package:barangay_legal_aid/chat_provider.dart';
import 'package:barangay_legal_aid/models/user_model.dart';

class ChatScreen extends StatefulWidget {
  final ChatProvider chatProvider;
  final User currentUser;

  const ChatScreen({
    super.key,
    required this.chatProvider,
    required this.currentUser,
  });

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
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

    _messageController.clear();
    setState(() => _isSending = true);

    await widget.chatProvider.sendMessageToBot(message, widget.currentUser);

    if (mounted) setState(() => _isSending = false);
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
                    color: Color(0xFFFFFFFF).withValues(alpha:0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    'BOT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    currentSession?.title ?? 'New Chat',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
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
                top: BorderSide(color: Color(0xFF36454F).withValues(alpha:0.2)),
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
                            color: Color(0xFF36454F).withValues(alpha:0.3)),
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

  static _ActionCardData? _resolveAction(String? uiAction) {
    switch (uiAction) {
      case 'HIGHLIGHT_MENU:complaint':
        return _ActionCardData(
          icon: Icons.report_problem_outlined,
          label: 'Go to Complaint Form',
          color: Color(0xFFB71C1C),
        );
      case 'HIGHLIGHT_MENU:document':
        return _ActionCardData(
          icon: Icons.description_outlined,
          label: 'Go to Document Request',
          color: Color(0xFF1565C0),
        );
      case 'HIGHLIGHT_MENU:suggestion':
        return _ActionCardData(
          icon: Icons.lightbulb_outline,
          label: 'Go to Suggestion Box',
          color: Color(0xFF2E7D32),
        );
      case 'OPEN:tracking':
        return _ActionCardData(
          icon: Icons.track_changes_outlined,
          label: 'Go to Request Tracking',
          color: Color(0xFF6A1B9A),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionData = !message.isUser ? _resolveAction(message.uiAction) : null;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                if (actionData != null) ...[
                  SizedBox(height: 6),
                  _ActionCard(data: actionData),
                ],
              ],
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

class _ActionCardData {
  final IconData icon;
  final String label;
  final Color color;
  const _ActionCardData({required this.icon, required this.label, required this.color});
}

class _ActionCard extends StatelessWidget {
  final _ActionCardData data;

  const _ActionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final icon = data.icon;
    final label = data.label;
    final color = data.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 6),
          Icon(Icons.arrow_forward_ios, color: color, size: 12),
        ],
      ),
    );
  }
}
