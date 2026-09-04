import 'package:flutter/material.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';
import 'glass_button.dart';

/// Centered empty-state composition: optional leading icon, title, guidance
/// line, and a primary action where sensible. Tokenized per active preset.
class EmptyState extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTheme.colorsOf(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GlassSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 48,
                color: tokens.textLow,
              ),
              const SizedBox(height: GlassSpacing.lg),
            ],
            Text(
              title,
              style: GlassTypeScale.heading.copyWith(color: tokens.textHigh),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: GlassSpacing.sm),
              Text(
                subtitle!,
                style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: GlassSpacing.xl),
              GlassButton(
                text: actionLabel,
                icon: icon,
                onPressed: onAction,
                variant: GlassButtonVariant.elevated,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
