import 'package:flutter/material.dart';
import '../../core/models/article.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';
import 'glass_container.dart';

/// Canonical article list-row anatomy: favicon-or-avatar, title, meta line
/// (feed, time, read time), unread dot, star, optional snippet and actions.
class ArticleCard extends StatelessWidget {
  final Article article;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? faviconUrl;
  final bool showSnippet;
  final bool selected;
  final VoidCallback? onToggleRead;
  final VoidCallback? onToggleStar;
  final VoidCallback? onShare;
  final VoidCallback? onOpenExternally;

  const ArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.trailing,
    this.faviconUrl,
    this.showSnippet = true,
    this.selected = false,
    this.onToggleRead,
    this.onToggleStar,
    this.onShare,
    this.onOpenExternally,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTheme.colorsOf(context);
    final snippet = article.description.isNotEmpty
        ? article.description
        : (article.summary ?? '');

    final hasActions = onToggleRead != null ||
        onToggleStar != null ||
        onShare != null ||
        onOpenExternally != null;

    return GlassContainer(
      onTap: onTap,
      selected: selected,
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(tokens),
          const SizedBox(width: GlassSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        article.title,
                        style: GlassTypeScale.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color:
                              article.isRead ? tokens.textMedium : tokens.textHigh,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (article.isStarred) ...[
                      const SizedBox(width: GlassSpacing.sm),
                      Icon(Icons.star, size: 16, color: tokens.warning),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(width: GlassSpacing.sm),
                      trailing!,
                    ],
                  ],
                ),
                const SizedBox(height: GlassSpacing.xs),
                _buildMetaLine(tokens),
                if (showSnippet && snippet.isNotEmpty) ...[
                  const SizedBox(height: GlassSpacing.sm),
                  Text(
                    snippet,
                    style:
                        GlassTypeScale.label.copyWith(color: tokens.textMedium),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (hasActions) ...[
                  const SizedBox(height: GlassSpacing.md),
                  _ActionRow(
                    article: article,
                    tokens: tokens,
                    onToggleRead: onToggleRead,
                    onToggleStar: onToggleStar,
                    onShare: onShare,
                    onOpenExternally: onOpenExternally,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(tokens) {
    final radius = BorderRadius.circular(GlassRadii.sm + 4);
    if (faviconUrl != null && faviconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          faviconUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(tokens, radius),
        ),
      );
    }
    return _avatarFallback(tokens, radius);
  }

  Widget _avatarFallback(tokens, BorderRadius radius) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: radius,
      ),
      child: Icon(Icons.rss_feed, size: 20, color: tokens.accent),
    );
  }

  Widget _buildMetaLine(tokens) {
    final parts = <String>[
      article.feedTitle ?? 'Unknown source',
      _formatDate(article.publishedAt ?? article.createdAt),
      if (article.estimatedReadTime > 0)
        '${article.estimatedReadTime} min read',
    ];

    return Row(
      children: [
        Expanded(
          child: Text(
            parts.join('  ·  '),
            style: GlassTypeScale.caption.copyWith(color: tokens.textLow),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!article.isRead) ...[
          const SizedBox(width: GlassSpacing.sm),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: tokens.accent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _ActionRow extends StatefulWidget {
  final Article article;
  final GlassColorTokens tokens;
  final VoidCallback? onToggleRead;
  final VoidCallback? onToggleStar;
  final VoidCallback? onShare;
  final VoidCallback? onOpenExternally;

  const _ActionRow({
    required this.article,
    required this.tokens,
    this.onToggleRead,
    this.onToggleStar,
    this.onShare,
    this.onOpenExternally,
  });

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        opacity: _hovered ? 1 : GlassOpacity.medium,
        child: Row(
          children: [
            if (widget.onToggleRead != null)
              _actionButton(
                tooltip: widget.article.isRead ? 'Mark as unread' : 'Mark as read',
                icon: widget.article.isRead
                    ? Icons.mark_email_read
                    : Icons.mark_email_unread,
                color: widget.article.isRead ? tokens.success : null,
                onTap: widget.onToggleRead!,
              ),
            if (widget.onToggleStar != null)
              _actionButton(
                tooltip: widget.article.isStarred ? 'Unstar' : 'Star',
                icon: widget.article.isStarred ? Icons.star : Icons.star_outline,
                color: widget.article.isStarred ? tokens.warning : null,
                onTap: widget.onToggleStar!,
              ),
            if (widget.onShare != null)
              _actionButton(
                tooltip: 'Share',
                icon: Icons.share,
                onTap: widget.onShare!,
              ),
            if (widget.onOpenExternally != null)
              _actionButton(
                tooltip: 'Open in browser',
                icon: Icons.open_in_browser,
                onTap: widget.onOpenExternally!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    final tokens = widget.tokens;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(right: GlassSpacing.lg),
            child: Icon(
              icon,
              size: 18,
              color: color ?? tokens.textMedium,
            ),
          ),
        ),
      ),
    );
  }
}
