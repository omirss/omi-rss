import 'package:flutter/material.dart';
import '../analytics_service.dart';

class ReadingStatsCard extends StatelessWidget {
  final UserAnalytics analytics;

  const ReadingStatsCard({
    super.key,
    required this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    final readingTime = analytics.readingTime;
    if (readingTime == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_stories,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Reading Statistics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  context,
                  Icons.article,
                  'Articles Read',
                  readingTime.articlesRead.toString(),
                  Theme.of(context).colorScheme.primary,
                ),
                _buildStatColumn(
                  context,
                  Icons.timer,
                  'Total Hours',
                  readingTime.totalTimeHours.toStringAsFixed(1),
                  Theme.of(context).colorScheme.secondary,
                ),
                _buildStatColumn(
                  context,
                  Icons.speed,
                  'Avg Minutes',
                  readingTime.averageTimeMinutes.toStringAsFixed(0),
                  Theme.of(context).colorScheme.tertiary,
                ),
              ],
            ),
            if (readingTime.dailyReading.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Daily Reading Trend',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _buildDailyTrend(context, readingTime.dailyReading),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 32),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildDailyTrend(
    BuildContext context,
    Map<String, int> dailyReading,
  ) {
    final maxReading = dailyReading.values.fold(0, (a, b) => a > b ? a : b);
    final entries = dailyReading.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return SizedBox(
      height: 60,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.take(7).map((entry) {
          final height = maxReading > 0
              ? (entry.value / maxReading) * 40 + 10
              : 10.0;
          
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: '${entry.key}: ${entry.value} articles',
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}