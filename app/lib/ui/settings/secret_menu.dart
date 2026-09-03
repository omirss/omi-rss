import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../glass_theme.dart';
import '../../core/services/bypass_service.dart';

/// Secret menu for paywall bypass - activated by triple-tap
class SecretMenu extends ConsumerStatefulWidget {
  const SecretMenu({super.key});

  @override
  ConsumerState<SecretMenu> createState() => _SecretMenuState();
}

class _SecretMenuState extends ConsumerState<SecretMenu>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _glitchController;
  late BypassService _bypassService;
  
  bool _hasAcceptedTerms = false;
  bool _showTerms = true;
  bool _isEnabled = false;
  
  // Konami code state
  final List<LogicalKeyboardKey> _konamiCode = [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyA,
  ];
  List<LogicalKeyboardKey> _currentSequence = [];
  
  @override
  void initState() {
    super.initState();
    _bypassService = BypassService();
    _isEnabled = _bypassService.isEnabled;
    
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _glitchController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    )..repeat(reverse: true);
    
    _entranceController.forward();
    
    // Add keyboard listener for Konami code
    RawKeyboard.instance.addListener(_handleKeyEvent);
  }
  
  @override
  void dispose() {
    _entranceController.dispose();
    _glitchController.dispose();
    RawKeyboard.instance.removeListener(_handleKeyEvent);
    super.dispose();
  }
  
  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      _currentSequence.add(event.logicalKey);
      
      if (_currentSequence.length > _konamiCode.length) {
        _currentSequence.removeAt(0);
      }
      
      if (_currentSequence.length == _konamiCode.length) {
        bool matches = true;
        for (int i = 0; i < _konamiCode.length; i++) {
          if (_currentSequence[i] != _konamiCode[i]) {
            matches = false;
            break;
          }
        }
        
        if (matches) {
          // Konami code entered!
          _showEasterEgg();
        }
      }
    }
  }
  
  void _showEasterEgg() {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('🎮 Achievement Unlocked: Konami Master!'),
        backgroundColor: GlassThemeData.purple.gradientColors.first,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Animated matrix background
          _buildMatrixBackground(),
          
          // Glitch overlay
          AnimatedBuilder(
            animation: _glitchController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.withOpacity(0.05 * _glitchController.value),
                      Colors.blue.withOpacity(0.05 * (1 - _glitchController.value)),
                      Colors.green.withOpacity(0.05 * _glitchController.value),
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Content
          SafeArea(
            child: AnimatedBuilder(
              animation: _entranceController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.9 + (0.1 * _entranceController.value),
                  child: Opacity(
                    opacity: _entranceController.value,
                    child: _showTerms ? _buildTermsView() : _buildControlPanel(),
                  ),
                );
              },
            ),
          ),
          
          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ).animate()
              .fadeIn(delay: 800.ms)
              .slideX(begin: 1, end: 0),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMatrixBackground() {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        return CustomPaint(
          painter: MatrixRainPainter(
            progress: _entranceController.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
  
  Widget _buildTermsView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Warning icon with glitch effect
            AnimatedBuilder(
              animation: _glitchController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(
                    (_glitchController.value - 0.5) * 4,
                    0,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 80,
                    color: Colors.amber.withOpacity(0.8),
                  ),
                );
              },
            ).animate()
              .fadeIn(duration: 600.ms)
              .scale(begin: 0, delay: 200.ms),
            
            const SizedBox(height: 32),
            
            // Title
            Text(
              'RESTRICTED ACCESS',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 3,
                shadows: [
                  Shadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 10,
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
            ).animate()
              .fadeIn(delay: 400.ms)
              .slideY(begin: -0.2, end: 0),
            
            const SizedBox(height: 24),
            
            // Legal disclaimer
            GlassContainer(
              blur: 30,
              opacity: 0.1,
              gradient: LinearGradient(
                colors: [
                  Colors.red.withOpacity(0.1),
                  Colors.orange.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LEGAL DISCLAIMER',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This feature is provided for educational and archival purposes only. '
                    'By enabling this feature, you acknowledge that:\n\n'
                    '• You will use it responsibly and ethically\n'
                    '• You understand it may violate terms of service\n'
                    '• You accept all legal responsibility\n'
                    '• The developers are not liable for any consequences\n'
                    '• You support journalism by subscribing when possible\n\n'
                    'This feature bypasses paywalls using publicly available methods. '
                    'We strongly encourage supporting quality journalism through '
                    'legitimate subscriptions.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Checkbox(
                        value: _hasAcceptedTerms,
                        onChanged: (value) {
                          setState(() {
                            _hasAcceptedTerms = value ?? false;
                          });
                        },
                        fillColor: MaterialStateProperty.all(Colors.red),
                      ),
                      Expanded(
                        child: Text(
                          'I understand and accept the risks',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate()
              .fadeIn(delay: 600.ms)
              .slideY(begin: 0.1, end: 0),
            
            const SizedBox(height: 32),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlassButton(
                  onPressed: () => Navigator.of(context).pop(),
                  variant: GlassButtonVariant.outlined,
                  child: const Text('Cancel'),
                ).animate()
                  .fadeIn(delay: 800.ms)
                  .slideX(begin: -0.2, end: 0),
                
                const SizedBox(width: 16),
                
                GlassButton(
                  onPressed: _hasAcceptedTerms
                    ? () async {
                        await _bypassService.enableBypass(accepted: true);
                        setState(() {
                          _showTerms = false;
                          _isEnabled = true;
                        });
                      }
                    : null,
                  variant: GlassButtonVariant.elevated,
                  gradient: LinearGradient(
                    colors: _hasAcceptedTerms
                      ? [Colors.red.withOpacity(0.3), Colors.orange.withOpacity(0.1)]
                      : [Colors.grey.withOpacity(0.2), Colors.grey.withOpacity(0.1)],
                  ),
                  child: const Text('Enable'),
                ).animate()
                  .fadeIn(delay: 800.ms)
                  .slideX(begin: 0.2, end: 0),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildControlPanel() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: _isEnabled
                    ? [Colors.green.withOpacity(0.5), Colors.green.withOpacity(0.1)]
                    : [Colors.red.withOpacity(0.5), Colors.red.withOpacity(0.1)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isEnabled ? Colors.green : Colors.red,
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                _isEnabled ? Icons.shield : Icons.shield_outlined,
                size: 60,
                color: Colors.white,
              ),
            ).animate(onPlay: (controller) => controller.repeat())
              .shimmer(duration: 2.seconds, color: Colors.white.withOpacity(0.3))
              .shake(hz: 2, curve: Curves.easeInOut),
            
            const SizedBox(height: 32),
            
            // Status text
            Text(
              _isEnabled ? 'BYPASS ACTIVE' : 'BYPASS INACTIVE',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _isEnabled ? Colors.green : Colors.red,
                letterSpacing: 2,
              ),
            ).animate()
              .fadeIn()
              .slideY(begin: -0.2, end: 0),
            
            const SizedBox(height: 40),
            
            // Control panel
            GlassContainer(
              blur: 30,
              opacity: 0.1,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Toggle switch
                  _buildToggleRow(
                    'Bypass System',
                    'Enable paywall bypass for supported sites',
                    _isEnabled,
                    (value) async {
                      if (value) {
                        await _bypassService.enableBypass(accepted: true);
                      } else {
                        await _bypassService.disableBypass();
                      }
                      setState(() {
                        _isEnabled = value;
                      });
                    },
                  ),
                  
                  const Divider(height: 32, color: Colors.white24),
                  
                  // Statistics
                  _buildStatRow('Supported Sites', '50+'),
                  const SizedBox(height: 12),
                  _buildStatRow('Success Rate', '85%'),
                  const SizedBox(height: 12),
                  _buildStatRow('Last Updated', '2 days ago'),
                  
                  const Divider(height: 32, color: Colors.white24),
                  
                  // Advanced options
                  _buildActionButton(
                    'View Supported Sites',
                    Icons.list_alt,
                    () => _showSupportedSites(context),
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    'Clear Cache',
                    Icons.clear_all,
                    () => _clearCache(),
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    'Report Issue',
                    Icons.bug_report,
                    () => _reportIssue(),
                  ),
                ],
              ),
            ).animate()
              .fadeIn(delay: 200.ms)
              .slideY(begin: 0.1, end: 0),
          ],
        ),
      ),
    );
  }
  
  Widget _buildToggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.green,
          inactiveThumbColor: Colors.red,
        ),
      ],
    );
  }
  
  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white.withOpacity(0.8)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.white.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showSupportedSites(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const SupportedSitesSheet(),
    );
  }
  
  void _clearCache() {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache cleared successfully'),
      ),
    );
  }
  
  void _reportIssue() {
    // TODO: Open issue reporter
  }
}

/// Matrix rain painter for background effect
class MatrixRainPainter extends CustomPainter {
  final double progress;
  
  MatrixRainPainter({required this.progress});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    
    final random = math.Random(42);
    final columnWidth = 20.0;
    final columns = (size.width / columnWidth).ceil();
    
    for (int i = 0; i < columns; i++) {
      final x = i * columnWidth;
      final height = random.nextDouble() * size.height * progress;
      final y = random.nextDouble() * (size.height - height);
      
      // Draw matrix column
      for (double dy = y; dy < y + height; dy += 20) {
        final opacity = ((dy - y) / height) * 0.5 * progress;
        paint.color = Colors.green.withOpacity(opacity);
        
        final char = String.fromCharCode(
          0x30A0 + random.nextInt(96), // Katakana characters
        );
        
        final textPainter = TextPainter(
          text: TextSpan(
            text: char,
            style: TextStyle(
              color: paint.color,
              fontSize: 16,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        
        textPainter.layout();
        textPainter.paint(canvas, Offset(x, dy));
      }
    }
  }
  
  @override
  bool shouldRepaint(MatrixRainPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Supported sites sheet
class SupportedSitesSheet extends StatelessWidget {
  const SupportedSitesSheet({super.key});
  
  final List<SiteInfo> sites = const [
    SiteInfo('The New York Times', 'nytimes.com', 0.92),
    SiteInfo('Wall Street Journal', 'wsj.com', 0.88),
    SiteInfo('The Washington Post', 'washingtonpost.com', 0.90),
    SiteInfo('Financial Times', 'ft.com', 0.85),
    SiteInfo('The Atlantic', 'theatlantic.com', 0.87),
    SiteInfo('Medium', 'medium.com', 0.95),
    SiteInfo('Bloomberg', 'bloomberg.com', 0.83),
    SiteInfo('The Economist', 'economist.com', 0.80),
    SiteInfo('Wired', 'wired.com', 0.91),
    SiteInfo('The New Yorker', 'newyorker.com', 0.86),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Color(0xFF0B1929),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Title
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Supported Sites',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          
          // Sites list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: sites.length,
              itemBuilder: (context, index) {
                final site = sites[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              site.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              site.domain,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Success rate
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getSuccessColor(site.successRate).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _getSuccessColor(site.successRate).withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          '${(site.successRate * 100).round()}%',
                          style: TextStyle(
                            color: _getSuccessColor(site.successRate),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate()
                  .fadeIn(delay: Duration(milliseconds: 50 * index))
                  .slideX(begin: 0.1, end: 0);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getSuccessColor(double rate) {
    if (rate >= 0.9) return Colors.green;
    if (rate >= 0.8) return Colors.amber;
    return Colors.orange;
  }
}

/// Site info model
class SiteInfo {
  final String name;
  final String domain;
  final double successRate;
  
  const SiteInfo(this.name, this.domain, this.successRate);
}

/// Triple tap detector for secret menu activation
class TripleTapDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onTripleTap;
  final Duration timeout;
  
  const TripleTapDetector({
    super.key,
    required this.child,
    required this.onTripleTap,
    this.timeout = const Duration(milliseconds: 500),
  });
  
  @override
  State<TripleTapDetector> createState() => _TripleTapDetectorState();
}

class _TripleTapDetectorState extends State<TripleTapDetector> {
  int _tapCount = 0;
  DateTime? _lastTapTime;
  
  void _handleTap() {
    final now = DateTime.now();
    
    if (_lastTapTime != null && now.difference(_lastTapTime!) > widget.timeout) {
      _tapCount = 0;
    }
    
    _tapCount++;
    _lastTapTime = now;
    
    if (_tapCount == 3) {
      widget.onTripleTap();
      _tapCount = 0;
      
      // Haptic feedback
      HapticFeedback.heavyImpact();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: widget.child,
    );
  }
}