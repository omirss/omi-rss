import 'package:flutter/material.dart';
import '../collaboration_service.dart';

class PresenceIndicator extends StatelessWidget {
  final List<UserPresence> activeUsers;
  final int maxDisplay;

  const PresenceIndicator({
    super.key,
    required this.activeUsers,
    this.maxDisplay = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (activeUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayUsers = activeUsers.take(maxDisplay).toList();
    final remainingCount = activeUsers.length - maxDisplay;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...displayUsers.map((user) => _buildUserAvatar(context, user)),
          if (remainingCount > 0) _buildRemainingCount(context, remainingCount),
          const SizedBox(width: 8),
          _buildActiveIndicator(context),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(BuildContext context, UserPresence user) {
    final statusColor = _getStatusColor(user.status);
    
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Stack(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 14,
              backgroundImage: user.userAvatar != null
                  ? NetworkImage(user.userAvatar!)
                  : null,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: user.userAvatar == null
                  ? Text(
                      user.userName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemainingCount(BuildContext context, int count) {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceVariant,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          '+$count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveIndicator(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green,
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.4),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${activeUsers.length} active',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'online':
        return Colors.green;
      case 'idle':
        return Colors.orange;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}

class CollaborationFloatingButton extends StatefulWidget {
  final String folderId;
  final CollaborationService collaborationService;
  final VoidCallback? onStartSession;

  const CollaborationFloatingButton({
    super.key,
    required this.folderId,
    required this.collaborationService,
    this.onStartSession,
  });

  @override
  State<CollaborationFloatingButton> createState() =>
      _CollaborationFloatingButtonState();
}

class _CollaborationFloatingButtonState
    extends State<CollaborationFloatingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeUsers = widget.collaborationService.folderPresence.values
        .where((p) => p.status != 'offline')
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              alignment: Alignment.bottomRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_isExpanded) ...[
                    _buildActionButton(
                      context,
                      icon: Icons.people_outline,
                      label: 'Start Reading Session',
                      onTap: () {
                        widget.onStartSession?.call();
                        _toggleExpanded();
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildActionButton(
                      context,
                      icon: Icons.edit_note,
                      label: 'Start Annotation Session',
                      onTap: () {
                        // Start annotation session
                        _toggleExpanded();
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildActionButton(
                      context,
                      icon: Icons.forum,
                      label: 'Start Discussion',
                      onTap: () {
                        // Start discussion
                        _toggleExpanded();
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            );
          },
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            FloatingActionButton(
              onPressed: _toggleExpanded,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: AnimatedRotation(
                turns: _isExpanded ? 0.125 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _isExpanded ? Icons.close : Icons.group_add,
                  color: Colors.white,
                ),
              ),
            ),
            if (activeUsers.isNotEmpty)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    '${activeUsers.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}