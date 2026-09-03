// Glass UI Component Examples

import 'package:flutter/material.dart';
import 'dart:ui';

// Example 1: Advanced Glass Container with Magnetic Hover
class MagneticGlassContainer extends StatefulWidget {
  final Widget child;
  final double magneticRange = 50.0;
  final double magneticStrength = 0.3;
  
  const MagneticGlassContainer({Key? key, required this.child}) : super(key: key);
  
  @override
  State<MagneticGlassContainer> createState() => _MagneticGlassContainerState();
}

class _MagneticGlassContainerState extends State<MagneticGlassContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Offset _mousePosition = Offset.zero;
  Offset _widgetPosition = Offset.zero;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
  }
  
  void _updateMagneticEffect(PointerEvent event) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(event.position);
    final center = Offset(box.size.width / 2, box.size.height / 2);
    final distance = (localPosition - center).distance;
    
    if (distance < widget.magneticRange) {
      final attraction = (widget.magneticRange - distance) / widget.magneticRange;
      final offset = (localPosition - center) * attraction * widget.magneticStrength;
      setState(() {
        _widgetPosition = offset;
      });
      _controller.forward();
    } else {
      setState(() {
        _widgetPosition = Offset.zero;
      });
      _controller.reverse();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _updateMagneticEffect,
      onExit: (_) {
        setState(() {
          _widgetPosition = Offset.zero;
        });
        _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: _widgetPosition * _controller.value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 20 + (_controller.value * 10),
                    offset: Offset(0, 10 + (_controller.value * 5)),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.15),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                        width: 1.5,
                      ),
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Example 2: Glass Morph Transition
class GlassMorphTransition extends StatefulWidget {
  final Widget firstChild;
  final Widget secondChild;
  final Duration duration;
  
  const GlassMorphTransition({
    Key? key,
    required this.firstChild,
    required this.secondChild,
    this.duration = const Duration(milliseconds: 800),
  }) : super(key: key);
  
  @override
  State<GlassMorphTransition> createState() => _GlassMorphTransitionState();
}

class _GlassMorphTransitionState extends State<GlassMorphTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _blurAnimation;
  bool _showSecond = false;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    _blurAnimation = Tween<double>(
      begin: 0.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeInOut),
    ));
  }
  
  void _toggle() {
    if (_showSecond) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() {
      _showSecond = !_showSecond;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // First child with blur and fade out
              Transform.scale(
                scale: _scaleAnimation.value,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: _blurAnimation.value,
                    sigmaY: _blurAnimation.value,
                  ),
                  child: Opacity(
                    opacity: _fadeAnimation.value,
                    child: widget.firstChild,
                  ),
                ),
              ),
              // Second child with inverse fade
              Opacity(
                opacity: 1 - _fadeAnimation.value,
                child: Transform.scale(
                  scale: 2 - _scaleAnimation.value,
                  child: widget.secondChild,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Example 3: Liquid Glass Effect
class LiquidGlassContainer extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  
  const LiquidGlassContainer({
    Key? key,
    required this.child,
    this.colors = const [Colors.blue, Colors.purple],
  }) : super(key: key);
  
  @override
  State<LiquidGlassContainer> createState() => _LiquidGlassContainerState();
}

class _LiquidGlassContainerState extends State<LiquidGlassContainer>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _morphController;
  
  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    
    _morphController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_waveController, _morphController]),
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CustomPaint(
              painter: LiquidGlassPainter(
                waveProgress: _waveController.value,
                morphProgress: _morphController.value,
                colors: widget.colors,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  @override
  void dispose() {
    _waveController.dispose();
    _morphController.dispose();
    super.dispose();
  }
}

class LiquidGlassPainter extends CustomPainter {
  final double waveProgress;
  final double morphProgress;
  final List<Color> colors;
  
  LiquidGlassPainter({
    required this.waveProgress,
    required this.morphProgress,
    required this.colors,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    
    // Create liquid gradient
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors.map((c) => c.withOpacity(0.3)).toList(),
      transform: GradientRotation(morphProgress * 2 * 3.14159),
    );
    
    paint.shader = gradient.createShader(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    
    // Draw liquid shapes
    final path = Path();
    
    for (int i = 0; i < 3; i++) {
      final offset = i * 0.3;
      final x = size.width * (0.5 + 0.3 * math.sin(waveProgress * 2 * 3.14159 + offset));
      final y = size.height * (0.5 + 0.3 * math.cos(waveProgress * 2 * 3.14159 + offset));
      final radius = size.width * (0.3 + 0.1 * math.sin(morphProgress * 2 * 3.14159 + offset));
      
      if (i == 0) {
        path.addOval(Rect.fromCircle(center: Offset(x, y), radius: radius));
      } else {
        final tempPath = Path()
          ..addOval(Rect.fromCircle(center: Offset(x, y), radius: radius));
        path.addPath(tempPath, Offset.zero);
      }
    }
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(LiquidGlassPainter oldDelegate) {
    return oldDelegate.waveProgress != waveProgress ||
           oldDelegate.morphProgress != morphProgress;
  }
}

// Example 4: Glass Shatter Effect
class GlassShatterTransition extends StatefulWidget {
  final Widget child;
  final VoidCallback onShatter;
  
  const GlassShatterTransition({
    Key? key,
    required this.child,
    required this.onShatter,
  }) : super(key: key);
  
  @override
  State<GlassShatterTransition> createState() => _GlassShatterTransitionState();
}

class _GlassShatterTransitionState extends State<GlassShatterTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<ShatterPiece> _pieces;
  bool _isShattered = false;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pieces = [];
  }
  
  void _shatter() {
    if (_isShattered) return;
    
    setState(() {
      _isShattered = true;
      _pieces = _generateShatterPieces();
    });
    
    _controller.forward().then((_) {
      widget.onShatter();
    });
  }
  
  List<ShatterPiece> _generateShatterPieces() {
    final pieces = <ShatterPiece>[];
    final random = math.Random();
    
    for (int i = 0; i < 20; i++) {
      pieces.add(ShatterPiece(
        position: Offset(
          random.nextDouble(),
          random.nextDouble(),
        ),
        size: 0.1 + random.nextDouble() * 0.1,
        rotation: random.nextDouble() * 2 * math.pi,
        velocity: Offset(
          (random.nextDouble() - 0.5) * 2,
          random.nextDouble() * 2,
        ),
      ));
    }
    
    return pieces;
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isShattered) {
      return GestureDetector(
        onLongPress: _shatter,
        child: widget.child,
      );
    }
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: _pieces.map((piece) {
            final progress = Curves.easeOut.transform(_controller.value);
            final position = piece.position + (piece.velocity * progress);
            final opacity = 1.0 - progress;
            final scale = 1.0 - (progress * 0.5);
            
            return Positioned(
              left: position.dx * MediaQuery.of(context).size.width,
              top: position.dy * MediaQuery.of(context).size.height,
              child: Transform.rotate(
                angle: piece.rotation * progress,
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: ClipPath(
                      clipper: RandomShapeClipper(),
                      child: Container(
                        width: piece.size * MediaQuery.of(context).size.width,
                        height: piece.size * MediaQuery.of(context).size.width,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class ShatterPiece {
  final Offset position;
  final double size;
  final double rotation;
  final Offset velocity;
  
  ShatterPiece({
    required this.position,
    required this.size,
    required this.rotation,
    required this.velocity,
  });
}

class RandomShapeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final random = math.Random();
    final points = <Offset>[];
    
    // Generate random polygon
    for (int i = 0; i < 5; i++) {
      final angle = (i / 5) * 2 * math.pi + (random.nextDouble() - 0.5) * 0.5;
      final radius = size.width * (0.3 + random.nextDouble() * 0.2);
      points.add(Offset(
        size.width / 2 + radius * math.cos(angle),
        size.height / 2 + radius * math.sin(angle),
      ));
    }
    
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    
    return path;
  }
  
  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

import 'dart:math' as math;