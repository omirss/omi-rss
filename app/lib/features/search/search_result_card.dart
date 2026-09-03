import 'package:flutter/material.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import 'search_service.dart';

class SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  
  const SearchResultCard({
    super.key,
    required this.result,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Result type and score
              Row(
                children: [
                  Icon(
                    _getTypeIcon(result.type),
                    size: 16,
                    color: _getTypeColor(result.type),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getTypeLabel(result.type),
                    style: TextStyle(
                      color: _getTypeColor(result.type),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (result.score > 0.8)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'High match',
                        style: TextStyle(
                          color: Colors.green.shade300,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Title with highlights
              _buildHighlightedText(
                result.title,
                result.highlights.where((h) => h.field == 'title').toList(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              
              // Snippet with highlights
              if (result.snippet.isNotEmpty)
                _buildHighlightedText(
                  result.snippet,
                  result.highlights.where((h) => h.field == 'content').toList(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  maxLines: 3,
                ),
              const SizedBox(height: 8),
              
              // Metadata
              Wrap(
                spacing: 12,
                children: [
                  if (result.metadata['feedTitle'] != null)
                    _buildMetadataChip(
                      Icons.rss_feed,
                      result.metadata['feedTitle'],
                    ),
                  if (result.metadata['publishedAt'] != null)
                    _buildMetadataChip(
                      Icons.calendar_today,
                      _formatDate(DateTime.parse(result.metadata['publishedAt'])),
                    ),
                  if (result.metadata['author'] != null)
                    _buildMetadataChip(
                      Icons.person,
                      result.metadata['author'],
                    ),
                  if (result.metadata['wordCount'] != null)
                    _buildMetadataChip(
                      Icons.text_snippet,
                      '${result.metadata['wordCount']} words',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHighlightedText(
    String text,
    List<TextHighlight> highlights,
    {required TextStyle style, int? maxLines}
  ) {
    if (highlights.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    
    // Get all positions from highlights
    final positions = <HighlightPosition>[];
    for (final highlight in highlights) {
      positions.addAll(highlight.positions);
    }
    
    // Sort positions by start
    positions.sort((a, b) => a.start.compareTo(b.start));
    
    // Build text spans
    final spans = <TextSpan>[];
    int currentIndex = 0;
    
    for (final position in positions) {
      // Add non-highlighted text before this position
      if (currentIndex < position.start && position.start < text.length) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, position.start),
          style: style,
        ));
      }
      
      // Add highlighted text
      if (position.start < text.length && position.end <= text.length) {
        spans.add(TextSpan(
          text: text.substring(position.start, position.end),
          style: style.copyWith(
            backgroundColor: Colors.yellow.withOpacity(0.3),
            fontWeight: FontWeight.bold,
          ),
        ));
      }
      
      currentIndex = position.end;
    }
    
    // Add remaining text
    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: style,
      ));
    }
    
    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
  
  Widget _buildMetadataChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Colors.white.withOpacity(0.5),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
  
  IconData _getTypeIcon(SearchResultType type) {
    switch (type) {
      case SearchResultType.article:
        return Icons.article;
      case SearchResultType.feed:
        return Icons.rss_feed;
      case SearchResultType.highlight:
        return Icons.highlight;
      case SearchResultType.annotation:
        return Icons.note;
    }
  }
  
  Color _getTypeColor(SearchResultType type) {
    switch (type) {
      case SearchResultType.article:
        return Colors.blue.shade300;
      case SearchResultType.feed:
        return Colors.orange.shade300;
      case SearchResultType.highlight:
        return Colors.yellow.shade300;
      case SearchResultType.annotation:
        return Colors.green.shade300;
    }
  }
  
  String _getTypeLabel(SearchResultType type) {
    switch (type) {
      case SearchResultType.article:
        return 'Article';
      case SearchResultType.feed:
        return 'Feed';
      case SearchResultType.highlight:
        return 'Highlight';
      case SearchResultType.annotation:
        return 'Note';
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    }
  }
}