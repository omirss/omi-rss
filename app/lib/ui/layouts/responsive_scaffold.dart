import 'package:flutter/material.dart';
import '../glass_theme.dart';
import '../components/glass_app_bar.dart';
import '../components/glass_bottom_nav.dart';
import '../components/glass_drawer.dart';
import '../animations/particle_background.dart';
import 'three_column_layout.dart';

/// Responsive breakpoints
class Breakpoints {
  static const double mobile = 768;
  static const double tablet = 1280;
  static const double desktop = 1920;
}

/// Screen size type
enum ScreenType {
  mobile,
  tablet,
  desktop,
}

/// Responsive scaffold configuration
class ResponsiveConfig {
  final bool showDrawer;
  final bool showBottomNav;
  final bool showRail;
  final int columns;
  final EdgeInsets padding;
  
  const ResponsiveConfig({
    this.showDrawer = false,
    this.showBottomNav = false,
    this.showRail = false,
    this.columns = 1,
    this.padding = EdgeInsets.zero,
  });
}

/// Responsive scaffold that adapts to screen size
class ResponsiveScaffold extends StatefulWidget {
  final Widget? mobileBody;
  final Widget? tabletBody;
  final Widget? desktopBody;
  final GlassAppBar? appBar;
  final List<ResponsiveNavItem> navItems;
  final int currentIndex;
  final ValueChanged<int>? onNavItemTap;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final bool useParticleBackground;
  final GlassThemeData? theme;
  
  const ResponsiveScaffold({
    super.key,
    this.mobileBody,
    this.tabletBody,
    this.desktopBody,
    this.appBar,
    required this.navItems,
    this.currentIndex = 0,
    this.onNavItemTap,
    this.floatingActionButton,
    this.backgroundColor,
    this.useParticleBackground = true,
    this.theme,
  });

  @override
  State<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends State<ResponsiveScaffold>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  ScreenType? _previousScreenType;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  ScreenType _getScreenType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    if (width < Breakpoints.mobile) {
      return ScreenType.mobile;
    } else if (width < Breakpoints.tablet) {
      return ScreenType.tablet;
    } else {
      return ScreenType.desktop;
    }
  }

  ResponsiveConfig _getConfig(ScreenType screenType) {
    switch (screenType) {
      case ScreenType.mobile:
        return const ResponsiveConfig(
          showBottomNav: true,
          columns: 1,
          padding: EdgeInsets.all(16),
        );
      case ScreenType.tablet:
        return const ResponsiveConfig(
          showRail: true,
          columns: 2,
          padding: EdgeInsets.all(24),
        );
      case ScreenType.desktop:
        return const ResponsiveConfig(
          showRail: true,
          columns: 3,
          padding: EdgeInsets.all(32),
        );
    }
  }

  Widget _getBody(ScreenType screenType) {
    switch (screenType) {
      case ScreenType.mobile:
        return widget.mobileBody ?? widget.tabletBody ?? widget.desktopBody ?? Container();
      case ScreenType.tablet:
        return widget.tabletBody ?? widget.desktopBody ?? widget.mobileBody ?? Container();
      case ScreenType.desktop:
        return widget.desktopBody ?? widget.tabletBody ?? widget.mobileBody ?? Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GlassTheme.of(context);
    final screenType = _getScreenType(context);
    final config = _getConfig(screenType);
    
    // Animate on screen type change
    if (_previousScreenType != null && _previousScreenType != screenType) {
      _animationController.forward(from: 0);
    }
    _previousScreenType = screenType;
    
    Widget body = FadeTransition(
      opacity: _fadeAnimation,
      child: _getBody(screenType),
    );
    
    if (widget.useParticleBackground) {
      body = ParticleBackground(
        particleCount: 60,
        backgroundGradient: theme.backgroundGradient,
        child: body,
      );
    }
    
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? Colors.black,
      appBar: widget.appBar,
      body: Row(
        children: [
          if (config.showRail) _buildNavigationRail(theme),
          Expanded(
            child: Padding(
              padding: config.padding,
              child: body,
            ),
          ),
        ],
      ),
      bottomNavigationBar: config.showBottomNav
          ? GlassBottomNav(
              items: widget.navItems
                  .map((item) => GlassBottomNavItem(
                        icon: item.icon,
                        activeIcon: item.activeIcon,
                        label: item.label,
                      ))
                  .toList(),
              currentIndex: widget.currentIndex,
              onTap: widget.onNavItemTap,
              theme: theme,
            )
          : null,
      floatingActionButton: widget.floatingActionButton,
    );
  }

  Widget _buildNavigationRail(GlassThemeData theme) {
    return NavigationRail(
      selectedIndex: widget.currentIndex,
      onDestinationSelected: widget.onNavItemTap,
      backgroundColor: Colors.white.withOpacity(0.05),
      selectedIconTheme: IconThemeData(
        color: theme.accentColor,
        size: 28,
      ),
      unselectedIconTheme: IconThemeData(
        color: Colors.white.withOpacity(0.6),
        size: 24,
      ),
      selectedLabelTextStyle: TextStyle(
        color: theme.accentColor,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: Colors.white.withOpacity(0.6),
      ),
      labelType: NavigationRailLabelType.all,
      destinations: widget.navItems
          .map((item) => NavigationRailDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon ?? item.icon),
                label: Text(item.label),
              ))
          .toList(),
    );
  }
}

/// Navigation item for responsive scaffold
class ResponsiveNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  
  const ResponsiveNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}

/// Responsive builder widget
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext, ScreenType, ResponsiveConfig) builder;
  
  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenType = _getScreenType(constraints.maxWidth);
        final config = _getConfig(screenType);
        
        return builder(context, screenType, config);
      },
    );
  }
  
  ScreenType _getScreenType(double width) {
    if (width < Breakpoints.mobile) {
      return ScreenType.mobile;
    } else if (width < Breakpoints.tablet) {
      return ScreenType.tablet;
    } else {
      return ScreenType.desktop;
    }
  }
  
  ResponsiveConfig _getConfig(ScreenType screenType) {
    switch (screenType) {
      case ScreenType.mobile:
        return const ResponsiveConfig(
          showBottomNav: true,
          columns: 1,
          padding: EdgeInsets.all(16),
        );
      case ScreenType.tablet:
        return const ResponsiveConfig(
          showRail: true,
          columns: 2,
          padding: EdgeInsets.all(24),
        );
      case ScreenType.desktop:
        return const ResponsiveConfig(
          showRail: true,
          columns: 3,
          padding: EdgeInsets.all(32),
        );
    }
  }
}

/// Extension for responsive values
extension ResponsiveExtension on BuildContext {
  ScreenType get screenType {
    final width = MediaQuery.of(this).size.width;
    
    if (width < Breakpoints.mobile) {
      return ScreenType.mobile;
    } else if (width < Breakpoints.tablet) {
      return ScreenType.tablet;
    } else {
      return ScreenType.desktop;
    }
  }
  
  bool get isMobile => screenType == ScreenType.mobile;
  bool get isTablet => screenType == ScreenType.tablet;
  bool get isDesktop => screenType == ScreenType.desktop;
  
  T responsive<T>({
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    switch (screenType) {
      case ScreenType.mobile:
        return mobile;
      case ScreenType.tablet:
        return tablet ?? desktop ?? mobile;
      case ScreenType.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }
}