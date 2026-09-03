import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/analytics_provider.dart';
import 'widgets/reading_stats_card.dart';
import 'widgets/streak_indicator.dart';
import 'widgets/category_chart.dart';
import 'widgets/activity_heatmap.dart';
import 'widgets/recommendations_list.dart';
import 'widgets/insights_carousel.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_button.dart';
import '../../ui/components/glass_dialog.dart';
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
    _tabController = TabController(length: 4, vsync: this);
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
                            if (analytics.readingPatterns?.currentStreak != null) {
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
                                    '${analytics.readingPatterns!.currentStreak!.days} Day Streak!',
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
                  Tab(text: 'Recommendations', icon: Icon(Icons.recommend)),
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
              _buildRecommendationsTab(),
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
                if (analytics.readingPatterns?.currentStreak != null ||
                    analytics.readingPatterns?.longestStreak != null) ...[
                  Row(
                    children: [
                      if (analytics.readingPatterns?.currentStreak != null)
                        Expanded(
                          child: StreakIndicator(
                            title: 'Current Streak',
                            streak: analytics.readingPatterns!.currentStreak!,
                            icon: Icons.local_fire_department,
                            color: Colors.orange,
                          ),
                        ),
                      if (analytics.readingPatterns?.currentStreak != null &&
                          analytics.readingPatterns?.longestStreak != null)
                        const SizedBox(width: 16),
                      if (analytics.readingPatterns?.longestStreak != null)
                        Expanded(
                          child: StreakIndicator(
                            title: 'Longest Streak',
                            streak: analytics.readingPatterns!.longestStreak!,
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
                if (analytics.engagementMetrics != null) ...[
                  Text(
                    'Engagement Metrics',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildEngagementMetrics(analytics.engagementMetrics!),
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
        if (analytics.readingPatterns == null) {
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

              // Peak Hours
              if (analytics.readingPatterns!.peakHours.isNotEmpty) ...[
                Text(
                  'Peak Reading Hours',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: analytics.readingPatterns!.peakHours
                      .map((hour) => Chip(
                            label: Text(hour),
                            avatar: const Icon(Icons.access_time, size: 16),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Reading Trends
              if (analytics.readingPatterns!.trends.isNotEmpty) ...[
                Text(
                  'Reading Trends',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTrendsChart(analytics.readingPatterns!.trends),
              ],

              // Compare with Others
              const SizedBox(height: 24),
              Center(
                child: GlassButton(
                  onPressed: _compareWithOthers,
                  icon: Icons.compare,
                  text: 'Compare with Other Readers',
                  variant: GlassButtonVariant.elevated,
                ),
              ),
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
    final insightsAsync = ref.watch(insightsProvider('all'));

    return insightsAsync.when(
      data: (insights) {
        if (insights.isEmpty) {
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

        return InsightsCarousel(insights: insights);
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

  Widget _buildRecommendationsTab() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Articles'),
              Tab(text: 'Feeds'),
              Tab(text: 'Mixed'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final recommendationsAsync = ref.watch(
                      recommendationsProvider(RecommendationQuery(type: 'articles')),
                    );
                    return recommendationsAsync.when(
                      data: (recommendations) => RecommendationsList(
                        recommendations: recommendations,
                        onRefresh: () => ref.invalidate(recommendationsProvider),
                      ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, stack) => Center(
                        child: Text(
                          'Failed to load recommendations',
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                      ),
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final recommendationsAsync = ref.watch(
                      recommendationsProvider(RecommendationQuery(type: 'feeds')),
                    );
                    return recommendationsAsync.when(
                      data: (recommendations) => RecommendationsList(
                        recommendations: recommendations,
                        onRefresh: () => ref.invalidate(recommendationsProvider),
                      ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, stack) => Center(
                        child: Text(
                          'Failed to load recommendations',
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                      ),
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final recommendationsAsync = ref.watch(
                      recommendationsProvider(RecommendationQuery(type: 'mixed')),
                    );
                    return recommendationsAsync.when(
                      data: (recommendations) => RecommendationsList(
                        recommendations: recommendations,
                        onRefresh: () => ref.invalidate(recommendationsProvider),
                      ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, stack) => Center(
                        child: Text(
                          'Failed to load recommendations',
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngagementMetrics(EngagementMetrics metrics) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMetricRow(
            'Avg. Scroll Depth',
            '${metrics.averageScrollDepth.toStringAsFixed(0)}%',
            Icons.vertical_align_bottom,
          ),
          const Divider(color: Colors.white24),
          _buildMetricRow(
            'Bookmark Rate',
            '${(metrics.bookmarkRate * 100).toStringAsFixed(1)}%',
            Icons.bookmark,
          ),
          const Divider(color: Colors.white24),
          _buildMetricRow(
            'Share Rate',
            '${(metrics.shareRate * 100).toStringAsFixed(1)}%',
            Icons.share,
          ),
          const Divider(color: Colors.white24),
          _buildMetricRow(
            'Completion Rate',
            '${(metrics.completionRate * 100).toStringAsFixed(1)}%',
            Icons.check_circle,
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

  Widget _buildTrendsChart(Map<String, double> trends) {
    final spots = trends.entries.map((entry) {
      final index = trends.keys.toList().indexOf(entry.key);
      return FlSpot(index.toDouble(), entry.value);
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
                getTitlesWidget: (value, meta) {
                  final labels = trends.keys.toList();
                  if (value.toInt() < labels.length) {
                    return Text(
                      labels[value.toInt()],
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    );
                  }
                  return const SizedBox.shrink();
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
    final exportAsync = await ref.read(exportAnalyticsProvider.future);
    
    if (mounted) {
      context.showSuccessSnackBar('Analytics data exported successfully');
    }
  }

  Future<void> _compareWithOthers() async {
    final comparisonAsync = await ref.read(comparisonProvider.future);
    
    if (mounted) {
      showGlassDialog(
        context: context,
        title: const Text('How You Compare'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildComparisonItem(
                'Reading Time',
                comparisonAsync['percentile']?['readingTime']?.toString() ?? '0',
              ),
              _buildComparisonItem(
                'Articles Read',
                comparisonAsync['percentile']?['articlesRead']?.toString() ?? '0',
              ),
              _buildComparisonItem(
                'Streak',
                comparisonAsync['percentile']?['streak']?.toString() ?? '0',
              ),
            ],
          ),
        ),
        actions: [
          GlassButton(
            onPressed: () => Navigator.pop(context),
            text: 'Close',
            variant: GlassButtonVariant.text,
          ),
        ],
      );
    }
  }

  Widget _buildComparisonItem(String label, String percentile) {
    final value = double.tryParse(percentile) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.8)),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: value / 100,
            backgroundColor: Colors.grey[300]?.withOpacity(0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Top ${(100 - value).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}