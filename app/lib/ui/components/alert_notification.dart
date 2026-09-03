import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/alert.dart';
import '../glass_theme.dart';
import 'glass_container.dart';

/// In-app alert notification widget
class AlertNotification extends StatefulWidget {
  final Alert alert;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final Duration displayDuration;
  
  const AlertNotification({
    super.key,
    required this.alert,
    this.onTap,
    this.onDismiss,
    this.displayDuration = const Duration(seconds: 5),
  });
  
  @override
  State<AlertNotification> createState() => _AlertNotificationState();
}

class _AlertNotificationState extends State<AlertNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isDismissed = false;
  
  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(
      begin: -100,
      end: 0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));
    
    _controller.forward();
    
    // Auto dismiss after duration
    Future.delayed(widget.displayDuration, () {
      if (mounted && !_isDismissed) {
        _dismiss();
      }
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  void _dismiss() {
    if (_isDismissed) return;
    
    setState(() => _isDismissed = true);
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss?.call();
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () {
              widget.onTap?.call();
              _dismiss();
            },
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity!.abs() > 100) {
                _dismiss();
              }
            },
            child: GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getAlertColor(widget.alert.type).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getAlertIcon(widget.alert.category),
                      color: _getAlertColor(widget.alert.type),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.alert.title,
                          style: theme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.alert.message,
                          style: theme.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // Dismiss button
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white.withOpacity(0.5),
                      size: 18,
                    ),
                    onPressed: _dismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ).animate()
              .shake(delay: 300.ms, duration: 300.ms)
              .then()
              .shimmer(delay: 100.ms, duration: 1000.ms),
          ),
        ),
      ),
    );
  }
  
  Color _getAlertColor(AlertType type) {
    switch (type) {
      case AlertType.info:
        return Colors.blue;
      case AlertType.warning:
        return Colors.orange;
      case AlertType.error:
        return Colors.red;
      case AlertType.success:
        return Colors.green;
      case AlertType.notification:
        return Colors.purple;
    }
  }
  
  IconData _getAlertIcon(AlertCategory category) {
    switch (category) {
      case AlertCategory.feed_update:
        return Icons.rss_feed;
      case AlertCategory.feed_error:
      case AlertCategory.feed_health:
        return Icons.warning;
      case AlertCategory.article_keyword:
      case AlertCategory.article_author:
      case AlertCategory.article_topic:
        return Icons.article;
      case AlertCategory.portfolio_price:
      case AlertCategory.portfolio_gain_loss:
        return Icons.trending_up;
      case AlertCategory.portfolio_news:
        return Icons.newspaper;
      case AlertCategory.portfolio_dividend:
        return Icons.attach_money;
      case AlertCategory.system_update:
      case AlertCategory.system_maintenance:
      case AlertCategory.system_error:
        return Icons.settings;
      case AlertCategory.user_achievement:
      case AlertCategory.user_milestone:
        return Icons.emoji_events;
      case AlertCategory.user_reminder:
        return Icons.alarm;
    }
  }
}

/// Alert notification manager to show in-app notifications
class AlertNotificationManager {
  static final _overlayEntries = <OverlayEntry>[];
  static const _maxNotifications = 3;
  
  static void show(
    BuildContext context,
    Alert alert, {
    VoidCallback? onTap,
  }) {
    // Remove oldest if at max
    if (_overlayEntries.length >= _maxNotifications) {
      _overlayEntries.first.remove();
      _overlayEntries.removeAt(0);
    }
    
    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AlertNotification(
          alert: alert,
          onTap: onTap,
          onDismiss: () {
            overlayEntry.remove();
            _overlayEntries.remove(overlayEntry);
            _updatePositions();
          },
        ).animate().slideY(
          begin: _overlayEntries.length * 0.2,
          end: 0,
          duration: 200.ms,
        ),
      ),
    );
    
    _overlayEntries.add(overlayEntry);
    Overlay.of(context).insert(overlayEntry);
    _updatePositions();
  }
  
  static void _updatePositions() {
    // Update positions of remaining notifications
    for (int i = 0; i < _overlayEntries.length; i++) {
      _overlayEntries[i].markNeedsBuild();
    }
  }
  
  static void clearAll() {
    for (final entry in _overlayEntries) {
      entry.remove();
    }
    _overlayEntries.clear();
  }
}