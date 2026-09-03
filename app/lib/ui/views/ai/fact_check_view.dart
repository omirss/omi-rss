import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/ai_service.dart';
import '../../components/glass_container.dart';
import '../../glass_theme.dart';

/// View for displaying fact check results
class FactCheckView extends ConsumerWidget {
  final List<FactCheckResult> factCheckResults;
  final VoidCallback onClose;
  
  const FactCheckView({
    super.key,
    required this.factCheckResults,
    required this.onClose,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(glassThemeProvider);
    
    // Group results by verdict
    final groupedResults = <String, List<FactCheckResult>>{};
    for (final result in factCheckResults) {
      groupedResults.putIfAbsent(result.verdict, () => []).add(result);
    }
    
    // Sort groups by severity
    final verdictOrder = ['false', 'mostly_false', 'mixed', 'mostly_true', 'true', 'unverifiable'];
    final sortedGroups = verdictOrder
        .where((verdict) => groupedResults.containsKey(verdict))
        .map((verdict) => MapEntry(verdict, groupedResults[verdict]!))
        .toList();
    
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
            child: Row(
              children: [
                Icon(
                  Icons.fact_check,
                  color: theme.textColor,
                  size: 28,
                ).animate().scale(
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fact Check Results',
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${factCheckResults.length} claims analyzed',
                        style: TextStyle(
                          color: theme.textColor.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: theme.textColor.withOpacity(0.7),
                  ),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          
          // Summary
          if (factCheckResults.isNotEmpty) ...[
            _FactCheckSummary(
              results: factCheckResults,
              theme: theme,
            ).animate().fadeIn(duration: 600.ms),
          ],
          
          // Results
          Expanded(
            child: factCheckResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          color: theme.textColor.withOpacity(0.3),
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No factual claims found to verify',
                          style: TextStyle(
                            color: theme.textColor.withOpacity(0.5),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: sortedGroups.length,
                    itemBuilder: (context, index) {
                      final group = sortedGroups[index];
                      return _VerdictGroup(
                        verdict: group.key,
                        results: group.value,
                        theme: theme,
                        delay: index * 200,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Fact check summary statistics
class _FactCheckSummary extends StatelessWidget {
  final List<FactCheckResult> results;
  final GlassThemeData theme;
  
  const _FactCheckSummary({
    required this.results,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    // Calculate statistics
    final stats = <String, int>{};
    for (final result in results) {
      stats[result.verdict] = (stats[result.verdict] ?? 0) + 1;
    }
    
    final avgConfidence = results.isEmpty ? 0.0 :
        results.map((r) => r.confidence).reduce((a, b) => a + b) / results.length;
    
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.borderColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatCard(
                icon: Icons.check_circle,
                label: 'True',
                value: '${stats['true'] ?? 0}',
                color: Colors.green,
                theme: theme,
              ),
              _StatCard(
                icon: Icons.warning,
                label: 'Mixed',
                value: '${stats['mixed'] ?? 0}',
                color: Colors.orange,
                theme: theme,
              ),
              _StatCard(
                icon: Icons.cancel,
                label: 'False',
                value: '${stats['false'] ?? 0}',
                color: Colors.red,
                theme: theme,
              ),
              _StatCard(
                icon: Icons.help,
                label: 'Unverified',
                value: '${stats['unverifiable'] ?? 0}',
                color: Colors.grey,
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.borderColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.analytics,
                  color: theme.textColor.withOpacity(0.7),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Average Confidence: ${(avgConfidence * 100).toInt()}%',
                  style: TextStyle(
                    color: theme.textColor.withOpacity(0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small stat card
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final GlassThemeData theme;
  
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 32,
        ).animate().scale(
          delay: 200.ms,
          duration: 400.ms,
          curve: Curves.elasticOut,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: theme.textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: theme.textColor.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Group of results with same verdict
class _VerdictGroup extends StatelessWidget {
  final String verdict;
  final List<FactCheckResult> results;
  final GlassThemeData theme;
  final int delay;
  
  const _VerdictGroup({
    required this.verdict,
    required this.results,
    required this.theme,
    required this.delay,
  });
  
  Color _getVerdictColor() {
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
  
  IconData _getVerdictIcon() {
    switch (verdict) {
      case 'true':
      case 'mostly_true':
        return Icons.check_circle;
      case 'mixed':
        return Icons.help;
      case 'mostly_false':
      case 'false':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }
  
  String _getVerdictLabel() {
    return verdict.replaceAll('_', ' ').split(' ').map((word) =>
      word[0].toUpperCase() + word.substring(1)
    ).join(' ');
  }
  
  @override
  Widget build(BuildContext context) {
    final color = _getVerdictColor();
    final icon = _getVerdictIcon();
    final label = _getVerdictLabel();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verdict header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${results.length}',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ).animate()
            .fadeIn(delay: delay.ms)
            .slideX(begin: -0.1),
          
          const SizedBox(height: 8),
          
          // Claims
          ...results.asMap().entries.map((entry) {
            final index = entry.key;
            final result = entry.value;
            
            return _FactCheckCard(
              result: result,
              color: color,
              theme: theme,
              delay: delay + (index * 100),
            );
          }),
        ],
      ),
    );
  }
}

/// Individual fact check result card
class _FactCheckCard extends StatefulWidget {
  final FactCheckResult result;
  final Color color;
  final GlassThemeData theme;
  final int delay;
  
  const _FactCheckCard({
    required this.result,
    required this.color,
    required this.theme,
    required this.delay,
  });
  
  @override
  State<_FactCheckCard> createState() => _FactCheckCardState();
}

class _FactCheckCardState extends State<_FactCheckCard> {
  bool _expanded = false;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 32),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.theme.cardColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.theme.borderColor.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Claim
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.format_quote,
                      color: widget.theme.textColor.withOpacity(0.5),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.result.claim,
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: widget.theme.textColor.withOpacity(0.5),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // Metadata
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.theme.borderColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.result.claimType,
                        style: TextStyle(
                          color: widget.theme.textColor.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Checkability: ${(widget.result.checkability * 100).toInt()}%',
                      style: TextStyle(
                        color: widget.theme.textColor.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Confidence: ${(widget.result.confidence * 100).toInt()}%',
                      style: TextStyle(
                        color: widget.color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                
                // Expanded content
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      if (widget.result.sources.isNotEmpty) ...[
                        Text(
                          'Sources',
                          style: TextStyle(
                            color: widget.theme.textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...widget.result.sources.map((source) => _SourceCard(
                          source: source,
                          theme: widget.theme,
                        )),
                      ],
                    ],
                  ),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate()
      .fadeIn(delay: widget.delay.ms)
      .slideY(begin: 0.1);
  }
}

/// Source card for fact check
class _SourceCard extends StatelessWidget {
  final FactSource source;
  final GlassThemeData theme;
  
  const _SourceCard({
    required this.source,
    required this.theme,
  });
  
  Color _getSourceColor() {
    switch (source.verdict) {
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
  
  @override
  Widget build(BuildContext context) {
    final color = _getSourceColor();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.borderColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.borderColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                source.name,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                source.verdict.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            source.explanation,
            style: TextStyle(
              color: theme.textColor.withOpacity(0.8),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (source.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: source.sources.map((ref) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.primaryColor.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  ref,
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 11,
                  ),
                ),
              )).toList(),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Checked ${_formatTime(source.checkedAt)}',
            style: TextStyle(
              color: theme.textColor.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}