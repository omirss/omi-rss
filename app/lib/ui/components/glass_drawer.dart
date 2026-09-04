import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';

/// Glass drawer with blur overlay and nested menus.
///
/// The panel's backdrop blur uses a reduced sigma while the drawer is in
/// motion and ramps back to full sigma once the slide settles, so the web
/// compositor does not re-rasterize a full-strength blur for the moving
/// 280px column every frame.
class GlassDrawer extends StatefulWidget {
  final Widget? header;
  final List<GlassDrawerItem> items;
  final Widget? footer;
  final double width;
  final double? blur;
  final List<Color>? gradientColors;
  final VoidCallback? onClose;
  final GlassThemeData? theme;

  const GlassDrawer({
    super.key,
    this.header,
    required this.items,
    this.footer,
    this.width = 280,
    this.blur,
    this.gradientColors,
    this.onClose,
    this.theme,
  });

  @override
  State<GlassDrawer> createState() => _GlassDrawerState();
}

class _GlassDrawerState extends State<GlassDrawer>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late AnimationController _blurRampController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  static const double _motionBlurSigma = 4;

  final Map<String, AnimationController> _expansionControllers = {};
  final Map<String, bool> _expandedItems = {};

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Ramps the panel blur from the cheap motion sigma back to full after
    // the slide animation settles.
    _blurRampController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _slideController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _blurRampController.forward();
      } else {
        _blurRampController.reset();
      }
    });

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    // Start animations
    _slideController.forward();
    _fadeController.forward();

    // Initialize expansion controllers for nested items
    for (final item in widget.items) {
      if (item.children != null && item.children!.isNotEmpty) {
        _expansionControllers[item.id] = AnimationController(
          duration: const Duration(milliseconds: 300),
          vsync: this,
        );
        _expandedItems[item.id] = false;
      }
    }

    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    _blurRampController.dispose();
    for (final controller in _expansionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _close() {
    _fadeController.reverse();
    _slideController.reverse().then((_) {
      widget.onClose?.call();
    });
  }

  void _toggleExpansion(String itemId) {
    setState(() {
      _expandedItems[itemId] = !(_expandedItems[itemId] ?? false);
      if (_expandedItems[itemId]!) {
        _expansionControllers[itemId]?.forward();
      } else {
        _expansionControllers[itemId]?.reverse();
      }
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GlassTheme.of(context);
    final tokens = GlassTheme.colorsOf(context);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Backdrop
          GestureDetector(
            onTap: _close,
            child: AnimatedBuilder(
              animation: _fadeAnimation,
              builder: (context, child) {
                return Container(
                  color: tokens.overlay.withValues(
                    alpha: tokens.overlay.a * _fadeAnimation.value,
                  ),
                  child: child,
                );
              },
              // Fixed blur sigma: animating it re-rasterizes the
              // full-screen blur every frame, which stalls the slide on web.
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _motionBlurSigma,
                  sigmaY: _motionBlurSigma,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // Drawer
          Align(
            alignment: Alignment.centerLeft,
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                width: widget.width,
                height: double.infinity,
                child: _buildDrawerContent(theme, tokens),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerContent(
      GlassThemeData theme, GlassColorTokens tokens) {
    final fullBlur = widget.blur ?? theme.blur;
    final panelRadius = const BorderRadius.only(
      topRight: Radius.circular(GlassRadii.xl),
      bottomRight: Radius.circular(GlassRadii.xl),
    );

    return ClipRRect(
      borderRadius: panelRadius,
      child: AnimatedBuilder(
        animation: _blurRampController,
        builder: (context, child) {
          final sigma = _slideController.isCompleted
              ? (_motionBlurSigma +
                  (fullBlur - _motionBlurSigma) * _blurRampController.value)
              : _motionBlurSigma;
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.gradientColors ?? theme.gradientColors,
            ),
            borderRadius: panelRadius,
            border: Border(
              right: BorderSide(
                color: theme.borderColor,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: tokens.overlay.withValues(alpha: 0.3),
                blurRadius: GlassSpacing.xl,
                offset: const Offset(GlassSpacing.sm, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              if (widget.header != null) widget.header!,
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: GlassSpacing.sm),
                  children: [
                    for (final item in widget.items)
                      _buildDrawerItem(item, theme, tokens),
                  ],
                ),
              ),
              if (widget.footer != null) widget.footer!,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
      GlassDrawerItem item, GlassThemeData theme, GlassColorTokens tokens,
      {int depth = 0}) {
    final hasChildren = item.children != null && item.children!.isNotEmpty;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (hasChildren) {
                _toggleExpansion(item.id);
              } else {
                item.onTap?.call();
                if (item.closeOnTap) {
                  _close();
                }
              }
            },
            hoverColor: tokens.hoverFill,
            focusColor: tokens.accentSoft,
            borderRadius: BorderRadius.circular(GlassRadii.sm),
            child: Container(
              padding: EdgeInsets.only(
                left: GlassSpacing.lg + (depth * GlassSpacing.lg),
                right: GlassSpacing.md,
                top: GlassSpacing.md,
                bottom: GlassSpacing.md,
              ),
              child: Row(
                children: [
                  if (item.icon != null)
                    Icon(
                      item.icon,
                      color: item.selected ? tokens.accent : tokens.textMedium,
                      size: 20,
                    ),
                  if (item.icon != null) const SizedBox(width: GlassSpacing.md),
                  Expanded(
                    child: Text(
                      item.title,
                      style: GlassTypeScale.label.copyWith(
                        color: item.selected
                            ? tokens.textHigh
                            : tokens.textMedium,
                        fontWeight: item.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (item.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GlassSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.badgeColor?.withValues(
                                alpha: GlassOpacity.faint) ??
                            tokens.accentSoft,
                        borderRadius: BorderRadius.circular(GlassRadii.md),
                      ),
                      child: Text(
                        item.badge!,
                        style: GlassTypeScale.caption.copyWith(
                          color: item.badgeColor ?? tokens.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (hasChildren)
                    AnimatedBuilder(
                      animation: _expansionControllers[item.id]!,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle:
                              _expansionControllers[item.id]!.value * 0.5 * 3.14159,
                          child: Icon(
                            Icons.chevron_right,
                            color: tokens.textLow,
                            size: 20,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        if (hasChildren)
          AnimatedBuilder(
            animation: _expansionControllers[item.id]!,
            builder: (context, child) {
              return ClipRect(
                child: SizeTransition(
                  sizeFactor: _expansionControllers[item.id]!,
                  child: Column(
                    children: [
                      for (final child in item.children!)
                        _buildDrawerItem(child, theme, tokens, depth: depth + 1),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Glass drawer item model
class GlassDrawerItem {
  final String id;
  final String title;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;
  final bool closeOnTap;
  final String? badge;
  final Color? badgeColor;
  final List<GlassDrawerItem>? children;

  const GlassDrawerItem({
    required this.id,
    required this.title,
    this.icon,
    this.onTap,
    this.selected = false,
    this.closeOnTap = true,
    this.badge,
    this.badgeColor,
    this.children,
  });
}

/// Glass drawer header with user profile
class GlassDrawerHeader extends StatelessWidget {
  final String? avatarUrl;
  final String userName;
  final String? userEmail;
  final VoidCallback? onProfileTap;

  const GlassDrawerHeader({
    super.key,
    this.avatarUrl,
    required this.userName,
    this.userEmail,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
          GlassSpacing.lg, 48, GlassSpacing.lg, GlassSpacing.lg),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.divider,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onProfileTap,
            hoverColor: tokens.hoverFill,
            borderRadius: BorderRadius.circular(GlassRadii.sm),
            child: Padding(
              padding: const EdgeInsets.all(GlassSpacing.sm),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: tokens.primaryGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.primary.withValues(alpha: 0.3),
                          blurRadius: GlassSpacing.md,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: GlassTypeScale.title.copyWith(
                          color: tokens.textHigh,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: GlassSpacing.md),
                  // User info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: GlassTypeScale.label.copyWith(
                            color: tokens.textHigh,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (userEmail != null)
                          Text(
                            userEmail!,
                            style: GlassTypeScale.caption
                                .copyWith(color: tokens.textMedium),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: tokens.textLow,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the glass drawer
void showGlassDrawer({
  required BuildContext context,
  Widget? header,
  required List<GlassDrawerItem> items,
  Widget? footer,
  double width = 280,
  double? blur,
  List<Color>? gradientColors,
  GlassThemeData? theme,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, animation, secondaryAnimation) {
      return GlassDrawer(
        header: header,
        items: items,
        footer: footer,
        width: width,
        blur: blur,
        gradientColors: gradientColors,
        onClose: () => Navigator.of(context).pop(),
        theme: theme,
      );
    },
  );
}
