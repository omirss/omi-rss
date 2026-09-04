import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';
import '../tokens/glass_presets.dart';
import 'glass_button.dart';

/// Glass dialog sizes
enum GlassDialogSize {
  small(400, 300),
  medium(600, 400),
  large(800, 600),
  fullscreen(double.infinity, double.infinity);

  final double width;
  final double height;

  const GlassDialogSize(this.width, this.height);
}

/// Glass dialog with backdrop blur and animations
class GlassDialog extends StatefulWidget {
  final Widget? title;
  final Widget content;
  final List<Widget>? actions;
  final GlassDialogSize size;
  final bool dismissible;
  final VoidCallback? onDismiss;
  final double? blur;
  final List<Color>? gradientColors;
  final BorderRadius? borderRadius;
  final EdgeInsets? contentPadding;
  final GlassThemeData? theme;

  const GlassDialog({
    super.key,
    this.title,
    required this.content,
    this.actions,
    this.size = GlassDialogSize.medium,
    this.dismissible = true,
    this.onDismiss,
    this.blur,
    this.gradientColors,
    this.borderRadius,
    this.contentPadding,
    this.theme,
  });

  /// Shows the glass dialog with animations
  static Future<T?> show<T>({
    required BuildContext context,
    Widget? title,
    required Widget content,
    List<Widget>? actions,
    GlassDialogSize size = GlassDialogSize.medium,
    bool dismissible = true,
    double? blur,
    List<Color>? gradientColors,
    BorderRadius? borderRadius,
    EdgeInsets? contentPadding,
    GlassThemeData? theme,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: GlassPresets.glass.dark.overlay,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GlassDialog(
          title: title,
          content: content,
          actions: actions,
          size: size,
          dismissible: dismissible,
          onDismiss: () => Navigator.of(context).pop(),
          blur: blur,
          gradientColors: gradientColors,
          borderRadius: borderRadius,
          contentPadding: contentPadding,
          theme: theme,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.9,
              end: 1.0,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<GlassDialog> createState() => _GlassDialogState();

  /// Shows a loading dialog with glass effect
  static Future<void> showLoading({
    required BuildContext context,
    String? message,
  }) {
    return GlassLoadingDialog.show(context: context, message: message);
  }

  /// Shows a confirmation dialog returning true when confirmed
  static Future<bool?> showConfirmation({
    required BuildContext context,
    required String title,
    required String content,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    Color? confirmColor,
  }) {
    return showGlassDialog<bool>(
      context: context,
      title: Text(title),
      content: Text(
        content,
        style: GlassThemeData.fromTokens(GlassTheme.colorsOf(context)).bodyLarge,
      ),
      actions: [
        GlassButton(
          text: cancelText,
          onPressed: () => Navigator.of(context).pop(false),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: confirmText,
          onPressed: () => Navigator.of(context).pop(true),
          variant: GlassButtonVariant.elevated,
          gradientColors: confirmColor != null
              ? [confirmColor.withValues(alpha: 0.8), confirmColor.withValues(alpha: 0.6)]
              : null,
        ),
      ],
      size: GlassDialogSize.small,
    );
  }
}

class _GlassDialogState extends State<GlassDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _blurAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    ));

    _blurAnimation = Tween<double>(
      begin: 0.0,
      end: 10.0,
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

  void _handleDismiss() {
    if (widget.dismissible) {
      _animationController.reverse().then((_) {
        widget.onDismiss?.call();
      });
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GlassTheme.of(context);
    final screenSize = MediaQuery.of(context).size;
    
    // Calculate dialog size
    final dialogWidth = widget.size == GlassDialogSize.fullscreen
        ? screenSize.width
        : widget.size.width.clamp(0.0, screenSize.width * 0.9).toDouble();
    final dialogHeight = widget.size == GlassDialogSize.fullscreen
        ? screenSize.height
        : widget.size.height.clamp(0.0, screenSize.height * 0.9).toDouble();

    return GestureDetector(
      onTap: _handleDismiss,
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Stack(
              children: [
                // Backdrop blur
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: _blurAnimation.value,
                      sigmaY: _blurAnimation.value,
                    ),
                    child: Container(
                      color: GlassTheme.colorsOf(context).overlay
                          .withValues(alpha: 0.3 * _animationController.value),
                    ),
                  ),
                ),
                // Dialog
                Center(
                  child: GestureDetector(
                    onTap: () {}, // Prevent dismissal when tapping dialog
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        width: dialogWidth,
                        height: dialogHeight,
                        constraints: BoxConstraints(
                          maxWidth: dialogWidth,
                          maxHeight: dialogHeight,
                        ),
                        child: _buildDialogContent(theme),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDialogContent(GlassThemeData theme) {
    final tokens = GlassTheme.colorsOf(context);
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(GlassRadii.xl),
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
              colors: widget.gradientColors ?? theme.gradientColors,
            ),
            borderRadius: widget.borderRadius ?? BorderRadius.circular(GlassRadii.xl),
            border: Border.all(
              color: tokens.glassStroke,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: tokens.overlay.withValues(alpha: 0.2),
                blurRadius: GlassSpacing.xl,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.title != null) _buildTitle(),
              Flexible(
                child: SingleChildScrollView(
                  padding: widget.contentPadding ?? const EdgeInsets.all(24),
                  child: widget.content,
                ),
              ),
              if (widget.actions != null && widget.actions!.isNotEmpty)
                _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    final tokens = GlassTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(GlassSpacing.xl),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.divider,
            width: 1,
          ),
        ),
      ),
      child: DefaultTextStyle(
        style: GlassTypeScale.title.copyWith(color: tokens.textHigh),
        child: widget.title!,
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: GlassTheme.colorsOf(context).divider,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (int i = 0; i < widget.actions!.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            widget.actions![i],
          ],
        ],
      ),
    );
  }
}

/// Convenience method to show a glass dialog
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  Widget? title,
  required Widget content,
  List<Widget>? actions,
  GlassDialogSize size = GlassDialogSize.medium,
  bool dismissible = true,
  double? blur,
  List<Color>? gradientColors,
  BorderRadius? borderRadius,
  EdgeInsets? contentPadding,
  GlassThemeData? theme,
}) {
  return GlassDialog.show<T>(
    context: context,
    title: title,
    content: content,
    actions: actions,
    size: size,
    dismissible: dismissible,
    blur: blur,
    gradientColors: gradientColors,
    borderRadius: borderRadius,
    contentPadding: contentPadding,
    theme: theme,
  );
}

/// Convenience method for confirmation dialogs
Future<bool?> showGlassConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  bool destructive = false,
  GlassDialogSize size = GlassDialogSize.small,
}) {
  return showGlassDialog<bool>(
    context: context,
    title: Text(title),
    content: Text(
      message,
      style: GlassThemeData.fromTokens(GlassTheme.colorsOf(context)).bodyLarge,
    ),
    actions: [
      GlassButton(
        text: cancelText,
        onPressed: () => Navigator.of(context).pop(false),
        variant: GlassButtonVariant.text,
      ),
      GlassButton(
        text: confirmText,
        onPressed: () => Navigator.of(context).pop(true),
        variant: destructive
            ? GlassButtonVariant.elevated
            : GlassButtonVariant.elevated,
        gradientColors: destructive
            ? [
                Colors.red.withValues(alpha: 0.8),
                Colors.red.withValues(alpha: 0.6),
              ]
            : null,
      ),
    ],
    size: size,
  );
}

/// Loading dialog with glass effect
class GlassLoadingDialog extends StatelessWidget {
  final String? message;
  
  const GlassLoadingDialog({
    super.key,
    this.message,
  });

  static Future<void> show({
    required BuildContext context,
    String? message,
  }) {
    return showGlassDialog(
      context: context,
      content: GlassLoadingDialog(message: message),
      size: GlassDialogSize.small,
      dismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: GlassSpacing.xl),
          Text(
            message!,
            style: GlassTypeScale.body.copyWith(
              color: GlassTheme.colorsOf(context).textHigh,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}