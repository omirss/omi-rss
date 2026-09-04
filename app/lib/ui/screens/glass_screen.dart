import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/theme_settings_provider.dart';
import '../animations/particle_background.dart';
import '../components/glass_button.dart';
import '../components/glass_container.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';

/// Resolves the color tokens in effect for this screen from the active
/// preset and mode, following the platform brightness in system mode.
GlassColorTokens screenTokensOf(BuildContext context, WidgetRef ref) {
  final settings = ref.watch(themeSettingsProvider);
  final preset = ref.watch(themePresetProvider);
  final brightness = switch (settings.mode) {
    AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
  };
  return preset.resolve(brightness);
}

/// Screen scaffold for secondary screens: token background in both modes,
/// tokenized app bar, and a [GlassTheme] provision so glass components
/// below it follow the active preset.
class GlassScreen extends ConsumerWidget {
  final String? title;
  final PreferredSizeWidget? appBarBottom;
  final Widget body;
  final bool particles;

  const GlassScreen({
    super.key,
    this.title,
    this.appBarBottom,
    required this.body,
    this.particles = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = screenTokensOf(context, ref);
    final hasAppBar = title != null || appBarBottom != null;

    final Widget background = particles
        ? ParticleBackground(
            particleCount: 16,
            enableMouseInteraction: false,
            enableParallax: false,
            backgroundGradient: tokens.backgroundGradient,
            child: const SizedBox.expand(),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tokens.backgroundGradient,
              ),
            ),
          );

    return GlassTheme(
      data: GlassThemeData.fromTokens(tokens),
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        extendBodyBehindAppBar: true,
        appBar: hasAppBar
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: tokens.textHigh,
                iconTheme: IconThemeData(color: tokens.textHigh),
                title: title == null
                    ? null
                    : Text(
                        title!,
                        style: GlassTypeScale.title.copyWith(
                          color: tokens.textHigh,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                bottom: appBarBottom,
              )
            : null,
        body: Stack(
          children: [
            Positioned.fill(child: background),
            SafeArea(child: body),
          ],
        ),
      ),
    );
  }
}

/// Section header shared by secondary screens.
class ScreenSectionHeader extends StatelessWidget {
  final String title;
  final GlassColorTokens tokens;

  const ScreenSectionHeader({
    super.key,
    required this.title,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: GlassSpacing.sm,
        bottom: GlassSpacing.md,
      ),
      child: Text(
        title,
        style: GlassTypeScale.label.copyWith(
          fontSize: 16,
          color: tokens.textMedium,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Empty state with guidance copy, tokenized for both modes.
class ScreenEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final GlassColorTokens tokens;

  const ScreenEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GlassSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: tokens.textLow.withValues(alpha: 0.7),
            ),
            const SizedBox(height: GlassSpacing.lg),
            Text(
              title,
              style: GlassTypeScale.label.copyWith(
                fontSize: 18,
                color: tokens.textHigh,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: GlassSpacing.sm),
              Text(
                subtitle!,
                style: GlassTypeScale.label.copyWith(
                  color: tokens.textMedium,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state with retry action, tokenized for both modes.
class ScreenErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final GlassColorTokens tokens;

  const ScreenErrorState({
    super.key,
    required this.message,
    this.onRetry,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GlassSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: tokens.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: GlassSpacing.lg),
            Text(
              'Something went wrong',
              style: GlassTypeScale.label.copyWith(
                fontSize: 18,
                color: tokens.textHigh,
              ),
            ),
            const SizedBox(height: GlassSpacing.sm),
            Text(
              message,
              style: GlassTypeScale.label.copyWith(
                color: tokens.textMedium,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: GlassSpacing.lg),
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

/// Loading skeleton for content-shaped screens (stat cards + chart block).
class ScreenSkeleton extends StatelessWidget {
  final GlassColorTokens tokens;

  const ScreenSkeleton({super.key, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final blockColor = tokens.glassFill;

    Widget block({double? height}) {
      return GlassContainer(
        padding: EdgeInsets.zero,
        child: Container(
          height: height ?? 96,
          decoration: BoxDecoration(
            color: blockColor,
            borderRadius: BorderRadius.circular(GlassRadii.md),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(GlassSpacing.xl),
      child: Column(
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: GlassSpacing.lg,
            crossAxisSpacing: GlassSpacing.lg,
            childAspectRatio: 1.6,
            children: List.generate(4, (_) => block()),
          ),
          const SizedBox(height: GlassSpacing.xxl),
          block(height: 220),
          const SizedBox(height: GlassSpacing.lg),
          block(height: 64),
          const SizedBox(height: GlassSpacing.lg),
          block(height: 64),
        ],
      ),
    );
  }
}

/// Centered spinner for tab and dialog loads.
class ScreenLoading extends StatelessWidget {
  final GlassColorTokens tokens;

  const ScreenLoading({super.key, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(color: tokens.accent),
    );
  }
}

/// Shared list-row anatomy for settings and statistics rows.
class ScreenListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final GlassColorTokens tokens;
  final Color? iconColor;

  const ScreenListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    required this.tokens,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (iconColor ?? tokens.accent).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(GlassRadii.md),
          ),
          child: Icon(
            icon,
            color: iconColor ?? tokens.accent,
            size: 22,
          ),
        ),
        const SizedBox(width: GlassSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GlassTypeScale.body.copyWith(color: tokens.textHigh),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: GlassSpacing.xs),
                Text(
                  subtitle!,
                  style: GlassTypeScale.label.copyWith(
                    color: tokens.textMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );

    if (onTap == null) {
      return row;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassRadii.md),
      child: row,
    );
  }
}
