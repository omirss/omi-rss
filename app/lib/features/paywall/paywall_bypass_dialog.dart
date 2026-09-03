import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/paywall_provider.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_button.dart';
import '../../ui/components/glass_dialog.dart';
import '../../ui/components/glass_snack_bar.dart';

class PaywallBypassDialog extends ConsumerStatefulWidget {
  final String articleUrl;
  final String articleTitle;

  const PaywallBypassDialog({
    super.key,
    required this.articleUrl,
    required this.articleTitle,
  });

  @override
  ConsumerState<PaywallBypassDialog> createState() => _PaywallBypassDialogState();
}

class _PaywallBypassDialogState extends ConsumerState<PaywallBypassDialog> {
  bool _isAttempting = false;

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: const Text('Article Access Options'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.articleTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This article appears to be behind a paywall. Here are your options:',
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
            const SizedBox(height: 24),
            
            // Ethical bypass attempt
            _buildBypassOption(
              icon: Icons.archive,
              title: 'Check Archives',
              description: 'Look for this article in public archives like Wayback Machine',
              onTap: _attemptBypass,
              isLoading: _isAttempting,
            ),
            const SizedBox(height: 12),
            
            // Suggestions
            Consumer(
              builder: (context, ref, _) {
                final suggestionsAsync = ref.watch(
                  paywallSuggestionsProvider(widget.articleUrl),
                );
                
                return suggestionsAsync.when(
                  data: (suggestions) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Other Options:',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...suggestions.map((suggestion) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: Colors.amber.withOpacity(0.8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                suggestion,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, stack) => const SizedBox.shrink(),
                );
              },
            ),
            const SizedBox(height: 16),
            
            // Direct options
            _buildDirectOption(
              icon: Icons.open_in_browser,
              title: 'Open in Browser',
              description: 'Try viewing in your browser',
              onTap: () => _openInBrowser(widget.articleUrl),
            ),
            const SizedBox(height: 12),
            
            _buildDirectOption(
              icon: Icons.search,
              title: 'Search Archive.org',
              description: 'Search for this page on Internet Archive',
              onTap: () => _searchArchive(),
            ),
            const SizedBox(height: 12),
            
            _buildDirectOption(
              icon: Icons.library_books,
              title: 'Check Library Access',
              description: 'Many libraries offer free digital access',
              onTap: () => _openInBrowser('https://www.worldcat.org/'),
            ),
            const SizedBox(height: 24),
            
            // Support journalism message
            GlassContainer(
              padding: const EdgeInsets.all(16),
              gradientColors: [
                Colors.blue.withOpacity(0.2),
                Colors.purple.withOpacity(0.1),
              ],
              child: Row(
                children: [
                  Icon(
                    Icons.favorite,
                    color: Colors.red.withOpacity(0.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Consider supporting quality journalism by subscribing',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        GlassButton(
          text: 'Close',
          onPressed: () => Navigator.pop(context),
          variant: GlassButtonVariant.text,
        ),
      ],
    );
  }

  Widget _buildBypassOption({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward,
              color: Colors.white.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectOption({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attemptBypass() async {
    setState(() {
      _isAttempting = true;
    });

    try {
      final result = await ref.read(
        paywallBypassProvider(widget.articleUrl).future,
      );

      if (result.success && mounted) {
        Navigator.pop(context, result);
        context.showSuccessSnackBar(
          'Article retrieved via ${result.method?.replaceAll('_', ' ')}',
        );
      } else if (mounted) {
        context.showWarningSnackBar(
          result.error ?? 'Unable to access article through ethical means',
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to retrieve article: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAttempting = false;
        });
      }
    }
  }

  Future<void> _openInBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        context.showErrorSnackBar('Could not open URL');
      }
    }
  }

  Future<void> _searchArchive() async {
    final archiveUrl = 'https://web.archive.org/web/*/${widget.articleUrl}';
    await _openInBrowser(archiveUrl);
  }
}