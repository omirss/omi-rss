import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/services/collaboration_service.dart';
import '../../../core/providers/collaboration_provider.dart';
import '../../components/glass_morphism.dart';
import '../../theme/app_theme.dart';
import 'create_shared_folder_dialog.dart';
import 'shared_folder_detail_screen.dart';
import 'accept_invite_dialog.dart';

/// Shared folders management screen
class SharedFoldersScreen extends ConsumerStatefulWidget {
  const SharedFoldersScreen({super.key});

  @override
  ConsumerState<SharedFoldersScreen> createState() => _SharedFoldersScreenState();
}

class _SharedFoldersScreenState extends ConsumerState<SharedFoldersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
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
            title: const Text('Shared Folders'),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.userPlus),
                onPressed: _showAcceptInviteDialog,
                tooltip: 'Accept Invite',
              ),
              IconButton(
                icon: const Icon(LucideIcons.plus),
                onPressed: _showCreateFolderDialog,
                tooltip: 'Create Shared Folder',
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(text: 'My Folders'),
                Tab(text: 'Shared with Me'),
                Tab(text: 'Public'),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildMyFolders(collaboration),
            _buildSharedWithMe(collaboration),
            _buildPublicFolders(collaboration),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMyFolders(CollaborationService collaboration) {
    final myFolders = collaboration.sharedFolders
        .where((f) => f.ownerId == collaboration.currentUserId)
        .toList();
    
    if (myFolders.isEmpty) {
      return _buildEmptyState(
        icon: LucideIcons.folderOpen,
        title: 'No Shared Folders',
        subtitle: 'Create a shared folder to collaborate with others',
        actionLabel: 'Create Folder',
        onAction: _showCreateFolderDialog,
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: myFolders.length,
      itemBuilder: (context, index) {
        return _buildFolderCard(myFolders[index])
            .animate()
            .fadeIn(delay: (index * 100).ms)
            .slideY(begin: 0.2, end: 0);
      },
    );
  }
  
  Widget _buildSharedWithMe(CollaborationService collaboration) {
    final sharedFolders = collaboration.sharedFolders
        .where((f) => f.ownerId != collaboration.currentUserId)
        .toList();
    
    if (sharedFolders.isEmpty) {
      return _buildEmptyState(
        icon: LucideIcons.users,
        title: 'No Shared Folders',
        subtitle: 'Ask someone to share a folder with you',
        actionLabel: 'Enter Invite Code',
        onAction: _showAcceptInviteDialog,
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sharedFolders.length,
      itemBuilder: (context, index) {
        return _buildFolderCard(sharedFolders[index])
            .animate()
            .fadeIn(delay: (index * 100).ms)
            .slideY(begin: 0.2, end: 0);
      },
    );
  }
  
  Widget _buildPublicFolders(CollaborationService collaboration) {
    final publicFolders = collaboration.sharedFolders
        .where((f) => f.isPublic)
        .toList();
    
    if (publicFolders.isEmpty) {
      return _buildEmptyState(
        icon: LucideIcons.globe,
        title: 'No Public Folders',
        subtitle: 'Public folders will appear here',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: publicFolders.length,
      itemBuilder: (context, index) {
        return _buildFolderCard(publicFolders[index])
            .animate()
            .fadeIn(delay: (index * 100).ms)
            .slideY(begin: 0.2, end: 0);
      },
    );
  }
  
  Widget _buildFolderCard(SharedFolder folder) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final collaboration = ref.read(collaborationProvider);
    final members = collaboration.getFolderMembers(folder.id);
    final myRole = members.firstWhere(
      (m) => m.userId == collaboration.currentUserId,
      orElse: () => FolderMember(
        userId: '',
        userName: '',
        email: '',
        role: MemberRole.viewer,
        joinedAt: DateTime.now(),
      ),
    ).role;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassMorphism(
        blur: 10,
        opacity: 0.1,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openFolderDetail(folder),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withOpacity(0.6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        folder.isPublic ? LucideIcons.globe : LucideIcons.folderOpen,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                folder.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildRoleBadge(myRole),
                            ],
                          ),
                          Text(
                            folder.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.4),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStat(
                      icon: LucideIcons.users,
                      label: '${folder.memberCount} members',
                    ),
                    const SizedBox(width: 24),
                    _buildStat(
                      icon: LucideIcons.fileText,
                      label: '${folder.articleCount} articles',
                    ),
                    const SizedBox(width: 24),
                    _buildStat(
                      icon: LucideIcons.rss,
                      label: '${folder.feedIds.length} feeds',
                    ),
                  ],
                ),
                if (folder.ownerId != collaboration.currentUserId) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.userCheck,
                        size: 14,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Shared by ${folder.ownerName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildRoleBadge(MemberRole role) {
    final theme = Theme.of(context);
    Color color;
    String label;
    
    switch (role) {
      case MemberRole.owner:
        color = Colors.purple;
        label = 'Owner';
        break;
      case MemberRole.editor:
        color = Colors.blue;
        label = 'Editor';
        break;
      case MemberRole.contributor:
        color = Colors.green;
        label = 'Contributor';
        break;
      case MemberRole.viewer:
        color = Colors.grey;
        label = 'Viewer';
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  Widget _buildStat({required IconData icon, required String label}) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
  
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
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
              icon,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text(
            title,
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(LucideIcons.plus),
              label: Text(actionLabel),
            ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2, end: 0),
          ],
        ],
      ),
    );
  }
  
  void _showCreateFolderDialog() {
    showDialog(
      context: context,
      builder: (context) => const CreateSharedFolderDialog(),
    );
  }
  
  void _showAcceptInviteDialog() {
    showDialog(
      context: context,
      builder: (context) => const AcceptInviteDialog(),
    );
  }
  
  void _openFolderDetail(SharedFolder folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SharedFolderDetailScreen(folder: folder),
      ),
    );
  }
}