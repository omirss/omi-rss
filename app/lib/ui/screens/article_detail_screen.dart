import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/article.dart';
import '../../core/services/extraction_service.dart';
import '../../core/services/paywall_service.dart';
import '../../providers/article_provider.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_dialog.dart';
import '../components/secret_menu.dart';
import '../animations/loading_animation.dart';

/// Article detail screen with reader mode and paywall bypass
class ArticleDetailScreen extends ConsumerStatefulWidget {
  final Article article;
  
  const ArticleDetailScreen({
    super.key,
    required this.article,
  });
  
  @override
  ConsumerState<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends ConsumerState<ArticleDetailScreen>
    with TickerProviderStateMixin {
  final _extractionService = ExtractionService();
  final _paywallService = PaywallService();
  
  ViewMode _viewMode = ViewMode.webView;
  ExtractedContent? _extractedContent;
  bool _isExtracting = false;
  bool _isBookmarked = false;
  
  late AnimationController _fabAnimationController;
  late AnimationController _contentAnimationController;
  late Animation<double> _fabScaleAnimation;
  late Animation<double> _contentFadeAnimation;
  
  WebViewController? _webViewController;
  
  @override
  void initState() {
    super.initState();
    
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _contentAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fabScaleAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeOut,
    ));
    
    _contentFadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _contentAnimationController,
      curve: Curves.easeIn,
    ));
    
    _fabAnimationController.forward();
    _contentAnimationController.forward();
    
    // Initialize WebView
    _initWebView();
    
    // Check bookmark status
    _checkBookmarkStatus();
    
    // Mark as read
    ref.read(articleServiceProvider).markAsRead(widget.article.id);
  }
  
  @override
  void dispose() {
    _fabAnimationController.dispose();
    _contentAnimationController.dispose();
    super.dispose();
  }
  
  void _initWebView() {
    if (Platform.isAndroid || Platform.isIOS) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              // Update loading progress
            },
            onPageStarted: (String url) {
              // Page started loading
            },
            onPageFinished: (String url) {
              // Page finished loading
            },
            onWebResourceError: (WebResourceError error) {
              // Handle error
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.article.url));
    }
  }
  
  void _checkBookmarkStatus() {
    final bookmarked = ref.read(articleServiceProvider).isBookmarked(widget.article.id);
    setState(() {
      _isBookmarked = bookmarked;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main content
          AnimatedBuilder(
            animation: _contentFadeAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _contentFadeAnimation.value,
                child: _buildContent(theme),
              );
            },
          ),
          
          // Top bar
          _buildTopBar(theme),
          
          // FAB
          Positioned(
            right: 16,
            bottom: 16,
            child: _buildFAB(theme),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContent(GlassThemeData theme) {
    switch (_viewMode) {
      case ViewMode.webView:
        return _buildWebView();
      case ViewMode.reader:
        return _buildReaderView(theme);
      case ViewMode.fullText:
        return _buildFullTextView(theme);
    }
  }
  
  Widget _buildWebView() {
    if (_webViewController == null) {
      return const Center(
        child: LoadingAnimation(),
      );
    }
    
    return WebViewWidget(controller: _webViewController!);
  }
  
  Widget _buildReaderView(GlassThemeData theme) {
    if (_isExtracting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const LoadingAnimation(),
            const SizedBox(height: 16),
            Text(
              'Extracting article content...',
              style: theme.bodyLarge,
            ),
          ],
        ),
      );
    }
    
    if (_extractedContent == null || !_extractedContent!.success) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to extract article',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _extractedContent?.error ?? 'Unknown error',
              style: theme.bodyMedium.copyWith(
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            GlassButton(
              onPressed: _extractContent,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        top: 100,
        left: 16,
        right: 16,
        bottom: 100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            _extractedContent!.title ?? widget.article.title,
            style: theme.headlineMedium,
          ),
          const SizedBox(height: 16),
          
          // Metadata
          _buildMetadata(theme),
          const SizedBox(height: 24),
          
          // Main image
          if (_extractedContent!.mainImage != null)
            _buildMainImage(_extractedContent!.mainImage!),
          const SizedBox(height: 24),
          
          // Content
          _buildHtmlContent(_extractedContent!.content, theme),
          
          // Reading stats
          if (_extractedContent!.wordCount != null) ...[
            const SizedBox(height: 32),
            _buildReadingStats(theme),
          ],
        ],
      ),
    );
  }
  
  Widget _buildFullTextView(GlassThemeData theme) {
    // Similar to reader view but uses paywall bypass
    return _buildReaderView(theme);
  }
  
  Widget _buildTopBar(GlassThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black,
            Colors.black.withOpacity(0),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              
              const Spacer(),
              
              // Secret menu trigger (triple tap on title area)
              SecretMenu(
                activationCode: '2024', // Optional access code
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    widget.article.feed?.title ?? 'Article',
                    style: theme.bodyMedium,
                  ),
                ),
              ),
              
              const Spacer(),
              
              // View mode selector
              IconButton(
                icon: Icon(_getViewModeIcon()),
                onPressed: _showViewModeSelector,
                tooltip: 'View mode',
              ),
              
              // More options
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: _showMoreOptions,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFAB(GlassThemeData theme) {
    return AnimatedBuilder(
      animation: _fabScaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _fabScaleAnimation.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bookmark FAB
              FloatingActionButton(
                mini: true,
                backgroundColor: theme.accentColor.withOpacity(0.2),
                onPressed: _toggleBookmark,
                child: Icon(
                  _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: theme.accentColor,
                ),
              ),
              const SizedBox(height: 8),
              
              // Share FAB
              FloatingActionButton(
                backgroundColor: theme.primaryColor.withOpacity(0.2),
                onPressed: _shareArticle,
                child: Icon(
                  Icons.share,
                  color: theme.primaryColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildMetadata(GlassThemeData theme) {
    return Row(
      children: [
        if (_extractedContent!.author != null) ...[
          Icon(
            Icons.person_outline,
            size: 16,
            color: Colors.white.withOpacity(0.6),
          ),
          const SizedBox(width: 4),
          Text(
            _extractedContent!.author!,
            style: theme.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(width: 16),
        ],
        if (_extractedContent!.publishedDate != null) ...[
          Icon(
            Icons.calendar_today,
            size: 16,
            color: Colors.white.withOpacity(0.6),
          ),
          const SizedBox(width: 4),
          Text(
            _formatDate(_extractedContent!.publishedDate!),
            style: theme.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildMainImage(String imageUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 200,
            color: Colors.white.withOpacity(0.1),
            child: const Center(
              child: Icon(
                Icons.image_not_supported,
                size: 48,
                color: Colors.white30,
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildHtmlContent(String html, GlassThemeData theme) {
    // In a real implementation, use flutter_html or flutter_widget_from_html
    // For now, show plain text
    final text = html.replaceAll(RegExp(r'<[^>]*>'), '');
    
    return Text(
      text,
      style: theme.bodyLarge.copyWith(
        height: 1.6,
      ),
    );
  }
  
  Widget _buildReadingStats(GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStat(
              icon: Icons.text_fields,
              label: 'Words',
              value: _extractedContent!.wordCount.toString(),
              theme: theme,
            ),
            _buildStat(
              icon: Icons.timer,
              label: 'Reading time',
              value: '${_extractedContent!.readingTime} min',
              theme: theme,
            ),
            if (_extractedContent!.pages != null)
              _buildStat(
                icon: Icons.pages,
                label: 'Pages',
                value: _extractedContent!.pages!.length.toString(),
                theme: theme,
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
    required GlassThemeData theme,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.accentColor,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.titleMedium,
        ),
        Text(
          label,
          style: theme.bodySmall.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
  
  void _showViewModeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassCard(
        theme: GlassTheme.of(context),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.web),
                title: const Text('Web View'),
                subtitle: const Text('Original website'),
                trailing: _viewMode == ViewMode.webView
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() => _viewMode = ViewMode.webView);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chrome_reader_mode),
                title: const Text('Reader Mode'),
                subtitle: const Text('Clean, distraction-free reading'),
                trailing: _viewMode == ViewMode.reader
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() => _viewMode = ViewMode.reader);
                  Navigator.pop(context);
                  if (_extractedContent == null) {
                    _extractContent();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: const Text('Full Text'),
                subtitle: const Text('Bypass restrictions'),
                trailing: _viewMode == ViewMode.fullText
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() => _viewMode = ViewMode.fullText);
                  Navigator.pop(context);
                  _extractFullText();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassCard(
        theme: GlassTheme.of(context),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: const Text('Open in Browser'),
                onTap: () {
                  Navigator.pop(context);
                  _openInBrowser();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Link'),
                onTap: () {
                  Navigator.pop(context);
                  _copyLink();
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_increase),
                title: const Text('Adjust Font Size'),
                onTap: () {
                  Navigator.pop(context);
                  _showFontSizeDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('Translate'),
                onTap: () {
                  Navigator.pop(context);
                  _translateArticle();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Save Offline'),
                onTap: () {
                  Navigator.pop(context);
                  _saveOffline();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _extractContent() async {
    setState(() => _isExtracting = true);
    
    try {
      final content = await _extractionService.extractContent(widget.article.url);
      setState(() {
        _extractedContent = content;
        _isExtracting = false;
      });
    } catch (e) {
      setState(() {
        _extractedContent = ExtractedContent(
          content: '',
          success: false,
          error: e.toString(),
        );
        _isExtracting = false;
      });
    }
  }
  
  Future<void> _extractFullText() async {
    setState(() => _isExtracting = true);
    
    try {
      final result = await _paywallService.bypassAndExtract(
        widget.article.url,
        aggressive: true,
      );
      
      setState(() {
        _extractedContent = ExtractedContent(
          content: result.content,
          title: result.title,
          success: result.success,
          error: result.error,
        );
        _isExtracting = false;
      });
      
      if (result.success) {
        GlassSnackBar.showSuccess(
          context: context,
          message: 'Full text extracted using ${result.method.name}',
        );
      }
    } catch (e) {
      setState(() {
        _extractedContent = ExtractedContent(
          content: '',
          success: false,
          error: e.toString(),
        );
        _isExtracting = false;
      });
    }
  }
  
  void _toggleBookmark() {
    final newState = !_isBookmarked;
    ref.read(articleServiceProvider).setBookmark(widget.article.id, newState);
    setState(() => _isBookmarked = newState);
    
    GlassSnackBar.showSuccess(
      context: context,
      message: newState ? 'Article bookmarked' : 'Bookmark removed',
    );
  }
  
  void _shareArticle() {
    Share.share(
      '${widget.article.title}\n\n${widget.article.url}',
      subject: widget.article.title,
    );
  }
  
  void _openInBrowser() {
    // Launch URL in external browser
    // Implementation depends on url_launcher package
  }
  
  void _copyLink() {
    Clipboard.setData(ClipboardData(text: widget.article.url));
    GlassSnackBar.showSuccess(
      context: context,
      message: 'Link copied to clipboard',
    );
  }
  
  void _showFontSizeDialog() {
    // Show font size adjustment dialog
  }
  
  void _translateArticle() {
    // Implement translation feature
  }
  
  void _saveOffline() {
    // Implement offline saving
  }
  
  IconData _getViewModeIcon() {
    switch (_viewMode) {
      case ViewMode.webView:
        return Icons.web;
      case ViewMode.reader:
        return Icons.chrome_reader_mode;
      case ViewMode.fullText:
        return Icons.lock_open;
    }
  }
  
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateStr;
    }
  }
}

/// View modes for article display
enum ViewMode {
  webView,
  reader,
  fullText,
}