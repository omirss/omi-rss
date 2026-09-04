import 'package:flutter/material.dart';
import '../../../ui/components/glass_container.dart';
import '../../../ui/glass_theme.dart';
import '../../../ui/tokens/glass_tokens.dart';
import '../analytics_service.dart';

class ReadingStatsCard extends StatelessWidget {
  final UserAnalytics analytics;

  const ReadingStatsCard({
    super.key,
    required this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final reading = analytics.reading;
    if (reading == null) {
      return const SizedBox.shrink();
    }

    return GlassContainer(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories,
                color: theme.accentColor,
              ),
              const SizedBox(width: GlassSpacing.sm),
              Text('Reading Statistics', style: theme.titleMedium),
            ],
          ),
          const SizedBox(height: GlassSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatColumn(
                context,
                Icons.article,
                'Articles Read',
                reading.totalArticlesRead.toString(),
                theme.primaryColor,
              ),
              _buildStatColumn(
                context,
                Icons.timer,
                'Total Minutes',
                reading.totalReadingTime.toString(),
                theme.secondaryColor,
              ),
              _buildStatColumn(
                context,
                Icons.speed,
                'Avg Minutes',
                reading.averageReadingTime.toString(),
                theme.accentColor,
              ),
            ],
          ),
          if ((analytics.patterns?.monthlyTrend ?? []).isNotEmpty) ...[
            const SizedBox(height: GlassSpacing.xl),
            Text('Daily Reading Trend', style: theme.titleSmall),
            const SizedBox(height: GlassSpacing.md),
            _buildDailyTrend(context, analytics.patterns!.monthlyTrend),
          ],
        ],
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
    final theme = GlassTheme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(GlassSpacing.md),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 32),
        ),
        const SizedBox(height: GlassSpacing.sm),
        Text(
          value,
          style: GlassTypeScale.title.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(label, style: theme.bodySmall),
      ],
    );
  }

  Widget _buildDailyTrend(
    BuildContext context,
    List<DateCount> monthlyTrend,
  ) {
    final theme = GlassTheme.of(context);
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
                    color: theme.primaryColor,
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
