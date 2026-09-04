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
    final reading = analytics.reading;
    if (reading == null) {
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
                  reading.totalArticlesRead.toString(),
                  Theme.of(context).colorScheme.primary,
                ),
                _buildStatColumn(
                  context,
                  Icons.timer,
                  'Total Minutes',
                  reading.totalReadingTime.toString(),
                  Theme.of(context).colorScheme.secondary,
                ),
                _buildStatColumn(
                  context,
                  Icons.speed,
                  'Avg Minutes',
                  reading.averageReadingTime.toString(),
                  Theme.of(context).colorScheme.tertiary,
                ),
              ],
            ),
            if ((analytics.patterns?.monthlyTrend ?? []).isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Daily Reading Trend',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _buildDailyTrend(context, analytics.patterns!.monthlyTrend),
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
    List<DateCount> monthlyTrend,
  ) {
    final entries = monthlyTrend.length > 30
        ? monthlyTrend.sublist(monthlyTrend.length - 30)
        : monthlyTrend;
    final maxReading =
        entries.fold<int>(0, (a, b) => a > b.count ? a : b.count);

    return SizedBox(
      height: 60,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.map((entry) {
          final height = maxReading > 0
              ? (entry.count / maxReading) * 40 + 10
              : 10.0;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: '${entry.date}: ${entry.count} articles',
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
