import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/services/ai_service.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';

/// AI Bias Detection view component
class AIBiasView extends StatefulWidget {
  final AIAnalysisResult result;
  
  const AIBiasView({
    super.key,
    required this.result,
  });
  
  @override
  State<AIBiasView> createState() => _AIBiasViewState();
}

class _AIBiasViewState extends State<AIBiasView> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final bias = widget.result.biasAnalysis;
    
    if (bias == null) {
      return Center(
        child: Text(
          'No bias analysis available',
          style: theme.bodyLarge.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverallScore(bias, theme),
          const SizedBox(height: 24),
          _buildPoliticalBias(bias, theme),
          const SizedBox(height: 24),
          _buildBiasIndicators(bias, theme),
          const SizedBox(height: 24),
          _buildMetrics(bias, theme),
          if (bias.examples.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildExamples(bias, theme),
          ],
          if (bias.suggestions.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSuggestions(bias, theme),
          ],
        ],
      ),
    );
  }
  
  Widget _buildOverallScore(BiasAnalysis bias, GlassThemeData theme) {
    final score = bias.overallScore;
    final color = _getScoreColor(score);
    final rating = _getScoreRating(score);
    
    return GlassCard(
      theme: theme,
      borderColor: color.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CustomPaint(
                        painter: _BiasGaugePainter(
                          value: _animation.value * score / 100,
                          color: color,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          '${(score * _animation.value).toInt()}',
                          style: theme.headlineLarge.copyWith(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        Text(
                          'Bias Score',
                          style: theme.bodyMedium.copyWith(
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
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
          ],
        ),
      ),
    );
  }
  
  Widget _buildPoliticalBias(BiasAnalysis bias, GlassThemeData theme) {
    final political = bias.politicalBias;
    final position = political.score; // -1 to +1
    
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
                  Icons.how_to_vote,
                  color: theme.accentColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Political Bias',
                  style: theme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade700,
                    Colors.blue,
                    Colors.purple,
                    Colors.red,
                    Colors.red.shade700,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 16,
                    child: Text(
                      'Left',
                      style: theme.bodySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    child: Text(
                      'Right',
                      style: theme.bodySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    left: ((position + 1) / 2) * (MediaQuery.of(context).size.width - 80),
                    child: Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                political.direction.substring(0, 1).toUpperCase() + 
                political.direction.substring(1),
                style: theme.bodyLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBiasIndicators(BiasAnalysis bias, GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bias Indicators',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 16),
            ...bias.biasIndicators.entries.map((entry) {
              final type = entry.key;
              final score = entry.value;
              final severity = _getSeverity(score);
              final color = _getSeverityColor(severity);
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatBiasType(type),
                          style: theme.bodyMedium,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            severity,
                            style: theme.bodySmall.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: score,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
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
  
  Widget _buildMetrics(BiasAnalysis bias, GlassThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            'Factual Density',
            bias.factualDensity,
            Icons.fact_check,
            Colors.blue,
            'facts/¶',
            theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Emotional Index',
            bias.emotionalIndex,
            Icons.psychology,
            Colors.orange,
            'level',
            theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Loaded Terms',
            bias.loadedTermsCount.toDouble(),
            Icons.warning,
            Colors.red,
            'count',
            theme,
          ),
        ),
      ],
    );
  }
  
  Widget _buildMetricCard(
    String label,
    double value,
    IconData icon,
    Color color,
    String unit,
    GlassThemeData theme,
  ) {
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value < 10 ? value.toStringAsFixed(1) : value.toInt().toString(),
              style: theme.titleLarge.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              unit,
              style: theme.bodySmall.copyWith(
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildExamples(BiasAnalysis bias, GlassThemeData theme) {
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
                  Icons.format_quote,
                  color: theme.accentColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Examples of Bias',
                  style: theme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...bias.examples.map((example) {
              final color = _getBiasTypeColor(example.type);
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
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
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            example.type,
                            style: theme.bodySmall.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '"${example.text}"',
                      style: theme.bodyMedium.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      example.explanation,
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.7),
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
  
  Widget _buildSuggestions(BiasAnalysis bias, GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      borderColor: Colors.green.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb,
                  color: Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Suggestions for Balance',
                  style: theme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...bias.suggestions.map((suggestion) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        suggestion,
                        style: theme.bodyMedium,
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
  
  Color _getScoreColor(double score) {
    if (score < 30) return Colors.green;
    if (score < 50) return Colors.yellow;
    if (score < 70) return Colors.orange;
    return Colors.red;
  }
  
  String _getScoreRating(double score) {
    if (score < 20) return 'Very Low Bias';
    if (score < 40) return 'Low Bias';
    if (score < 60) return 'Moderate Bias';
    if (score < 80) return 'High Bias';
    return 'Very High Bias';
  }
  
  String _getSeverity(double score) {
    if (score < 0.2) return 'None';
    if (score < 0.4) return 'Low';
    if (score < 0.6) return 'Medium';
    if (score < 0.8) return 'High';
    return 'Severe';
  }
  
  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'None':
        return Colors.green;
      case 'Low':
        return Colors.lightGreen;
      case 'Medium':
        return Colors.yellow;
      case 'High':
        return Colors.orange;
      case 'Severe':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  String _formatBiasType(String type) {
    return type.replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.substring(0, 1).toUpperCase() + word.substring(1))
        .join(' ');
  }
  
  Color _getBiasTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'framing':
        return Colors.purple;
      case 'emotional':
        return Colors.orange;
      case 'selection':
        return Colors.blue;
      case 'confirmation':
        return Colors.red;
      case 'sensationalism':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }
}

/// Custom painter for bias gauge
class _BiasGaugePainter extends CustomPainter {
  final double value;
  final Color color;
  
  _BiasGaugePainter({
    required this.value,
    required this.color,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Background arc
    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 10),
      -math.pi * 1.25,
      math.pi * 1.5,
      false,
      backgroundPaint,
    );
    
    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 10),
      -math.pi * 1.25,
      math.pi * 1.5 * value,
      false,
      valuePaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant _BiasGaugePainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}