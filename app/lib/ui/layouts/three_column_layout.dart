import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/glass_container.dart';
import '../glass_theme.dart';

/// Column configuration for three-column layout
class ColumnConfig {
  final double minWidth;
  final double maxWidth;
  final double initialWidth;
  final bool collapsible;
  
  const ColumnConfig({
    this.minWidth = 200,
    this.maxWidth = 600,
    this.initialWidth = 300,
    this.collapsible = true,
  });
}

/// Three-column layout with draggable dividers
class ThreeColumnLayout extends StatefulWidget {
  final Widget leftPanel;
  final Widget middlePanel;
  final Widget rightPanel;
  final ColumnConfig leftConfig;
  final ColumnConfig middleConfig;
  final ColumnConfig rightConfig;
  final bool saveLayoutPreferences;
  final Color? dividerColor;
  final double dividerWidth;
  final bool enableAnimations;
  final Duration animationDuration;
  
  const ThreeColumnLayout({
    super.key,
    required this.leftPanel,
    required this.middlePanel,
    required this.rightPanel,
    this.leftConfig = const ColumnConfig(
      minWidth: 200,
      maxWidth: 400,
      initialWidth: 250,
    ),
    this.middleConfig = const ColumnConfig(
      minWidth: 300,
      maxWidth: 800,
      initialWidth: 400,
    ),
    this.rightConfig = const ColumnConfig(
      minWidth: 300,
      maxWidth: double.infinity,
      initialWidth: 500,
    ),
    this.saveLayoutPreferences = true,
    this.dividerColor,
    this.dividerWidth = 8.0,
    this.enableAnimations = true,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<ThreeColumnLayout> createState() => _ThreeColumnLayoutState();
}

class _ThreeColumnLayoutState extends State<ThreeColumnLayout>
    with TickerProviderStateMixin {
  late double _leftWidth;
  late double _middleWidth;
  late double _rightWidth;
  
  bool _leftCollapsed = false;
  bool _rightCollapsed = false;
  
  // Animation controllers
  late AnimationController _leftCollapseController;
  late AnimationController _rightCollapseController;
  late Animation<double> _leftCollapseAnimation;
  late Animation<double> _rightCollapseAnimation;
  
  // Dragging state
  bool _isDraggingLeft = false;
  bool _isDraggingRight = false;
  double _dragStartX = 0;
  double _startLeftWidth = 0;
  double _startMiddleWidth = 0;
  double _startRightWidth = 0;

  @override
  void initState() {
    super.initState();
    
    _leftWidth = widget.leftConfig.initialWidth;
    _middleWidth = widget.middleConfig.initialWidth;
    _rightWidth = widget.rightConfig.initialWidth;
    
    // Initialize animation controllers
    _leftCollapseController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    
    _rightCollapseController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    
    _leftCollapseAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _leftCollapseController,
      curve: Curves.easeInOutCubic,
    ));
    
    _rightCollapseAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _rightCollapseController,
      curve: Curves.easeInOutCubic,
    ));
    
    // Load saved preferences
    if (widget.saveLayoutPreferences) {
      _loadLayoutPreferences();
    }
  }
  
  void _loadLayoutPreferences() {
    // TODO: Implement loading from SharedPreferences
  }
  
  void _saveLayoutPreferences() {
    // TODO: Implement saving to SharedPreferences
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final theme = GlassTheme.of(context);
    
    // Calculate actual widths
    final actualLeftWidth = _leftCollapsed ? 60 : _leftWidth;
    final actualRightWidth = _rightCollapsed ? 60 : _rightWidth;
    final actualMiddleWidth = screenWidth - actualLeftWidth - actualRightWidth - (widget.dividerWidth * 2);
    
    return Row(
      children: [
        // Left Panel
        AnimatedContainer(
          duration: widget.enableAnimations ? widget.animationDuration : Duration.zero,
          width: actualLeftWidth,
          child: Stack(
            children: [
              // Panel content
              AnimatedBuilder(
                animation: _leftCollapseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _leftCollapsed ? 0.0 : 1.0,
                    child: ClipRect(
                      child: OverflowBox(
                        maxWidth: _leftWidth,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: _leftWidth,
                          child: widget.leftPanel,
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Collapse button
              if (widget.leftConfig.collapsible)
                Positioned(
                  right: 0,
                  top: 16,
                  child: _buildCollapseButton(
                    isCollapsed: _leftCollapsed,
                    onTap: () => _toggleLeftPanel(),
                    alignment: Alignment.centerRight,
                  ),
                ),
            ],
          ),
        ),
        
        // Left Divider
        _buildDivider(
          onDragStart: (details) => _startLeftDrag(details, actualLeftWidth, actualMiddleWidth),
          onDragUpdate: _updateLeftDrag,
          onDragEnd: _endLeftDrag,
          isActive: _isDraggingLeft,
        ),
        
        // Middle Panel
        Expanded(
          child: widget.middlePanel,
        ),
        
        // Right Divider
        _buildDivider(
          onDragStart: (details) => _startRightDrag(details, actualMiddleWidth, actualRightWidth),
          onDragUpdate: _updateRightDrag,
          onDragEnd: _endRightDrag,
          isActive: _isDraggingRight,
        ),
        
        // Right Panel
        AnimatedContainer(
          duration: widget.enableAnimations ? widget.animationDuration : Duration.zero,
          width: actualRightWidth,
          child: Stack(
            children: [
              // Panel content
              AnimatedBuilder(
                animation: _rightCollapseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _rightCollapsed ? 0.0 : 1.0,
                    child: ClipRect(
                      child: OverflowBox(
                        maxWidth: _rightWidth,
                        alignment: Alignment.topRight,
                        child: SizedBox(
                          width: _rightWidth,
                          child: widget.rightPanel,
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Collapse button
              if (widget.rightConfig.collapsible)
                Positioned(
                  left: 0,
                  top: 16,
                  child: _buildCollapseButton(
                    isCollapsed: _rightCollapsed,
                    onTap: () => _toggleRightPanel(),
                    alignment: Alignment.centerLeft,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildDivider({
    required GestureDragStartCallback onDragStart,
    required GestureDragUpdateCallback onDragUpdate,
    required GestureDragEndCallback onDragEnd,
    required bool isActive,
  }) {
    final theme = GlassTheme.of(context);
    
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: onDragStart,
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: onDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.dividerWidth,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: isActive ? 4 : 2,
              decoration: BoxDecoration(
                color: widget.dividerColor ?? 
                    (isActive 
                        ? GlassColors.accentGradient[0].withOpacity(0.5)
                        : theme.borderColor),
                borderRadius: BorderRadius.circular(2),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: GlassColors.accentGradient[0].withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildCollapseButton({
    required bool isCollapsed,
    required VoidCallback onTap,
    required Alignment alignment,
  }) {
    return GlassContainer(
      width: 32,
      height: 32,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Center(
        child: Icon(
          alignment == Alignment.centerLeft
              ? (isCollapsed ? Icons.chevron_left : Icons.chevron_right)
              : (isCollapsed ? Icons.chevron_right : Icons.chevron_left),
          color: Colors.white.withOpacity(0.7),
          size: 20,
        ),
      ),
    );
  }
  
  void _toggleLeftPanel() {
    setState(() {
      _leftCollapsed = !_leftCollapsed;
      if (_leftCollapsed) {
        _leftCollapseController.forward();
      } else {
        _leftCollapseController.reverse();
      }
    });
    HapticFeedback.lightImpact();
    if (widget.saveLayoutPreferences) {
      _saveLayoutPreferences();
    }
  }
  
  void _toggleRightPanel() {
    setState(() {
      _rightCollapsed = !_rightCollapsed;
      if (_rightCollapsed) {
        _rightCollapseController.forward();
      } else {
        _rightCollapseController.reverse();
      }
    });
    HapticFeedback.lightImpact();
    if (widget.saveLayoutPreferences) {
      _saveLayoutPreferences();
    }
  }
  
  void _startLeftDrag(DragStartDetails details, double leftWidth, double middleWidth) {
    setState(() {
      _isDraggingLeft = true;
      _dragStartX = details.globalPosition.dx;
      _startLeftWidth = leftWidth;
      _startMiddleWidth = middleWidth;
    });
    HapticFeedback.selectionClick();
  }
  
  void _updateLeftDrag(DragUpdateDetails details) {
    final delta = details.globalPosition.dx - _dragStartX;
    setState(() {
      _leftWidth = (_startLeftWidth + delta).clamp(
        widget.leftConfig.minWidth,
        widget.leftConfig.maxWidth,
      );
    });
  }
  
  void _endLeftDrag(DragEndDetails details) {
    setState(() {
      _isDraggingLeft = false;
    });
    if (widget.saveLayoutPreferences) {
      _saveLayoutPreferences();
    }
  }
  
  void _startRightDrag(DragStartDetails details, double middleWidth, double rightWidth) {
    setState(() {
      _isDraggingRight = true;
      _dragStartX = details.globalPosition.dx;
      _startMiddleWidth = middleWidth;
      _startRightWidth = rightWidth;
    });
    HapticFeedback.selectionClick();
  }
  
  void _updateRightDrag(DragUpdateDetails details) {
    final delta = details.globalPosition.dx - _dragStartX;
    setState(() {
      _rightWidth = (_startRightWidth - delta).clamp(
        widget.rightConfig.minWidth,
        widget.rightConfig.maxWidth,
      );
    });
  }
  
  void _endRightDrag(DragEndDetails details) {
    setState(() {
      _isDraggingRight = false;
    });
    if (widget.saveLayoutPreferences) {
      _saveLayoutPreferences();
    }
  }

  @override
  void dispose() {
    _leftCollapseController.dispose();
    _rightCollapseController.dispose();
    super.dispose();
  }
}