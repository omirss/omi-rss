import 'package:flutter/material.dart';
import 'dart:ui';
import '../glass_theme.dart';

/// Glass bottom navigation bar
class GlassBottomNavigationBar extends StatefulWidget {
  final List<GlassBottomNavigationBarItem> items;
  final int currentIndex;
  final ValueChanged<int>? onTap;
  final double blur;
  final double opacity;
  final List<Color>? gradientColors;
  final double elevation;
  final double iconSize;
  final double? selectedFontSize;
  final double? unselectedFontSize;
  final bool showSelectedLabels;
  final bool showUnselectedLabels;
  final Color? selectedItemColor;
  final Color? unselectedItemColor;
  
  const GlassBottomNavigationBar({
    super.key,
    required this.items,
    required this.currentIndex,
    this.onTap,
    this.blur = 20,
    this.opacity = 0.15,
    this.gradientColors,
    this.elevation = 8,
    this.iconSize = 24,
    this.selectedFontSize = 14,
    this.unselectedFontSize = 12,
    this.showSelectedLabels = true,
    this.showUnselectedLabels = true,
    this.selectedItemColor,
    this.unselectedItemColor,
  }) : assert(items.length >= 2);
  
  @override
  State<GlassBottomNavigationBar> createState() => _GlassBottomNavigationBarState();
}

class _GlassBottomNavigationBarState extends State<GlassBottomNavigationBar>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  
  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.items.length,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      ),
    );
    
    _animations = _controllers.map((controller) => 
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutBack,
      ),
    ).toList();
    
    _controllers[widget.currentIndex].forward();
  }
  
  @override
  void didUpdateWidget(GlassBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _controllers[oldWidget.currentIndex].reverse();
      _controllers[widget.currentIndex].forward();
    }
  }
  
  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final colors = widget.gradientColors ?? theme.gradientColors;
    final selectedColor = widget.selectedItemColor ?? theme.accentColor;
    final unselectedColor = widget.unselectedItemColor ?? Colors.white.withOpacity(0.7);
    
    return Container(
      height: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.15),
            blurRadius: widget.elevation,
            offset: Offset(0, -widget.elevation / 2),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: widget.blur,
            sigmaY: widget.blur,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors.map((c) => c.withOpacity(widget.opacity)).toList(),
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.18),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = index == widget.currentIndex;
                  
                  return Expanded(
                    child: InkWell(
                      onTap: () => widget.onTap?.call(index),
                      splashColor: selectedColor.withOpacity(0.2),
                      highlightColor: selectedColor.withOpacity(0.1),
                      child: AnimatedBuilder(
                        animation: _animations[index],
                        builder: (context, child) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Icon with animated scale and color
                                Transform.scale(
                                  scale: 1 + (_animations[index].value * 0.15),
                                  child: Icon(
                                    isSelected ? item.activeIcon ?? item.icon : item.icon,
                                    size: widget.iconSize,
                                    color: Color.lerp(
                                      unselectedColor,
                                      selectedColor,
                                      _animations[index].value,
                                    ),
                                  ),
                                ),
                                
                                // Label
                                if ((isSelected && widget.showSelectedLabels) ||
                                    (!isSelected && widget.showUnselectedLabels))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: isSelected 
                                          ? widget.selectedFontSize 
                                          : widget.unselectedFontSize,
                                        color: Color.lerp(
                                          unselectedColor,
                                          selectedColor,
                                          _animations[index].value,
                                        ),
                                        fontWeight: isSelected 
                                          ? FontWeight.w600 
                                          : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                
                                // Animated indicator
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: 3,
                                  width: isSelected ? 24 : 0,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    color: selectedColor,
                                    borderRadius: BorderRadius.circular(1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: selectedColor.withOpacity(0.5),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass bottom navigation bar item
class GlassBottomNavigationBarItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final Widget? badge;
  
  const GlassBottomNavigationBarItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badge,
  });
}

/// Glass floating navigation bar (alternative style)
class GlassFloatingNavigationBar extends StatefulWidget {
  final List<GlassBottomNavigationBarItem> items;
  final int currentIndex;
  final ValueChanged<int>? onTap;
  final double blur;
  final double opacity;
  final List<Color>? gradientColors;
  final double margin;
  final double borderRadius;
  
  const GlassFloatingNavigationBar({
    super.key,
    required this.items,
    required this.currentIndex,
    this.onTap,
    this.blur = 25,
    this.opacity = 0.2,
    this.gradientColors,
    this.margin = 16,
    this.borderRadius = 30,
  });
  
  @override
  State<GlassFloatingNavigationBar> createState() => _GlassFloatingNavigationBarState();
}

class _GlassFloatingNavigationBarState extends State<GlassFloatingNavigationBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final colors = widget.gradientColors ?? theme.gradientColors;
    final itemWidth = (MediaQuery.of(context).size.width - (widget.margin * 2)) / widget.items.length;
    
    return Container(
      margin: EdgeInsets.only(
        left: widget.margin,
        right: widget.margin,
        bottom: widget.margin + MediaQuery.of(context).padding.bottom,
      ),
      height: 65,
      child: Stack(
        children: [
          // Glass background
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.blur,
                sigmaY: widget.blur,
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors.map((c) => c.withOpacity(widget.opacity)).toList(),
                  ),
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.18),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Sliding indicator
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            left: widget.currentIndex * itemWidth,
            top: 0,
            bottom: 0,
            width: itemWidth,
            child: Center(
              child: Container(
                width: itemWidth - 20,
                height: 45,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.accentColor.withOpacity(0.3),
                      theme.accentColor.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22.5),
                  border: Border.all(
                    color: theme.accentColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          
          // Items
          Row(
            children: List.generate(widget.items.length, (index) {
              final item = widget.items[index];
              final isSelected = index == widget.currentIndex;
              
              return Expanded(
                child: InkWell(
                  onTap: () => widget.onTap?.call(index),
                  customBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                  ),
                  child: Center(
                    child: AnimatedScale(
                      scale: isSelected ? 1.2 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        isSelected ? item.activeIcon ?? item.icon : item.icon,
                        size: 24,
                        color: isSelected 
                          ? theme.accentColor
                          : Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }
}