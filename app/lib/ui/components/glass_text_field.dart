import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';

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
  final Object? prefixIcon;
  final Object? suffixIcon;
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
  final String? initialValue;
  final TextStyle? textStyle;
  
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
    this.initialValue,
    this.textStyle,
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
    
    _controller = widget.controller ?? TextEditingController(
      text: widget.initialValue,
    );
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
                            color: glowColor.withValues(alpha: 
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
                                  GlassTheme.colorsOf(context).textLow.withValues(alpha: 0.1),
                                  GlassTheme.colorsOf(context).textLow.withValues(alpha: 0.05),
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
                style: GlassTypeScale.caption.copyWith(
                  color: widget.errorText != null
                      ? GlassTheme.colorsOf(context).error
                      : GlassTheme.colorsOf(context).textMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildTextField(GlassThemeData theme) {
    final tokens = GlassTheme.colorsOf(context);
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
      style: widget.textStyle ??
          GlassTypeScale.body.copyWith(
            color: widget.enabled ? tokens.textHigh : tokens.textLow,
          ),
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        labelStyle: GlassTypeScale.label.copyWith(
          color: _isFocused
              ? _getGlowColor()
              : tokens.textMedium,
        ),
        hintStyle: GlassTypeScale.caption.copyWith(
          color: tokens.textLow,
          fontSize: GlassTypeScale.body.fontSize,
        ),
        contentPadding: const EdgeInsets.all(16),
        border: InputBorder.none,
        counterText: '',
        prefixIcon: _buildPrefixIcon(),
        suffixIcon: _buildSuffixIcon(),
      ),
    );
  }
  
  Widget? _buildPrefixIcon() {
    final tokens = GlassTheme.colorsOf(context);
    final icon = widget.prefixIcon;
    if (icon is Widget) return icon;
    if (icon is IconData) {
      return Icon(icon, color: tokens.textMedium);
    }
    if (widget.isSearch) {
      return Icon(
        Icons.search,
        color: tokens.textMedium,
      );
    }
    return null;
  }
  
  Widget? _buildSuffixIcon() {
    final icons = <Widget>[];
    
    // Password toggle
    if (widget.enablePasswordToggle && widget.obscureText) {
      icons.add(
        IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility : Icons.visibility_off,
            color: GlassTheme.colorsOf(context).textMedium,
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
            color: GlassTheme.colorsOf(context).textMedium,
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
      final suffix = widget.suffixIcon;
      if (suffix is Widget) {
        icons.add(suffix);
      } else if (suffix is IconData) {
        icons.add(
          Icon(
            suffix,
            color: GlassTheme.colorsOf(context).textMedium,
          ),
        );
      }
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
            ? theme.borderColor.withValues(alpha: 0.5)
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