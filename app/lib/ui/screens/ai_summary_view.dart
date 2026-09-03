import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/ai_service.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';

/// AI Summary view component
class AISummaryView extends StatefulWidget {
  final AIAnalysisResult result;
  
  const AISummaryView({
    super.key,
    required this.result,
  });
  
  @override
  State<AISummaryView> createState() => _AISummaryViewState();
}

class _AISummaryViewState extends State<AISummaryView> {
  String _selectedLength = 'medium';
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.result.summary != null) ...[
            _buildSummarySection(theme),
            const SizedBox(height: 24),
          ],
          if (widget.result.keyPoints != null && widget.result.keyPoints!.isNotEmpty) ...[
            _buildKeyPointsSection(theme),
            const SizedBox(height: 24),
          ],
          if (widget.result.tags != null && widget.result.tags!.isNotEmpty) ...[
            _buildTagsSection(theme),
          ],
        ],
      ),
    );
  }
  
  Widget _buildSummarySection(GlassThemeData theme) {
    final summary = widget.result.summary!;
    
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Summary',
                  style: theme.titleMedium,
                ),
                Row(
                  children: [
                    _buildLengthChip('short', '50 words', theme),
                    const SizedBox(width: 8),
                    _buildLengthChip('medium', '100 words', theme),
                    const SizedBox(width: 8),
                    _buildLengthChip('long', '200 words', theme),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _getSelectedSummary(summary),
                key: ValueKey(_selectedLength),
                style: theme.bodyLarge.copyWith(
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copySummary(context),
                  tooltip: 'Copy summary',
                ),
                IconButton(
                  icon: const Icon(Icons.share, size: 20),
                  onPressed: () => _shareSummary(),
                  tooltip: 'Share summary',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLengthChip(String value, String label, GlassThemeData theme) {
    final isSelected = _selectedLength == value;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedLength = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.accentColor.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.accentColor.withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: theme.bodySmall.copyWith(
            color: isSelected ? theme.accentColor : Colors.white.withOpacity(0.7),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  Widget _buildKeyPointsSection(GlassThemeData theme) {
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
                  Icons.star,
                  color: theme.accentColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Key Points',
                  style: theme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...widget.result.keyPoints!.asMap().entries.map((entry) {
              final index = entry.key;
              final point = entry.value;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: theme.accentColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: theme.bodySmall.copyWith(
                            color: theme.accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        point,
                        style: theme.bodyMedium.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTagsSection(GlassThemeData theme) {
    final tagsByCategory = <String, List<AITag>>{};
    for (final tag in widget.result.tags!) {
      tagsByCategory.putIfAbsent(tag.category, () => []).add(tag);
    }
    
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
                  Icons.label,
                  color: theme.accentColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI-Generated Tags',
                  style: theme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...tagsByCategory.entries.map((entry) {
              final category = entry.key;
              final tags = entry.value;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.substring(0, 1).toUpperCase() + category.substring(1),
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tags.map((tag) {
                        final confidence = tag.confidence;
                        final opacity = 0.1 + (confidence * 0.2);
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(category).withOpacity(opacity),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _getCategoryColor(category).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tag.name,
                                style: theme.bodySmall,
                              ),
                              if (confidence < 0.7) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.help_outline,
                                  size: 12,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
  
  String _getSelectedSummary(AISummary summary) {
    switch (_selectedLength) {
      case 'short':
        return summary.short;
      case 'long':
        return summary.long;
      default:
        return summary.medium;
    }
  }
  
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'topic':
        return Colors.blue;
      case 'industry':
        return Colors.purple;
      case 'location':
        return Colors.green;
      case 'person':
        return Colors.orange;
      case 'organization':
        return Colors.red;
      case 'event':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
  
  void _copySummary(BuildContext context) {
    final summary = _getSelectedSummary(widget.result.summary!);
    Clipboard.setData(ClipboardData(text: summary));
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Summary copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
  
  void _shareSummary() {
    final summary = _getSelectedSummary(widget.result.summary!);
    // Implement share functionality
  }
}