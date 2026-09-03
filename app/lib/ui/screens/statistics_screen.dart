import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../../providers/statistics_provider.dart';
import '../../core/models/reading_statistics.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticsAsync = ref.watch(readingStatisticsProvider);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Reading Statistics',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: statisticsAsync.when(
        data: (statistics) => _buildStatisticsContent(context, statistics),
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        error: (error, stack) => Center(
          child: Text(
            'Error loading statistics',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatisticsContent(BuildContext context, ReadingStatistics stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overview Cards
          _buildOverviewSection(stats),
          
          const SizedBox(height: 32),
          
          // Reading Activity Chart
          _buildSectionHeader('Reading Activity'),
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              height: 250,
              child: _buildReadingActivityChart(stats),
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
          
          const SizedBox(height: 32),
          
          // Top Sources
          _buildSectionHeader('Top Sources'),
          _buildTopSourcesList(stats),
          
          const SizedBox(height: 32),
          
          // Reading Time Distribution
          _buildSectionHeader('Reading Time Distribution'),
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              height: 250,
              child: _buildTimeDistributionChart(stats),
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 300.ms),
          
          const SizedBox(height: 32),
          
          // Reading Habits
          _buildSectionHeader('Reading Habits'),
          _buildReadingHabits(stats),
        ],
      ),
    );
  }
  
  Widget _buildOverviewSection(ReadingStatistics stats) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Articles Read',
          stats.totalArticlesRead.toString(),
          Icons.article,
          GlassColors.primaryGradient,
        ).animate().fadeIn(duration: 300.ms),
        _buildStatCard(
          'Reading Streak',
          '${stats.currentStreak} days',
          Icons.local_fire_department,
          stats.currentStreak > 0 
            ? [Colors.orange, Colors.red]
            : [Colors.grey, Colors.grey.shade700],
        ).animate().fadeIn(duration: 300.ms, delay: 50.ms),
        _buildStatCard(
          'Avg. Daily',
          stats.averageArticlesPerDay.toStringAsFixed(1),
          Icons.trending_up,
          GlassColors.secondaryGradient,
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
        _buildStatCard(
          'Total Time',
          _formatReadingTime(stats.totalReadingTime),
          Icons.timer,
          GlassColors.accentGradient,
        ).animate().fadeIn(duration: 300.ms, delay: 150.ms),
      ],
    );
  }
  
  Widget _buildStatCard(String title, String value, IconData icon, List<Color> gradient) {
    return GlassCard(
      elevation: 2,
      padding: const EdgeInsets.all(16),
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
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
  
  Widget _buildReadingActivityChart(ReadingStatistics stats) {
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
              color: Colors.white.withOpacity(0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 10,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
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
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    days[index],
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: LinearGradient(
              colors: GlassColors.primaryGradient,
            ),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: GlassColors.primaryGradient[0],
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: GlassColors.primaryGradient
                    .map((color) => color.withOpacity(0.1))
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
  
  Widget _buildTopSourcesList(ReadingStatistics stats) {
    return Column(
      children: stats.topSources
          .take(5)
          .map((source) => GlassContainer(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: GlassColors.primaryGradient[0].withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.rss_feed,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.feedTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${source.articlesRead} articles • ${source.readingTime} min',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
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
                        color: GlassColors.primaryGradient[0].withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        '${source.percentage}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
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
  
  Widget _buildTimeDistributionChart(ReadingStatistics stats) {
    final sections = stats.timeDistribution.entries
        .map((entry) => PieChartSectionData(
              color: _getColorForTimeSlot(entry.key),
              value: entry.value.toDouble(),
              title: '${entry.value}%',
              radius: 80,
              titleStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
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
        const SizedBox(width: 24),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: stats.timeDistribution.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _getColorForTimeSlot(entry.key),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.key,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
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
  
  Widget _buildReadingHabits(ReadingStatistics stats) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildHabitRow(
            'Most Active Day',
            stats.mostActiveDay,
            Icons.calendar_today,
          ),
          const Divider(color: Colors.white24, height: 32),
          _buildHabitRow(
            'Peak Reading Time',
            stats.peakReadingTime,
            Icons.access_time,
          ),
          const Divider(color: Colors.white24, height: 32),
          _buildHabitRow(
            'Avg. Article Length',
            '${stats.averageArticleLength} words',
            Icons.format_size,
          ),
          const Divider(color: Colors.white24, height: 32),
          _buildHabitRow(
            'Reading Speed',
            '${stats.readingSpeed} wpm',
            Icons.speed,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 400.ms);
  }
  
  Widget _buildHabitRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: GlassColors.primaryGradient[0].withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white70, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
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
  
  Color _getColorForTimeSlot(String timeSlot) {
    switch (timeSlot) {
      case 'Morning':
        return Colors.orange;
      case 'Afternoon':
        return Colors.blue;
      case 'Evening':
        return Colors.purple;
      case 'Night':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}