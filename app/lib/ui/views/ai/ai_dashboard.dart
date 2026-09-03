import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/models/article.dart';
import '../../components/glass_container.dart';
import '../../glass_theme.dart';
import 'perspectives_view.dart';
import 'bias_analysis_view.dart';
import 'fact_check_view.dart';
import 'ai_interaction_view.dart';

/// Provider for AI analysis
final aiAnalysisProvider = FutureProvider.family<AIAnalysisResult, String>(
  (ref, articleId) async {
    final aiService = ref.read(aiServiceProvider);
    final article = Article(
      id: articleId,
      feedId: '',
      title: '',
      url: '',
      publishedAt: DateTime.now(),
    ); // TODO: Get article from database
    
    return aiService.analyzeArticle(article);
  },
);

/// AI dashboard view
class AIDashboard extends ConsumerStatefulWidget {
  final Article article;
  
  const AIDashboard({
    super.key,
    required this.article,
  });
  
  @override
  ConsumerState<AIDashboard> createState() => _AIDashboardState();
}

class _AIDashboardState extends ConsumerState<AIDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AIAnalysisResult? _analysisResult;
  bool _isAnalyzing = false;
  String? _selectedView;
  
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
  
  Future<void> _analyzeArticle() async {
    setState(() => _isAnalyzing = true);
    
    try {
      final aiService = ref.read(aiServiceProvider);
      final result = await aiService.analyzeArticle(widget.article);
      
      if (mounted) {
        setState(() {
          _analysisResult = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Analysis failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: theme.primaryColor,
                      size: 32,
                    ).animate()
                      .scale(duration: 600.ms, curve: Curves.elasticOut)
                      .shimmer(duration: 2.seconds, delay: 1.seconds),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Analysis',
                            style: TextStyle(
                              color: theme.textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Advanced intelligence for deeper understanding',
                            style: TextStyle(
                              color: theme.textColor.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isAnalyzing && _analysisResult == null)
                      ElevatedButton.icon(
                        onPressed: _analyzeArticle,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Analyze'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ).animate()
                        .fadeIn(duration: 600.ms)
                        .scale(delay: 300.ms),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.article.title,
                  style: TextStyle(
                    color: theme.textColor.withOpacity(0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: _buildContent(theme),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContent(GlassThemeData theme) {
    if (_isAnalyzing) {
      return _buildAnalyzingState(theme);
    }
    
    if (_analysisResult == null) {
      return _buildInitialState(theme);
    }
    
    if (_selectedView != null) {
      return _buildSelectedView(theme);
    }
    
    return _buildAnalysisResults(theme);
  }
  
  Widget _buildInitialState(GlassThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insights,
            color: theme.textColor.withOpacity(0.3),
            size: 80,
          ).animate()
            .fadeIn(duration: 600.ms)
            .scale(delay: 300.ms),
          const SizedBox(height: 24),
          Text(
            'Ready to analyze this article',
            style: TextStyle(
              color: theme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 8),
          Text(
            'Click "Analyze" to start AI-powered analysis',
            style: TextStyle(
              color: theme.textColor.withOpacity(0.7),
              fontSize: 14,
            ),
          ).animate().fadeIn(delay: 500.ms),
          const SizedBox(height: 32),
          _buildFeatureGrid(theme),
        ],
      ),
    );
  }
  
  Widget _buildAnalyzingState(GlassThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 3,
                  color: theme.primaryColor,
                ).animate()
                  .fadeIn()
                  .scale(duration: 600.ms),
                Icon(
                  Icons.auto_awesome,
                  color: theme.primaryColor,
                  size: 40,
                ).animate()
                  .fadeIn(delay: 300.ms)
                  .scale(duration: 600.ms, curve: Curves.elasticOut)
                  .then()
                  .shimmer(duration: 1.seconds, delay: 0.ms),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Analyzing article...',
            style: TextStyle(
              color: theme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _AnalysisProgressIndicator(theme: theme),
        ],
      ),
    );
  }
  
  Widget _buildAnalysisResults(GlassThemeData theme) {
    final result = _analysisResult!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary section
          if (result.summary != null) ...[
            _SummarySection(
              summary: result.summary!,
              keyPoints: result.keyPoints ?? [],
              tags: result.tags ?? [],
              theme: theme,
              onExpand: () => setState(() => _selectedView = 'summary'),
            ).animate().fadeIn(duration: 600.ms),
            const SizedBox(height: 20),
          ],
          
          // Analysis cards
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              if (result.perspectives != null)
                _AnalysisCard(
                  icon: Icons.psychology,
                  title: 'Perspectives',
                  subtitle: '${result.perspectives!.perspectives.length} viewpoints',
                  color: Colors.purple,
                  theme: theme,
                  onTap: () => setState(() => _selectedView = 'perspectives'),
                ).animate()
                  .fadeIn(delay: 200.ms)
                  .scale(delay: 200.ms),
              
              if (result.biasAnalysis != null)
                _AnalysisCard(
                  icon: Icons.analytics,
                  title: 'Bias Analysis',
                  subtitle: 'Score: ${result.biasAnalysis!.overallScore.toInt()}',
                  color: Colors.orange,
                  theme: theme,
                  onTap: () => setState(() => _selectedView = 'bias'),
                ).animate()
                  .fadeIn(delay: 300.ms)
                  .scale(delay: 300.ms),
              
              if (result.factCheckResults != null)
                _AnalysisCard(
                  icon: Icons.fact_check,
                  title: 'Fact Check',
                  subtitle: '${result.factCheckResults!.length} claims',
                  color: Colors.green,
                  theme: theme,
                  onTap: () => setState(() => _selectedView = 'factcheck'),
                ).animate()
                  .fadeIn(delay: 400.ms)
                  .scale(delay: 400.ms),
              
              _AnalysisCard(
                icon: Icons.chat,
                title: 'Ask AI',
                subtitle: 'Interactive Q&A',
                color: Colors.blue,
                theme: theme,
                onTap: () => setState(() => _selectedView = 'chat'),
              ).animate()
                .fadeIn(delay: 500.ms)
                .scale(delay: 500.ms),
              
              if (result.sentimentAnalysis != null)
                _AnalysisCard(
                  icon: Icons.sentiment_satisfied,
                  title: 'Sentiment',
                  subtitle: result.sentimentAnalysis!.label.replaceAll('_', ' '),
                  color: Colors.teal,
                  theme: theme,
                  onTap: () => setState(() => _selectedView = 'sentiment'),
                ).animate()
                  .fadeIn(delay: 600.ms)
                  .scale(delay: 600.ms),
              
              if (result.complexity != null)
                _AnalysisCard(
                  icon: Icons.school,
                  title: 'Complexity',
                  subtitle: 'Grade ${result.complexity!.gradeLevel.toInt()}',
                  color: Colors.indigo,
                  theme: theme,
                  onTap: () => setState(() => _selectedView = 'complexity'),
                ).animate()
                  .fadeIn(delay: 700.ms)
                  .scale(delay: 700.ms),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSelectedView(GlassThemeData theme) {
    final result = _analysisResult!;
    final aiService = ref.read(aiServiceProvider);
    
    Widget? view;
    
    switch (_selectedView) {
      case 'perspectives':
        if (result.perspectives != null) {
          view = PerspectivesView(
            perspectives: result.perspectives!,
            onClose: () => setState(() => _selectedView = null),
          );
        }
        break;
        
      case 'bias':
        if (result.biasAnalysis != null) {
          view = BiasAnalysisView(
            biasAnalysis: result.biasAnalysis!,
            onClose: () => setState(() => _selectedView = null),
          );
        }
        break;
        
      case 'factcheck':
        if (result.factCheckResults != null) {
          view = FactCheckView(
            factCheckResults: result.factCheckResults!,
            onClose: () => setState(() => _selectedView = null),
          );
        }
        break;
        
      case 'chat':
        view = AIInteractionView(
          article: widget.article,
          aiService: aiService,
          onClose: () => setState(() => _selectedView = null),
        );
        break;
        
      case 'summary':
      case 'sentiment':
      case 'complexity':
        // TODO: Implement these views
        view = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction,
                color: theme.textColor.withOpacity(0.3),
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'Coming soon',
                style: TextStyle(
                  color: theme.textColor.withOpacity(0.5),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _selectedView = null),
                child: const Text('Go back'),
              ),
            ],
          ),
        );
        break;
    }
    
    return view ?? const SizedBox.shrink();
  }
  
  Widget _buildFeatureGrid(GlassThemeData theme) {
    final features = [
      ('Multi-Perspective Analysis', Icons.psychology, Colors.purple),
      ('Bias Detection', Icons.analytics, Colors.orange),
      ('Fact Checking', Icons.fact_check, Colors.green),
      ('Interactive Q&A', Icons.chat, Colors.blue),
    ];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: features.asMap().entries.map((entry) {
          final index = entry.key;
          final feature = entry.value;
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: feature.$3.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: feature.$3.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  feature.$2,
                  color: feature.$3,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  feature.$1,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ).animate()
            .fadeIn(delay: (600 + index * 100).ms)
            .scale(delay: (600 + index * 100).ms);
        }).toList(),
      ),
    );
  }
}

/// Summary section widget
class _SummarySection extends StatelessWidget {
  final AISummary summary;
  final List<String> keyPoints;
  final List<AITag> tags;
  final GlassThemeData theme;
  final VoidCallback onExpand;
  
  const _SummarySection({
    required this.summary,
    required this.keyPoints,
    required this.tags,
    required this.theme,
    required this.onExpand,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.borderColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.summarize,
                color: theme.primaryColor,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'AI Summary',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.open_in_full),
                onPressed: onExpand,
                color: theme.textColor.withOpacity(0.5),
                iconSize: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary.short,
            style: TextStyle(
              color: theme.textColor.withOpacity(0.9),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (keyPoints.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Key Points',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...keyPoints.take(3).map((point) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.arrow_right,
                    color: theme.primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      point,
                      style: TextStyle(
                        color: theme.textColor.withOpacity(0.8),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags.take(6).map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.primaryColor.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  tag.name,
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Analysis card widget
class _AnalysisCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final GlassThemeData theme;
  final VoidCallback onTap;
  
  const _AnalysisCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.theme,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.borderColor.withOpacity(0.3),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: theme.textColor.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Analysis progress indicator
class _AnalysisProgressIndicator extends StatefulWidget {
  final GlassThemeData theme;
  
  const _AnalysisProgressIndicator({
    required this.theme,
  });
  
  @override
  State<_AnalysisProgressIndicator> createState() => _AnalysisProgressIndicatorState();
}

class _AnalysisProgressIndicatorState extends State<_AnalysisProgressIndicator> {
  final List<String> _steps = [
    'Extracting content...',
    'Analyzing perspectives...',
    'Detecting bias...',
    'Checking facts...',
    'Generating insights...',
  ];
  
  int _currentStep = 0;
  
  @override
  void initState() {
    super.initState();
    _animateSteps();
  }
  
  void _animateSteps() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _currentStep = (_currentStep + 1) % _steps.length;
        });
        _animateSteps();
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Text(
        _steps[_currentStep],
        key: ValueKey(_currentStep),
        style: TextStyle(
          color: widget.theme.textColor.withOpacity(0.7),
          fontSize: 14,
        ),
      ),
    );
  }
}