import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/article.dart';
import '../../core/services/ai_service.dart';
import '../../providers/ai_providers.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../animations/loading_animation.dart';

/// AI analysis screen for articles
class AIAnalysisScreen extends ConsumerStatefulWidget {
  final Article article;
  
  const AIAnalysisScreen({
    super.key,
    required this.article,
  });
  
  @override
  ConsumerState<AIAnalysisScreen> createState() => _AIAnalysisScreenState();
}

class _AIAnalysisScreenState extends ConsumerState<AIAnalysisScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Set<AIAnalysisType> _selectedAnalyses = {
    AIAnalysisType.summary,
    AIAnalysisType.sentiment,
    AIAnalysisType.bias,
  };
  AIAnalysisResult? _analysisResult;
  bool _isAnalyzing = false;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _runAnalysis() async {
    setState(() {
      _isAnalyzing = true;
      _error = null;
    });
    
    try {
      final aiService = ref.read(aiServiceProvider);
      final result = await aiService.analyzeArticle(
        widget.article,
        analyses: _selectedAnalyses.toList(),
      );
      
      setState(() {
        _analysisResult = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Analysis failed: $e';
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
        title: const Text('AI Analysis'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showAnalysisSettings,
            tooltip: 'Analysis Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Article info
          GlassContainer(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.article.title,
                  style: theme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.article.source ?? 'Unknown source',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          
          // Analysis controls
          if (_analysisResult == null && !_isAnalyzing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GlassButton(
                text: 'Run AI Analysis',
                onPressed: _runAnalysis,
                icon: const Icon(Icons.psychology),
                variant: GlassButtonVariant.elevated,
                width: double.infinity,
              ),
            ),
          
          // Loading state
          if (_isAnalyzing)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LoadingAnimation(),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing article...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          
          // Error state
          if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade300),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      text: 'Retry',
                      onPressed: _runAnalysis,
                      variant: GlassButtonVariant.elevated,
                    ),
                  ],
                ),
              ),
            ),
          
          // Analysis results
          if (_analysisResult != null)
            Expanded(
              child: Column(
                children: [
                  // Tab bar
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: [
                      if (_analysisResult!.summary != null)
                        const Tab(text: 'Summary', icon: Icon(Icons.summarize)),
                      if (_analysisResult!.sentimentAnalysis != null)
                        const Tab(text: 'Sentiment', icon: Icon(Icons.mood)),
                      if (_analysisResult!.biasAnalysis != null)
                        const Tab(text: 'Bias', icon: Icon(Icons.balance)),
                      if (_analysisResult!.perspectives != null)
                        const Tab(text: 'Perspectives', icon: Icon(Icons.diversity_3)),
                      if (_analysisResult!.factCheckResults != null)
                        const Tab(text: 'Fact Check', icon: Icon(Icons.fact_check)),
                    ],
                    indicatorColor: theme.accentColor,
                  ),
                  
                  // Tab content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        if (_analysisResult!.summary != null)
                          _buildSummaryTab(theme),
                        if (_analysisResult!.sentimentAnalysis != null)
                          _buildSentimentTab(theme),
                        if (_analysisResult!.biasAnalysis != null)
                          _buildBiasTab(theme),
                        if (_analysisResult!.perspectives != null)
                          _buildPerspectivesTab(theme),
                        if (_analysisResult!.factCheckResults != null)
                          _buildFactCheckTab(theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryTab(GlassThemeData theme) {
    final summary = _analysisResult!.summary!;
    final keyPoints = _analysisResult!.keyPoints ?? [];
    final tags = _analysisResult!.tags ?? [];
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary lengths
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick Summary', style: theme.titleSmall),
              const SizedBox(height: 8),
              Text(summary.short, style: theme.bodyMedium),
              const SizedBox(height: 16),
              
              ExpansionTile(
                title: const Text('Detailed Summary'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(summary.long, style: theme.bodyMedium),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn().slideY(),
        
        // Key points
        if (keyPoints.isNotEmpty) ...[
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Key Points', style: theme.titleSmall),
                const SizedBox(height: 12),
                ...keyPoints.map((point) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle, size: 8, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(child: Text(point)),
                    ],
                  ),
                )),
              ],
            ),
          ).animate(delay: 100.ms).fadeIn().slideY(),
        ],
        
        // Tags
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Tags', style: theme.titleSmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.primaryColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tag.name, style: theme.bodySmall),
                        const SizedBox(width: 4),
                        Text(
                          '${(tag.confidence * 100).toInt()}%',
                          style: theme.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ],
            ),
          ).animate(delay: 200.ms).fadeIn().slideY(),
        ],
      ],
    );
  }
  
  Widget _buildSentimentTab(GlassThemeData theme) {
    final sentiment = _analysisResult!.sentimentAnalysis!;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Overall sentiment
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                _getSentimentIcon(sentiment.label),
                size: 64,
                color: _getSentimentColor(sentiment.label),
              ),
              const SizedBox(height: 16),
              Text(
                sentiment.label.replaceAll('_', ' ').toUpperCase(),
                style: theme.titleMedium.copyWith(
                  color: _getSentimentColor(sentiment.label),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Score: ${sentiment.score.toStringAsFixed(2)}',
                style: theme.bodyMedium,
              ),
              Text(
                'Confidence: ${(sentiment.confidence * 100).toStringAsFixed(0)}%',
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ).animate().fadeIn().scale(),
        
        // Emotions breakdown
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Emotion Analysis', style: theme.titleSmall),
              const SizedBox(height: 16),
              ...sentiment.emotions.entries.map((emotion) {
                final percentage = (emotion.value * 100).toInt();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _getEmotionIcon(emotion.key),
                                size: 20,
                                color: _getEmotionColor(emotion.key),
                              ),
                              const SizedBox(width: 8),
                              Text(emotion.key.toUpperCase()),
                            ],
                          ),
                          Text('$percentage%'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: emotion.value,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getEmotionColor(emotion.key),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ).animate(delay: 100.ms).fadeIn().slideY(),
        
        // Subjectivity
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Subjectivity Analysis', style: theme.titleSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Objective'),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(
                        value: sentiment.subjectivity,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color.lerp(Colors.blue, Colors.orange, sentiment.subjectivity)!,
                        ),
                      ),
                    ),
                  ),
                  const Text('Subjective'),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${(sentiment.subjectivity * 100).toStringAsFixed(0)}% Subjective',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
        ).animate(delay: 200.ms).fadeIn().slideY(),
      ],
    );
  }
  
  Widget _buildBiasTab(GlassThemeData theme) {
    final bias = _analysisResult!.biasAnalysis!;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Overall bias score
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: bias.overallScore / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getBiasColor(bias.overallScore),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${bias.overallScore.toInt()}',
                        style: theme.headlineLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Bias Score',
                        style: theme.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _getBiasLevel(bias.overallScore),
                style: theme.titleMedium.copyWith(
                  color: _getBiasColor(bias.overallScore),
                ),
              ),
            ],
          ),
        ).animate().fadeIn().scale(),
        
        // Bias indicators
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bias Indicators', style: theme.titleSmall),
              const SizedBox(height: 16),
              ...bias.biasIndicators.entries.map((indicator) {
                final percentage = (indicator.value * 100).toInt();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            indicator.key.replaceAll('_', ' ').toUpperCase(),
                            style: theme.bodyMedium,
                          ),
                          Text(
                            '$percentage%',
                            style: TextStyle(
                              color: _getBiasColor(percentage.toDouble()),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: indicator.value,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getBiasColor(percentage.toDouble()),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ).animate(delay: 100.ms).fadeIn().slideY(),
        
        // Political bias
        if (bias.politicalBias != null) ...[
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Political Lean', style: theme.titleSmall),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Left'),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue.shade600,
                                    Colors.purple,
                                    Colors.red.shade600,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Positioned(
                              left: ((bias.politicalBias!.score + 1) / 2) * 
                                  (MediaQuery.of(context).size.width - 120),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Text('Right'),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    bias.politicalBias!.direction.toUpperCase(),
                    style: theme.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
          ).animate(delay: 200.ms).fadeIn().slideY(),
        ],
        
        // Suggestions
        if (bias.suggestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline, 
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text('Suggestions', style: theme.titleSmall),
                  ],
                ),
                const SizedBox(height: 12),
                ...bias.suggestions.map((suggestion) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_right, size: 20),
                      const SizedBox(width: 4),
                      Expanded(child: Text(suggestion)),
                    ],
                  ),
                )),
              ],
            ),
          ).animate(delay: 300.ms).fadeIn().slideY(),
        ],
      ],
    );
  }
  
  Widget _buildPerspectivesTab(GlassThemeData theme) {
    final perspectives = _analysisResult!.perspectives!;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Primary stance
        if (perspectives.primaryStance.isNotEmpty)
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Article Stance', style: theme.titleSmall),
                const SizedBox(height: 12),
                ...perspectives.primaryStance.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key.toString()),
                      Text(
                        entry.value.toString(),
                        style: TextStyle(
                          color: theme.accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ).animate().fadeIn().slideY(),
        
        // Alternative perspectives
        const SizedBox(height: 16),
        Text(
          'Alternative Perspectives',
          style: theme.titleMedium,
        ),
        const SizedBox(height: 12),
        
        ...perspectives.perspectives.entries.map((perspective) {
          final delay = perspectives.perspectives.keys.toList()
              .indexOf(perspective.key) * 100;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              onTap: () => _showPerspectiveDetails(perspective.value),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getPerspectiveIcon(perspective.key),
                        color: _getPerspectiveColor(perspective.key),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          perspective.key.replaceAll('_', ' ').toUpperCase(),
                          style: theme.titleSmall,
                        ),
                      ),
                      Text(
                        '${(perspective.value.confidence * 100).toInt()}%',
                        style: theme.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    perspective.value.summary,
                    style: theme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ).animate(delay: delay.ms).fadeIn().slideX(),
          );
        }).toList(),
      ],
    );
  }
  
  Widget _buildFactCheckTab(GlassThemeData theme) {
    final factChecks = _analysisResult!.factCheckResults!;
    
    if (factChecks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fact_check,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No factual claims detected',
              style: theme.bodyLarge.copyWith(
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: factChecks.map((factCheck) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Claim
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.format_quote,
                    color: Colors.white.withOpacity(0.6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      factCheck.claim,
                      style: theme.bodyMedium.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Verdict
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getVerdictColor(factCheck.verdict).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _getVerdictColor(factCheck.verdict).withOpacity(0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getVerdictIcon(factCheck.verdict),
                      size: 16,
                      color: _getVerdictColor(factCheck.verdict),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      factCheck.verdict.toUpperCase(),
                      style: TextStyle(
                        color: _getVerdictColor(factCheck.verdict),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Sources
              if (factCheck.sources.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Sources:',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                ...factCheck.sources.map((source) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          source.name,
                          style: theme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      )).toList().animate(interval: 100.ms).fadeIn().slideY(),
    );
  }
  
  void _showAnalysisSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Analysis Options',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...AIAnalysisType.values.map((type) => CheckboxListTile(
              value: _selectedAnalyses.contains(type),
              onChanged: (value) {
                setState(() {
                  if (value ?? false) {
                    _selectedAnalyses.add(type);
                  } else {
                    _selectedAnalyses.remove(type);
                  }
                });
                Navigator.pop(context);
              },
              title: Text(_getAnalysisTypeName(type)),
              subtitle: Text(_getAnalysisTypeDescription(type)),
              secondary: Icon(_getAnalysisTypeIcon(type)),
            )),
          ],
        ),
      ),
    );
  }
  
  void _showPerspectiveDetails(PerspectiveSummary perspective) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              perspective.type.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(perspective.summary),
            if (perspective.keyPoints.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Key Points:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...perspective.keyPoints.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, size: 8),
                    const SizedBox(width: 8),
                    Expanded(child: Text(point)),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
  
  // Helper methods
  IconData _getSentimentIcon(String label) {
    switch (label) {
      case 'very_positive':
        return Icons.sentiment_very_satisfied;
      case 'positive':
        return Icons.sentiment_satisfied;
      case 'neutral':
        return Icons.sentiment_neutral;
      case 'negative':
        return Icons.sentiment_dissatisfied;
      case 'very_negative':
        return Icons.sentiment_very_dissatisfied;
      default:
        return Icons.sentiment_neutral;
    }
  }
  
  Color _getSentimentColor(String label) {
    switch (label) {
      case 'very_positive':
        return Colors.green.shade600;
      case 'positive':
        return Colors.green.shade400;
      case 'neutral':
        return Colors.grey;
      case 'negative':
        return Colors.orange.shade400;
      case 'very_negative':
        return Colors.red.shade600;
      default:
        return Colors.grey;
    }
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
        return Icons.priority_high;
      case 'disgust':
        return Icons.sick;
      default:
        return Icons.help_outline;
    }
  }
  
  Color _getEmotionColor(String emotion) {
    switch (emotion) {
      case 'joy':
        return Colors.amber;
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
  
  Color _getBiasColor(double score) {
    if (score < 30) return Colors.green;
    if (score < 60) return Colors.orange;
    return Colors.red;
  }
  
  String _getBiasLevel(double score) {
    if (score < 20) return 'Minimal Bias';
    if (score < 40) return 'Low Bias';
    if (score < 60) return 'Moderate Bias';
    if (score < 80) return 'High Bias';
    return 'Extreme Bias';
  }
  
  IconData _getPerspectiveIcon(String perspective) {
    switch (perspective) {
      case 'conservative':
      case 'liberal':
      case 'libertarian':
      case 'socialist':
      case 'centrist':
        return Icons.how_to_vote;
      case 'international':
        return Icons.public;
      case 'historical':
        return Icons.history;
      case 'economic':
        return Icons.attach_money;
      case 'environmental':
        return Icons.eco;
      case 'scientific':
        return Icons.science;
      default:
        return Icons.visibility;
    }
  }
  
  Color _getPerspectiveColor(String perspective) {
    switch (perspective) {
      case 'conservative':
        return Colors.red.shade400;
      case 'liberal':
        return Colors.blue.shade400;
      case 'libertarian':
        return Colors.amber.shade400;
      case 'socialist':
        return Colors.pink.shade400;
      case 'centrist':
        return Colors.purple.shade400;
      case 'international':
        return Colors.teal.shade400;
      case 'historical':
        return Colors.brown.shade400;
      case 'economic':
        return Colors.green.shade400;
      case 'environmental':
        return Colors.lightGreen.shade400;
      case 'scientific':
        return Colors.indigo.shade400;
      default:
        return Colors.grey.shade400;
    }
  }
  
  Color _getVerdictColor(String verdict) {
    switch (verdict) {
      case 'true':
        return Colors.green;
      case 'mostly_true':
        return Colors.lightGreen;
      case 'mixed':
        return Colors.orange;
      case 'mostly_false':
        return Colors.deepOrange;
      case 'false':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getVerdictIcon(String verdict) {
    switch (verdict) {
      case 'true':
        return Icons.check_circle;
      case 'mostly_true':
        return Icons.check_circle_outline;
      case 'mixed':
        return Icons.help_outline;
      case 'mostly_false':
        return Icons.cancel_outlined;
      case 'false':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }
  
  String _getAnalysisTypeName(AIAnalysisType type) {
    switch (type) {
      case AIAnalysisType.summary:
        return 'Summary';
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
        return 'Complexity Analysis';
    }
  }
  
  String _getAnalysisTypeDescription(AIAnalysisType type) {
    switch (type) {
      case AIAnalysisType.summary:
        return 'Generate concise summaries';
      case AIAnalysisType.perspectives:
        return 'View from different viewpoints';
      case AIAnalysisType.bias:
        return 'Detect various types of bias';
      case AIAnalysisType.sentiment:
        return 'Analyze emotional tone';
      case AIAnalysisType.factCheck:
        return 'Verify factual claims';
      case AIAnalysisType.entities:
        return 'Extract people, places, etc.';
      case AIAnalysisType.complexity:
        return 'Assess readability and complexity';
    }
  }
  
  IconData _getAnalysisTypeIcon(AIAnalysisType type) {
    switch (type) {
      case AIAnalysisType.summary:
        return Icons.summarize;
      case AIAnalysisType.perspectives:
        return Icons.diversity_3;
      case AIAnalysisType.bias:
        return Icons.balance;
      case AIAnalysisType.sentiment:
        return Icons.mood;
      case AIAnalysisType.factCheck:
        return Icons.fact_check;
      case AIAnalysisType.entities:
        return Icons.label_outline;
      case AIAnalysisType.complexity:
        return Icons.analytics;
    }
  }
}