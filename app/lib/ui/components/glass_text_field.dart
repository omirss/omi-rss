import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';

/// Glass text field states
enum GlassTextFieldState {
  normal,
  focused,
  error,
  success,
}

/// Glass text field with floating label and various states
class GlassTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final bool obscureText;
  final bool enablePasswordToggle;
  final bool enableClearButton;
  final bool isSearch;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final GlassTextFieldState? state;
  final GlassThemeData? theme;
  final bool enabled;
  final FocusNode? focusNode;
  
  const GlassTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.enablePasswordToggle = false,
    this.enableClearButton = false,
    this.isSearch = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.validator,
    this.state,
    this.theme,
    this.enabled = true,
    this.focusNode,
  });

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField>
    with TickerProviderStateMixin {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  late AnimationController _focusAnimationController;
  late AnimationController _glowAnimationController;
  late Animation<double> _focusAnimation;
  late Animation<double> _glowAnimation;
  
  bool _isFocused = false;
  bool _isHovered = false;
  bool _obscureText = false;
  GlassTextFieldState _currentState = GlassTextFieldState.normal;

  @override
  void initState() {
    super.initState();
    
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _obscureText = widget.obscureText;
    
    _focusAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _glowAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _focusAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _focusAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _focusNode.addListener(_handleFocusChange);
    _controller.addListener(_handleTextChange);
    
    // Update state based on initial values
    _updateState();
  }
  
  void _handleFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
      if (_isFocused) {
        _focusAnimationController.forward();
        _glowAnimationController.repeat(reverse: true);
        HapticFeedback.selectionClick();
      } else {
        _focusAnimationController.reverse();
        _glowAnimationController.stop();
      }
    });
    _updateState();
  }
  
  void _handleTextChange() {
    _updateState();
  }
  
  void _updateState() {
    setState(() {
      if (widget.state != null) {
        _currentState = widget.state!;
      } else if (widget.errorText != null) {
        _currentState = GlassTextFieldState.error;
      } else if (_isFocused) {
        _currentState = GlassTextFieldState.focused;
      } else {
        _currentState = GlassTextFieldState.normal;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GlassTheme.of(context);
    final glowColor = _getGlowColor();
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_focusAnimation, _glowAnimation]),
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: theme.borderRadius,
                  boxShadow: _currentState != GlassTextFieldState.normal
                      ? [
                          BoxShadow(
                            color: glowColor.withOpacity(
                              _glowAnimation.value * 0.4,
                            ),
                            blurRadius: 16,
                            spreadRadius: _focusAnimation.value * 2,
                          ),
                        ]
                      : [],
                ),
                child: ClipRRect(
                  borderRadius: theme.borderRadius,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: theme.blur,
                      sigmaY: theme.blur,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: widget.enabled
                              ? theme.gradientColors
                              : [
                                  Colors.grey.withOpacity(0.1),
                                  Colors.grey.withOpacity(0.05),
                                ],
                        ),
                        borderRadius: theme.borderRadius,
                        border: Border.all(
                          color: _getBorderColor(theme),
                          width: _isFocused ? 2 : theme.borderWidth,
                        ),
                      ),
                      child: _buildTextField(theme),
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.helperText != null || widget.errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16),
              child: Text(
                widget.errorText ?? widget.helperText!,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.errorText != null
                      ? Colors.red[400]
                      : Colors.white.withOpacity(0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildTextField(GlassThemeData theme) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      obscureText: _obscureText,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      onEditingComplete: widget.onEditingComplete,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(
        color: widget.enabled ? Colors.white : Colors.white.withOpacity(0.5),
        fontSize: 16,
      ),
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        labelStyle: TextStyle(
          color: _isFocused 
              ? _getGlowColor() 
              : Colors.white.withOpacity(0.7),
        ),
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.5),
        ),
        contentPadding: const EdgeInsets.all(16),
        border: InputBorder.none,
        counterText: '',
        prefixIcon: widget.prefixIcon != null || widget.isSearch
            ? Icon(
                widget.prefixIcon ?? Icons.search,
                color: Colors.white.withOpacity(0.7),
              )
            : null,
        suffixIcon: _buildSuffixIcon(),
      ),
    );
  }
  
  Widget? _buildSuffixIcon() {
    final icons = <Widget>[];
    
    // Password toggle
    if (widget.enablePasswordToggle && widget.obscureText) {
      icons.add(
        IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility : Icons.visibility_off,
            color: Colors.white.withOpacity(0.7),
          ),
          onPressed: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
        ),
      );
    }
    
    // Clear button
    if (widget.enableClearButton && _controller.text.isNotEmpty) {
      icons.add(
        IconButton(
          icon: Icon(
            Icons.clear,
            color: Colors.white.withOpacity(0.7),
          ),
          onPressed: () {
            _controller.clear();
            widget.onChanged?.call('');
          },
        ),
      );
    }
    
    // Custom suffix icon
    if (widget.suffixIcon != null) {
      icons.add(
        Icon(
          widget.suffixIcon,
          color: Colors.white.withOpacity(0.7),
        ),
      );
    }
    
    if (icons.isEmpty) return null;
    if (icons.length == 1) return icons.first;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: icons,
    );
  }
  
  Color _getBorderColor(GlassThemeData theme) {
    switch (_currentState) {
      case GlassTextFieldState.normal:
        return _isHovered
            ? theme.borderColor.withOpacity(0.5)
            : theme.borderColor;
      case GlassTextFieldState.focused:
        return GlassColors.accentGradient[0];
      case GlassTextFieldState.error:
        return Colors.red[400]!;
      case GlassTextFieldState.success:
        return Colors.green[400]!;
    }
  }
  
  Color _getGlowColor() {
    switch (_currentState) {
      case GlassTextFieldState.normal:
      case GlassTextFieldState.focused:
        return GlassColors.accentGradient[0];
      case GlassTextFieldState.error:
        return Colors.red[400]!;
      case GlassTextFieldState.success:
        return Colors.green[400]!;
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    _focusAnimationController.dispose();
    _glowAnimationController.dispose();
    super.dispose();
  }
}