import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../glass_theme.dart';

/// Particle model for floating orbs
class Particle {
  late double x, y;
  late double size;
  late double speed;
  late double opacity;
  late Color color;
  late double wobbleOffset;
  late double wobbleSpeed;
  late double glowIntensity;
  
  // Motion properties
  late double vx, vy;
  late double targetX, targetY;
  
  Particle.random() {
    final random = math.Random();
    reset(random);
  }
  
  void reset(math.Random random) {
    x = random.nextDouble();
    y = random.nextDouble() * 1.2 - 0.1; // Start slightly off screen
    size = random.nextDouble() * 6 + 2;
    speed = random.nextDouble() * 0.3 + 0.1;
    opacity = random.nextDouble() * 0.5 + 0.3;
    wobbleOffset = random.nextDouble() * math.pi * 2;
    wobbleSpeed = random.nextDouble() * 0.02 + 0.01;
    glowIntensity = random.nextDouble() * 0.5 + 0.5;
    
    // Random color from gradient
    color = Color.lerp(
      GlassColors.auroraColors[random.nextInt(GlassColors.auroraColors.length)],
      GlassColors.primaryGradient[random.nextInt(GlassColors.primaryGradient.length)],
      random.nextDouble(),
    )!;
    
    // Initialize velocity
    vx = (random.nextDouble() - 0.5) * 0.001;
    vy = -speed * 0.01;
    
    // Random target for attraction
    targetX = random.nextDouble();
    targetY = random.nextDouble();
  }
  
  void update(double deltaTime, double time, Size size, {Offset? mousePosition}) {
    // Vertical movement
    y += vy * deltaTime;
    
    // Horizontal wobble
    final wobble = math.sin(time * wobbleSpeed + wobbleOffset) * 0.02;
    x += vx * deltaTime + wobble;
    
    // Mouse interaction
    if (mousePosition != null) {
      final dx = (mousePosition.dx / size.width) - x;
      final dy = (mousePosition.dy / size.height) - y;
      final distance = math.sqrt(dx * dx + dy * dy);
      
      if (distance < 0.2) {
        // Repel from mouse
        final force = (0.2 - distance) * 0.001;
        vx -= dx * force;
        vy -= dy * force;
      }
    }
    
    // Attraction to target (creates swirling patterns)
    final targetDx = targetX - x;
    final targetDy = targetY - y;
    vx += targetDx * 0.00001;
    vy += targetDy * 0.00001;
    
    // Apply damping
    vx *= 0.99;
    vy *= 0.99;
    
    // Wrap around edges
    if (y < -0.1) {
      y = 1.1;
      x = math.Random().nextDouble();
      targetX = math.Random().nextDouble();
      targetY = math.Random().nextDouble();
    }
    if (x < -0.1) x = 1.1;
    if (x > 1.1) x = -0.1;
    
    // Update glow intensity
    glowIntensity = 0.5 + math.sin(time * 0.001 + wobbleOffset) * 0.3;
  }
}

/// Particle background with floating orbs
class ParticleBackground extends StatefulWidget {
  final Widget child;
  final int particleCount;
  final bool enableMouseInteraction;
  final bool enableParallax;
  final List<Color>? backgroundGradient;
  
  const ParticleBackground({
    super.key,
    required this.child,
    this.particleCount = 50,
    this.enableMouseInteraction = true,
    this.enableParallax = true,
    this.backgroundGradient,
  });

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Particle> _particles;
  Offset? _mousePosition;
  double _parallaxOffsetX = 0;
  double _parallaxOffsetY = 0;
  
  // Performance optimization
  DateTime _lastFrame = DateTime.now();

  @override
  void initState() {
    super.initState();
    
    _particles = List.generate(
      widget.particleCount,
      (index) => Particle.random(),
    );
    
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: widget.enableMouseInteraction ? _handleMouseMove : null,
      onExit: widget.enableMouseInteraction 
          ? (_) => setState(() => _mousePosition = null)
          : null,
      child: Stack(
        children: [
          // Gradient mesh background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.backgroundGradient ?? GlassColors.primaryGradient,
              ),
            ),
          ),
          // Animated particles
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, _) {
              return CustomPaint(
                painter: ParticlePainter(
                  particles: _particles,
                  animationValue: _animationController.value,
                  mousePosition: _mousePosition,
                  parallaxOffset: Offset(_parallaxOffsetX, _parallaxOffsetY),
                  onUpdate: _updateParticles,
                ),
                child: Container(),
              );
            },
          ),
          // Overlay gradient for depth
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.2),
                ],
              ),
            ),
          ),
          // Main content
          widget.child,
        ],
      ),
    );
  }
  
  void _handleMouseMove(PointerHoverEvent event) {
    setState(() {
      _mousePosition = event.position;
      
      if (widget.enableParallax) {
        final size = MediaQuery.of(context).size;
        _parallaxOffsetX = (event.position.dx - size.width / 2) / size.width * 20;
        _parallaxOffsetY = (event.position.dy - size.height / 2) / size.height * 20;
      }
    });
  }
  
  void _updateParticles(Size size) {
    final now = DateTime.now();
    final deltaTime = now.difference(_lastFrame).inMilliseconds / 1000.0;
    _lastFrame = now;
    
    final time = _animationController.value * 1000;
    
    for (final particle in _particles) {
      particle.update(deltaTime * 60, time, size, mousePosition: _mousePosition);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

/// Custom painter for particles
class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double animationValue;
  final Offset? mousePosition;
  final Offset parallaxOffset;
  final Function(Size) onUpdate;
  
  ParticlePainter({
    required this.particles,
    required this.animationValue,
    this.mousePosition,
    required this.parallaxOffset,
    required this.onUpdate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Update particles
    onUpdate(size);
    
    // Draw connections between nearby particles
    _drawConnections(canvas, size);
    
    // Draw particles
    for (final particle in particles) {
      final x = particle.x * size.width + parallaxOffset.dx;
      final y = particle.y * size.height + parallaxOffset.dy;
      
      // Glow effect
      final glowPaint = Paint()
        ..color = particle.color.withOpacity(particle.opacity * 0.3 * particle.glowIntensity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, particle.size * 3);
      
      canvas.drawCircle(
        Offset(x, y),
        particle.size * 2,
        glowPaint,
      );
      
      // Main particle
      final paint = Paint()
        ..color = particle.color.withOpacity(particle.opacity)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(x, y),
        particle.size,
        paint,
      );
      
      // Inner highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(particle.opacity * 0.5)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(x - particle.size * 0.3, y - particle.size * 0.3),
        particle.size * 0.3,
        highlightPaint,
      );
    }
  }
  
  void _drawConnections(Canvas canvas, Size size) {
    final connectionDistance = 100.0;
    
    for (int i = 0; i < particles.length; i++) {
      final p1 = particles[i];
      final x1 = p1.x * size.width + parallaxOffset.dx;
      final y1 = p1.y * size.height + parallaxOffset.dy;
      
      for (int j = i + 1; j < particles.length; j++) {
        final p2 = particles[j];
        final x2 = p2.x * size.width + parallaxOffset.dx;
        final y2 = p2.y * size.height + parallaxOffset.dy;
        
        final distance = math.sqrt(
          math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2),
        );
        
        if (distance < connectionDistance) {
          final opacity = (1 - distance / connectionDistance) * 0.2;
          final paint = Paint()
            ..color = Colors.white.withOpacity(opacity)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;
          
          canvas.drawLine(
            Offset(x1, y1),
            Offset(x2, y2),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(ParticlePainter oldDelegate) => true;
}