import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/analytics_provider.dart';
import 'analytics_service.dart';
import 'widgets/reading_stats_card.dart';
import 'widgets/streak_indicator.dart';
import 'widgets/category_chart.dart';
import 'widgets/activity_heatmap.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_button.dart';
import '../../ui/components/glass_snack_bar.dart';

class AnalyticsDashboard extends ConsumerStatefulWidget {
  const AnalyticsDashboard({super.key});

  @override
  ConsumerState<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends ConsumerState<AnalyticsDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTimeframe = ref.watch(selectedTimeframeProvider);

    return GlassTheme(
      data: GlassThemeData.defaultTheme,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 200,
              floating: true,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: const Text('Analytics'),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final analyticsAsync = ref.watch(userAnalyticsProvider(selectedTimeframe));

                        return analyticsAsync.maybeWhen(
                          data: (analytics) {
                            final streak = analytics.reading?.readingStreak ?? 0;
                            if (streak > 0) {
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.local_fire_department,
                                    size: 48,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$streak Day Streak!',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                          orElse: () => const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),
                ),
              ),
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
                  Tab(text: 'Activity', icon: Icon(Icons.timeline)),
                  Tab(text: 'Insights', icon: Icon(Icons.lightbulb)),
                ],
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.calendar_today),
                  onSelected: (value) {
                    ref.read(selectedTimeframeProvider.notifier).state = value;
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'day',
                      child: Text('Today', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                    PopupMenuItem(
                      value: 'week',
                      child: Text('This Week', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                    PopupMenuItem(
                      value: 'month',
                      child: Text('This Month', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                    PopupMenuItem(
                      value: 'year',
                      child: Text('This Year', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                    PopupMenuItem(
                      value: 'all',
                      child: Text('All Time', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _exportAnalytics,
                ),
              ],
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildActivityTab(),
              _buildInsightsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final selectedTimeframe = ref.watch(selectedTimeframeProvider);
    final analyticsAsync = ref.watch(userAnalyticsProvider(selectedTimeframe));

    return analyticsAsync.when(
      data: (analytics) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(userAnalyticsProvider);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reading Stats Overview
                ReadingStatsCard(analytics: analytics),
                const SizedBox(height: 16),

                // Streak Indicators
                if (analytics.reading != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: StreakIndicator(
                          title: 'Current Streak',
                          days: analytics.reading!.readingStreak,
                          icon: Icons.local_fire_department,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StreakIndicator(
                          title: 'Longest Streak',
                          days: analytics.reading!.longestStreak,
                          icon: Icons.emoji_events,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Category Distribution
                Text(
                  'Top Categories',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                CategoryChart(data: ref.watch(categoryChartProvider(analytics))),
                const SizedBox(height: 24),

                // Engagement Metrics
                if (analytics.engagement != null) ...[
                  Text(
                    'Engagement Metrics',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildEngagementMetrics(analytics.engagement!),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load analytics',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            GlassButton(
              onPressed: () => ref.invalidate(userAnalyticsProvider),
              text: 'Retry',
              variant: GlassButtonVariant.elevated,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTab() {
    final selectedTimeframe = ref.watch(selectedTimeframeProvider);
    final analyticsAsync = ref.watch(userAnalyticsProvider(selectedTimeframe));

    return analyticsAsync.maybeWhen(
      data: (analytics) {
        if (analytics.patterns == null) {
          return const Center(
            child: Text(
              'No activity data available',
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Activity Heatmap
              Text(
                'Reading Activity',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              ActivityHeatmap(
                hourlyData: ref.watch(hourlyActivityChartProvider(analytics)),
                weeklyData: ref.watch(weeklyActivityChartProvider(analytics)),
              ),
              const SizedBox(height: 24),

              // Reading Trends
              if (analytics.patterns!.monthlyTrend.length > 1) ...[
                Text(
                  'Reading Trends',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTrendsChart(analytics.patterns!.monthlyTrend),
              ],
            ],
          ),
        );
      },
      orElse: () => const Center(
        child: Text(
          'No activity data available',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildInsightsTab() {
    final selectedTimeframe = ref.watch(selectedTimeframeProvider);
    final analyticsAsync = ref.watch(userAnalyticsProvider(selectedTimeframe));

    return analyticsAsync.when(
      data: (analytics) {
        if (analytics.insights.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No insights available yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Keep reading to generate personalized insights',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: analytics.insights.length,
          itemBuilder: (context, index) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.lightbulb),
                title: Text(
                  analytics.insights[index],
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text(
          'Failed to load insights',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      ),
    );
  }

  Widget _buildEngagementMetrics(EngagementMetrics metrics) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMetricRow(
            'Avg. Time Per Paragraph',
            '${metrics.averageTimePerParagraph.toStringAsFixed(1)} min',
            Icons.timelapse,
          ),
          const Divider(color: Colors.white24),
          _buildMetricRow(
            'Bookmark Rate',
            '${metrics.bookmarkRate.toStringAsFixed(0)}%',
            Icons.bookmark,
          ),
          const Divider(color: Colors.white24),
          _buildMetricRow(
            'Interaction Score',
            '${metrics.interactionScore.toStringAsFixed(0)}/100',
            Icons.bolt,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: Colors.white.withOpacity(0.8)),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsChart(List<DateCount> monthlyTrend) {
    final spots = monthlyTrend.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.count.toDouble());
    }).toList();

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= monthlyTrend.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        monthlyTrend[index].date.substring(5),
                        style: const TextStyle(fontSize: 9, color: Colors.white70),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Theme.of(context).colorScheme.primary,
              barWidth: 3,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAnalytics() async {
    await ref.read(exportAnalyticsProvider.future);

    if (mounted) {
      context.showSuccessSnackBar('Analytics data exported successfully');
    }
  }
}
