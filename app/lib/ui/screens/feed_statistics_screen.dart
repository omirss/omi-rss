import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/models/feed_statistics.dart';
import '../../core/services/statistics_service.dart';
import '../../providers/statistics_provider.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../animations/loading_animation.dart';

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
  ConsumerState<FeedStatisticsScreen> createState() => _FeedStatisticsScreenState();
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
    final theme = GlassTheme.of(context);
    final statisticsAsync = widget.feedId != null
        ? ref.watch(feedStatisticsProvider(widget.feedId!))
        : ref.watch(aggregatedStatisticsProvider(widget.categoryId));
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.feedId != null ? 'Feed Statistics' : 'Overall Statistics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Trends', icon: Icon(Icons.trending_up)),
            Tab(text: 'Performance', icon: Icon(Icons.speed)),
            Tab(text: 'Reading', icon: Icon(Icons.chrome_reader_mode)),
          ],
          indicatorColor: theme.accentColor,
        ),
      ),
      body: statisticsAsync.when(
        data: (statistics) => TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(statistics, theme),
            _buildTrendsTab(statistics, theme),
            _buildPerformanceTab(statistics, theme),
            _buildReadingTab(theme),
          ],
        ),
        loading: () => const Center(child: LoadingAnimation()),
        error: (error, stack) => Center(
          child: Text(
            'Failed to load statistics: $error',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
  
  Widget _buildOverviewTab(dynamic statistics, GlassThemeData theme) {
    if (statistics is FeedStatistics) {
      return _buildFeedOverview(statistics, theme);
    } else if (statistics is AggregatedStatistics) {
      return _buildAggregatedOverview(statistics, theme);
    }
    return const SizedBox();
  }
  
  Widget _buildFeedOverview(FeedStatistics stats, GlassThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Key metrics
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Articles',
                stats.totalArticles.toString(),
                Icons.article,
                theme.primaryColor,
                theme,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'Unread',
                stats.unreadArticles.toString(),
                Icons.mark_email_unread,
                Colors.orange,
                theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Articles/Day',
                stats.articlesPerDay.toStringAsFixed(1),
                Icons.calendar_today,
                Colors.blue,
                theme,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'Read Rate',
                '${(stats.readRate * 100).toStringAsFixed(0)}%',
                Icons.check_circle,
                Colors.green,
                theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Articles by time
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Articles by Hour',
                style: theme.titleMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: _buildHourlyChart(stats.articlesByHour, theme),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Articles by day of week
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Articles by Day of Week',
                style: theme.titleMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: _buildDayOfWeekChart(stats.articlesByDayOfWeek, theme),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Top keywords
        if (stats.topKeywords.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Keywords',
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: stats.topKeywords.map((keyword) {
                    return Chip(
                      label: Text(keyword),
                      backgroundColor: theme.primaryColor.withOpacity(0.2),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Top authors
        if (stats.topAuthors.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Authors',
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 16),
                ...stats.topAuthors.map((author) {
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(author[0].toUpperCase()),
                      backgroundColor: theme.accentColor.withOpacity(0.3),
                    ),
                    title: Text(author),
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildAggregatedOverview(AggregatedStatistics stats, GlassThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Key metrics
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Feeds',
                stats.totalFeeds.toString(),
                Icons.rss_feed,
                theme.primaryColor,
                theme,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'Active Feeds',
                stats.activeFeeds.toString(),
                Icons.play_circle,
                Colors.green,
                theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Articles',
                _formatNumber(stats.totalArticles),
                Icons.article,
                Colors.blue,
                theme,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'Unread',
                _formatNumber(stats.unreadArticles),
                Icons.mark_email_unread,
                Colors.orange,
                theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Articles by category
        if (stats.articlesByCategory.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Articles by Category',
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: _buildPieChart(stats.articlesByCategory, theme),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Top performing feeds
        if (stats.topPerformingFeeds.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Performing Feeds',
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 16),
                ...stats.topPerformingFeeds.map((feed) {
                  return ListTile(
                    title: Text(feed.feedTitle),
                    subtitle: Text('${feed.articlesPerDay.toStringAsFixed(1)} articles/day'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(feed.healthScore * 100).toStringAsFixed(0)}%',
                        style: TextStyle(color: Colors.green),
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Worst performing feeds
        if (stats.worstPerformingFeeds.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feeds Needing Attention',
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 16),
                ...stats.worstPerformingFeeds.map((feed) {
                  return ListTile(
                    title: Text(feed.feedTitle),
                    subtitle: Text(
                      feed.lastSuccessfulUpdate != null
                          ? 'Last updated ${_formatRelativeTime(feed.lastSuccessfulUpdate!)}'
                          : 'Never updated successfully',
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(feed.healthScore * 100).toStringAsFixed(0)}%',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildTrendsTab(dynamic statistics, GlassThemeData theme) {
    final Map<DateTime, int> articlesOverTime;
    
    if (statistics is FeedStatistics) {
      // Convert monthly data to daily for consistent display
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
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Articles Over Time',
                style: theme.titleMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: _buildTimelineChart(articlesOverTime, theme),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Read rate trend
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reading Trends',
                style: theme.titleMedium,
              ),
              const SizedBox(height: 16),
              _buildReadingTrendIndicators(theme),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildPerformanceTab(dynamic statistics, GlassThemeData theme) {
    if (statistics is AggregatedStatistics) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Health by category
          if (statistics.healthByCategory.isNotEmpty) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Health by Category',
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ...statistics.healthByCategory.entries.map((entry) {
                    final health = entry.value;
                    final color = health > 0.8
                        ? Colors.green
                        : health > 0.5
                            ? Colors.orange
                            : Colors.red;
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(entry.key),
                              Text(
                                '${(health * 100).toStringAsFixed(0)}%',
                                style: TextStyle(color: color),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: health,
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
          ],
        ],
      );
    }
    
    return const Center(
      child: Text('Performance data not available for individual feeds'),
    );
  }
  
  Widget _buildReadingTab(GlassThemeData theme) {
    final readingStatsAsync = ref.watch(readingStatisticsProvider);
    
    return readingStatsAsync.when(
      data: (stats) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Today's reading
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Read Today',
                  stats.articlesReadToday.toString(),
                  Icons.today,
                  theme.primaryColor,
                  theme,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Time Today',
                  '${stats.totalReadingTimeToday} min',
                  Icons.timer,
                  Colors.blue,
                  theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Reading streaks
          if (stats.streaks.isNotEmpty) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reading Streaks',
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ...stats.streaks.take(3).map((streak) {
                    return ListTile(
                      leading: Icon(
                        streak.isCurrent ? Icons.local_fire_department : Icons.check_circle,
                        color: streak.isCurrent ? Colors.orange : Colors.green,
                      ),
                      title: Text('${streak.daysCount} days'),
                      subtitle: Text(
                        '${streak.articlesRead} articles • ${_formatDateRange(streak.startDate, streak.endDate)}',
                      ),
                      contentPadding: EdgeInsets.zero,
                    );
                  }).toList(),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Reading time by category
          if (stats.readingTimeByCategory.isNotEmpty) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reading Time by Category',
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _buildPieChart(
                      stats.readingTimeByCategory.map((k, v) => MapEntry(k, v.toDouble())),
                      theme,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Reading speed
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.speed, size: 48, color: theme.accentColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Average Reading Speed',
                        style: theme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stats.averageReadingSpeed.toStringAsFixed(0)} words per minute',
                        style: theme.bodyLarge.copyWith(
                          color: theme.accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      loading: () => const Center(child: LoadingAnimation()),
      error: (error, stack) => Center(
        child: Text(
          'Failed to load reading statistics: $error',
          style: TextStyle(color: Colors.red),
        ),
      ),
    );
  }
  
  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
    GlassThemeData theme,
  ) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHourlyChart(Map<String, int> data, GlassThemeData theme) {
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
              color: Colors.white.withOpacity(0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
    );
  }
  
  Widget _buildDayOfWeekChart(Map<String, int> data, GlassThemeData theme) {
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
                color: theme.primaryColor,
                width: 30,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  days[value.toInt()],
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
  
  Widget _buildPieChart(Map<String, double> data, GlassThemeData theme) {
    final total = data.values.reduce((a, b) => a + b);
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.amber,
      Colors.pink,
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
            radius: 80,
            titleStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            badgeWidget: Text(
              item.key,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
            badgePositionPercentageOffset: 1.3,
          );
        }).toList(),
        sectionsSpace: 2,
        centerSpaceRadius: 40,
      ),
    );
  }
  
  Widget _buildTimelineChart(Map<DateTime, int> data, GlassThemeData theme) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }
    
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
              color: Colors.white.withOpacity(0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (sortedEntries.length / 5).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= sortedEntries.length) return const SizedBox();
                final date = sortedEntries[value.toInt()].key;
                return Text(
                  '${date.month}/${date.day}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: theme.accentColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 3,
                  color: theme.accentColor,
                  strokeWidth: 1,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: theme.accentColor.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildReadingTrendIndicators(GlassThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildTrendIndicator(
          'Daily Average',
          '+12%',
          true,
          theme,
        ),
        _buildTrendIndicator(
          'Read Rate',
          '-5%',
          false,
          theme,
        ),
        _buildTrendIndicator(
          'Completion',
          '+8%',
          true,
          theme,
        ),
      ],
    );
  }
  
  Widget _buildTrendIndicator(
    String label,
    String value,
    bool isPositive,
    GlassThemeData theme,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: theme.bodySmall.copyWith(
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              isPositive ? Icons.trending_up : Icons.trending_down,
              color: isPositive ? Colors.green : Colors.red,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: isPositive ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
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
    final formatter = (DateTime date) => '${date.month}/${date.day}';
    return '${formatter(start)} - ${formatter(end)}';
  }
}