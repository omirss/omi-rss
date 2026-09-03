import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/services/collaboration_service.dart';
import '../../../core/providers/collaboration_provider.dart';
import '../../components/glass_morphism.dart';
import '../../theme/app_theme.dart';

/// Screen showing folder activity feed
class FolderActivityScreen extends ConsumerWidget {
  final SharedFolder folder;
  
  const FolderActivityScreen({
    super.key,
    required this.folder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final collaboration = ref.watch(collaborationProvider);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.getScaffoldBackground(isDark),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: GlassMorphism(
          blur: 10,
          opacity: 0.1,
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activity',
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  folder.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<FolderActivity>>(
          stream: collaboration.getFolderActivity(folder.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
            
            final activities = snapshot.data!;
            
            if (activities.isEmpty) {
              return _buildEmptyState(theme);
            }
            
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: activities.length,
              itemBuilder: (context, index) {
                final activity = activities[index];
                final isLast = index == activities.length - 1;
                
                return _buildActivityItem(
                  activity,
                  theme,
                  isLast,
                  index,
                );
              },
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withOpacity(0.2),
                  theme.colorScheme.primary.withOpacity(0.1),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.activity,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text(
            'No Activity Yet',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 8),
          Text(
            'Activity will appear here as members interact',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms),
        ],
      ),
    );
  }
  
  Widget _buildActivityItem(
    FolderActivity activity,
    ThemeData theme,
    bool isLast,
    int index,
  ) {
    final icon = _getActivityIcon(activity.action);
    final color = _getActivityColor(activity.action);
    final description = _getActivityDescription(activity);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: color,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 60,
                  color: theme.dividerColor.withOpacity(0.2),
                ),
            ],
          ),
          const SizedBox(width: 16),
          
          // Content
          Expanded(
            child: GlassMorphism(
              blur: 10,
              opacity: 0.05,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                          child: Text(
                            activity.userName.substring(0, 2).toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: theme.textTheme.bodyMedium,
                              children: [
                                TextSpan(
                                  text: activity.userName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextSpan(text: ' $description'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(activity.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1, end: 0);
  }
  
  IconData _getActivityIcon(ActivityAction action) {
    switch (action) {
      case ActivityAction.joinedFolder:
        return LucideIcons.userPlus;
      case ActivityAction.leftFolder:
        return LucideIcons.userMinus;
      case ActivityAction.addedArticle:
        return LucideIcons.filePlus;
      case ActivityAction.removedArticle:
        return LucideIcons.fileMinus;
      case ActivityAction.commented:
        return LucideIcons.messageCircle;
      case ActivityAction.annotated:
        return LucideIcons.highlighter;
      case ActivityAction.invitedMember:
        return LucideIcons.mail;
      case ActivityAction.roleChanged:
        return LucideIcons.userCog;
    }
  }
  
  Color _getActivityColor(ActivityAction action) {
    switch (action) {
      case ActivityAction.joinedFolder:
      case ActivityAction.invitedMember:
        return Colors.green;
      case ActivityAction.leftFolder:
      case ActivityAction.removedArticle:
        return Colors.red;
      case ActivityAction.addedArticle:
      case ActivityAction.commented:
      case ActivityAction.annotated:
        return Colors.blue;
      case ActivityAction.roleChanged:
        return Colors.orange;
    }
  }
  
  String _getActivityDescription(FolderActivity activity) {
    switch (activity.action) {
      case ActivityAction.joinedFolder:
        return 'joined the folder';
      case ActivityAction.leftFolder:
        return 'left the folder';
      case ActivityAction.addedArticle:
        return 'added "${activity.targetName}"';
      case ActivityAction.removedArticle:
        return 'removed "${activity.targetName}"';
      case ActivityAction.commented:
        return 'commented on "${activity.targetName}"';
      case ActivityAction.annotated:
        return 'annotated "${activity.targetName}"';
      case ActivityAction.invitedMember:
        return 'invited ${activity.targetName}';
      case ActivityAction.roleChanged:
        return 'changed role to ${activity.targetName}';
    }
  }
  
  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}