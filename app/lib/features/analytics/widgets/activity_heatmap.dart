import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../providers/analytics_provider.dart';
import '../../../ui/components/glass_container.dart';
import '../../../ui/glass_theme.dart';
import '../../../ui/tokens/glass_tokens.dart';

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
    final theme = GlassTheme.of(context);

    return GlassContainer(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Hourly'),
              Tab(text: 'Weekly'),
            ],
            indicatorColor: theme.accentColor,
            labelColor: theme.titleSmall.color,
            unselectedLabelColor: theme.bodySmall.color,
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

  Widget _buildEmptyChart(String message) {
    final theme = GlassTheme.of(context);
    return Center(
      child: Text(message, style: theme.bodyMedium),
    );
  }

  Widget _buildHourlyChart() {
    if (widget.hourlyData.isEmpty) {
      return _buildEmptyChart('No hourly data available');
    }

    final theme = GlassTheme.of(context);
    final axisStyle = GlassTypeScale.caption
        .copyWith(fontSize: 10, color: theme.bodySmall.color);
    final maxValue = widget.hourlyData
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: theme.backgroundColor,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${widget.hourlyData[groupIndex].label}\n',
                  GlassTypeScale.label.copyWith(
                    color: theme.titleSmall.color,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    TextSpan(
                      text: '${rod.toY.toInt()} articles',
                      style: GlassTypeScale.label.copyWith(
                        color: theme.bodySmall.color,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
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
                      return Text(hour, style: axisStyle);
                    }
                  }
                  return const SizedBox.shrink();
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
                    style: axisStyle,
                  );
                },
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
      return _buildEmptyChart('No weekly data available');
    }

    final theme = GlassTheme.of(context);
    final axisStyle = GlassTypeScale.caption
        .copyWith(fontSize: 10, color: theme.bodySmall.color);
    final maxValue = widget.weeklyData
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: theme.backgroundColor,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${widget.weeklyData[groupIndex].label}\n',
                  GlassTypeScale.label.copyWith(
                    color: theme.titleSmall.color,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    TextSpan(
                      text: '${rod.toY.toInt()} articles',
                      style: GlassTypeScale.label.copyWith(
                        color: theme.bodySmall.color,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() < widget.weeklyData.length) {
                    return Text(
                      widget.weeklyData[value.toInt()].label,
                      style: axisStyle.copyWith(fontSize: 12),
                    );
                  }
                  return const SizedBox.shrink();
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
                    style: axisStyle,
                  );
                },
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
    final baseColor = GlassTheme.of(context).accentColor;

    if (ratio > 0.8) {
      return baseColor;
    } else if (ratio > 0.6) {
      return baseColor.withValues(alpha: 0.8);
    } else if (ratio > 0.4) {
      return baseColor.withValues(alpha: 0.6);
    } else if (ratio > 0.2) {
      return baseColor.withValues(alpha: 0.4);
    } else {
      return baseColor.withValues(alpha: 0.2);
    }
  }
}
