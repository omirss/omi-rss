import 'package:flutter/material.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';
import 'glass_button.dart';

/// Centered error state with a retry affordance. Tokenized per active preset.
class ErrorState extends StatelessWidget {
  final String error;
  final String title;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    required this.error,
    this.title = 'Something went wrong',
    this.onRetry,
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
            Icon(
              Icons.error_outline,
              size: 48,
              color: tokens.error,
            ),
            const SizedBox(height: GlassSpacing.lg),
            Text(
              title,
              style: GlassTypeScale.heading.copyWith(color: tokens.textHigh),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GlassSpacing.sm),
            Text(
              error,
              style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: GlassSpacing.xl),
              GlassButton(
                text: 'Retry',
                icon: Icons.refresh,
                onPressed: onRetry,
                variant: GlassButtonVariant.outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
