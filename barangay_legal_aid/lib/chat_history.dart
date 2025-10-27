import 'package:flutter/material.dart';
import 'package:barangay_legal_aid/chat_model.dart';
import 'package:barangay_legal_aid/chat_provider.dart';
import 'package:barangay_legal_aid/screens/request_form.dart';
import 'package:barangay_legal_aid/services/auth_service.dart';

class ChatHistorySidebar extends StatelessWidget {
  final ChatProvider chatProvider;
  final VoidCallback? onToggle;

  const ChatHistorySidebar({required this.chatProvider, this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color(0xFF36454F),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFF36454F),
              border: Border(bottom: BorderSide(color: Color(0xFF99272D).withOpacity(0.5))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.chat, color: Color(0xFFFFFFFF)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Chat History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFFFFF),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onToggle != null)
                      IconButton(
                        icon: Icon(Icons.chevron_left, color: Color(0xFFFFFFFF)),
                        tooltip: 'Hide',
                        onPressed: onToggle,
                      ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: chatProvider.createNewSession,
                        icon: Icon(Icons.add, size: 18),
                        label: Text('New Chat'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFFFFFF).withOpacity(0.2),
                          foregroundColor: Color(0xFFFFFFFF),
                          padding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final authService = AuthService();
                          final user = await authService.getCurrentUser();
                          if (user != null && context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RequestForm(
                                  userBarangay: user.barangay,
                                  preselectedDocumentType: null, // No preselection from chat history
                                ),
                              ),
                            );
                          }
                        },
                        icon: Icon(Icons.description, size: 18),
                        label: Text('Request'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF99272D),
                          foregroundColor: Color(0xFFFFFFFF),
                          padding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: chatProvider.chatSessions.length,
              itemBuilder: (context, index) {
                final session = chatProvider.chatSessions[index];
                final isSelected = chatProvider.currentSession?.id == session.id;

                return Container(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? Color(0xFF99272D).withOpacity(0.8) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ChatSessionTile(
                    session: session,
                    isSelected: isSelected,
                    onTap: () => chatProvider.selectSession(session.id),
                    onDelete: () => chatProvider.deleteSession(session.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ChatSessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ChatSessionTile({
    required this.session,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.chat_bubble_outline,
        color: isSelected ? Color(0xFFFFFFFF) : Color(0xFFFFFFFF).withOpacity(0.7),
      ),
      title: Text(
        session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Color(0xFFFFFFFF) : Color(0xFFFFFFFF).withOpacity(0.8),
        ),
      ),
      subtitle: Text(
        '${session.messages.length} messages',
        style: TextStyle(fontSize: 12, color: Color(0xFFFFFFFF).withOpacity(0.6)),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, size: 18, color: Color(0xFFFFFFFF).withOpacity(0.7)),
        onPressed: onDelete,
      ),
      onTap: onTap,
      selected: isSelected,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }
}
