import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../analytics_provider.dart';

class CategoryChart extends StatefulWidget {
  final List<ChartDataPoint> data;

  const CategoryChart({
    super.key,
    required this.data,
  });

  @override
  State<CategoryChart> createState() => _CategoryChartState();
}

class _CategoryChartState extends State<CategoryChart> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return Card(
        child: Container(
          height: 300,
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No category data available',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return Card(
      child: Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: PieChart(
          PieChartData(
            pieTouchData: PieTouchData(
              touchCallback: (FlTouchEvent event, pieTouchResponse) {
                setState(() {
                  if (!event.isInterestedForInteractions ||
                      pieTouchResponse == null ||
                      pieTouchResponse.touchedSection == null) {
                    touchedIndex = -1;
                    return;
                  }
                  touchedIndex =
                      pieTouchResponse.touchedSection!.touchedSectionIndex;
                });
              },
            ),
            borderData: FlBorderData(show: false),
            sectionsSpace: 2,
            centerSpaceRadius: 40,
            sections: _buildSections(),
          ),
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.error,
      Theme.of(context).colorScheme.inversePrimary,
    ];

    return widget.data.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final isTouched = index == touchedIndex;
      final fontSize = isTouched ? 18.0 : 14.0;
      final radius = isTouched ? 110.0 : 100.0;

      return PieChartSectionData(
        color: colors[index % colors.length],
        value: data.value,
        title: '${data.value.toInt()}',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        badgeWidget: isTouched
            ? _Badge(
                data.label,
                color: colors[index % colors.length],
              )
            : null,
        badgePositionPercentageOffset: .98,
      );
    }).toList();
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge(
    this.label, {
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}