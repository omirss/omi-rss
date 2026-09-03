import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// Animated gradient mesh background
class GradientMesh extends StatefulWidget {
  final List<MeshPoint> points;
  final double speed;
  final double blur;
  final Widget? child;
  
  const GradientMesh({
    super.key,
    required this.points,
    this.speed = 1.0,
    this.blur = 100,
    this.child,
  });
  
  factory GradientMesh.preset({
    Key? key,
    required MeshPreset preset,
    double speed = 1.0,
    double blur = 100,
    Widget? child,
  }) {
    return GradientMesh(
      key: key,
      points: _getPresetPoints(preset),
      speed: speed,
      blur: blur,
      child: child,
    );
  }
  
  static List<MeshPoint> _getPresetPoints(MeshPreset preset) {
    switch (preset) {
      case MeshPreset.ocean:
        return [
          MeshPoint(
            position: const Offset(0.2, 0.3),
            color: const Color(0xFF0EA5E9),
            radius: 0.4,
          ),
          MeshPoint(
            position: const Offset(0.8, 0.7),
            color: const Color(0xFF2563EB),
            radius: 0.5,
          ),
          MeshPoint(
            position: const Offset(0.5, 0.5),
            color: const Color(0xFF7C3AED),
            radius: 0.3,
          ),
        ];
      case MeshPreset.sunset:
        return [
          MeshPoint(
            position: const Offset(0.3, 0.2),
            color: const Color(0xFFF97316),
            radius: 0.5,
          ),
          MeshPoint(
            position: const Offset(0.7, 0.4),
            color: const Color(0xFFEC4899),
            radius: 0.4,
          ),
          MeshPoint(
            position: const Offset(0.5, 0.8),
            color: const Color(0xFF8B5CF6),
            radius: 0.3,
          ),
        ];
      case MeshPreset.aurora:
        return [
          MeshPoint(
            position: const Offset(0.1, 0.5),
            color: const Color(0xFF10B981),
            radius: 0.6,
          ),
          MeshPoint(
            position: const Offset(0.5, 0.2),
            color: const Color(0xFF3B82F6),
            radius: 0.4,
          ),
          MeshPoint(
            position: const Offset(0.9, 0.5),
            color: const Color(0xFFA855F7),
            radius: 0.5,
          ),
          MeshPoint(
            position: const Offset(0.5, 0.8),
            color: const Color(0xFF0EA5E9),
            radius: 0.3,
          ),
        ];
      case MeshPreset.cosmic:
        return [
          MeshPoint(
            position: const Offset(0.2, 0.2),
            color: const Color(0xFF6366F1),
            radius: 0.3,
          ),
          MeshPoint(
            position: const Offset(0.8, 0.3),
            color: const Color(0xFFEC4899),
            radius: 0.4,
          ),
          MeshPoint(
            position: const Offset(0.3, 0.8),
            color: const Color(0xFF8B5CF6),
            radius: 0.5,
          ),
          MeshPoint(
            position: const Offset(0.7, 0.7),
            color: const Color(0xFF0EA5E9),
            radius: 0.3,
          ),
        ];
    }
  }
  
  @override
  State<GradientMesh> createState() => _GradientMeshState();
}

class _GradientMeshState extends State<GradientMesh>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<Offset>> _positionAnimations;
  late List<Animation<double>> _radiusAnimations;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }
  
  void _initializeAnimations() {
    _controllers = [];
    _positionAnimations = [];
    _radiusAnimations = [];
    
    for (int i = 0; i < widget.points.length; i++) {
      final controller = AnimationController(
        duration: Duration(seconds: (10 + i * 2) ~/ widget.speed),
        vsync: this,
      );
      
      // Create circular motion path
      final positionAnimation = TweenSequence<Offset>([
        TweenSequenceItem(
          tween: Tween<Offset>(
            begin: widget.points[i].position,
            end: _getNextPosition(widget.points[i].position, 0),
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 25,
        ),
        TweenSequenceItem(
          tween: Tween<Offset>(
            begin: _getNextPosition(widget.points[i].position, 0),
            end: _getNextPosition(widget.points[i].position, 1),
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 25,
        ),
        TweenSequenceItem(
          tween: Tween<Offset>(
            begin: _getNextPosition(widget.points[i].position, 1),
            end: _getNextPosition(widget.points[i].position, 2),
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 25,
        ),
        TweenSequenceItem(
          tween: Tween<Offset>(
            begin: _getNextPosition(widget.points[i].position, 2),
            end: widget.points[i].position,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 25,
        ),
      ]).animate(controller);
      
      // Create radius pulsing animation
      final radiusAnimation = Tween<double>(
        begin: widget.points[i].radius * 0.8,
        end: widget.points[i].radius * 1.2,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      ));
      
      _controllers.add(controller);
      _positionAnimations.add(positionAnimation);
      _radiusAnimations.add(radiusAnimation);
      
      controller.repeat();
    }
  }
  
  Offset _getNextPosition(Offset current, int step) {
    final angle = (step * math.pi / 2) + (math.Random().nextDouble() - 0.5);
    final distance = 0.1 + (math.Random().nextDouble() * 0.1);
    
    return Offset(
      (current.dx + math.cos(angle) * distance).clamp(0.0, 1.0),
      (current.dy + math.sin(angle) * distance).clamp(0.0, 1.0),
    );
  }
  
  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient mesh background
        Positioned.fill(
          child: AnimatedBuilder(
            animation: Listenable.merge(_controllers),
            builder: (context, _) {
              return CustomPaint(
                painter: GradientMeshPainter(
                  points: List.generate(widget.points.length, (i) {
                    return AnimatedMeshPoint(
                      position: _positionAnimations[i].value,
                      color: widget.points[i].color,
                      radius: _radiusAnimations[i].value,
                    );
                  }),
                  blur: widget.blur,
                ),
              );
            },
          ),
        ),
        // Child content
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

/// Mesh point configuration
class MeshPoint {
  final Offset position;
  final Color color;
  final double radius;
  
  const MeshPoint({
    required this.position,
    required this.color,
    required this.radius,
  });
}

/// Animated mesh point
class AnimatedMeshPoint extends MeshPoint {
  const AnimatedMeshPoint({
    required Offset position,
    required Color color,
    required double radius,
  }) : super(position: position, color: color, radius: radius);
}

/// Gradient mesh painter
class GradientMeshPainter extends CustomPainter {
  final List<AnimatedMeshPoint> points;
  final double blur;
  
  GradientMeshPainter({
    required this.points,
    required this.blur,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Create mesh by drawing gradient circles
    for (final point in points) {
      final center = Offset(
        point.position.dx * size.width,
        point.position.dy * size.height,
      );
      
      final radius = point.radius * math.min(size.width, size.height);
      
      // Create radial gradient
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            point.color.withOpacity(0.6),
            point.color.withOpacity(0.3),
            point.color.withOpacity(0.0),
          ],
          [0.0, 0.5, 1.0],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      
      canvas.drawCircle(center, radius, paint);
    }
  }
  
  @override
  bool shouldRepaint(GradientMeshPainter oldDelegate) {
    return true; // Always repaint for smooth animation
  }
}

/// Preset gradient mesh configurations
enum MeshPreset {
  ocean,
  sunset,
  aurora,
  cosmic,
}

/// Interactive gradient mesh that responds to touch
class InteractiveGradientMesh extends StatefulWidget {
  final List<MeshPoint> basePoints;
  final double interactionRadius;
  final double interactionStrength;
  final Widget? child;
  
  const InteractiveGradientMesh({
    super.key,
    required this.basePoints,
    this.interactionRadius = 150,
    this.interactionStrength = 0.3,
    this.child,
  });
  
  @override
  State<InteractiveGradientMesh> createState() => _InteractiveGradientMeshState();
}

class _InteractiveGradientMeshState extends State<InteractiveGradientMesh>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Offset? _touchPosition;
  final List<Offset> _pointOffsets = [];
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    // Initialize offsets
    for (int i = 0; i < widget.basePoints.length; i++) {
      _pointOffsets.add(Offset.zero);
    }
  }
  
  void _updateTouch(Offset? position) {
    setState(() {
      _touchPosition = position;
      
      if (position != null) {
        _controller.forward();
        
        // Calculate offsets for each point based on touch
        for (int i = 0; i < widget.basePoints.length; i++) {
          final point = widget.basePoints[i];
          final pointPos = Offset(
            point.position.dx * context.size!.width,
            point.position.dy * context.size!.height,
          );
          
          final distance = (position - pointPos).distance;
          
          if (distance < widget.interactionRadius) {
            final strength = 1.0 - (distance / widget.interactionRadius);
            final direction = (pointPos - position).direction;
            final offset = Offset.fromDirection(
              direction,
              strength * widget.interactionStrength * 50,
            );
            
            _pointOffsets[i] = offset;
          } else {
            _pointOffsets[i] = Offset.zero;
          }
        }
      } else {
        _controller.reverse();
        
        // Reset offsets
        for (int i = 0; i < _pointOffsets.length; i++) {
          _pointOffsets[i] = Offset.zero;
        }
      }
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) => _updateTouch(event.position),
      onExit: (_) => _updateTouch(null),
      child: GestureDetector(
        onPanUpdate: (details) => _updateTouch(details.globalPosition),
        onPanEnd: (_) => _updateTouch(null),
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: GradientMeshPainter(
                    points: List.generate(widget.basePoints.length, (i) {
                      final basePoint = widget.basePoints[i];
                      final offset = _pointOffsets[i] * _controller.value;
                      
                      return AnimatedMeshPoint(
                        position: Offset(
                          basePoint.position.dx + offset.dx / context.size!.width,
                          basePoint.position.dy + offset.dy / context.size!.height,
                        ),
                        color: basePoint.color,
                        radius: basePoint.radius,
                      );
                    }),
                    blur: 100,
                  ),
                );
              },
            ),
            if (widget.child != null) widget.child!,
          ],
        ),
      ),
    );
  }
}