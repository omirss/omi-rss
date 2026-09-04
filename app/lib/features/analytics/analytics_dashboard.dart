import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/analytics_provider.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_snack_bar.dart';
import '../../ui/glass_theme.dart';
import '../../ui/screens/glass_screen.dart';
import '../../ui/tokens/glass_tokens.dart';
import 'analytics_service.dart';
import 'widgets/activity_heatmap.dart';
import 'widgets/category_chart.dart';
import 'widgets/reading_stats_card.dart';
import 'widgets/streak_indicator.dart';

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
    final tokens = screenTokensOf(context, ref);

    return GlassTheme(
      data: GlassThemeData.fromTokens(tokens),
      child: GlassSnackBarManager(
        child: Scaffold(
          backgroundColor: tokens.bgBase,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tokens.backgroundGradient,
              ),
            ),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  expandedHeight: 200,
                  floating: true,
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  foregroundColor: tokens.textHigh,
                  iconTheme: IconThemeData(color: tokens.textHigh),
                  title: Text(
                    'Analytics',
                    style: GlassTypeScale.title.copyWith(
                      color: tokens.textHigh,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [tokens.primary, tokens.secondary],
                        ),
                      ),
                      child: Center(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final analyticsAsync = ref.watch(
                                userAnalyticsProvider(selectedTimeframe));

                            return analyticsAsync.maybeWhen(
                              data: (analytics) {
                                final streak =
                                    analytics.reading?.readingStreak ?? 0;
                                if (streak > 0) {
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.local_fire_department,
                                        size: 48,
                                        color: tokens.textHigh,
                                      ),
                                      const SizedBox(height: GlassSpacing.sm),
                                      Text(
                                        '$streak Day Streak!',
                                        style: GlassTypeScale.display.copyWith(
                                          color: tokens.textHigh,
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
                    indicatorColor: tokens.accent,
                    labelColor: tokens.textHigh,
                    unselectedLabelColor: tokens.textMedium,
                  ),
                  actions: [
                    PopupMenuButton<String>(
                      icon: Icon(Icons.calendar_today,
                          color: tokens.textHigh),
                      onSelected: (value) {
                        ref.read(selectedTimeframeProvider.notifier).state =
                            value;
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'day',
                          child: Text('Today',
                              style: GlassTypeScale.label.copyWith(
                                  color: tokens.textHigh)),
                        ),
                        PopupMenuItem(
                          value: 'week',
                          child: Text('This Week',
                              style: GlassTypeScale.label.copyWith(
                                  color: tokens.textHigh)),
                        ),
                        PopupMenuItem(
                          value: 'month',
                          child: Text('This Month',
                              style: GlassTypeScale.label.copyWith(
                                  color: tokens.textHigh)),
                        ),
                        PopupMenuItem(
                          value: 'year',
                          child: Text('This Year',
                              style: GlassTypeScale.label.copyWith(
                                  color: tokens.textHigh)),
                        ),
                        PopupMenuItem(
                          value: 'all',
                          child: Text('All Time',
                              style: GlassTypeScale.label.copyWith(
                                  color: tokens.textHigh)),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.download, color: tokens.textHigh),
                      onPressed: _exportAnalytics,
                    ),
                  ],
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(tokens),
                  _buildActivityTab(tokens),
                  _buildInsightsTab(tokens),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(GlassColorTokens tokens) {
    final selectedTimeframe = ref.watch(selectedTimeframeProvider);
    final analyticsAsync = ref.watch(userAnalyticsProvider(selectedTimeframe));

    return analyticsAsync.when(
      data: (analytics) {
        return RefreshIndicator(
          color: tokens.accent,
          backgroundColor: tokens.bgBase,
          onRefresh: () async {
            ref.invalidate(userAnalyticsProvider);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(GlassSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReadingStatsCard(analytics: analytics),

                if (analytics.reading != null) ...[
                  const SizedBox(height: GlassSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: StreakIndicator(
                          title: 'Current Streak',
                          days: analytics.reading!.readingStreak,
                          icon: Icons.local_fire_department,
                          color: tokens.warning,
                        ),
                      ),
                      const SizedBox(width: GlassSpacing.lg),
                      Expanded(
                        child: StreakIndicator(
                          title: 'Longest Streak',
                          days: analytics.reading!.longestStreak,
                          icon: Icons.emoji_events,
                          color: tokens.accent,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: GlassSpacing.xl),
                ScreenSectionHeader(
                    title: 'Top Categories', tokens: tokens),
                CategoryChart(
                    data: ref.watch(categoryChartProvider(analytics))),
                const SizedBox(height: GlassSpacing.xl),

                if (analytics.engagement != null) ...[
                  ScreenSectionHeader(
                      title: 'Engagement Metrics', tokens: tokens),
                  _buildEngagementMetrics(analytics.engagement!, tokens),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => ScreenSkeleton(tokens: tokens),
      error: (error, stack) => ScreenErrorState(
        message: error.toString(),
        onRetry: () => ref.invalidate(userAnalyticsProvider),
        tokens: tokens,
      ),
    );
  }

  Widget _buildActivityTab(GlassColorTokens tokens) {
    final selectedTimeframe = ref.watch(selectedTimeframeProvider);
    final analyticsAsync = ref.watch(userAnalyticsProvider(selectedTimeframe));

    return analyticsAsync.when(
      data: (analytics) {
        if (analytics.patterns == null) {
          return ScreenEmptyState(
            icon: Icons.timeline_outlined,
            title: 'No activity data available',
            subtitle: 'Your reading activity will show up here',
            tokens: tokens,
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(GlassSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScreenSectionHeader(title: 'Reading Activity', tokens: tokens),
              ActivityHeatmap(
                hourlyData:
                    ref.watch(hourlyActivityChartProvider(analytics)),
                weeklyData:
                    ref.watch(weeklyActivityChartProvider(analytics)),
              ),
              const SizedBox(height: GlassSpacing.xl),

              if (analytics.patterns!.monthlyTrend.length > 1) ...[
                ScreenSectionHeader(title: 'Reading Trends', tokens: tokens),
                _buildTrendsChart(
                    analytics.patterns!.monthlyTrend, tokens),
              ],
            ],
          ),
        );
      },
      loading: () => ScreenLoading(tokens: tokens),
      error: (error, stack) => ScreenErrorState(
        message: error.toString(),
        onRetry: () => ref.invalidate(userAnalyticsProvider),
        tokens: tokens,
      ),
    );
  }

  Widget _buildInsightsTab(GlassColorTokens tokens) {
    final selectedTimeframe = ref.watch(selectedTimeframeProvider);
    final analyticsAsync = ref.watch(userAnalyticsProvider(selectedTimeframe));

    return analyticsAsync.when(
      data: (analytics) {
        if (analytics.insights.isEmpty) {
          return ScreenEmptyState(
            icon: Icons.lightbulb_outline,
            title: 'No insights available yet',
            subtitle: 'Keep reading to generate personalized insights',
            tokens: tokens,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(GlassSpacing.lg),
          itemCount: analytics.insights.length,
          itemBuilder: (context, index) {
            return GlassContainer(
              margin: const EdgeInsets.only(bottom: GlassSpacing.md),
              padding: const EdgeInsets.all(GlassSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.lightbulb, color: tokens.warning, size: 22),
                  const SizedBox(width: GlassSpacing.md),
                  Expanded(
                    child: Text(
                      analytics.insights[index],
                      style: GlassTypeScale.label
                          .copyWith(color: tokens.textHigh),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => ScreenLoading(tokens: tokens),
      error: (error, stack) => ScreenErrorState(
        message: error.toString(),
        onRetry: () => ref.invalidate(userAnalyticsProvider),
        tokens: tokens,
      ),
    );
  }

  Widget _buildEngagementMetrics(
      EngagementMetrics metrics, GlassColorTokens tokens) {
    return GlassContainer(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: Column(
        children: [
          _buildMetricRow(
            'Avg. Time Per Paragraph',
            '${metrics.averageTimePerParagraph.toStringAsFixed(1)} min',
            Icons.timelapse,
            tokens,
          ),
          Divider(color: tokens.glassStroke),
          _buildMetricRow(
            'Bookmark Rate',
            '${metrics.bookmarkRate.toStringAsFixed(0)}%',
            Icons.bookmark,
            tokens,
          ),
          Divider(color: tokens.glassStroke),
          _buildMetricRow(
            'Interaction Score',
            '${metrics.interactionScore.toStringAsFixed(0)}/100',
            Icons.bolt,
            tokens,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(
      String label, String value, IconData icon, GlassColorTokens tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GlassSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 24, color: tokens.textMedium),
          const SizedBox(width: GlassSpacing.md),
          Expanded(
            child: Text(
              label,
              style: GlassTypeScale.body.copyWith(
                color: tokens.textMedium,
              ),
            ),
          ),
          Text(
            value,
            style: GlassTypeScale.body.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.textHigh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsChart(
      List<DateCount> monthlyTrend, GlassColorTokens tokens) {
    final spots = monthlyTrend.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.count.toDouble());
    }).toList();

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= monthlyTrend.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: GlassSpacing.xs),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        monthlyTrend[index].date.substring(5),
                        style: GlassTypeScale.caption.copyWith(
                          fontSize: 9,
                          color: tokens.textLow,
                        ),
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
              color: tokens.accent,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: tokens.accent.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAnalytics() async {
    try {
      await ref.read(exportAnalyticsProvider.future);
      if (mounted) {
        context.showSuccessSnackBar('Analytics data exported successfully');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to export analytics: $e');
      }
    }
  }
}
