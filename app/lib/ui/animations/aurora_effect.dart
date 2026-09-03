import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Aurora effect widget with wave motion
class AuroraEffect extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final double opacity;
  final double speed;
  final bool enabled;
  
  const AuroraEffect({
    super.key,
    required this.child,
    this.colors = const [
      Color(0xFF00FF88),
      Color(0xFF00AAFF),
      Color(0xFFFF00FF),
      Color(0xFF8800FF),
    ],
    this.opacity = 0.3,
    this.speed = 1.0,
    this.enabled = true,
  });
  
  @override
  State<AuroraEffect> createState() => _AuroraEffectState();
}

class _AuroraEffectState extends State<AuroraEffect>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<AuroraWave> _waves;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: (20 / widget.speed).round()),
      vsync: this,
    )..repeat();
    
    _waves = List.generate(4, (index) => AuroraWave(
      color: widget.colors[index % widget.colors.length],
      amplitude: 50.0 + (index * 20),
      frequency: 0.5 + (index * 0.2),
      phase: index * math.pi / 2,
      speed: 0.5 + (index * 0.1),
    ));
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    
    return Stack(
      children: [
        // Aurora background
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: AuroraPainter(
                  waves: _waves,
                  progress: _controller.value,
                  opacity: widget.opacity,
                ),
              );
            },
          ),
        ),
        // Child content
        widget.child,
      ],
    );
  }
}

/// Aurora wave configuration
class AuroraWave {
  final Color color;
  final double amplitude;
  final double frequency;
  final double phase;
  final double speed;
  
  AuroraWave({
    required this.color,
    required this.amplitude,
    required this.frequency,
    required this.phase,
    required this.speed,
  });
}

/// Aurora painter
class AuroraPainter extends CustomPainter {
  final List<AuroraWave> waves;
  final double progress;
  final double opacity;
  
  AuroraPainter({
    required this.waves,
    required this.progress,
    required this.opacity,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    for (final wave in waves) {
      _drawWave(canvas, size, wave);
    }
  }
  
  void _drawWave(Canvas canvas, Size size, AuroraWave wave) {
    final paint = Paint()
      ..color = wave.color.withOpacity(opacity)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);
    
    final path = Path();
    final waveProgress = progress * wave.speed;
    
    // Create flowing wave path
    path.moveTo(0, size.height);
    
    for (double x = 0; x <= size.width; x += 5) {
      final normalizedX = x / size.width;
      final y = size.height * 0.5 +
          wave.amplitude * math.sin(
            wave.frequency * normalizedX * 2 * math.pi +
            wave.phase +
            waveProgress * 2 * math.pi
          ) +
          wave.amplitude * 0.3 * math.sin(
            wave.frequency * 2 * normalizedX * 2 * math.pi +
            wave.phase * 2 +
            waveProgress * 4 * math.pi
          );
      
      path.lineTo(x, y);
    }
    
    path.lineTo(size.width, size.height);
    path.close();
    
    // Apply gradient shader
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        wave.color.withOpacity(0),
        wave.color.withOpacity(opacity * 0.5),
        wave.color.withOpacity(opacity),
        wave.color.withOpacity(0),
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );
    
    paint.shader = gradient.createShader(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(AuroraPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Aurora shimmer effect for loading states
class AuroraShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Duration duration;
  final List<Color> colors;
  
  const AuroraShimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(seconds: 2),
    this.colors = const [
      Color(0x20FFFFFF),
      Color(0x40FFFFFF),
      Color(0x20FFFFFF),
    ],
  });
  
  @override
  State<AuroraShimmer> createState() => _AuroraShimmerState();
}

class _AuroraShimmerState extends State<AuroraShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    
    _animation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    if (widget.enabled) {
      _controller.repeat();
    }
  }
  
  @override
  void didUpdateWidget(AuroraShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _controller.repeat();
    } else if (!widget.enabled && oldWidget.enabled) {
      _controller.stop();
    }
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.colors,
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ],
              transform: const GradientRotation(math.pi / 4),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcOver,
          child: widget.child,
        );
      },
    );
  }
}

/// Wave animation effect
class WaveEffect extends StatefulWidget {
  final Widget child;
  final Color waveColor;
  final double waveHeight;
  final double waveSpeed;
  final int waveCount;
  final bool enabled;
  
  const WaveEffect({
    super.key,
    required this.child,
    this.waveColor = Colors.blue,
    this.waveHeight = 20,
    this.waveSpeed = 1.0,
    this.waveCount = 2,
    this.enabled = true,
  });

  @override
  State<WaveEffect> createState() => _WaveEffectState();
}

class _WaveEffectState extends State<WaveEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: (3 / widget.waveSpeed).round()),
      vsync: this,
    );
    
    if (widget.enabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(WaveEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _controller.repeat();
    } else if (!widget.enabled && oldWidget.enabled) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ClipPath(
          clipper: _WaveClipper(
            progress: _controller.value,
            waveHeight: widget.waveHeight,
            waveCount: widget.waveCount,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.waveColor.withOpacity(0.3),
                  widget.waveColor.withOpacity(0.1),
                ],
              ),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  final double progress;
  final double waveHeight;
  final int waveCount;
  
  _WaveClipper({
    required this.progress,
    required this.waveHeight,
    required this.waveCount,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    
    // Start from top-left
    path.moveTo(0, 0);
    
    // Draw top edge with wave
    for (double x = 0; x <= size.width; x++) {
      final normalizedX = x / size.width;
      final waveProgress = (normalizedX + progress) * waveCount * 2 * math.pi;
      final y = waveHeight + (waveHeight * math.sin(waveProgress));
      
      path.lineTo(x, y);
    }
    
    // Complete the rectangle
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) {
    return progress != oldClipper.progress ||
           waveHeight != oldClipper.waveHeight ||
           waveCount != oldClipper.waveCount;
  }
}