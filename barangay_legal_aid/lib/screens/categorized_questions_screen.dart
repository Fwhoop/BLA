import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/faq_model.dart';
import '../chat_model.dart';
import '../chat_provider.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class CategorizedQuestionsScreen extends StatefulWidget {
  final ChatProvider chatProvider;
  final User currentUser;

  const CategorizedQuestionsScreen({
    super.key,
    required this.chatProvider,
    required this.currentUser,
  });

  @override
  CategorizedQuestionsScreenState createState() =>
      CategorizedQuestionsScreenState();
}

class CategorizedQuestionsScreenState
    extends State<CategorizedQuestionsScreen> with SingleTickerProviderStateMixin {
  FaqData? _faqData;
  bool _isLoading = true;
  String _searchQuery = '';
  Category? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
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
    _messageController.dispose();
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
      // Try loading from assets first
      try {
        final String jsonString =
            await rootBundle.loadString('assets/barangay_law_flutter.json');
        final Map<String, dynamic> jsonData = json.decode(jsonString);
        setState(() {
          _faqData = FaqData.fromJson(jsonData);
          _isLoading = false;
        });
        // FAQ loaded from assets
        return;
      } catch (assetError) {
        // Fallback to API if assets fail
        // Fallback to API
      }
      
      // Fallback: Load from API
      try {
        final apiService = ApiService();
        final jsonData = await apiService.getFaqData();
        if (jsonData.isNotEmpty && jsonData.containsKey('categories')) {
          setState(() {
            _faqData = FaqData.fromJson(jsonData);
            _isLoading = false;
          });
          // FAQ loaded from API
          return;
        }
      } catch (apiError) {
        // API FAQ failed, use assets or empty
      }
      
      // If both fail, show error
      setState(() {
        _isLoading = false;
      });
      // FAQ unavailable from both sources
    } catch (e) {
      // Error loading FAQ: $e
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage(String message) async {
    if (message.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    await widget.chatProvider.sendMessageToBot(message, widget.currentUser);
    if (mounted) setState(() => _isSending = false);
  }

  void _ensureSession() {
    if (widget.chatProvider.currentSession == null) {
      widget.chatProvider.createNewSession();
    }
  }

  Future<void> _handleQuestionTap(Question question) async {
    _ensureSession();
    await _sendMessage(question.question);
    if (mounted) {
      setState(() {
        _selectedCategory = null;
        _searchQuery = '';
        _searchController.clear();
      });
    }
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

  /// First few questions from FAQ to show as quick-reply chips below the conversation.
  List<Question> get _suggestionChips {
    if (_faqData == null || _faqData!.categories.isEmpty) return [];
    final List<Question> chips = [];
    for (final c in _faqData!.categories) {
      for (final q in c.questions) {
        chips.add(q);
        if (chips.length >= 8) return chips;
      }
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = widget.chatProvider.currentSession;
    final hasMessages = currentSession != null && currentSession.messages.isNotEmpty;

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
          _buildHeader(hasMessages, currentSession),
          Expanded(
            child: hasMessages
                ? _buildConversationView(currentSession)
                : _buildWelcomeAndSuggestionsView(),
          ),
          _buildChatInput(),
          if (hasMessages) _buildSecondaryActions(),
        ],
      ),
    );
  }

  Widget _buildHeader(bool hasMessages, ChatSession? currentSession) {
    final showSearchInHeader = !hasMessages;
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
            color: Color(0xFF99272D).withValues(alpha:0.3),
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
                      color: Colors.white.withValues(alpha:0.25),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.1),
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
                            color: Colors.white.withValues(alpha:0.9),
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
              if (showSearchInHeader) ...[
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.1),
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

  Widget _buildConversationView(ChatSession? currentSession) {
    final session = currentSession!;
    final chips = _suggestionChips;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: session.messages.length + (_isSending ? 1 : 0) + (chips.isEmpty ? 0 : 1),
      itemBuilder: (context, index) {
        if (index < session.messages.length) {
          final message = session.messages[index];
          return ChatBubble(message: message);
        }
        if (index == session.messages.length && _isSending) {
          return _buildTypingIndicator();
        }
        if (index == session.messages.length + (_isSending ? 1 : 0)) {
          return _buildSuggestionChipsSection(chips);
        }
        return SizedBox.shrink();
      },
    );
  }

  Widget _buildSuggestionChipsSection(List<Question> questions) {
    if (questions.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 24, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested questions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: questions.map((q) {
              return ActionChip(
                label: Text(
                  q.question,
                  style: TextStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                backgroundColor: Color(0xFF99272D).withValues(alpha: 0.08),
                side: BorderSide(color: Color(0xFF99272D).withValues(alpha: 0.3)),
                onPressed: () => _handleQuestionTap(q),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeAndSuggestionsView() {
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
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }
    if (_faqData == null) return _buildErrorState();

    final searchResults = _searchQuery.isNotEmpty ? _allQuestions : <Question>[];
    final hasSearchResults = searchResults.isNotEmpty;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeCard(),
          SizedBox(height: 24),
          if (_selectedCategory != null)
            _buildQuestionsListInline(_selectedCategory!.questions, _selectedCategory!.name)
          else if (_searchQuery.isNotEmpty)
            hasSearchResults
                ? _buildQuestionsListInline(searchResults, 'Search Results')
                : _buildEmptySearchState()
          else
            _buildCategoriesListInline(),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Center(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Color(0xFF99272D).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: Color(0xFF99272D).withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'How can I help you today?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF36454F),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Choose a topic below or type your question',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsListInline(List<Question> questions, String title) {
    if (questions.isEmpty) return _buildEmptySearchState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF36454F),
          ),
        ),
        SizedBox(height: 12),
        ...questions.map((q) => Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: _buildQuestionCard(q),
        )),
      ],
    );
  }

  Widget _buildCategoriesListInline() {
    final categories = _filteredCategories;
    if (categories.isEmpty) return _buildEmptySearchState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Browse by category',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF36454F),
          ),
        ),
        SizedBox(height: 12),
        ...categories.map((c) => Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: _buildCategoryCard(c),
        )),
      ],
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE0E0E0), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitChatInput(),
              ),
            ),
            SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Color(0xFF99272D),
              child: IconButton(
                icon: Icon(Icons.send, color: Colors.white),
                onPressed: _submitChatInput,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitChatInput() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;
    _messageController.clear();
    _ensureSession();
    _sendMessage(text);
  }

  Widget _buildSecondaryActions() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE0E0E0), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _showBrowseSheet(context),
              icon: Icon(Icons.search, size: 18, color: Color(0xFF99272D)),
              label: Text('Browse Questions', style: TextStyle(color: Color(0xFF99272D))),
            ),
            SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  widget.chatProvider.createNewSession();
                  _selectedCategory = null;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
              icon: Icon(Icons.refresh, size: 18, color: Color(0xFF99272D)),
              label: Text('New Chat', style: TextStyle(color: Color(0xFF99272D))),
            ),
          ],
        ),
      ),
    );
  }

  void _showBrowseSheet(BuildContext context) {
    if (_faqData == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Suggested questions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF36454F)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _faqData!.categories.length,
                  itemBuilder: (context, index) {
                    final category = _faqData!.categories[index];
                    return ExpansionTile(
                      title: Text(category.name, style: TextStyle(fontWeight: FontWeight.w600)),
                      children: category.questions.map((q) {
                        return ListTile(
                          title: Text(q.question, style: TextStyle(fontSize: 14)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _handleQuestionTap(q);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
            color: Colors.white.withValues(alpha:0.3 + (value * 0.7)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
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

  Widget _buildCategoryCard(Category category) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
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
                    color: Color(0xFF99272D).withValues(alpha:0.1),
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
            color: Colors.black.withValues(alpha:0.03),
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
                    color: Color(0xFF99272D).withValues(alpha:0.1),
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
                    color: Color(0xFF99272D).withValues(alpha:0.1),
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
                    color: Color(0xFF99272D).withValues(alpha:0.3),
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
                    color: Colors.black.withValues(alpha:0.1),
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
                    color: Color(0xFF99272D).withValues(alpha:0.3),
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
