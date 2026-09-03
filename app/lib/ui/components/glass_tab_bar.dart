import 'package:flutter/material.dart';
import '../glass_theme.dart';

/// Glass-styled tab bar
class GlassTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<Tab> tabs;
  final bool isScrollable;
  final TabBarIndicatorSize indicatorSize;
  final EdgeInsets padding;
  final Color? indicatorColor;
  final double indicatorWeight;
  
  const GlassTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.isScrollable = false,
    this.indicatorSize = TabBarIndicatorSize.tab,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.indicatorColor,
    this.indicatorWeight = 3,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return Container(
      height: preferredSize.height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: controller,
        tabs: tabs,
        isScrollable: isScrollable,
        indicatorSize: indicatorSize,
        indicatorColor: indicatorColor ?? theme.accentColor,
        indicatorWeight: indicatorWeight,
        labelColor: indicatorColor ?? theme.accentColor,
        unselectedLabelColor: Colors.white.withOpacity(0.6),
        labelStyle: theme.bodyMedium.copyWith(
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: theme.bodyMedium,
        padding: padding,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(
            color: indicatorColor ?? theme.accentColor,
            width: indicatorWeight,
          ),
          insets: EdgeInsets.symmetric(
            horizontal: indicatorSize == TabBarIndicatorSize.label ? 8 : 0,
          ),
        ),
      ),
    );
  }
  
  @override
  Size get preferredSize => const Size.fromHeight(48);
}

/// Glass-styled segmented tab bar
class GlassSegmentedTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  final List<IconData>? icons;
  final void Function(int)? onTap;
  final EdgeInsets padding;
  final double height;
  
  const GlassSegmentedTabBar({
    super.key,
    required this.controller,
    required this.labels,
    this.icons,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.height = 40,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return Padding(
      padding: padding,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            return Stack(
              children: [
                // Sliding indicator
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  left: controller.index * (MediaQuery.of(context).size.width - 32) / labels.length,
                  child: Container(
                    width: (MediaQuery.of(context).size.width - 32) / labels.length,
                    height: height,
                    decoration: BoxDecoration(
                      color: theme.accentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(height / 2),
                      border: Border.all(
                        color: theme.accentColor.withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
                // Tab items
                Row(
                  children: List.generate(labels.length, (index) {
                    final isSelected = controller.index == index;
                    
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          controller.animateTo(index);
                          onTap?.call(index);
                        },
                        child: Container(
                          color: Colors.transparent,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (icons != null && icons!.length > index) ...[
                                  Icon(
                                    icons![index],
                                    size: 16,
                                    color: isSelected
                                        ? theme.accentColor
                                        : Colors.white.withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  labels[index],
                                  style: theme.bodySmall.copyWith(
                                    color: isSelected
                                        ? theme.accentColor
                                        : Colors.white.withOpacity(0.6),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Glass-styled vertical tab bar
class GlassVerticalTabBar extends StatelessWidget {
  final TabController controller;
  final List<Tab> tabs;
  final double width;
  final Color? indicatorColor;
  final EdgeInsets padding;
  
  const GlassVerticalTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.width = 200,
    this.indicatorColor,
    this.padding = const EdgeInsets.all(8),
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border(
          right: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return ListView.builder(
            padding: padding,
            itemCount: tabs.length,
            itemBuilder: (context, index) {
              final isSelected = controller.index == index;
              final tab = tabs[index];
              
              return GestureDetector(
                onTap: () => controller.animateTo(index),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (indicatorColor ?? theme.accentColor).withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? (indicatorColor ?? theme.accentColor).withOpacity(0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: ListTile(
                    leading: tab.icon,
                    title: tab.text != null
                        ? Text(
                            (tab.text as Text).data ?? '',
                            style: theme.bodyMedium.copyWith(
                              color: isSelected
                                  ? indicatorColor ?? theme.accentColor
                                  : Colors.white.withOpacity(0.7),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          )
                        : tab.child,
                    selected: isSelected,
                    selectedTileColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}