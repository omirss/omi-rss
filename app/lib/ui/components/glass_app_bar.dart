import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../glass_theme.dart';

/// Glass app bar with blur effect
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final double elevation;
  final double blur;
  final double opacity;
  final List<Color>? gradientColors;
  final PreferredSizeWidget? bottom;
  final double? leadingWidth;
  final bool centerTitle;
  final double toolbarHeight;
  final SystemUiOverlayStyle? systemOverlayStyle;
  
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.elevation = 0,
    this.blur = 20,
    this.opacity = 0.15,
    this.gradientColors,
    this.bottom,
    this.leadingWidth,
    this.centerTitle = true,
    this.toolbarHeight = kToolbarHeight,
    this.systemOverlayStyle,
  });
  
  @override
  Size get preferredSize => Size.fromHeight(
    toolbarHeight + (bottom?.preferredSize.height ?? 0),
  );
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final colors = gradientColors ?? theme.gradientColors;
    
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayStyle ?? SystemUiOverlayStyle.light,
      child: Container(
        height: preferredSize.height + MediaQuery.of(context).padding.top,
        child: Stack(
          children: [
            // Blur background
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blur,
                    sigmaY: blur,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: colors.map((c) => c.withOpacity(opacity)).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Border
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.18),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            
            // Content
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: toolbarHeight,
                    child: NavigationToolbar(
                      leading: leading,
                      middle: centerTitle ? Center(child: title) : title,
                      trailing: actions != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions!,
                            )
                          : null,
                      centerMiddle: centerTitle,
                      middleSpacing: NavigationToolbar.kMiddleSpacing,
                    ),
                  ),
                  if (bottom != null) bottom!,
                ],
              ),
            ),
            
            // Elevation shadow
            if (elevation > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: -elevation,
                child: Container(
                  height: elevation,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.shadowColor.withOpacity(0.15),
                        theme.shadowColor.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sliver version of glass app bar
class SliverGlassAppBar extends StatelessWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final double expandedHeight;
  final Widget? flexibleSpace;
  final bool floating;
  final bool pinned;
  final bool snap;
  final double blur;
  final double opacity;
  final List<Color>? gradientColors;
  
  const SliverGlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.expandedHeight = kToolbarHeight,
    this.flexibleSpace,
    this.floating = false,
    this.pinned = true,
    this.snap = false,
    this.blur = 20,
    this.opacity = 0.15,
    this.gradientColors,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final colors = gradientColors ?? theme.gradientColors;
    
    return SliverAppBar(
      title: title,
      leading: leading,
      actions: actions,
      expandedHeight: expandedHeight,
      floating: floating,
      pinned: pinned,
      snap: snap,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Stack(
        children: [
          // Blur background
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors.map((c) => c.withOpacity(opacity)).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Flexible space content
          if (flexibleSpace != null)
            Positioned.fill(
              child: flexibleSpace!,
            ),
          
          // Border
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.0),
                    Colors.white.withOpacity(0.18),
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}