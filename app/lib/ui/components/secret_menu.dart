import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../glass_theme.dart';
import 'glass_card.dart';
import 'glass_button.dart';
import 'glass_text_field.dart';
import 'glass_dialog.dart';
import '../../core/services/paywall_service.dart';

/// Secret menu for advanced features (paywall bypass)
/// Activated by triple-tapping on specific UI elements
class SecretMenu extends StatefulWidget {
  final Widget child;
  final String? activationCode;
  final VoidCallback? onActivated;
  
  const SecretMenu({
    super.key,
    required this.child,
    this.activationCode,
    this.onActivated,
  });
  
  @override
  State<SecretMenu> createState() => _SecretMenuState();
}

class _SecretMenuState extends State<SecretMenu> with SingleTickerProviderStateMixin {
  int _tapCount = 0;
  Timer? _resetTimer;
  bool _isActivated = false;
  
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 0.02,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }
  
  @override
  void dispose() {
    _resetTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }
  
  void _handleTap() {
    _tapCount++;
    
    // Visual feedback
    _animationController.forward().then((_) {
      _animationController.reverse();
    });
    
    // Haptic feedback on each tap
    HapticFeedback.lightImpact();
    
    // Reset timer
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _tapCount = 0;
      });
    });
    
    // Check for activation
    if (_tapCount >= 3) {
      _activate();
    }
  }
  
  void _activate() {
    setState(() {
      _isActivated = true;
      _tapCount = 0;
    });
    
    // Strong haptic feedback
    HapticFeedback.heavyImpact();
    
    // Show secret menu
    if (widget.activationCode != null) {
      _showCodeDialog();
    } else {
      _showSecretMenu();
    }
    
    widget.onActivated?.call();
  }
  
  void _showCodeDialog() {
    final codeController = TextEditingController();
    
    GlassDialog.show<bool>(
      context: context,
      title: const Text('Enter Access Code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This feature requires an access code.'),
          const SizedBox(height: 16),
          GlassTextField(
            controller: codeController,
            hintText: 'Access code',
            obscureText: true,
            autofocus: true,
            onSubmitted: (code) {
              if (code == widget.activationCode) {
                Navigator.of(context).pop(true);
              }
            },
          ),
        ],
      ),
      actions: [
        GlassButton(
          onPressed: () => Navigator.of(context).pop(false),
          variant: GlassButtonVariant.text,
          child: const Text('Cancel'),
        ),
        GlassButton(
          onPressed: () {
            if (codeController.text == widget.activationCode) {
              Navigator.of(context).pop(true);
            }
          },
          child: const Text('Unlock'),
        ),
      ],
    ).then((unlocked) {
      if (unlocked == true) {
        _showSecretMenu();
      } else {
        setState(() {
          _isActivated = false;
        });
      }
    });
  }
  
  void _showSecretMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const SecretMenuSheet(),
    ).then((_) {
      setState(() {
        _isActivated = false;
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform.rotate(
              angle: _rotationAnimation.value,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// Secret menu sheet
class SecretMenuSheet extends StatefulWidget {
  const SecretMenuSheet({super.key});
  
  @override
  State<SecretMenuSheet> createState() => _SecretMenuSheetState();
}

class _SecretMenuSheetState extends State<SecretMenuSheet> with SingleTickerProviderStateMixin {
  final _paywallService = PaywallService();
  final _urlController = TextEditingController();
  
  bool _isProcessing = false;
  PaywallResult? _result;
  PaywallMethod _selectedMethod = PaywallMethod.googlebot;
  bool _aggressiveMode = false;
  
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(
      begin: 100,
      end: 0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));
    
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _urlController.dispose();
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: Container(
              height: screenHeight * 0.9,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  _buildHandle(),
                  _buildHeader(theme),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWarning(theme),
                          const SizedBox(height: 24),
                          _buildUrlInput(theme),
                          const SizedBox(height: 16),
                          _buildMethodSelector(theme),
                          const SizedBox(height: 16),
                          _buildOptions(theme),
                          const SizedBox(height: 24),
                          _buildActionButtons(theme),
                          if (_isProcessing) ...[
                            const SizedBox(height: 24),
                            _buildProcessing(theme),
                          ],
                          if (_result != null) ...[
                            const SizedBox(height: 24),
                            _buildResult(theme),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
  
  Widget _buildHeader(GlassThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.red.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_open,
            color: Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            'Advanced Content Access',
            style: theme.titleLarge.copyWith(
              color: Colors.red,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWarning(GlassThemeData theme) {
    return GlassCard(
      theme: theme,
      borderColor: Colors.orange.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'For research and archival purposes only. '
                'Respect content creators and consider supporting them.',
                style: theme.bodySmall.copyWith(
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildUrlInput(GlassThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Article URL',
          style: theme.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        GlassTextField(
          controller: _urlController,
          hintText: 'https://example.com/article',
          prefixIcon: Icons.link,
          suffixIcon: IconButton(
            icon: const Icon(Icons.paste),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) {
                _urlController.text = data!.text!;
              }
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildMethodSelector(GlassThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bypass Method',
          style: theme.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PaywallMethod.values
              .where((m) => m != PaywallMethod.none)
              .map((method) => ChoiceChip(
                    label: Text(_getMethodName(method)),
                    selected: _selectedMethod == method,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedMethod = method);
                      }
                    },
                    selectedColor: Colors.red.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _selectedMethod == method
                          ? Colors.red
                          : Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
  
  Widget _buildOptions(GlassThemeData theme) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(
            'Aggressive Mode',
            style: theme.bodyMedium,
          ),
          subtitle: Text(
            'Try all available methods automatically',
            style: theme.bodySmall.copyWith(
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          value: _aggressiveMode,
          onChanged: (value) {
            setState(() => _aggressiveMode = value);
          },
          activeColor: Colors.red,
        ),
      ],
    );
  }
  
  Widget _buildActionButtons(GlassThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GlassButton(
          onPressed: _isProcessing ? null : _extractContent,
          variant: GlassButtonVariant.primary,
          child: Row(
            children: [
              Icon(Icons.download),
              const SizedBox(width: 8),
              Text('Extract Content'),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GlassButton(
          onPressed: _detectPaywall,
          variant: GlassButtonVariant.outlined,
          child: Row(
            children: [
              Icon(Icons.search),
              const SizedBox(width: 8),
              Text('Detect Paywall'),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildProcessing(GlassThemeData theme) {
    return Center(
      child: Column(
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
          ),
          const SizedBox(height: 16),
          Text(
            'Attempting to bypass paywall...',
            style: theme.bodyMedium,
          ),
        ],
      ),
    );
  }
  
  Widget _buildResult(GlassThemeData theme) {
    if (_result == null) return const SizedBox.shrink();
    
    return GlassCard(
      theme: theme,
      borderColor: _result!.success 
          ? Colors.green.withOpacity(0.3)
          : Colors.red.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _result!.success ? Icons.check_circle : Icons.error,
                  color: _result!.success ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _result!.success ? 'Content Extracted' : 'Extraction Failed',
                  style: theme.titleMedium.copyWith(
                    color: _result!.success ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_result!.success) ...[
              Text(
                'Method: ${_getMethodName(_result!.method)}',
                style: theme.bodySmall,
              ),
              Text(
                'Full content: ${_result!.fullContent ? "Yes" : "Partial"}',
                style: theme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GlassButton(
                    onPressed: _copyContent,
                    variant: GlassButtonVariant.text,
                    child: Row(
                      children: [
                        Icon(Icons.copy, size: 16),
                        const SizedBox(width: 4),
                        Text('Copy'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GlassButton(
                    onPressed: _shareContent,
                    variant: GlassButtonVariant.text,
                    child: Row(
                      children: [
                        Icon(Icons.share, size: 16),
                        const SizedBox(width: 4),
                        Text('Share'),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                _result!.error ?? 'Unable to extract content',
                style: theme.bodySmall.copyWith(
                  color: Colors.red.withOpacity(0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Future<void> _extractContent() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    
    setState(() {
      _isProcessing = true;
      _result = null;
    });
    
    try {
      final result = await _paywallService.bypassAndExtract(
        url,
        aggressive: _aggressiveMode,
        preferredMethods: _aggressiveMode ? null : [_selectedMethod],
      );
      
      setState(() {
        _result = result;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _result = PaywallResult(
          content: '',
          method: PaywallMethod.none,
          success: false,
          error: e.toString(),
        );
        _isProcessing = false;
      });
    }
  }
  
  Future<void> _detectPaywall() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    
    final hasPaywall = _paywallService.mightHavePaywall(url);
    final methods = _paywallService.getAvailableMethods(url);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(
          hasPaywall ? 'Paywall Detected' : 'No Known Paywall',
          style: TextStyle(color: hasPaywall ? Colors.orange : Colors.green),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasPaywall
                  ? 'This site is known to have a paywall.'
                  : 'This site is not in our paywall database.',
            ),
            if (hasPaywall) ...[
              const SizedBox(height: 12),
              Text('Recommended methods:'),
              const SizedBox(height: 8),
              ...methods.map((m) => Text('• ${_getMethodName(m)}')),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  void _copyContent() {
    if (_result?.content != null) {
      Clipboard.setData(ClipboardData(text: _result!.content));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content copied to clipboard')),
      );
    }
  }
  
  void _shareContent() {
    // Implement share functionality
    // This would integrate with platform share APIs
  }
  
  String _getMethodName(PaywallMethod method) {
    switch (method) {
      case PaywallMethod.googlebot:
        return 'Googlebot';
      case PaywallMethod.archiveOrg:
        return 'Archive.org';
      case PaywallMethod.googleCache:
        return 'Google Cache';
      case PaywallMethod.ampVersion:
        return 'AMP Version';
      case PaywallMethod.disableJavascript:
        return 'No JavaScript';
      case PaywallMethod.disableCookies:
        return 'No Cookies';
      case PaywallMethod.facebookReferer:
        return 'Facebook Ref';
      case PaywallMethod.twitterReferer:
        return 'Twitter Ref';
      case PaywallMethod.textOnly:
        return 'Text Only';
      case PaywallMethod.readerMode:
        return 'Reader Mode';
      case PaywallMethod.webArchive:
        return 'Web Archive';
      case PaywallMethod.twelveFootLadder:
        return '12ft Ladder';
      case PaywallMethod.none:
      default:
        return 'None';
    }
  }
}