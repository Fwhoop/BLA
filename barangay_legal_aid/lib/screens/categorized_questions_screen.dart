import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../models/faq_model.dart';
import '../chat_model.dart';
import '../chat_provider.dart';
import '../models/user_model.dart';
import 'package:http/http.dart' as http;

class CategorizedQuestionsScreen extends StatefulWidget {
  final ChatProvider chatProvider;
  final User currentUser;

  const CategorizedQuestionsScreen({
    super.key,
    required this.chatProvider,
    required this.currentUser,
  });

  @override
  _CategorizedQuestionsScreenState createState() =>
      _CategorizedQuestionsScreenState();
}

class _CategorizedQuestionsScreenState
    extends State<CategorizedQuestionsScreen> with SingleTickerProviderStateMixin {
  FaqData? _faqData;
  bool _isLoading = true;
  String _searchQuery = '';
  Category? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    widget.chatProvider.addListener(_refresh);
    _loadFaqData();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    widget.chatProvider.removeListener(_refresh);
    _searchController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
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

  Future<void> _loadFaqData() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/barangay_law_flutter.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      setState(() {
        _faqData = FaqData.fromJson(jsonData);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading FAQ data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage(String message) async {
    if (message.isEmpty || _isSending) return;

    widget.chatProvider.addMessage(message, true);

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
          'receiver_id': 1,
          'message': message,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final botReply = data['message'] ?? "Sorry, I couldn't understand that.";

        widget.chatProvider.addMessage(botReply, false);
      } else {
        final errorMsg =
            "I'm having trouble connecting right now. Please try again in a moment.";
        widget.chatProvider.addMessage(errorMsg, false);
      }
    } catch (e) {
      print('Error: $e');
      widget.chatProvider
          .addMessage("I'm having trouble connecting right now. Please check your internet connection and try again.", false);
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _handleQuestionTap(Question question) async {
    // Ensure we have a session before sending (reuse existing if available)
    if (widget.chatProvider.currentSession == null) {
      widget.chatProvider.createNewSession();
    }
    
    // Send the question - this will add messages to the current session
    await _sendMessage(question.question);
    
    // Clear selection and switch to chat view AFTER message is sent
    setState(() {
      _selectedCategory = null;
      _searchQuery = '';
      _searchController.clear();
      _showOptionsView = false; // Show chat view after question is selected
    });
  }

  List<Category> get _filteredCategories {
    if (_faqData == null) return [];
    if (_searchQuery.isEmpty) return _faqData!.categories;

    final query = _searchQuery.toLowerCase();
    return _faqData!.categories.where((category) {
      if (category.name.toLowerCase().contains(query)) return true;
      return category.questions.any((q) =>
          q.question.toLowerCase().contains(query) ||
          q.answer.toLowerCase().contains(query));
    }).toList();
  }

  List<Question> get _allQuestions {
    if (_faqData == null) return [];
    if (_selectedCategory != null) {
      return _selectedCategory!.questions;
    }
    if (_searchQuery.isEmpty) {
      return [];
    }

    final query = _searchQuery.toLowerCase();
    final List<Question> all = [];
    for (final category in _faqData!.categories) {
      all.addAll(category.questions.where((q) =>
          q.question.toLowerCase().contains(query) ||
          q.answer.toLowerCase().contains(query)));
    }
    return all;
  }

  void _selectCategory(Category category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedCategory = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  bool _showOptionsView = true; // Track if we should show options view

  @override
  Widget build(BuildContext context) {
    final currentSession = widget.chatProvider.currentSession;
    // Determine what to show:
    // - If _showOptionsView is explicitly set, respect it
    // - Otherwise, show options if no session, session is empty, or category is selected
    // - Otherwise show chat view
    bool showOptions;
    if (currentSession != null && currentSession.messages.isNotEmpty) {
      // If we have messages, respect the _showOptionsView flag
      showOptions = _showOptionsView || _selectedCategory != null;
    } else {
      // If no messages, always show options
      showOptions = true;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF8F9FA),
            Color(0xFFFFFFFF),
          ],
        ),
      ),
      child: Column(
        children: [
          // Enhanced Header
          _buildHeader(showOptions, currentSession),
          
          // Content area
          Expanded(
            child: showOptions
                ? _buildOptionsView()
                : _buildChatView(currentSession),
          ),

          // Chat actions (only show when in chat view)
          _buildChatActions(),
        ],
      ),
    );
  }

  Widget _buildHeader(bool showOptions, ChatSession? currentSession) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF99272D),
            Color(0xFFB83A42),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF99272D).withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(Icons.smart_toy, color: Colors.white, size: 24),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Barangay Legal Aid',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          currentSession?.title ?? 'Ask me anything',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedCategory != null)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _clearSelection,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                ],
              ),
              if (showOptions) ...[
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search questions or categories...',
                      hintStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 15,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: Colors.grey[600]),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: TextStyle(color: Colors.black, fontSize: 15),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatView(ChatSession? currentSession) {
    final session = currentSession;
    // Show empty state only if truly empty (not during message sending)
    if (session == null || (session.messages.isEmpty && !_isSending)) {
      return _buildEmptyChatState();
    }
    
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: session.messages.length + (_isSending ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == session.messages.length) {
              return _buildTypingIndicator();
            }
            final message = session.messages[index];
            return ChatBubble(message: message);
          },
        ),
      ],
    );
  }

  Widget _buildEmptyChatState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Color(0xFF99272D).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Color(0xFF99272D).withOpacity(0.6),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Start a conversation',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF36454F),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Select a question above or type your message',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFF36454F),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                SizedBox(width: 4),
                _buildDot(1),
                SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final delay = index * 0.2;
        final value = (_animationController.value + delay) % 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3 + (value * 0.7)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildChatActions() {
    final currentSession = widget.chatProvider.currentSession;
    final bool showChatActions = currentSession != null &&
        currentSession.messages.isNotEmpty;

    if (!showChatActions) {
      return SizedBox.shrink();
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Color(0xFFE0E0E0),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Button to go back to questions (doesn't create new chat)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _showOptionsView = true; // Show options to select another question
                    _selectedCategory = null; // Clear any selected category
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search, color: Color(0xFF99272D), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Browse Questions',
                        style: TextStyle(
                          color: Color(0xFF99272D),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            // Button to start a new chat
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    widget.chatProvider.createNewSession();
                    _showOptionsView = true; // Show options for new chat
                    _selectedCategory = null;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Color(0xFF99272D),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'New Chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsView() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF99272D)),
            ),
            SizedBox(height: 16),
            Text(
              'Loading questions...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_faqData == null) {
      return _buildErrorState();
    }

    if (_selectedCategory != null) {
      return _buildQuestionsList(_selectedCategory!.questions, _selectedCategory!.name);
    }

    if (_searchQuery.isNotEmpty) {
      final questions = _allQuestions;
      if (questions.isNotEmpty) {
        return _buildQuestionsList(questions, 'Search Results');
      }
      return _buildEmptySearchState();
    }

    return _buildCategoriesList();
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'Failed to load FAQ data',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Please try again later',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Try different keywords',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesList() {
    final categories = _filteredCategories;

    if (categories.isEmpty) {
      return _buildEmptySearchState();
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (index * 50)),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            );
          },
          child: _buildCategoryCard(category),
        );
      },
    );
  }

  Widget _buildCategoryCard(Category category) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectCategory(category),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF99272D).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    color: Color(0xFF99272D),
                    size: 24,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF36454F),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.help_outline,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          SizedBox(width: 4),
                          Text(
                            '${category.questions.length} question${category.questions.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Color(0xFF99272D),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionsList(List<Question> questions, String title) {
    if (questions.isEmpty) {
      return _buildEmptySearchState();
    }

    return Column(
      children: [
        if (title.isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey[200]!,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.arrow_back, size: 20, color: Color(0xFF99272D)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF36454F),
                    ),
                  ),
                ),
                Text(
                  '${questions.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: questions.length,
            itemBuilder: (context, index) {
              final question = questions[index];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 200 + (index * 30)),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 15 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: _buildQuestionCard(question),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(Question question) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Color(0xFFE0E0E0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleQuestionTap(question),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Color(0xFF99272D).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.question_answer,
                    color: Color(0xFF99272D),
                    size: 20,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    question.question,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF36454F),
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Color(0xFF99272D).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.send,
                    color: Color(0xFF99272D),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF99272D), Color(0xFFB83A42)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF99272D).withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.smart_toy, color: Colors.white, size: 18),
            ),
            SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: message.isUser
                    ? LinearGradient(
                        colors: [Color(0xFF99272D), Color(0xFFB83A42)],
                      )
                    : null,
                color: message.isUser ? null : Color(0xFF36454F),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(message.isUser ? 20 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF99272D), Color(0xFFB83A42)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF99272D).withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}
