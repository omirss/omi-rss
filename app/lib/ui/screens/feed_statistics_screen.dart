import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/feed_statistics.dart';
import '../../providers/statistics_provider.dart';
import '../components/glass_card.dart';
import '../components/glass_container.dart';
import '../tokens/glass_tokens.dart';
import 'glass_screen.dart';

/// Feed statistics dashboard screen
class FeedStatisticsScreen extends ConsumerStatefulWidget {
  final String? feedId;
  final String? categoryId;

  const FeedStatisticsScreen({
    super.key,
    this.feedId,
    this.categoryId,
  });

  @override
  ConsumerState<FeedStatisticsScreen> createState() =>
      _FeedStatisticsScreenState();
}

class _FeedStatisticsScreenState extends ConsumerState<FeedStatisticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statisticsAsync = widget.feedId != null
        ? ref.watch(feedStatisticsProvider(widget.feedId!))
        : ref.watch(aggregatedStatisticsProvider(widget.categoryId));
    final tokens = screenTokensOf(context, ref);

    return GlassScreen(
      title: widget.feedId != null ? 'Feed Statistics' : 'Overall Statistics',
      appBarBottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
          Tab(text: 'Trends', icon: Icon(Icons.trending_up)),
          Tab(text: 'Performance', icon: Icon(Icons.speed)),
          Tab(text: 'Reading', icon: Icon(Icons.chrome_reader_mode)),
        ],
        indicatorColor: tokens.accent,
        labelColor: tokens.textHigh,
        unselectedLabelColor: tokens.textMedium,
      ),
      body: statisticsAsync.when(
        data: (statistics) => TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(statistics, tokens),
            _buildTrendsTab(statistics, tokens),
            _buildPerformanceTab(statistics, tokens),
            _buildReadingTab(tokens),
          ],
        ),
        loading: () => ScreenSkeleton(tokens: tokens),
        error: (error, stack) => ScreenErrorState(
          message: error.toString(),
          onRetry: () {
            if (widget.feedId != null) {
              ref.invalidate(feedStatisticsProvider(widget.feedId!));
            } else {
              ref.invalidate(
                  aggregatedStatisticsProvider(widget.categoryId));
            }
          },
          tokens: tokens,
        ),
      ),
    );
  }

  Widget _buildOverviewTab(dynamic statistics, GlassColorTokens tokens) {
    if (statistics is FeedStatistics) {
      return _buildFeedOverview(statistics, tokens);
    } else if (statistics is AggregatedStatistics) {
      return _buildAggregatedOverview(statistics, tokens);
    }
    return const SizedBox();
  }

  Widget _buildFeedOverview(
      FeedStatistics stats, GlassColorTokens tokens) {
    return ListView(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Articles',
                stats.totalArticles.toString(),
                Icons.article,
                tokens.primary,
                tokens,
              ),
            ),
            const SizedBox(width: GlassSpacing.lg),
            Expanded(
              child: _buildMetricCard(
                'Unread',
                stats.unreadArticles.toString(),
                Icons.mark_email_unread,
                tokens.warning,
                tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: GlassSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Articles/Day',
                stats.articlesPerDay.toStringAsFixed(1),
                Icons.calendar_today,
                tokens.accent,
                tokens,
              ),
            ),
            const SizedBox(width: GlassSpacing.lg),
            Expanded(
              child: _buildMetricCard(
                'Read Rate',
                '${(stats.readRate * 100).toStringAsFixed(0)}%',
                Icons.check_circle,
                tokens.success,
                tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: GlassSpacing.xl),

        GlassCard(
          padding: const EdgeInsets.all(GlassSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Articles by Hour',
                style:
                    GlassTypeScale.label.copyWith(color: tokens.textHigh),
              ),
              const SizedBox(height: GlassSpacing.lg),
              SizedBox(
                height: 200,
                child: _buildHourlyChart(stats.articlesByHour, tokens),
              ),
            ],
          ),
        ),
        const SizedBox(height: GlassSpacing.lg),

        GlassCard(
          padding: const EdgeInsets.all(GlassSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Articles by Day of Week',
                style:
                    GlassTypeScale.label.copyWith(color: tokens.textHigh),
              ),
              const SizedBox(height: GlassSpacing.lg),
              SizedBox(
                height: 200,
                child:
                    _buildDayOfWeekChart(stats.articlesByDayOfWeek, tokens),
              ),
            ],
          ),
        ),
        const SizedBox(height: GlassSpacing.lg),

        if (stats.topKeywords.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(GlassSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Keywords',
                  style: GlassTypeScale.label
                      .copyWith(color: tokens.textHigh),
                ),
                const SizedBox(height: GlassSpacing.lg),
                Wrap(
                  spacing: GlassSpacing.sm,
                  runSpacing: GlassSpacing.sm,
                  children: stats.topKeywords.map((keyword) {
                    return Chip(
                      label: Text(
                        keyword,
                        style: GlassTypeScale.caption
                            .copyWith(color: tokens.textHigh),
                      ),
                      backgroundColor:
                          tokens.primary.withValues(alpha: 0.2),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: GlassSpacing.lg),
        ],

        if (stats.topAuthors.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(GlassSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Authors',
                  style: GlassTypeScale.label
                      .copyWith(color: tokens.textHigh),
                ),
                const SizedBox(height: GlassSpacing.lg),
                ...stats.topAuthors.map((author) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          tokens.accent.withValues(alpha: 0.3),
                      child: Text(
                        author[0].toUpperCase(),
                        style: GlassTypeScale.caption
                            .copyWith(color: tokens.textHigh),
                      ),
                    ),
                    title: Text(
                      author,
                      style: GlassTypeScale.body
                          .copyWith(color: tokens.textHigh),
                    ),
                    contentPadding: EdgeInsets.zero,
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAggregatedOverview(
      AggregatedStatistics stats, GlassColorTokens tokens) {
    return ListView(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Feeds',
                stats.totalFeeds.toString(),
                Icons.rss_feed,
                tokens.primary,
                tokens,
              ),
            ),
            const SizedBox(width: GlassSpacing.lg),
            Expanded(
              child: _buildMetricCard(
                'Active Feeds',
                stats.activeFeeds.toString(),
                Icons.play_circle,
                tokens.success,
                tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: GlassSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Articles',
                _formatNumber(stats.totalArticles),
                Icons.article,
                tokens.accent,
                tokens,
              ),
            ),
            const SizedBox(width: GlassSpacing.lg),
            Expanded(
              child: _buildMetricCard(
                'Unread',
                _formatNumber(stats.unreadArticles),
                Icons.mark_email_unread,
                tokens.warning,
                tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: GlassSpacing.xl),

        if (stats.articlesByCategory.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(GlassSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Articles by Category',
                  style: GlassTypeScale.label
                      .copyWith(color: tokens.textHigh),
                ),
                const SizedBox(height: GlassSpacing.lg),
                SizedBox(
                  height: 200,
                  child: _buildPieChart(
                      stats.articlesByCategory
                          .map((k, v) => MapEntry(k, v.toDouble())),
                      tokens),
                ),
              ],
            ),
          ),
          const SizedBox(height: GlassSpacing.lg),
        ],

        if (stats.topPerformingFeeds.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(GlassSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Performing Feeds',
                  style: GlassTypeScale.label
                      .copyWith(color: tokens.textHigh),
                ),
                const SizedBox(height: GlassSpacing.lg),
                ...stats.topPerformingFeeds.map((feed) {
                  return ListTile(
                    title: Text(
                      feed.feedTitle,
                      style: GlassTypeScale.body
                          .copyWith(color: tokens.textHigh),
                    ),
                    subtitle: Text(
                      '${feed.articlesPerDay.toStringAsFixed(1)} articles/day',
                      style: GlassTypeScale.label
                          .copyWith(color: tokens.textMedium),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: GlassSpacing.sm,
                          vertical: GlassSpacing.xs),
                      decoration: BoxDecoration(
                        color: tokens.success.withValues(alpha: 0.2),
                        borderRadius:
                            BorderRadius.circular(GlassRadii.md),
                      ),
                      child: Text(
                        '${(feed.healthScore * 100).toStringAsFixed(0)}%',
                        style: GlassTypeScale.label
                            .copyWith(color: tokens.success),
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: GlassSpacing.lg),
        ],

        if (stats.worstPerformingFeeds.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(GlassSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feeds Needing Attention',
                  style: GlassTypeScale.label
                      .copyWith(color: tokens.textHigh),
                ),
                const SizedBox(height: GlassSpacing.lg),
                ...stats.worstPerformingFeeds.map((feed) {
                  return ListTile(
                    title: Text(
                      feed.feedTitle,
                      style: GlassTypeScale.body
                          .copyWith(color: tokens.textHigh),
                    ),
                    subtitle: Text(
                      feed.lastSuccessfulUpdate != null
                          ? 'Last updated ${_formatRelativeTime(feed.lastSuccessfulUpdate!)}'
                          : 'Never updated successfully',
                      style: GlassTypeScale.label
                          .copyWith(color: tokens.textMedium),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: GlassSpacing.sm,
                          vertical: GlassSpacing.xs),
                      decoration: BoxDecoration(
                        color: tokens.error.withValues(alpha: 0.2),
                        borderRadius:
                            BorderRadius.circular(GlassRadii.md),
                      ),
                      child: Text(
                        '${(feed.healthScore * 100).toStringAsFixed(0)}%',
                        style: GlassTypeScale.label
                            .copyWith(color: tokens.error),
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrendsTab(dynamic statistics, GlassColorTokens tokens) {
    final Map<DateTime, int> articlesOverTime;

    if (statistics is FeedStatistics) {
      articlesOverTime = {};
      statistics.articlesByMonth.forEach((monthKey, count) {
        final parts = monthKey.split('-');
        final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), 15);
        articlesOverTime[date] = count;
      });
    } else if (statistics is AggregatedStatistics) {
      articlesOverTime = statistics.articlesOverTime;
    } else {
      articlesOverTime = {};
    }

    return ListView(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(GlassSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Articles Over Time',
                style:
                    GlassTypeScale.label.copyWith(color: tokens.textHigh),
              ),
              const SizedBox(height: GlassSpacing.lg),
              SizedBox(
                height: 300,
                child: articlesOverTime.isEmpty
                    ? ScreenEmptyState(
                        icon: Icons.show_chart_outlined,
                        title: 'No trend data yet',
                        subtitle:
                            'Trends appear once your feeds publish new articles',
                        tokens: tokens,
                      )
                    : _buildTimelineChart(articlesOverTime, tokens),
              ),
            ],
          ),
        ),
        const SizedBox(height: GlassSpacing.lg),

        GlassCard(
          padding: const EdgeInsets.all(GlassSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Averages',
                style:
                    GlassTypeScale.label.copyWith(color: tokens.textHigh),
              ),
              const SizedBox(height: GlassSpacing.lg),
              _buildCurrentAverages(statistics, tokens),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentAverages(
      dynamic statistics, GlassColorTokens tokens) {
    final double readRate;
    final String dailyAverage;

    if (statistics is FeedStatistics) {
      readRate = statistics.readRate;
      dailyAverage = statistics.articlesPerDay.toStringAsFixed(1);
    } else if (statistics is AggregatedStatistics) {
      final total = statistics.totalArticles;
      readRate =
          total > 0 ? (total - statistics.unreadArticles) / total : 0;
      dailyAverage = statistics.totalFeeds > 0
          ? (total / statistics.totalFeeds).toStringAsFixed(1)
          : '0.0';
    } else {
      readRate = 0;
      dailyAverage = '0.0';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildTrendIndicator(
          'Read Rate',
          '${(readRate * 100).toStringAsFixed(0)}%',
          Icons.visibility,
          tokens.textMedium,
          tokens,
        ),
        _buildTrendIndicator(
          'Avg. Articles',
          dailyAverage,
          Icons.article_outlined,
          tokens.textMedium,
          tokens,
        ),
      ],
    );
  }

  Widget _buildPerformanceTab(
      dynamic statistics, GlassColorTokens tokens) {
    if (statistics is AggregatedStatistics) {
      if (statistics.healthByCategory.isEmpty) {
        return ScreenEmptyState(
          icon: Icons.speed_outlined,
          title: 'No performance data yet',
          subtitle: 'Feed health appears after a few refresh cycles',
          tokens: tokens,
        );
      }

      return ListView(
        padding: const EdgeInsets.all(GlassSpacing.lg),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(GlassSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Health by Category',
                  style: GlassTypeScale.label
                      .copyWith(color: tokens.textHigh),
                ),
                const SizedBox(height: GlassSpacing.lg),
                ...statistics.healthByCategory.entries.map((entry) {
                  final health = entry.value;
                  final color = health > 0.8
                      ? tokens.success
                      : health > 0.5
                          ? tokens.warning
                          : tokens.error;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: GlassSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.key,
                              style: GlassTypeScale.body
                                  .copyWith(color: tokens.textHigh),
                            ),
                            Text(
                              '${(health * 100).toStringAsFixed(0)}%',
                              style: GlassTypeScale.label
                                  .copyWith(color: color),
                            ),
                          ],
                        ),
                        const SizedBox(height: GlassSpacing.xs),
                        LinearProgressIndicator(
                          value: health,
                          backgroundColor: tokens.glassStroke,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      );
    }

    return ScreenEmptyState(
      icon: Icons.speed_outlined,
      title: 'Performance data not available for individual feeds',
      subtitle: 'Open overall statistics to compare feed health',
      tokens: tokens,
    );
  }

  Widget _buildReadingTab(GlassColorTokens tokens) {
    final readingStatsAsync = ref.watch(detailedReadingStatisticsProvider);

    return readingStatsAsync.when(
      data: (stats) {
        if (stats.streaks.isEmpty &&
            stats.readingTimeByCategory.isEmpty &&
            stats.articlesReadToday == 0) {
          return ScreenEmptyState(
            icon: Icons.chrome_reader_mode_outlined,
            title: 'No reading history yet',
            subtitle: 'Read a few articles to build your reading profile',
            tokens: tokens,
          );
        }

        return ListView(
          padding: const EdgeInsets.all(GlassSpacing.lg),
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Read Today',
                    stats.articlesReadToday.toString(),
                    Icons.today,
                    tokens.primary,
                    tokens,
                  ),
                ),
                const SizedBox(width: GlassSpacing.lg),
                Expanded(
                  child: _buildMetricCard(
                    'Time Today',
                    '${stats.totalReadingTimeToday} min',
                    Icons.timer,
                    tokens.accent,
                    tokens,
                  ),
                ),
              ],
            ),
            const SizedBox(height: GlassSpacing.lg),

            if (stats.streaks.isNotEmpty) ...[
              GlassCard(
                padding: const EdgeInsets.all(GlassSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reading Streaks',
                      style: GlassTypeScale.label
                          .copyWith(color: tokens.textHigh),
                    ),
                    const SizedBox(height: GlassSpacing.lg),
                    ...stats.streaks.take(3).map((streak) {
                      return ListTile(
                        leading: Icon(
                          streak.isCurrent
                              ? Icons.local_fire_department
                              : Icons.check_circle,
                          color: streak.isCurrent
                              ? tokens.warning
                              : tokens.success,
                        ),
                        title: Text(
                          '${streak.daysCount} days',
                          style: GlassTypeScale.body
                              .copyWith(color: tokens.textHigh),
                        ),
                        subtitle: Text(
                          '${streak.articlesRead} articles • ${_formatDateRange(streak.startDate, streak.endDate)}',
                          style: GlassTypeScale.label
                              .copyWith(color: tokens.textMedium),
                        ),
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: GlassSpacing.lg),
            ],

            if (stats.readingTimeByCategory.isNotEmpty) ...[
              GlassCard(
                padding: const EdgeInsets.all(GlassSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reading Time by Category',
                      style: GlassTypeScale.label
                          .copyWith(color: tokens.textHigh),
                    ),
                    const SizedBox(height: GlassSpacing.lg),
                    SizedBox(
                      height: 200,
                      child: _buildPieChart(
                        stats.readingTimeByCategory
                            .map((k, v) => MapEntry(k, v.toDouble())),
                        tokens,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GlassSpacing.lg),
            ],

            GlassCard(
              padding: const EdgeInsets.all(GlassSpacing.lg),
              child: Row(
                children: [
                  Icon(Icons.speed, size: 48, color: tokens.accent),
                  const SizedBox(width: GlassSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Average Reading Speed',
                          style: GlassTypeScale.label
                              .copyWith(color: tokens.textHigh),
                        ),
                        const SizedBox(height: GlassSpacing.xs),
                        Text(
                          '${stats.averageReadingSpeed.toStringAsFixed(0)} words per minute',
                          style: GlassTypeScale.body.copyWith(
                            color: tokens.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => ScreenLoading(tokens: tokens),
      error: (error, stack) => ScreenErrorState(
        message: error.toString(),
        onRetry: () => ref.refresh(detailedReadingStatisticsProvider),
        tokens: tokens,
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
    GlassColorTokens tokens,
  ) {
    return GlassContainer(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: GlassSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: GlassTypeScale.caption
                      .copyWith(color: tokens.textMedium),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GlassSpacing.sm),
          Text(
            value,
            style: GlassTypeScale.display.copyWith(
              fontSize: 24,
              color: tokens.textHigh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyChart(
      Map<String, int> data, GlassColorTokens tokens) {
    final spots = <FlSpot>[];
    for (int hour = 0; hour < 24; hour++) {
      final hourStr = hour.toString().padLeft(2, '0');
      spots.add(FlSpot(hour.toDouble(), (data[hourStr] ?? 0).toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: tokens.glassStroke,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GlassTypeScale.caption
                      .copyWith(color: tokens.textLow),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GlassTypeScale.caption
                      .copyWith(color: tokens.textLow),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: tokens.accent,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: tokens.accent.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayOfWeekChart(
      Map<String, int> data, GlassColorTokens tokens) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return BarChart(
      BarChartData(
        barGroups: days.asMap().entries.map((entry) {
          final index = entry.key;
          final day = entry.value;
          final value = data[day] ?? 0;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: value.toDouble(),
                color: tokens.primary,
                width: 30,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                return Text(
                  days[value.toInt()],
                  style: GlassTypeScale.caption
                      .copyWith(color: tokens.textLow),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GlassTypeScale.caption
                      .copyWith(color: tokens.textLow),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildPieChart(
      Map<String, double> data, GlassColorTokens tokens) {
    final total = data.values.reduce((a, b) => a + b);
    if (total <= 0) {
      return Center(
        child: Text(
          'No data available',
          style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
        ),
      );
    }

    final colors = [
      tokens.primary,
      tokens.accent,
      tokens.secondary,
      tokens.warning,
      ...tokens.auroraColors,
    ];

    return PieChart(
      PieChartData(
        sections: data.entries.toList().asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final percentage = (item.value / total) * 100;

          return PieChartSectionData(
            color: colors[index % colors.length],
            value: item.value,
            title: '${percentage.toStringAsFixed(0)}%',
            radius: 70,
            titleStyle: GlassTypeScale.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          );
        }).toList(),
        sectionsSpace: 2,
        centerSpaceRadius: 40,
      ),
    );
  }

  Widget _buildTimelineChart(
      Map<DateTime, int> data, GlassColorTokens tokens) {
    final sortedEntries = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = sortedEntries.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value.toDouble());
    }).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: tokens.glassStroke,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (sortedEntries.length / 5).ceilToDouble(),
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= sortedEntries.length) {
                  return const SizedBox();
                }
                final date = sortedEntries[value.toInt()].key;
                return Text(
                  '${date.month}/${date.day}',
                  style: GlassTypeScale.caption
                      .copyWith(color: tokens.textLow),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GlassTypeScale.caption
                      .copyWith(color: tokens.textLow),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: tokens.accent,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 3,
                  color: tokens.accent,
                  strokeWidth: 1,
                  strokeColor: tokens.bgBase,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: tokens.accent.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendIndicator(
    String label,
    String value,
    IconData icon,
    Color color,
    GlassColorTokens tokens,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: GlassTypeScale.caption.copyWith(color: tokens.textMedium),
        ),
        const SizedBox(height: GlassSpacing.xs),
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: GlassSpacing.xs),
            Text(
              value,
              style: GlassTypeScale.label.copyWith(
                color: tokens.textHigh,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  String _formatDateRange(DateTime start, DateTime end) {
    String format(DateTime date) => '${date.month}/${date.day}';
    return '${format(start)} - ${format(end)}';
  }
}
