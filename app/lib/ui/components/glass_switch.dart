import 'package:flutter/material.dart';
import '../glass_theme.dart';

class GlassSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final double width;
  final double height;
  
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 52,
    this.height = 28,
  });
  
  @override
  Widget build(BuildContext context) {
    final tokens = GlassTheme.colorsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: value
              ? LinearGradient(
                  colors: tokens.primaryGradient,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: value ? null : tokens.glassFill,
          border: Border.all(
            color: tokens.glassStroke,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: value
                  ? tokens.primary.withValues(alpha: 0.3)
                  : tokens.overlay.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: value ? width - height + 2 : 2,
              top: 2,
              child: Container(
                width: height - 4,
                height: height - 4,
                decoration: BoxDecoration(
                  color: tokens.textHigh,
                  borderRadius: BorderRadius.circular((height - 4) / 2),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.overlay.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}