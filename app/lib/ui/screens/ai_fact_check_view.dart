import 'package:flutter/material.dart';
import '../../core/services/ai_service.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';

/// AI Fact Check view component
class AIFactCheckView extends StatefulWidget {
  final AIAnalysisResult result;
  
  const AIFactCheckView({
    super.key,
    required this.result,
  });
  
  @override
  State<AIFactCheckView> createState() => _AIFactCheckViewState();
}

class _AIFactCheckViewState extends State<AIFactCheckView> {
  String _filterVerdict = 'all';
  bool _showDetails = false;
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final factChecks = widget.result.factCheckResults;
    
    if (factChecks == null || factChecks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fact_check,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No fact checks available',
              style: theme.bodyLarge.copyWith(
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No verifiable claims found in this article',
              style: theme.bodyMedium.copyWith(
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }
    
    final filteredChecks = _filterFactChecks(factChecks);
    final overallCredibility = _calculateOverallCredibility(factChecks);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverallCredibility(overallCredibility, factChecks.length, theme),
          const SizedBox(height: 24),
          _buildVerdictSummary(factChecks, theme),
          const SizedBox(height: 24),
          _buildFilters(theme),
          const SizedBox(height: 16),
          _buildFactChecksList(filteredChecks, theme),
        ],
      ),
    );
  }
  
  Widget _buildOverallCredibility(double credibility, int totalClaims, GlassThemeData theme) {
    final color = _getCredibilityColor(credibility);
    final rating = _getCredibilityRating(credibility);
    
    return GlassCard(
      theme: theme,
      borderColor: color.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getCredibilityIcon(credibility),
                  color: color,
                  size: 48,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(credibility * 100).toStringAsFixed(0)}%',
                      style: theme.headlineMedium.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Credibility Score',
                      style: theme.bodyMedium.copyWith(
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withOpacity(0.5),
                ),
              ),
              child: Text(
                rating,
                style: theme.bodyLarge.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Based on $totalClaims verified claims',
              style: theme.bodySmall.copyWith(
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildVerdictSummary(List<FactCheckResult> factChecks, GlassThemeData theme) {
    final verdictCounts = <String, int>{};
    for (final check in factChecks) {
      verdictCounts[check.verdict] = (verdictCounts[check.verdict] ?? 0) + 1;
    }
    
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verdict Summary',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildVerdictStat('True', verdictCounts['true'] ?? 0, Colors.green, theme),
                _buildVerdictStat('False', verdictCounts['false'] ?? 0, Colors.red, theme),
                _buildVerdictStat('Mixed', verdictCounts['mixed'] ?? 0, Colors.orange, theme),
                _buildVerdictStat('Unverified', verdictCounts['unverifiable'] ?? 0, Colors.grey, theme),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildVerdictStat(String label, int count, Color color, GlassThemeData theme) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(0.5),
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: theme.titleLarge.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.bodySmall.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
  
  Widget _buildFilters(GlassThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Fact Checks',
          style: theme.titleLarge,
        ),
        Row(
          children: [
            _buildFilterChip('All', 'all', theme),
            const SizedBox(width: 8),
            _buildFilterChip('True', 'true', theme),
            const SizedBox(width: 8),
            _buildFilterChip('False', 'false', theme),
            const SizedBox(width: 8),
            _buildFilterChip('Mixed', 'mixed', theme),
          ],
        ),
      ],
    );
  }
  
  Widget _buildFilterChip(String label, String value, GlassThemeData theme) {
    final isSelected = _filterVerdict == value;
    final color = _getVerdictColor(value);
    
    return GestureDetector(
      onTap: () => setState(() => _filterVerdict = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color.withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: theme.bodySmall.copyWith(
            color: isSelected ? color : Colors.white.withOpacity(0.7),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  Widget _buildFactChecksList(List<FactCheckResult> factChecks, GlassThemeData theme) {
    return Column(
      children: factChecks.map((check) {
        return _buildFactCheckCard(check, theme);
      }).toList(),
    );
  }
  
  Widget _buildFactCheckCard(FactCheckResult check, GlassThemeData theme) {
    final color = _getVerdictColor(check.verdict);
    final icon = _getVerdictIcon(check.verdict);
    final isExpanded = _showDetails;
    
    return GlassCard(
      theme: theme,
      borderColor: color.withOpacity(0.2),
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.all(16),
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          leading: Container(
            width: 40,
            height: 40,
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
          title: Text(
            check.claim,
            style: theme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    check.verdict.toUpperCase(),
                    style: theme.bodySmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (check.confidence > 0) ...[
                  Icon(
                    Icons.shield,
                    size: 14,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(check.confidence * 100).toStringAsFixed(0)}%',
                    style: theme.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          children: [
            if (check.sources.isNotEmpty)
              _buildFactCheckDetails(check, theme),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFactCheckDetails(FactCheckResult check, GlassThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (check.claimType.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.category,
                size: 16,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(width: 8),
              Text(
                'Type: ${check.claimType}',
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Sources:',
          style: theme.bodyMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...check.sources.map((source) {
          return _buildSourceCard(source, theme);
        }).toList(),
      ],
    );
  }
  
  Widget _buildSourceCard(FactSource source, GlassThemeData theme) {
    final color = _getVerdictColor(source.verdict);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.source,
                    size: 16,
                    color: theme.accentColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    source.name,
                    style: theme.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                _formatDate(source.checkedAt),
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            source.explanation,
            style: theme.bodySmall.copyWith(
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          if (source.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...source.sources.map((ref) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.link,
                      size: 12,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ref,
                        style: theme.bodySmall.copyWith(
                          color: theme.accentColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }
  
  List<FactCheckResult> _filterFactChecks(List<FactCheckResult> checks) {
    if (_filterVerdict == 'all') return checks;
    
    return checks.where((check) {
      switch (_filterVerdict) {
        case 'true':
          return check.verdict == 'true' || check.verdict == 'mostly_true';
        case 'false':
          return check.verdict == 'false' || check.verdict == 'mostly_false';
        case 'mixed':
          return check.verdict == 'mixed';
        default:
          return true;
      }
    }).toList();
  }
  
  double _calculateOverallCredibility(List<FactCheckResult> checks) {
    if (checks.isEmpty) return 0.5;
    
    double totalScore = 0;
    double totalWeight = 0;
    
    for (final check in checks) {
      final weight = check.confidence * check.checkability;
      final score = _getVerdictScore(check.verdict);
      
      totalScore += score * weight;
      totalWeight += weight;
    }
    
    return totalWeight > 0 ? totalScore / totalWeight : 0.5;
  }
  
  double _getVerdictScore(String verdict) {
    switch (verdict) {
      case 'true':
        return 1.0;
      case 'mostly_true':
        return 0.75;
      case 'mixed':
        return 0.5;
      case 'mostly_false':
        return 0.25;
      case 'false':
        return 0.0;
      default:
        return 0.5;
    }
  }
  
  Color _getVerdictColor(String verdict) {
    switch (verdict) {
      case 'all':
        return Colors.blue;
      case 'true':
      case 'mostly_true':
        return Colors.green;
      case 'false':
      case 'mostly_false':
        return Colors.red;
      case 'mixed':
        return Colors.orange;
      case 'unverifiable':
      default:
        return Colors.grey;
    }
  }
  
  IconData _getVerdictIcon(String verdict) {
    switch (verdict) {
      case 'true':
      case 'mostly_true':
        return Icons.check_circle;
      case 'false':
      case 'mostly_false':
        return Icons.cancel;
      case 'mixed':
        return Icons.help;
      case 'unverifiable':
      default:
        return Icons.help_outline;
    }
  }
  
  Color _getCredibilityColor(double credibility) {
    if (credibility >= 0.8) return Colors.green;
    if (credibility >= 0.6) return Colors.lightGreen;
    if (credibility >= 0.4) return Colors.orange;
    return Colors.red;
  }
  
  String _getCredibilityRating(double credibility) {
    if (credibility >= 0.8) return 'Highly Credible';
    if (credibility >= 0.6) return 'Mostly Credible';
    if (credibility >= 0.4) return 'Mixed Credibility';
    if (credibility >= 0.2) return 'Low Credibility';
    return 'Very Low Credibility';
  }
  
  IconData _getCredibilityIcon(double credibility) {
    if (credibility >= 0.8) return Icons.verified;
    if (credibility >= 0.6) return Icons.check_circle_outline;
    if (credibility >= 0.4) return Icons.info_outline;
    return Icons.warning_amber;
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
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}