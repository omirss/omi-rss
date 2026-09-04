import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../providers/analytics_provider.dart';
import '../../../ui/components/glass_container.dart';
import '../../../ui/glass_theme.dart';
import '../../../ui/tokens/glass_tokens.dart';

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
    final theme = GlassTheme.of(context);

    if (widget.data.isEmpty) {
      return GlassContainer(
        padding: const EdgeInsets.all(GlassSpacing.xl),
        child: SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.pie_chart_outline,
                  size: 48,
                  color: theme.bodySmall.color,
                ),
                const SizedBox(height: GlassSpacing.md),
                Text(
                  'No category data available',
                  style: theme.bodyMedium,
                ),
                const SizedBox(height: GlassSpacing.xs),
                Text(
                  'Categories appear once you read across several feeds',
                  style: theme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GlassContainer(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: SizedBox(
        height: 300,
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
      GlassTheme.of(context).primaryColor,
      GlassTheme.of(context).secondaryColor,
      GlassTheme.of(context).accentColor,
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
        titleStyle: GlassTypeScale.label.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
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
    final theme = GlassTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: GlassSpacing.sm, vertical: GlassSpacing.xs),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(GlassRadii.sm),
        border: Border.all(color: theme.borderColor),
      ),
      child: Text(
        label,
        style: GlassTypeScale.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
