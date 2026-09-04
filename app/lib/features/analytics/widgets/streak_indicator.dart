import 'package:flutter/material.dart';
import '../../../ui/components/glass_container.dart';
import '../../../ui/glass_theme.dart';
import '../../../ui/tokens/glass_tokens.dart';

class StreakIndicator extends StatelessWidget {
  final String title;
  final int days;
  final IconData icon;
  final Color color;

  const StreakIndicator({
    super.key,
    required this.title,
    required this.days,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);

    return GlassContainer(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: InkWell(
        onTap: () => _showStreakDetails(context),
        borderRadius: BorderRadius.circular(GlassRadii.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: GlassSpacing.sm),
                Expanded(
                  child: Text(title, style: theme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: GlassSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  days.toString(),
                  style: GlassTypeScale.display.copyWith(
                    color: color,
                  ),
                ),
                const SizedBox(width: GlassSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('days', style: theme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: GlassSpacing.sm),
            Text(
              'Consecutive days with reading activity',
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _showStreakDetails(BuildContext context) {
    final theme = GlassTheme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: GlassSpacing.sm),
            Text(title),
          ],
        ),
        content: Text(
          '$days consecutive days',
          style: theme.titleLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
