import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/services/feed_service.dart';
import '../../core/models/feed.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../animations/loading_animation.dart';

/// Feed health monitoring screen
class FeedHealthScreen extends StatefulWidget {
  final Feed feed;
  final FeedService feedService;
  
  const FeedHealthScreen({
    super.key,
    required this.feed,
    required this.feedService,
  });

  @override
  State<FeedHealthScreen> createState() => _FeedHealthScreenState();
}

class _FeedHealthScreenState extends State<FeedHealthScreen> {
  late FeedHealth _health;
  late FeedStatistics _statistics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      _health = widget.feedService.getFeedHealth(widget.feed.id);
      _statistics = await widget.feedService.getFeedStatistics(widget.feed.id);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.feed.title} Health'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: LoadingAnimation())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHealthOverview(theme),
                  const SizedBox(height: 16),
                  _buildResponseTimeChart(theme),
                  const SizedBox(height: 16),
                  _buildSuccessRateChart(theme),
                  const SizedBox(height: 16),
                  _buildStatistics(theme),
                  const SizedBox(height: 16),
                  _buildRecentEvents(theme),
                ],
              ),
            ),
    );
  }

  Widget _buildHealthOverview(GlassThemeData theme) {
    final isHealthy = _health.isHealthy;
    
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
                  isHealthy ? Icons.check_circle : Icons.error,
                  color: isHealthy ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  isHealthy ? 'Feed is Healthy' : 'Feed Has Issues',
                  style: theme.titleLarge.copyWith(
                    color: isHealthy ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetric('Success Rate', '${(_health.successRate * 100).toStringAsFixed(1)}%'),
            _buildMetric('Total Fetches', _health.totalFetches.toString()),
            _buildMetric('Failed Fetches', _health.failedFetches.toString()),
            _buildMetric(
              'Average Response Time',
              '${_health.averageResponseTime.inMilliseconds}ms',
            ),
            if (_health.lastError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Error',
                      style: theme.bodySmall.copyWith(color: Colors.red),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _health.lastError!,
                      style: theme.bodyMedium,
                    ),
                    if (_health.lastFailureAt != null)
                      Text(
                        _formatDateTime(_health.lastFailureAt!),
                        style: theme.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    final theme = GlassTheme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          Text(
            value,
            style: theme.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseTimeChart(GlassThemeData theme) {
    final recentEvents = _health.recentEvents.take(20).toList();
    if (recentEvents.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (int i = 0; i < recentEvents.length; i++) {
      spots.add(FlSpot(
        i.toDouble(),
        recentEvents[i].responseTime.inMilliseconds.toDouble(),
      ));
    }

    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Response Time Trend',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.white.withOpacity(0.1),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}ms',
                            style: theme.bodySmall.copyWith(
                              color: Colors.white.withOpacity(0.5),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: theme.accentColor,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: theme.accentColor.withOpacity(0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessRateChart(GlassThemeData theme) {
    final successRate = _health.successRate * 100;
    
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Success Rate',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          value: successRate,
                          color: Colors.green,
                          title: '',
                          radius: 50,
                        ),
                        PieChartSectionData(
                          value: 100 - successRate,
                          color: Colors.red.withOpacity(0.3),
                          title: '',
                          radius: 50,
                        ),
                      ],
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                    ),
                  ),
                  Text(
                    '${successRate.toStringAsFixed(1)}%',
                    style: theme.titleLarge.copyWith(
                      fontWeight: FontWeight.bold,
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

  Widget _buildStatistics(GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Feed Statistics',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildMetric('Total Articles', _statistics.totalArticles.toString()),
            _buildMetric('Read Articles', _statistics.readArticles.toString()),
            _buildMetric('Starred Articles', _statistics.starredArticles.toString()),
            _buildMetric(
              'Articles per Day',
              _statistics.articlesPerDay.toStringAsFixed(1),
            ),
            if (_statistics.mostActiveHours.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Most Active Hours',
                style: theme.bodyMedium.copyWith(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: _statistics.mostActiveHours.map((hour) {
                  return Chip(
                    label: Text(
                      '${hour.toString().padLeft(2, '0')}:00',
                      style: theme.bodySmall,
                    ),
                    backgroundColor: theme.accentColor.withOpacity(0.2),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentEvents(GlassThemeData theme) {
    final recentEvents = _health.recentEvents.take(10).toList();
    if (recentEvents.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Events',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...recentEvents.map((event) => _buildEventItem(event, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildEventItem(FeedHealthEvent event, GlassThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: event.success
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: event.success
              ? Colors.green.withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            event.success ? Icons.check_circle : Icons.error,
            color: event.success ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.success ? 'Successful fetch' : 'Failed fetch',
                  style: theme.bodyMedium,
                ),
                if (event.error != null)
                  Text(
                    event.error!,
                    style: theme.bodySmall.copyWith(
                      color: Colors.red,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${event.responseTime.inMilliseconds}ms',
                style: theme.bodySmall,
              ),
              Text(
                _formatTime(event.timestamp),
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}