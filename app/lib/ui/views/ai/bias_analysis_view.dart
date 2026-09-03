import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../../core/services/ai_service.dart';
import '../../components/glass_container.dart';
import '../../glass_theme.dart';

/// View for displaying bias analysis results
class BiasAnalysisView extends ConsumerWidget {
  final BiasAnalysis biasAnalysis;
  final VoidCallback onClose;
  
  const BiasAnalysisView({
    super.key,
    required this.biasAnalysis,
    required this.onClose,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(glassThemeProvider);
    
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
                  Icons.analytics,
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
                        'Bias Analysis',
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Understanding article perspective and balance',
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
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overall Bias Score
                  _OverallBiasScore(
                    score: biasAnalysis.overallScore,
                    theme: theme,
                  ).animate().fadeIn(duration: 600.ms),
                  
                  const SizedBox(height: 24),
                  
                  // Political Bias
                  _PoliticalBiasIndicator(
                    bias: biasAnalysis.politicalBias,
                    theme: theme,
                  ).animate().fadeIn(delay: 200.ms),
                  
                  const SizedBox(height: 24),
                  
                  // Bias Indicators
                  _BiasIndicators(
                    indicators: biasAnalysis.biasIndicators,
                    theme: theme,
                  ).animate().fadeIn(delay: 400.ms),
                  
                  const SizedBox(height: 24),
                  
                  // Article Metrics
                  _ArticleMetrics(
                    factualDensity: biasAnalysis.factualDensity,
                    emotionalIndex: biasAnalysis.emotionalIndex,
                    loadedTermsCount: biasAnalysis.loadedTermsCount,
                    theme: theme,
                  ).animate().fadeIn(delay: 600.ms),
                  
                  const SizedBox(height: 24),
                  
                  // Bias Examples
                  if (biasAnalysis.examples.isNotEmpty) ...[
                    _BiasExamples(
                      examples: biasAnalysis.examples,
                      theme: theme,
                    ).animate().fadeIn(delay: 800.ms),
                    const SizedBox(height: 24),
                  ],
                  
                  // Suggestions
                  if (biasAnalysis.suggestions.isNotEmpty) ...[
                    _BalancedReadingSuggestions(
                      suggestions: biasAnalysis.suggestions,
                      theme: theme,
                    ).animate().fadeIn(delay: 1000.ms),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Overall bias score visualization
class _OverallBiasScore extends StatelessWidget {
  final double score;
  final GlassThemeData theme;
  
  const _OverallBiasScore({
    required this.score,
    required this.theme,
  });
  
  Color _getScoreColor(double score) {
    if (score < 30) return Colors.green;
    if (score < 50) return Colors.lightGreen;
    if (score < 70) return Colors.orange;
    return Colors.red;
  }
  
  String _getScoreLabel(double score) {
    if (score < 30) return 'Low Bias';
    if (score < 50) return 'Moderate Bias';
    if (score < 70) return 'High Bias';
    return 'Very High Bias';
  }
  
  @override
  Widget build(BuildContext context) {
    final color = _getScoreColor(score);
    final label = _getScoreLabel(score);
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.borderColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Overall Bias Score',
            style: TextStyle(
              color: theme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 180,
            height: 180,
            child: CustomPaint(
              painter: _BiasMeterPainter(
                score: score,
                color: color,
                backgroundColor: theme.borderColor.withOpacity(0.2),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${score.toInt()}',
                      style: TextStyle(
                        color: color,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ).animate().countUp(
                      duration: 1.5.seconds,
                      begin: 0,
                      end: score,
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: theme.textColor.withOpacity(0.7),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Score ranges from 0 (unbiased) to 100 (extremely biased)',
            style: TextStyle(
              color: theme.textColor.withOpacity(0.6),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Political bias indicator
class _PoliticalBiasIndicator extends StatelessWidget {
  final PoliticalBias bias;
  final GlassThemeData theme;
  
  const _PoliticalBiasIndicator({
    required this.bias,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    final normalizedScore = (bias.score + 1) / 2; // Convert -1 to 1 => 0 to 1
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.borderColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Political Leaning',
            style: TextStyle(
              color: theme.textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // Scale
          Container(
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Colors.blue,
                  Colors.purple,
                  Colors.grey,
                  Colors.orange,
                  Colors.red,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.borderColor.withOpacity(0.3),
              ),
            ),
            child: Stack(
              children: [
                // Labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Left',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Center',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Right',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // Indicator
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutBack,
                  left: normalizedScore * (MediaQuery.of(context).size.width - 120),
                  top: -10,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.borderColor,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_pin,
                            color: theme.primaryColor,
                            size: 20,
                          ),
                          Text(
                            bias.direction.toUpperCase(),
                            style: TextStyle(
                              color: theme.textColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Score: ${bias.score.toStringAsFixed(2)} (${bias.direction})',
            style: TextStyle(
              color: theme.textColor.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bias indicators grid
class _BiasIndicators extends StatelessWidget {
  final Map<String, double> indicators;
  final GlassThemeData theme;
  
  const _BiasIndicators({
    required this.indicators,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    final sortedIndicators = indicators.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bias Indicators',
          style: TextStyle(
            color: theme.textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: sortedIndicators.length,
          itemBuilder: (context, index) {
            final indicator = sortedIndicators[index];
            return _BiasIndicatorTile(
              name: indicator.key,
              value: indicator.value,
              theme: theme,
              delay: index * 50,
            );
          },
        ),
      ],
    );
  }
}

/// Individual bias indicator tile
class _BiasIndicatorTile extends StatelessWidget {
  final String name;
  final double value;
  final GlassThemeData theme;
  final int delay;
  
  const _BiasIndicatorTile({
    required this.name,
    required this.value,
    required this.theme,
    required this.delay,
  });
  
  Color _getIndicatorColor(double value) {
    if (value < 0.3) return Colors.green;
    if (value < 0.6) return Colors.orange;
    return Colors.red;
  }
  
  @override
  Widget build(BuildContext context) {
    final color = _getIndicatorColor(value);
    final displayName = name.replaceAll('_', ' ').split(' ').map((word) =>
      word[0].toUpperCase() + word.substring(1)
    ).join(' ');
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.borderColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            displayName,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: theme.borderColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              AnimatedContainer(
                duration: Duration(milliseconds: 800 + delay),
                curve: Curves.easeOutCubic,
                height: 6,
                width: value * (MediaQuery.of(context).size.width / 2 - 56),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${(value * 100).toInt()}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ).animate()
      .fadeIn(delay: delay.ms)
      .slideX(begin: 0.1);
  }
}

/// Article metrics display
class _ArticleMetrics extends StatelessWidget {
  final double factualDensity;
  final double emotionalIndex;
  final int loadedTermsCount;
  final GlassThemeData theme;
  
  const _ArticleMetrics({
    required this.factualDensity,
    required this.emotionalIndex,
    required this.loadedTermsCount,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            icon: Icons.fact_check,
            label: 'Factual Density',
            value: '${(factualDensity * 100).toInt()}%',
            color: Colors.blue,
            theme: theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            icon: Icons.sentiment_satisfied,
            label: 'Emotional Index',
            value: '${(emotionalIndex * 100).toInt()}%',
            color: Colors.orange,
            theme: theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            icon: Icons.warning,
            label: 'Loaded Terms',
            value: '$loadedTermsCount',
            color: Colors.red,
            theme: theme,
          ),
        ),
      ],
    );
  }
}

/// Metric card widget
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final GlassThemeData theme;
  
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.borderColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: theme.textColor.withOpacity(0.7),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Bias examples section
class _BiasExamples extends StatelessWidget {
  final List<BiasExample> examples;
  final GlassThemeData theme;
  
  const _BiasExamples({
    required this.examples,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Examples of Bias',
          style: TextStyle(
            color: theme.textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...examples.take(3).map((example) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.borderColor.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      example.type.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.borderColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.borderColor.withOpacity(0.2),
                  ),
                ),
                child: Text(
                  '"${example.text}"',
                  style: TextStyle(
                    color: theme.textColor.withOpacity(0.9),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                example.explanation,
                style: TextStyle(
                  color: theme.textColor.withOpacity(0.7),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

/// Balanced reading suggestions
class _BalancedReadingSuggestions extends StatelessWidget {
  final List<String> suggestions;
  final GlassThemeData theme;
  
  const _BalancedReadingSuggestions({
    required this.suggestions,
    required this.theme,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb,
                color: Colors.blue,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'For More Balanced Reading',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...suggestions.map((suggestion) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.arrow_right,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    suggestion,
                    style: TextStyle(
                      color: theme.textColor.withOpacity(0.9),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

/// Custom painter for bias meter
class _BiasMeterPainter extends CustomPainter {
  final double score;
  final Color color;
  final Color backgroundColor;
  
  _BiasMeterPainter({
    required this.score,
    required this.color,
    required this.backgroundColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    
    // Background arc
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 10),
      -math.pi * 1.25,
      math.pi * 1.5,
      false,
      backgroundPaint,
    );
    
    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    
    final progressAngle = (score / 100) * math.pi * 1.5;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 10),
      -math.pi * 1.25,
      progressAngle,
      false,
      progressPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}