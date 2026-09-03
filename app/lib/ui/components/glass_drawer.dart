import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';
import 'glass_container.dart';

/// Glass drawer with blur overlay and nested menus
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
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
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
                  color: Colors.black.withOpacity(0.5 * _fadeAnimation.value),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 5 * _fadeAnimation.value,
                      sigmaY: 5 * _fadeAnimation.value,
                    ),
                    child: Container(),
                  ),
                );
              },
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
                child: _buildDrawerContent(theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerContent(GlassThemeData theme) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: widget.blur ?? theme.blur,
          sigmaY: widget.blur ?? theme.blur,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.gradientColors ?? [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.08),
              ],
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border(
              right: BorderSide(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 24,
                offset: const Offset(8, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              if (widget.header != null) widget.header!,
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final item in widget.items)
                      _buildDrawerItem(item, theme),
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

  Widget _buildDrawerItem(GlassDrawerItem item, GlassThemeData theme, {int depth = 0}) {
    final hasChildren = item.children != null && item.children!.isNotEmpty;
    final isExpanded = _expandedItems[item.id] ?? false;
    
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
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.only(
                left: 16 + (depth * 16),
                right: 12,
                top: 12,
                bottom: 12,
              ),
              child: Row(
                children: [
                  if (item.icon != null)
                    Icon(
                      item.icon,
                      color: item.selected 
                          ? Colors.white 
                          : Colors.white.withOpacity(0.7),
                      size: 20,
                    ),
                  if (item.icon != null) const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        color: item.selected 
                            ? Colors.white 
                            : Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: item.selected 
                            ? FontWeight.w600 
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (item.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.badgeColor?.withOpacity(0.2) ??
                            theme.accentColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.badge!,
                        style: TextStyle(
                          color: item.badgeColor ?? theme.accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (hasChildren)
                    AnimatedBuilder(
                      animation: _expansionControllers[item.id]!,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _expansionControllers[item.id]!.value * 0.5 * 3.14159,
                          child: Icon(
                            Icons.chevron_right,
                            color: Colors.white.withOpacity(0.5),
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
                        _buildDrawerItem(child, theme, depth: depth + 1),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
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
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.withOpacity(0.8),
                          Colors.blue.withOpacity(0.8),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // User info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (userEmail != null)
                          Text(
                            userEmail!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(0.5),
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