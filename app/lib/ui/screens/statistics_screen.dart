import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/reading_statistics.dart';
import '../../providers/statistics_provider.dart';
import '../components/glass_card.dart';
import '../components/glass_container.dart';
import '../tokens/glass_tokens.dart';
import 'glass_screen.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticsAsync = ref.watch(readingStatisticsProvider);
    final tokens = screenTokensOf(context, ref);

    return GlassScreen(
      title: 'Reading Statistics',
      body: statisticsAsync.when(
        data: (statistics) {
          if (statistics.totalArticlesRead == 0) {
            return ScreenEmptyState(
              icon: Icons.query_stats_outlined,
              title: 'No reading data yet',
              subtitle:
                  'Read a few articles and your statistics will appear here',
              tokens: tokens,
            );
          }
          return _buildStatisticsContent(context, statistics, tokens);
        },
        loading: () => ScreenSkeleton(tokens: tokens),
        error: (error, stack) => ScreenErrorState(
          message: error.toString(),
          onRetry: () => ref.refresh(readingStatisticsProvider),
          tokens: tokens,
        ),
      ),
    );
  }

  Widget _buildStatisticsContent(
      BuildContext context, ReadingStatistics stats, GlassColorTokens tokens) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GlassSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewSection(stats, tokens),

          const SizedBox(height: GlassSpacing.xxl),

          ScreenSectionHeader(title: 'Reading Activity', tokens: tokens),
          GlassContainer(
            padding: const EdgeInsets.all(GlassSpacing.xl),
            child: SizedBox(
              height: 250,
              child: _buildReadingActivityChart(stats, tokens),
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 100.ms),

          const SizedBox(height: GlassSpacing.xxl),

          ScreenSectionHeader(title: 'Top Sources', tokens: tokens),
          _buildTopSourcesList(stats, tokens),

          const SizedBox(height: GlassSpacing.xxl),

          ScreenSectionHeader(
              title: 'Reading Time Distribution', tokens: tokens),
          GlassContainer(
            padding: const EdgeInsets.all(GlassSpacing.xl),
            child: SizedBox(
              height: 250,
              child: _buildTimeDistributionChart(stats, tokens),
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 300.ms),

          const SizedBox(height: GlassSpacing.xxl),

          ScreenSectionHeader(title: 'Reading Habits', tokens: tokens),
          _buildReadingHabits(stats, tokens),
        ],
      ),
    );
  }

  Widget _buildOverviewSection(
      ReadingStatistics stats, GlassColorTokens tokens) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: GlassSpacing.lg,
      crossAxisSpacing: GlassSpacing.lg,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Articles Read',
          stats.totalArticlesRead.toString(),
          Icons.article,
          tokens.primaryGradient,
          tokens,
        ).animate().fadeIn(duration: 300.ms),
        _buildStatCard(
          'Reading Streak',
          '${stats.currentStreak} days',
          Icons.local_fire_department,
          stats.currentStreak > 0
              ? [tokens.warning, tokens.error]
              : [tokens.textLow, tokens.textMedium],
          tokens,
        ).animate().fadeIn(duration: 300.ms, delay: 50.ms),
        _buildStatCard(
          'Avg. Daily',
          stats.averageArticlesPerDay.toStringAsFixed(1),
          Icons.trending_up,
          [tokens.primary, tokens.secondary],
          tokens,
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
        _buildStatCard(
          'Total Time',
          _formatReadingTime(stats.totalReadingTime),
          Icons.timer,
          tokens.accentGradient,
          tokens,
        ).animate().fadeIn(duration: 300.ms, delay: 150.ms),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon,
      List<Color> gradient, GlassColorTokens tokens) {
    return GlassCard(
      elevation: 2,
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(GlassRadii.md),
            ),
            child: Icon(icon, color: tokens.textHigh, size: 24),
          ),
          const SizedBox(height: GlassSpacing.md),
          Text(
            value,
            style: GlassTypeScale.display.copyWith(
              fontSize: 24,
              color: tokens.textHigh,
            ),
          ),
          const SizedBox(height: GlassSpacing.xs),
          Text(
            title,
            style:
                GlassTypeScale.label.copyWith(color: tokens.textMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingActivityChart(
      ReadingStatistics stats, GlassColorTokens tokens) {
    final spots = stats.dailyReadingData
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.toDouble()))
        .toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: tokens.glassStroke,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 10,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GlassTypeScale.caption
                      .copyWith(color: tokens.textLow),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              getTitlesWidget: (value, meta) {
                final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                final index = value.toInt() % 7;
                return Padding(
                  padding: const EdgeInsets.only(top: GlassSpacing.sm),
                  child: Text(
                    days[index],
                    style: GlassTypeScale.caption
                        .copyWith(color: tokens.textLow),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: LinearGradient(colors: tokens.primaryGradient),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: tokens.bgBase,
                  strokeWidth: 2,
                  strokeColor: tokens.primaryGradient[0],
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: tokens.primaryGradient
                    .map((color) => color.withValues(alpha: 0.15))
                    .toList(),
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSourcesList(
      ReadingStatistics stats, GlassColorTokens tokens) {
    if (stats.topSources.isEmpty) {
      return GlassContainer(
        padding: const EdgeInsets.all(GlassSpacing.xl),
        child: Text(
          'Read articles from your feeds to rank them here',
          style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
        ),
      );
    }

    return Column(
      children: stats.topSources
          .take(5)
          .map((source) => GlassContainer(
                margin: const EdgeInsets.only(bottom: GlassSpacing.md),
                padding: const EdgeInsets.all(GlassSpacing.lg),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tokens.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(GlassRadii.sm),
                      ),
                      child: Icon(
                        Icons.rss_feed,
                        color: tokens.textMedium,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: GlassSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.feedTitle,
                            style: GlassTypeScale.body.copyWith(
                              color: tokens.textHigh,
                            ),
                          ),
                          const SizedBox(height: GlassSpacing.xs),
                          Text(
                            '${source.articlesRead} articles • ${source.readingTime} min',
                            style: GlassTypeScale.label.copyWith(
                              color: tokens.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 60,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        borderRadius: BorderRadius.circular(GlassRadii.md),
                      ),
                      child: Text(
                        '${source.percentage}%',
                        style: GlassTypeScale.label.copyWith(
                          color: tokens.textHigh,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ))
          .toList()
          .animate(interval: 50.ms)
          .fadeIn(duration: 300.ms),
    );
  }

  Widget _buildTimeDistributionChart(
      ReadingStatistics stats, GlassColorTokens tokens) {
    final hasDistribution = stats.timeDistribution.values.any((v) => v > 0);
    if (!hasDistribution) {
      return Center(
        child: Text(
          'No reading time recorded yet',
          style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
        ),
      );
    }

    final sections = stats.timeDistribution.entries
        .map((entry) => PieChartSectionData(
              color: _getColorForTimeSlot(entry.key, tokens),
              value: entry.value.toDouble(),
              title: '${entry.value}%',
              radius: 80,
              titleStyle: GlassTypeScale.label.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ))
        .toList();

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 40,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(width: GlassSpacing.xl),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: stats.timeDistribution.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: GlassSpacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _getColorForTimeSlot(entry.key, tokens),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: GlassSpacing.sm),
                  Text(
                    entry.key,
                    style: GlassTypeScale.label.copyWith(
                      color: tokens.textMedium,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildReadingHabits(
      ReadingStatistics stats, GlassColorTokens tokens) {
    return GlassContainer(
      padding: const EdgeInsets.all(GlassSpacing.xl),
      child: Column(
        children: [
          ScreenListRow(
            icon: Icons.calendar_today,
            title: 'Most Active Day',
            subtitle: stats.mostActiveDay,
            tokens: tokens,
          ),
          Divider(color: tokens.glassStroke, height: GlassSpacing.xxl),
          ScreenListRow(
            icon: Icons.access_time,
            title: 'Peak Reading Time',
            subtitle: stats.peakReadingTime,
            tokens: tokens,
          ),
          Divider(color: tokens.glassStroke, height: GlassSpacing.xxl),
          ScreenListRow(
            icon: Icons.format_size,
            title: 'Avg. Article Length',
            subtitle: '${stats.averageArticleLength} words',
            tokens: tokens,
          ),
          Divider(color: tokens.glassStroke, height: GlassSpacing.xxl),
          ScreenListRow(
            icon: Icons.speed,
            title: 'Reading Speed',
            subtitle: '${stats.readingSpeed} wpm',
            tokens: tokens,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 400.ms);
  }

  String _formatReadingTime(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '$hours h ${mins > 0 ? '$mins min' : ''}';
    }
  }

  Color _getColorForTimeSlot(String timeSlot, GlassColorTokens tokens) {
    switch (timeSlot) {
      case 'Morning':
        return tokens.warning;
      case 'Afternoon':
        return tokens.accent;
      case 'Evening':
        return tokens.secondary;
      case 'Night':
        return tokens.primary;
      default:
        return tokens.textLow;
    }
  }
}
