import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../analytics_provider.dart';

class ActivityHeatmap extends StatefulWidget {
  final List<ChartDataPoint> hourlyData;
  final List<ChartDataPoint> weeklyData;

  const ActivityHeatmap({
    super.key,
    required this.hourlyData,
    required this.weeklyData,
  });

  @override
  State<ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<ActivityHeatmap>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Hourly'),
              Tab(text: 'Weekly'),
            ],
          ),
          SizedBox(
            height: 250,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildHourlyChart(),
                _buildWeeklyChart(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyChart() {
    if (widget.hourlyData.isEmpty) {
      return const Center(
        child: Text('No hourly data available'),
      );
    }

    final maxValue = widget.hourlyData
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Theme.of(context).colorScheme.surfaceVariant,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${widget.hourlyData[groupIndex].label}\n',
                  TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(
                      text: '${rod.toY.toInt()} articles',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
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
                  if (value.toInt() < widget.hourlyData.length) {
                    final hour = widget.hourlyData[value.toInt()].label;
                    // Show every 3rd hour
                    if (value.toInt() % 3 == 0) {
                      return Text(
                        hour,
                        style: const TextStyle(fontSize: 10),
                      );
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
                reservedSize: 30,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: widget.hourlyData.asMap().entries.map((entry) {
            final index = entry.key;
            final data = entry.value;
            final color = _getHeatmapColor(data.value, maxValue);

            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: data.value,
                  color: color,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildWeeklyChart() {
    if (widget.weeklyData.isEmpty) {
      return const Center(
        child: Text('No weekly data available'),
      );
    }

    final maxValue = widget.weeklyData
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Theme.of(context).colorScheme.surfaceVariant,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${widget.weeklyData[groupIndex].label}\n',
                  TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(
                      text: '${rod.toY.toInt()} articles',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
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
                  if (value.toInt() < widget.weeklyData.length) {
                    return Text(
                      widget.weeklyData[value.toInt()].label,
                      style: const TextStyle(fontSize: 12),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
                reservedSize: 30,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: widget.weeklyData.asMap().entries.map((entry) {
            final index = entry.key;
            final data = entry.value;
            final color = _getHeatmapColor(data.value, maxValue);

            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: data.value,
                  color: color,
                  width: 40,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _getHeatmapColor(double value, double maxValue) {
    final ratio = value / maxValue;
    final baseColor = Theme.of(context).colorScheme.primary;

    if (ratio > 0.8) {
      return baseColor;
    } else if (ratio > 0.6) {
      return baseColor.withOpacity(0.8);
    } else if (ratio > 0.4) {
      return baseColor.withOpacity(0.6);
    } else if (ratio > 0.2) {
      return baseColor.withOpacity(0.4);
    } else {
      return baseColor.withOpacity(0.2);
    }
  }
}