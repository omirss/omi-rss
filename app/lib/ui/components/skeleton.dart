import 'package:flutter/material.dart';
import '../glass_theme.dart';

/// Single shimmering skeleton block.
class GlassSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const GlassSkeleton({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  State<GlassSkeleton> createState() => _GlassSkeletonState();
}

class _GlassSkeletonState extends State<GlassSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTheme.colorsOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dx = -1.0 + 2.0 * _controller.value;
        return ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                tokens.skeletonBase,
                tokens.skeletonHighlight,
                tokens.skeletonBase,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: GradientTranslation(dx * rect.width),
            ).createShader(rect);
          },
          child: child,
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: tokens.skeletonBase,
          borderRadius: widget.borderRadius,
        ),
      ),
    );
  }
}

class GradientTranslation extends GradientTransform {
  final double dx;

  const GradientTranslation(this.dx);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0, 0);
  }
}

/// Article-row-shaped skeleton list used as the single loading pattern for
/// article list surfaces (home, saved, search, discover).
class GlassSkeletonList extends StatelessWidget {
  final int itemCount;

  const GlassSkeletonList({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) => const GlassSkeletonArticleRow(),
    );
  }
}

class GlassSkeletonArticleRow extends StatelessWidget {
  const GlassSkeletonArticleRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassSkeleton(
            width: 40,
            height: 40,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassSkeleton(width: 200, height: 14),
                SizedBox(height: 8),
                GlassSkeleton(height: 14),
                SizedBox(height: 8),
                GlassSkeleton(width: 160, height: 11),
                SizedBox(height: 8),
                GlassSkeleton(height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
