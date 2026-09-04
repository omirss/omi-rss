import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/article.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/statistics_provider.dart';
import '../../providers/analytics_provider.dart';
import '../../features/gestures/gesture_detector_wrapper.dart';
import '../../providers/offline_provider.dart';
import '../../providers/article_actions_provider.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';
import '../components/empty_state.dart';

// Reader settings provider
final readerSettingsProvider = StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>((ref) {
  return ReaderSettingsNotifier();
});

class ReaderSettings {
  final double fontSize;
  final String fontFamily;
  final double lineHeight;
  final bool showImages;

  ReaderSettings({
    this.fontSize = 16,
    this.fontFamily = 'Inter',
    this.lineHeight = 1.6,
    this.showImages = true,
  });

  ReaderSettings copyWith({
    double? fontSize,
    String? fontFamily,
    double? lineHeight,
    bool? showImages,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      showImages: showImages ?? this.showImages,
    );
  }
}

class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  ReaderSettingsNotifier() : super(ReaderSettings());
  
  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
  }
  
  void increaseFontSize() {
    if (state.fontSize < 24) {
      state = state.copyWith(fontSize: state.fontSize + 2);
    }
  }
  
  void decreaseFontSize() {
    if (state.fontSize > 12) {
      state = state.copyWith(fontSize: state.fontSize - 2);
    }
  }
  
  void setFontFamily(String family) {
    state = state.copyWith(fontFamily: family);
  }
  
  void setLineHeight(double height) {
    state = state.copyWith(lineHeight: height);
  }
  
  void toggleImages() {
    state = state.copyWith(showImages: !state.showImages);
  }
}

class ArticleReaderScreen extends ConsumerStatefulWidget {
  final Article article;
  
  const ArticleReaderScreen({
    super.key,
    required this.article,
  });
  
  @override
  ConsumerState<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends ConsumerState<ArticleReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showControls = true;
  double _maxScrollDepth = 0;
  final _stopwatch = Stopwatch();
  bool _isOffline = false;
  late final Future<void> Function(String, double, int, bool) _trackArticleRead;
  late final ReadingSessionNotifier _readingSession;

  @override
  void initState() {
    super.initState();

    // Providers are captured up front: ref cannot be used in dispose()
    _trackArticleRead = ref.read(trackArticleReadProvider);
    _readingSession = ref.read(readingSessionProvider.notifier);

    // Start tracking reading time
    _stopwatch.start();
    
    // Mark article as read
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!widget.article.isRead) {
        ref.read(articleActionsProvider).markAsRead(widget.article.id);
      }

      // Check if article is offline (storage is unavailable on some platforms)
      try {
        final isOffline = await ref
            .read(offlineArticlesProvider.notifier)
            .isArticleOffline(widget.article.id);
        if (mounted) {
          setState(() => _isOffline = isOffline);
        }
      } catch (_) {
        // Offline availability is optional metadata
      }
      
      // Start reading session
      ref.read(readingSessionProvider.notifier).startSession(widget.article.id);
    });
    
    // Auto-hide controls on scroll and track scroll depth
    _scrollController.addListener(() {
      // Track scroll depth
      if (_scrollController.hasClients) {
        final currentScrollDepth = _scrollController.offset / 
            _scrollController.position.maxScrollExtent;
        if (currentScrollDepth > _maxScrollDepth) {
          _maxScrollDepth = currentScrollDepth.clamp(0.0, 1.0).toDouble();
        }
      }
      
      // Auto-hide controls
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_showControls) {
          setState(() => _showControls = false);
        }
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_showControls) {
          setState(() => _showControls = true);
        }
      }
    });
  }
  
  @override
  void dispose() {
    // Stop tracking time
    _stopwatch.stop();

    // Track article read analytics (providers captured in initState)
    final scrollDepthPercentage = (_maxScrollDepth * 100).clamp(0.0, 100.0).toDouble();
    final interactionTimeSeconds = _stopwatch.elapsed.inSeconds;
    final completed = _maxScrollDepth >= 0.9; // Consider 90% scroll as completed

    _trackArticleRead(
      widget.article.id,
      scrollDepthPercentage,
      interactionTimeSeconds,
      completed,
    );

    // End reading session
    final content = widget.article.fullContent ?? widget.article.content ?? widget.article.summary ?? '';
    final wordCount = content.split(' ').length;
    _readingSession.endSession(wordCount);

    _scrollController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final tokens = GlassTheme.colorsOf(context);
    final content = widget.article.fullContent ??
        widget.article.content ??
        widget.article.summary ??
        '';

    return ArticleGestureWrapper(
      onPreviousArticle: () {
        // TODO: Navigate to previous article
        context.showGlassSnackBar('Previous article');
      },
      onNextArticle: () {
        // TODO: Navigate to next article
        context.showGlassSnackBar('Next article');
      },
      onToggleStar: () async {
        await ref.read(articleActionsProvider).toggleStarred(widget.article.id);
        if (mounted) {
          context.showSuccessSnackBar(
            widget.article.isStarred ? 'Article unstarred' : 'Article starred'
          );
        }
      },
      onClose: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        body: Stack(
        children: [
          // Article content
          SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 80,
              bottom: 100,
            ),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 700),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      widget.article.title,
                      style: TextStyle(
                        color: tokens.textHigh,
                        fontSize: settings.fontSize + 8,
                        fontWeight: FontWeight.bold,
                        fontFamily: settings.fontFamily,
                        height: 1.3,
                      ),
                    ).animate().fadeIn(duration: 300.ms),

                    const SizedBox(height: GlassSpacing.lg),

                    // Metadata
                    Row(
                      children: [
                        if (widget.article.author != null) ...[
                          Icon(
                            Icons.person,
                            size: 16,
                            color: tokens.textMedium,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.article.author!,
                            style: GlassTypeScale.label
                                .copyWith(color: tokens.textMedium),
                          ),
                          const SizedBox(width: GlassSpacing.lg),
                        ],
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: tokens.textMedium,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(widget.article.publishedAt),
                          style: GlassTypeScale.label
                              .copyWith(color: tokens.textMedium),
                        ),
                        const Spacer(),
                        // Reading time
                        Icon(
                          Icons.timer,
                          size: 16,
                          color: tokens.textMedium,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.article.estimatedReadTime} min read',
                          style: GlassTypeScale.label
                              .copyWith(color: tokens.textMedium),
                        ),
                      ],
                    ).animate().fadeIn(duration: 300.ms, delay: 100.ms),

                    const SizedBox(height: GlassSpacing.xxl),

                    // Content
                    if (content.trim().isEmpty)
                      EmptyState(
                        title: 'No article content',
                        subtitle:
                            'This article has no extracted text to display.',
                        actionLabel: 'Open original',
                        onAction: _openInBrowser,
                      )
                    else
                      SelectableText(
                        _stripHtml(content),
                        style: TextStyle(
                          color: tokens.textHigh,
                          fontSize: settings.fontSize,
                          fontFamily: settings.fontFamily,
                          height: settings.lineHeight,
                        ),
                      ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
                  ],
                ),
              ),
            ),
          ),
          
          // Top controls
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showControls ? 0 : -100,
            left: 0,
            right: 0,
            child: GlassContainer(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              child: Row(
                children: [
                  GlassButton(
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.of(context).pop(),
                    variant: GlassButtonVariant.icon,
                  ),
                  const Spacer(),
                  GlassButton(
                    icon: widget.article.isStarred ? Icons.star : Icons.star_outline,
                    onPressed: () async {
                      await ref.read(articleActionsProvider).toggleStarred(widget.article.id);
                      if (mounted) {
                        context.showSuccessSnackBar(
                          widget.article.isStarred ? 'Article unstarred' : 'Article starred'
                        );
                      }
                    },
                    variant: GlassButtonVariant.icon,
                  ),
                  const SizedBox(width: 8),
                  GlassButton(
                    icon: Icons.share,
                    onPressed: () => _shareArticle(),
                    variant: GlassButtonVariant.icon,
                  ),
                  const SizedBox(width: 8),
                  GlassButton(
                    icon: Icons.open_in_browser,
                    onPressed: () => _openInBrowser(),
                    variant: GlassButtonVariant.icon,
                  ),
                  const SizedBox(width: 8),
                  GlassButton(
                    icon: _isOffline ? Icons.offline_pin : Icons.offline_pin_outlined,
                    onPressed: () => _toggleOfflineStatus(),
                    variant: GlassButtonVariant.icon,
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom controls
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showControls ? 0 : -120,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reading controls
                GlassContainer(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GlassButton(
                        icon: Icons.format_size,
                        text: 'Aa-',
                        onPressed: () => ref.read(readerSettingsProvider.notifier).decreaseFontSize(),
                        variant: GlassButtonVariant.text,
                      ),
                      GlassButton(
                        icon: Icons.format_size,
                        text: 'Aa+',
                        onPressed: () => ref.read(readerSettingsProvider.notifier).increaseFontSize(),
                        variant: GlassButtonVariant.text,
                      ),
                      GlassButton(
                        icon: Icons.settings,
                        onPressed: () => _showReaderSettings(context),
                        variant: GlassButtonVariant.icon,
                      ),
                    ],
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
  
  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown date';
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
  
  String _stripHtml(String html) {
    // Basic HTML stripping - in production, use html package
    return html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
  }
  
  void _shareArticle() async {
    try {
      await Share.share(
        '${widget.article.title}\n\n${widget.article.url}',
        subject: widget.article.title,
      );
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to share article');
      }
    }
  }
  
  void _openInBrowser() async {
    try {
      final uri = Uri.parse(widget.article.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to open article');
      }
    }
  }
  
  void _showReaderSettings(BuildContext context) {
    final tokens = GlassTheme.colorsOf(context);
    showGlassDialog(
      context: context,
      title: const Text('Reader Settings'),
      content: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Font Size'),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.remove, color: tokens.textHigh),
                        onPressed: () {
                          ref.read(readerSettingsProvider.notifier).decreaseFontSize();
                          setState(() {});
                        },
                      ),
                      Text(
                        '${ref.watch(readerSettingsProvider).fontSize.round()}',
                        style: GlassTypeScale.label.copyWith(color: tokens.textHigh),
                      ),
                      IconButton(
                        icon: Icon(Icons.add, color: tokens.textHigh),
                        onPressed: () {
                          ref.read(readerSettingsProvider.notifier).increaseFontSize();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GlassButton(
                text: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                width: double.infinity,
              ),
            ],
          );
        },
      ),
    );
  }
  
  void _toggleOfflineStatus() async {
    try {
      if (_isOffline) {
        // Remove from offline
        await ref.read(offlineArticlesProvider.notifier).deleteOfflineArticle(widget.article.id);
        if (mounted) {
          setState(() => _isOffline = false);
          context.showSuccessSnackBar('Article removed from offline storage');
        }
      } else {
        // Save for offline
        await ref.read(offlineArticlesProvider.notifier).saveArticleOffline(widget.article);
        if (mounted) {
          setState(() => _isOffline = true);
          context.showSuccessSnackBar('Article saved for offline reading');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to update offline status');
      }
    }
  }
}

// Article gesture wrapper
class ArticleGestureWrapper extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onPreviousArticle;
  final VoidCallback? onNextArticle;
  final VoidCallback? onToggleStar;
  final VoidCallback? onClose;
  
  const ArticleGestureWrapper({
    super.key,
    required this.child,
    this.onPreviousArticle,
    this.onNextArticle,
    this.onToggleStar,
    this.onClose,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetectorWrapper(
      child: child,
      onSwipeLeft: onNextArticle,
      onSwipeRight: onPreviousArticle,
      onDoubleTap: onToggleStar,
      onSwipeDown: onClose,
      enableNavigation: true,
    );
  }
}