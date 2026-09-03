import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/models/article.dart';
import '../../components/glass_container.dart';
import '../../glass_theme.dart';

/// AI interaction view for Q&A about articles
class AIInteractionView extends ConsumerStatefulWidget {
  final Article article;
  final AIService aiService;
  final VoidCallback onClose;
  
  const AIInteractionView({
    super.key,
    required this.article,
    required this.aiService,
    required this.onClose,
  });
  
  @override
  ConsumerState<AIInteractionView> createState() => _AIInteractionViewState();
}

class _AIInteractionViewState extends ConsumerState<AIInteractionView>
    with TickerProviderStateMixin {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  List<String> _suggestedQuestions = [];
  bool _isLoading = false;
  bool _isGeneratingQuestions = true;
  
  late AnimationController _typingAnimationController;
  
  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
    
    _generateInitialQuestions();
  }
  
  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
    super.dispose();
  }
  
  Future<void> _generateInitialQuestions() async {
    try {
      final content = widget.article.fullContent ?? 
                     widget.article.content ?? 
                     widget.article.summary ?? '';
      
      final questions = await widget.aiService.generateQuestions(content);
      
      if (mounted) {
        setState(() {
          _suggestedQuestions = questions;
          _isGeneratingQuestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGeneratingQuestions = false;
        });
      }
    }
  }
  
  Future<void> _askQuestion(String question) async {
    if (question.trim().isEmpty) return;
    
    setState(() {
      _messages.add(_ChatMessage(
        text: question,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });
    
    _questionController.clear();
    _scrollToBottom();
    
    try {
      final content = widget.article.fullContent ?? 
                     widget.article.content ?? 
                     widget.article.summary ?? '';
      
      final answer = await widget.aiService.answerQuestion(content, question);
      
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: answer,
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: 'Sorry, I couldn\'t process your question. Please try again.',
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(glassThemeProvider);
    
    return GlassContainer(
      blur: theme.blur,
      opacity: theme.opacity,
      gradient: LinearGradient(
        colors: theme.gradientColors,
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: theme.borderColor,
        width: theme.borderWidth,
      ),
      shadows: theme.shadows,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.borderColor.withOpacity(0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat,
                  color: theme.textColor,
                  size: 28,
                ).animate().scale(
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask About This Article',
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.article.title,
                        style: TextStyle(
                          color: theme.textColor.withOpacity(0.7),
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: theme.textColor.withOpacity(0.7),
                  ),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          
          // Chat area
          Expanded(
            child: Stack(
              children: [
                // Messages or initial state
                if (_messages.isEmpty && !_isGeneratingQuestions)
                  _buildInitialState(theme)
                else
                  _buildChatMessages(theme),
                
                // Loading indicator
                if (_isLoading)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildTypingIndicator(theme),
                  ),
              ],
            ),
          ),
          
          // Input area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.3),
              border: Border(
                top: BorderSide(
                  color: theme.borderColor.withOpacity(0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.cardColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.borderColor.withOpacity(0.3),
                      ),
                    ),
                    child: TextField(
                      controller: _questionController,
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ask a question about this article...',
                        hintStyle: TextStyle(
                          color: theme.textColor.withOpacity(0.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        border: InputBorder.none,
                      ),
                      onSubmitted: _askQuestion,
                      enabled: !_isLoading,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: _isLoading
                        ? theme.borderColor.withOpacity(0.3)
                        : theme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading
                          ? null
                          : () => _askQuestion(_questionController.text),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.send,
                          color: _isLoading
                              ? theme.textColor.withOpacity(0.3)
                              : Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ).animate().scale(
                  duration: 200.ms,
                  curve: Curves.easeOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInitialState(GlassThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.auto_awesome,
            color: theme.primaryColor,
            size: 64,
          ).animate()
            .scale(duration: 600.ms, curve: Curves.elasticOut)
            .shimmer(duration: 2.seconds),
          const SizedBox(height: 20),
          Text(
            'I\'m ready to answer your questions!',
            style: TextStyle(
              color: theme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 8),
          Text(
            'Ask me anything about this article',
            style: TextStyle(
              color: theme.textColor.withOpacity(0.7),
              fontSize: 14,
            ),
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 40),
          
          // Suggested questions
          if (_suggestedQuestions.isNotEmpty) ...[
            Text(
              'Suggested Questions',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ).animate().fadeIn(delay: 500.ms),
            const SizedBox(height: 16),
            ..._suggestedQuestions.asMap().entries.map((entry) {
              final index = entry.key;
              final question = entry.value;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _askQuestion(question),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.borderColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: theme.primaryColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              question,
                              style: TextStyle(
                                color: theme.textColor,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward,
                            color: theme.textColor.withOpacity(0.3),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ).animate()
                .fadeIn(delay: (600 + index * 100).ms)
                .slideX(begin: 0.1);
            }),
          ] else if (_isGeneratingQuestions) ...[
            CircularProgressIndicator(
              color: theme.primaryColor,
            ).animate().fadeIn(),
            const SizedBox(height: 12),
            Text(
              'Generating questions...',
              style: TextStyle(
                color: theme.textColor.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildChatMessages(GlassThemeData theme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _ChatBubble(
          message: message,
          theme: theme,
        );
      },
    );
  }
  
  Widget _buildTypingIndicator(GlassThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _typingAnimationController,
                  builder: (context, child) {
                    final value = _typingAnimationController.value;
                    final offset = (value + index * 0.3) % 1.0;
                    final y = 4 * (offset < 0.5 ? offset : 1 - offset);
                    
                    return Container(
                      margin: EdgeInsets.only(
                        left: index > 0 ? 4 : 0,
                        bottom: y,
                      ),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chat message bubble
class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  final GlassThemeData theme;
  
  const _ChatBubble({
    required this.message,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.auto_awesome,
                  color: theme.primaryColor,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.primaryColor
                    : theme.cardColor.withOpacity(0.5),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser ? null : Border.all(
                  color: theme.borderColor.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : theme.textColor,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  if (message.isError) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Error',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.person,
                  color: theme.primaryColor,
                  size: 16,
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate()
      .fadeIn(duration: 300.ms)
      .slideY(begin: 0.2);
  }
}

/// Chat message model
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  
  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}