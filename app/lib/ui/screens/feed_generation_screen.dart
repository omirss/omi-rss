import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/generation_service.dart';
import '../../core/models/article.dart';
import '../../providers/feed_provider.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../components/glass_text_field.dart';
import '../components/glass_dialog.dart';
import '../components/glass_snack_bar.dart';
import '../animations/loading_animation.dart';

/// Feed generation screen (RSSHub-style)
class FeedGenerationScreen extends ConsumerStatefulWidget {
  const FeedGenerationScreen({super.key});

  @override
  ConsumerState<FeedGenerationScreen> createState() => _FeedGenerationScreenState();
}

class _FeedGenerationScreenState extends ConsumerState<FeedGenerationScreen>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _generationService = GenerationService();
  
  GenerationState _state = GenerationState.idle;
  FeedPreview? _preview;
  GenerationProgress? _progress;
  String? _error;
  FeedFormat _selectedFormat = FeedFormat.rss;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    ));
    
    _slideAnimation = Tween<double>(
      begin: 50,
      end: 0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _urlController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Generate Feed'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 24),
            _buildUrlInput(theme),
            const SizedBox(height: 16),
            _buildFormatSelector(theme),
            const SizedBox(height: 24),
            _buildGenerateButton(theme),
            const SizedBox(height: 24),
            if (_state == GenerationState.generating)
              _buildProgress(theme),
            if (_state == GenerationState.error)
              _buildError(theme),
            if (_state == GenerationState.success && _preview != null)
              _buildPreview(theme),
            const SizedBox(height: 24),
            _buildSupportedSites(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(GlassThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create RSS from Any Website',
          style: theme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Generate RSS feeds from websites that don\'t provide them. '
          'Paste a URL and we\'ll extract the content automatically.',
          style: theme.bodyMedium.copyWith(
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildUrlInput(GlassThemeData theme) {
    return GlassTextField(
      controller: _urlController,
      hintText: 'https://example.com/blog',
      labelText: 'Website URL',
      prefixIcon: Icons.link,
      onChanged: (value) {
        // Auto-detect paste and trigger generation
        if (value.contains('http') && value.length > 20) {
          _checkClipboard();
        }
      },
      suffixIcon: IconButton(
        icon: const Icon(Icons.paste),
        onPressed: _pasteFromClipboard,
        tooltip: 'Paste from clipboard',
      ),
    );
  }

  Widget _buildFormatSelector(GlassThemeData theme) {
    return Row(
      children: [
        Text(
          'Format:',
          style: theme.bodyLarge,
        ),
        const SizedBox(width: 16),
        ...FeedFormat.values.map((format) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ChoiceChip(
            label: Text(format.name.toUpperCase()),
            selected: _selectedFormat == format,
            onSelected: (selected) {
              if (selected) {
                setState(() => _selectedFormat = format);
              }
            },
            selectedColor: theme.accentColor.withOpacity(0.3),
            labelStyle: TextStyle(
              color: _selectedFormat == format
                  ? theme.accentColor
                  : Colors.white.withOpacity(0.7),
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildGenerateButton(GlassThemeData theme) {
    return Center(
      child: GlassButton(
        onPressed: _state == GenerationState.generating ? null : _generateFeed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_state == GenerationState.generating)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              const Icon(Icons.auto_awesome),
            const SizedBox(width: 8),
            Text(_state == GenerationState.generating
                ? 'Generating...'
                : 'Generate Feed'),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(GlassThemeData theme) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: GlassCard(
              theme: theme,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const LoadingAnimation(),
                    const SizedBox(height: 16),
                    if (_progress != null) ...[
                      Text(
                        _progress!.message,
                        style: theme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      if (_progress!.progress > 0) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _progress!.progress,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.accentColor,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildError(GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      borderColor: Colors.red.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Generation Failed',
              style: theme.titleMedium.copyWith(color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error occurred',
              style: theme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GlassButton(
              onPressed: _generateFeed,
              variant: GlassButtonVariant.text,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(GlassThemeData theme) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Preview',
                      style: theme.titleMedium,
                    ),
                    Text(
                      'Generated in ${_preview!.generationTimeMs}ms',
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GlassCard(
                  theme: theme,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _preview!.title,
                          style: theme.titleLarge,
                        ),
                        if (_preview!.description != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _preview!.description!,
                            style: theme.bodyMedium.copyWith(
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'First ${_preview!.articles.length} Articles:',
                          style: theme.bodyLarge.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._preview!.articles.map((article) =>
                            _buildPreviewArticle(article, theme)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GlassButton(
                      onPressed: _subscribeFeed,
                      child: const Row(
                        children: [
                          Icon(Icons.add),
                          SizedBox(width: 8),
                          Text('Subscribe to Feed'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    GlassButton(
                      onPressed: _copyFeedUrl,
                      variant: GlassButtonVariant.outlined,
                      child: const Row(
                        children: [
                          Icon(Icons.copy),
                          SizedBox(width: 8),
                          Text('Copy Feed URL'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewArticle(Article article, GlassThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.title,
            style: theme.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (article.excerpt != null) ...[
            const SizedBox(height: 4),
            Text(
              article.excerpt!,
              style: theme.bodySmall.copyWith(
                color: Colors.white.withOpacity(0.6),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.5),
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
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupportedSites(GlassThemeData theme) {
    final rules = _generationService.getAvailableRules();
    
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified,
                  color: theme.accentColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Optimized for ${rules.length}+ Sites',
                  style: theme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'We have custom rules for popular websites to ensure '
              'the best extraction quality:',
              style: theme.bodyMedium.copyWith(
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: rules.take(20).map((rule) => Chip(
                label: Text(
                  rule.name,
                  style: theme.bodySmall,
                ),
                backgroundColor: theme.accentColor.withOpacity(0.2),
                side: BorderSide.none,
              )).toList(),
            ),
            if (rules.length > 20) ...[
              const SizedBox(height: 8),
              Text(
                '...and ${rules.length - 20} more',
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generateFeed() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      GlassSnackBar.showError(
        context: context,
        message: 'Please enter a URL',
      );
      return;
    }

    setState(() {
      _state = GenerationState.generating;
      _error = null;
      _preview = null;
      _progress = null;
    });

    _animationController.forward();

    try {
      final preview = await _generationService.generateFeed(
        url,
        format: _selectedFormat,
        onProgress: (progress) {
          setState(() => _progress = progress);
        },
      ).then((result) => _generationService.previewFeed(url));

      if (mounted) {
        setState(() {
          _state = GenerationState.success;
          _preview = preview;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = GenerationState.error;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      _urlController.text = data.text!;
      _generateFeed();
    }
  }

  Future<void> _checkClipboard() async {
    // Debounce auto-generation
    await Future.delayed(const Duration(milliseconds: 500));
    if (_urlController.text.contains('http') && _state == GenerationState.idle) {
      _generateFeed();
    }
  }

  Future<void> _subscribeFeed() async {
    if (_preview == null) return;

    try {
      // Subscribe to the generated feed
      await ref.read(feedServiceProvider).subscribeFeed(_preview!.feedUrl);
      
      if (mounted) {
        Navigator.pop(context);
        GlassSnackBar.showSuccess(
          context: context,
          message: 'Feed subscribed successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        GlassSnackBar.showError(
          context: context,
          message: 'Failed to subscribe: $e',
        );
      }
    }
  }

  Future<void> _copyFeedUrl() async {
    if (_preview == null) return;

    await Clipboard.setData(ClipboardData(text: _preview!.feedUrl));
    if (mounted) {
      GlassSnackBar.showSuccess(
        context: context,
        message: 'Feed URL copied to clipboard',
      );
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

/// Generation state
enum GenerationState {
  idle,
  generating,
  success,
  error,
}