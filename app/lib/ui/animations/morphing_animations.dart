import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// Morphing animation types
enum MorphType {
  shape,
  blur,
  size,
  color,
  all,
}

/// Morphing animation widget for smooth transitions
class MorphingAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final MorphType morphType;
  final VoidCallback? onComplete;
  
  const MorphingAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 800),
    this.curve = Curves.easeInOutCubic,
    this.morphType = MorphType.all,
    this.onComplete,
  });

  @override
  State<MorphingAnimation> createState() => _MorphingAnimationState();
}

class _MorphingAnimationState extends State<MorphingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  Widget? _oldChild;
  Widget? _newChild;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    
    _animation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );
    
    _newChild = widget.child;
    
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _oldChild = null;
          _isTransitioning = false;
        });
        widget.onComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(MorphingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.child.key != oldWidget.child.key) {
      setState(() {
        _isTransitioning = true;
        _oldChild = _newChild;
        _newChild = widget.child;
      });
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isTransitioning) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          children: [
            if (_oldChild != null)
              _buildMorphingChild(
                _oldChild!,
                1 - _animation.value,
                true,
              ),
            _buildMorphingChild(
              _newChild!,
              _animation.value,
              false,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMorphingChild(Widget child, double progress, bool isOld) {
    switch (widget.morphType) {
      case MorphType.shape:
        return _buildShapeMorph(child, progress, isOld);
      case MorphType.blur:
        return _buildBlurMorph(child, progress, isOld);
      case MorphType.size:
        return _buildSizeMorph(child, progress, isOld);
      case MorphType.color:
        return _buildColorMorph(child, progress, isOld);
      case MorphType.all:
        return _buildAllMorph(child, progress, isOld);
    }
  }

  Widget _buildShapeMorph(Widget child, double progress, bool isOld) {
    return ClipPath(
      clipper: _MorphingClipper(progress, isOld),
      child: child,
    );
  }

  Widget _buildBlurMorph(Widget child, double progress, bool isOld) {
    final blur = isOld ? (1 - progress) * 10 : (1 - progress) * 10;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: blur,
        sigmaY: blur,
      ),
      child: Opacity(
        opacity: progress,
        child: child,
      ),
    );
  }

  Widget _buildSizeMorph(Widget child, double progress, bool isOld) {
    final scale = isOld 
        ? 1 + (1 - progress) * 0.2 
        : 0.8 + progress * 0.2;
    
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: progress,
        child: child,
      ),
    );
  }

  Widget _buildColorMorph(Widget child, double progress, bool isOld) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.white.withOpacity(1 - progress),
        isOld ? BlendMode.dstOut : BlendMode.dstIn,
      ),
      child: child,
    );
  }

  Widget _buildAllMorph(Widget child, double progress, bool isOld) {
    final scale = isOld 
        ? 1 + (1 - progress) * 0.1 
        : 0.9 + progress * 0.1;
    final blur = isOld ? (1 - progress) * 5 : (1 - progress) * 5;
    
    return Transform.scale(
      scale: scale,
      child: ClipPath(
        clipper: _MorphingClipper(progress, isOld),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blur,
            sigmaY: blur,
          ),
          child: Opacity(
            opacity: progress,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MorphingClipper extends CustomClipper<Path> {
  final double progress;
  final bool isOld;

  _MorphingClipper(this.progress, this.isOld);

  @override
  Path getClip(Size size) {
    final path = Path();
    
    if (isOld) {
      // Morph out with circular reveal
      final radius = size.width * progress;
      path.addOval(Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: radius * 2,
        height: radius * 2,
      ));
    } else {
      // Morph in with expanding rectangle
      final inset = size.width * (1 - progress) / 2;
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset),
        Radius.circular(20 * (1 - progress)),
      ));
    }
    
    return path;
  }

  @override
  bool shouldReclip(_MorphingClipper oldClipper) {
    return progress != oldClipper.progress || isOld != oldClipper.isOld;
  }
}

/// Morphing container that transitions between states
class MorphingContainer extends StatefulWidget {
  final double? width;
  final double? height;
  final EdgeInsets? padding;
  final BoxDecoration? decoration;
  final Widget? child;
  final Duration duration;
  final Curve curve;
  
  const MorphingContainer({
    super.key,
    this.width,
    this.height,
    this.padding,
    this.decoration,
    this.child,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeInOutCubic,
  });

  @override
  State<MorphingContainer> createState() => _MorphingContainerState();
}

class _MorphingContainerState extends State<MorphingContainer>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: widget.duration,
      curve: widget.curve,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: widget.decoration,
      child: widget.child,
    );
  }
}

/// Morphing text that smoothly transitions between values
class MorphingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;
  
  const MorphingText(
    this.text, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeInOut,
  });

  @override
  State<MorphingText> createState() => _MorphingTextState();
}

class _MorphingTextState extends State<MorphingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  String _oldText = '';
  String _newText = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    
    _animation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );
    
    _newText = widget.text;
  }

  @override
  void didUpdateWidget(MorphingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.text != oldWidget.text) {
      _oldText = _newText;
      _newText = widget.text;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          children: [
            if (_oldText.isNotEmpty)
              Opacity(
                opacity: 1 - _animation.value,
                child: Transform.scale(
                  scale: 1 - _animation.value * 0.1,
                  child: Text(_oldText, style: widget.style),
                ),
              ),
            Opacity(
              opacity: _animation.value,
              child: Transform.scale(
                scale: 0.9 + _animation.value * 0.1,
                child: Text(_newText, style: widget.style),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Page route with morphing transition
class MorphingPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;
  
  MorphingPageRoute({
    required this.page,
    this.duration = const Duration(milliseconds: 600),
  }) : super(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(0.0, 0.1);
      const end = Offset.zero;
      const curve = Curves.easeInOutCubic;
      
      var slideTween = Tween(begin: begin, end: end).chain(
        CurveTween(curve: curve),
      );
      var fadeTween = Tween(begin: 0.0, end: 1.0).chain(
        CurveTween(curve: curve),
      );
      var scaleTween = Tween(begin: 0.9, end: 1.0).chain(
        CurveTween(curve: curve),
      );
      
      return SlideTransition(
        position: animation.drive(slideTween),
        child: FadeTransition(
          opacity: animation.drive(fadeTween),
          child: ScaleTransition(
            scale: animation.drive(scaleTween),
            child: child,
          ),
        ),
      );
    },
  );
}