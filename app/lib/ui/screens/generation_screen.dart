import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_text_field.dart';
import '../components/glass_card.dart';
import '../../core/services/generation_service.dart';
import '../../core/models/feed.dart';
import '../../core/models/article.dart';
import '../glass_theme.dart';

/// Feed generation screen
class GenerationScreen extends ConsumerStatefulWidget {
  const GenerationScreen({super.key});

  @override
  ConsumerState<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends ConsumerState<GenerationScreen> {
  final _urlController = TextEditingController();
  final _generationService = GenerationService();
  
  bool _isGenerating = false;
  bool _showPreview = false;
  FeedPreview? _preview;
  String? _error;
  
  // Popular examples
  final List<ExampleSite> _examples = [
    ExampleSite(
      name: 'Twitter User',
      icon: Icons.alternate_email,
      url: 'https://twitter.com/elonmusk',
      description: 'Generate feed from Twitter/X user timeline',
    ),
    ExampleSite(
      name: 'GitHub Repo',
      icon: Icons.code,
      url: 'https://github.com/flutter/flutter',
      description: 'Track releases, commits, and issues',
    ),
    ExampleSite(
      name: 'Reddit Subreddit',
      icon: Icons.forum,
      url: 'https://reddit.com/r/programming',
      description: 'Follow subreddit posts and discussions',
    ),
    ExampleSite(
      name: 'YouTube Channel',
      icon: Icons.play_circle_outline,
      url: 'https://youtube.com/@mkbhd',
      description: 'Get updates on new videos',
    ),
    ExampleSite(
      name: 'Hacker News',
      icon: Icons.trending_up,
      url: 'https://news.ycombinator.com',
      description: 'Top stories from HN',
    ),
    ExampleSite(
      name: 'Product Hunt',
      icon: Icons.rocket_launch,
      url: 'https://producthunt.com',
      description: 'Discover new products',
    ),
  ];
  
  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
  
  Future<void> _generateFeed() async {
    if (_urlController.text.isEmpty) return;
    
    setState(() {
      _isGenerating = true;
      _error = null;
      _showPreview = false;
    });
    
    try {
      final preview = await _generationService.previewFeed(_urlController.text);
      
      setState(() {
        _preview = preview;
        _showPreview = true;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isGenerating = false;
      });
    }
  }
  
  Future<void> _subscribeFeed() async {
    if (_preview == null) return;
    
    // TODO: Add feed to database
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Subscribed to ${_preview!.title}'),
        backgroundColor: GlassThemeData.darkBlue.gradientColors.first,
      ),
    );
    
    Navigator.of(context).pop();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlassThemeData.backgroundColor,
      body: Stack(
        children: [
          // Animated background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  GlassThemeData.darkBlue.gradientColors.first,
                  GlassThemeData.purple.gradientColors.last,
                ],
              ),
            ),
          ),
          
          // Content
          SafeArea(
            child: Column(
              children: [
                // Header
                GlassContainer(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Generate Feed',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // URL input
                        GlassContainer(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Enter Website URL',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Paste any website URL to generate an RSS feed',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: GlassTextField(
                                      controller: _urlController,
                                      labelText: 'Website URL',
                                      prefixIcon: Icons.link,
                                      onSubmitted: (_) => _generateFeed(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GlassButton(
                                    onPressed: _isGenerating ? null : _generateFeed,
                                    variant: GlassButtonVariant.elevated,
                                    child: _isGenerating
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Generate'),
                                  ),
                                ],
                              ),
                              
                              // Error message
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),
                        
                        // Preview
                        if (_showPreview && _preview != null) ...[
                          const SizedBox(height: 20),
                          _buildPreview().animate()
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.1, end: 0),
                        ] else ...[
                          // Examples
                          const SizedBox(height: 32),
                          const Text(
                            'Popular Examples',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._examples.asMap().entries.map((entry) {
                            final index = entry.key;
                            final example = entry.value;
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildExampleCard(example)
                                .animate()
                                .fadeIn(
                                  delay: Duration(milliseconds: 100 + (index * 50)),
                                  duration: 300.ms,
                                )
                                .slideX(begin: -0.1, end: 0),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPreview() {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(
                Icons.preview,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Feed Preview',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                '${_preview!.generationTimeMs}ms',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Feed info
          Text(
            _preview!.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (_preview!.description != null) ...[
            const SizedBox(height: 8),
            Text(
              _preview!.description!,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          
          // Articles preview
          const Text(
            'Recent Articles',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          
          // Article items
          ..._preview!.articles.map((article) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildArticlePreview(article),
          )),
          
          const SizedBox(height: 20),
          
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GlassButton(
                onPressed: () {
                  setState(() {
                    _showPreview = false;
                    _preview = null;
                  });
                },
                variant: GlassButtonVariant.text,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              GlassButton(
                onPressed: _subscribeFeed,
                variant: GlassButtonVariant.elevated,
                icon: Icons.add,
                child: const Text('Subscribe'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildArticlePreview(Article article) {
    return GlassContainer(
      padding: const EdgeInsets.all(12),
      gradient: LinearGradient(
        colors: [
          Colors.white.withOpacity(0.05),
          Colors.white.withOpacity(0.02),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (article.author != null) ...[
                Icon(
                  Icons.person_outline,
                  size: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  article.author!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (article.publishedAt != null) ...[
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDate(article.publishedAt!),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildExampleCard(ExampleSite example) {
    return GlassCard(
      onTap: () {
        _urlController.text = example.url;
        _generateFeed();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GlassContainer(
              width: 48,
              height: 48,
              gradient: LinearGradient(
                colors: [
                  GlassThemeData.purple.gradientColors.first,
                  GlassThemeData.purple.gradientColors.last,
                ],
              ),
              child: Icon(
                example.icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    example.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    example.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
}

/// Example site model
class ExampleSite {
  final String name;
  final IconData icon;
  final String url;
  final String description;
  
  ExampleSite({
    required this.name,
    required this.icon,
    required this.url,
    required this.description,
  });
}