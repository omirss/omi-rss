import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/article.dart';
import '../../core/services/ai_service.dart';
import '../../providers/ai_provider.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../components/glass_tab_bar.dart';
import '../animations/loading_animation.dart';
import 'ai_perspectives_view.dart';
import 'ai_bias_view.dart';
import 'ai_fact_check_view.dart';
import 'ai_summary_view.dart';

/// AI Dashboard screen for article analysis
class AIDashboardScreen extends ConsumerStatefulWidget {
  final Article article;
  
  const AIDashboardScreen({
    super.key,
    required this.article,
  });
  
  @override
  ConsumerState<AIDashboardScreen> createState() => _AIDashboardScreenState();
}

class _AIDashboardScreenState extends ConsumerState<AIDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  AIAnalysisResult? _analysisResult;
  bool _isAnalyzing = false;
  String? _error;
  
  final List<AIAnalysisType> _selectedAnalyses = [
    AIAnalysisType.summary,
    AIAnalysisType.perspectives,
    AIAnalysisType.bias,
    AIAnalysisType.sentiment,
    AIAnalysisType.factCheck,
  ];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _startAnalysis();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _startAnalysis() async {
    setState(() {
      _isAnalyzing = true;
      _error = null;
    });
    
    try {
      final aiService = ref.read(aiServiceProvider);
      final result = await aiService.analyzeArticle(
        widget.article,
        analyses: _selectedAnalyses,
      );
      
      setState(() {
        _analysisResult = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isAnalyzing = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('AI Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isAnalyzing ? null : _startAnalysis,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showAnalysisSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(theme),
          _buildTabBar(theme),
          Expanded(
            child: _buildContent(theme),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHeader(GlassThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.article.title,
            style: theme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.source,
                size: 14,
                color: Colors.white.withOpacity(0.6),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.article.feed?.title ?? 'Unknown Source',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_analysisResult != null) ...[
                const SizedBox(width: 16),
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: Colors.white.withOpacity(0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTimestamp(_analysisResult!.timestamp),
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildTabBar(GlassThemeData theme) {
    return GlassTabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: 'Summary', icon: Icon(Icons.summarize, size: 18)),
        Tab(text: 'Perspectives', icon: Icon(Icons.psychology, size: 18)),
        Tab(text: 'Bias', icon: Icon(Icons.balance, size: 18)),
        Tab(text: 'Fact Check', icon: Icon(Icons.fact_check, size: 18)),
        Tab(text: 'Sentiment', icon: Icon(Icons.mood, size: 18)),
      ],
    );
  }
  
  Widget _buildContent(GlassThemeData theme) {
    if (_isAnalyzing) {
      return _buildLoadingView(theme);
    }
    
    if (_error != null) {
      return _buildErrorView(theme);
    }
    
    if (_analysisResult == null) {
      return _buildEmptyView(theme);
    }
    
    return TabBarView(
      controller: _tabController,
      children: [
        AISummaryView(result: _analysisResult!),
        AIPerspectivesView(result: _analysisResult!),
        AIBiasView(result: _analysisResult!),
        AIFactCheckView(result: _analysisResult!),
        _buildSentimentView(theme),
      ],
    );
  }
  
  Widget _buildLoadingView(GlassThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const LoadingAnimation(),
          const SizedBox(height: 24),
          Text(
            'Analyzing article with AI...',
            style: theme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a moment',
            style: theme.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorView(GlassThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Analysis Failed',
              style: theme.titleLarge.copyWith(color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GlassButton(
              onPressed: _startAnalysis,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyView(GlassThemeData theme) {
    return Center(
      child: Text(
        'No analysis available',
        style: theme.bodyLarge.copyWith(
          color: Colors.white.withOpacity(0.6),
        ),
      ),
    );
  }
  
  Widget _buildSentimentView(GlassThemeData theme) {
    final sentiment = _analysisResult!.sentimentAnalysis;
    if (sentiment == null) {
      return const Center(child: Text('No sentiment analysis available'));
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSentimentOverview(sentiment, theme),
          const SizedBox(height: 24),
          _buildEmotionBreakdown(sentiment, theme),
          const SizedBox(height: 24),
          _buildKeyPhrases(sentiment, theme),
        ],
      ),
    );
  }
  
  Widget _buildSentimentOverview(SentimentAnalysis sentiment, GlassThemeData theme) {
    final color = _getSentimentColor(sentiment.score);
    final icon = _getSentimentIcon(sentiment.score);
    
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              icon,
              size: 64,
              color: color,
            ),
            const SizedBox(height: 16),
            Text(
              sentiment.label.toUpperCase(),
              style: theme.titleLarge.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Score: ',
                  style: theme.bodyLarge,
                ),
                Text(
                  sentiment.score.toStringAsFixed(2),
                  style: theme.titleMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Confidence: ${(sentiment.confidence * 100).toStringAsFixed(0)}%',
              style: theme.bodySmall.copyWith(
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (sentiment.score + 1) / 2, // Normalize -1 to 1 -> 0 to 1
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Negative',
                  style: theme.bodySmall.copyWith(
                    color: Colors.red.withOpacity(0.6),
                  ),
                ),
                Text(
                  'Neutral',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                Text(
                  'Positive',
                  style: theme.bodySmall.copyWith(
                    color: Colors.green.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmotionBreakdown(SentimentAnalysis sentiment, GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emotional Analysis',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 16),
            ...sentiment.emotions.entries.map((entry) {
              final emotion = entry.key;
              final score = entry.value;
              final icon = _getEmotionIcon(emotion);
              final color = _getEmotionColor(emotion);
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: color, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          emotion.substring(0, 1).toUpperCase() + emotion.substring(1),
                          style: theme.bodyMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${(score * 100).toStringAsFixed(0)}%',
                          style: theme.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: score,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(color.withOpacity(0.6)),
                    ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.analytics,
                    color: theme.accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Subjectivity: ',
                    style: theme.bodyMedium,
                  ),
                  Text(
                    '${(sentiment.subjectivity * 100).toStringAsFixed(0)}%',
                    style: theme.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.accentColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    sentiment.subjectivity < 0.3 ? 'Objective' :
                    sentiment.subjectivity < 0.7 ? 'Balanced' : 'Subjective',
                    style: theme.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildKeyPhrases(SentimentAnalysis sentiment, GlassThemeData theme) {
    if (sentiment.keyPhrases.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Key Emotional Phrases',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sentiment.keyPhrases.map((phrase) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.accentColor.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    phrase,
                    style: theme.bodySmall,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showAnalysisSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassCard(
        theme: GlassTheme.of(context),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analysis Settings',
                  style: GlassTheme.of(context).titleLarge,
                ),
                const SizedBox(height: 16),
                ...AIAnalysisType.values.map((type) {
                  return CheckboxListTile(
                    title: Text(_getAnalysisTypeName(type)),
                    subtitle: Text(_getAnalysisTypeDescription(type)),
                    value: _selectedAnalyses.contains(type),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedAnalyses.add(type);
                        } else {
                          _selectedAnalyses.remove(type);
                        }
                      });
                    },
                  );
                }).toList(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    GlassButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _startAnalysis();
                      },
                      child: const Text('Re-analyze'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Color _getSentimentColor(double score) {
    if (score <= -0.6) return Colors.red;
    if (score <= -0.2) return Colors.orange;
    if (score <= 0.2) return Colors.grey;
    if (score <= 0.6) return Colors.lightGreen;
    return Colors.green;
  }
  
  IconData _getSentimentIcon(double score) {
    if (score <= -0.6) return Icons.sentiment_very_dissatisfied;
    if (score <= -0.2) return Icons.sentiment_dissatisfied;
    if (score <= 0.2) return Icons.sentiment_neutral;
    if (score <= 0.6) return Icons.sentiment_satisfied;
    return Icons.sentiment_very_satisfied;
  }
  
  IconData _getEmotionIcon(String emotion) {
    switch (emotion) {
      case 'joy':
        return Icons.mood;
      case 'anger':
        return Icons.mood_bad;
      case 'fear':
        return Icons.warning;
      case 'sadness':
        return Icons.sentiment_very_dissatisfied;
      case 'surprise':
        return Icons.lightbulb;
      case 'disgust':
        return Icons.sick;
      default:
        return Icons.help_outline;
    }
  }
  
  Color _getEmotionColor(String emotion) {
    switch (emotion) {
      case 'joy':
        return Colors.yellow;
      case 'anger':
        return Colors.red;
      case 'fear':
        return Colors.purple;
      case 'sadness':
        return Colors.blue;
      case 'surprise':
        return Colors.orange;
      case 'disgust':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
  
  String _getAnalysisTypeName(AIAnalysisType type) {
    switch (type) {
      case AIAnalysisType.summary:
        return 'Summary & Key Points';
      case AIAnalysisType.perspectives:
        return 'Multiple Perspectives';
      case AIAnalysisType.bias:
        return 'Bias Detection';
      case AIAnalysisType.sentiment:
        return 'Sentiment Analysis';
      case AIAnalysisType.factCheck:
        return 'Fact Checking';
      case AIAnalysisType.entities:
        return 'Entity Extraction';
      case AIAnalysisType.complexity:
        return 'Readability Analysis';
    }
  }
  
  String _getAnalysisTypeDescription(AIAnalysisType type) {
    switch (type) {
      case AIAnalysisType.summary:
        return 'Generate concise summaries and extract key points';
      case AIAnalysisType.perspectives:
        return 'View article from multiple ideological perspectives';
      case AIAnalysisType.bias:
        return 'Detect political, emotional, and framing biases';
      case AIAnalysisType.sentiment:
        return 'Analyze emotional tone and sentiment';
      case AIAnalysisType.factCheck:
        return 'Verify claims and check facts';
      case AIAnalysisType.entities:
        return 'Extract people, places, and organizations';
      case AIAnalysisType.complexity:
        return 'Assess reading level and complexity';
    }
  }
  
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }
}