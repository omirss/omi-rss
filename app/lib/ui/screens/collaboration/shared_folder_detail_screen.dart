import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/services/collaboration_service.dart';
import '../../../core/providers/collaboration_provider.dart';
import '../../components/glass_morphism.dart';
import '../../theme/app_theme.dart';
import 'members_list_dialog.dart';
import 'invite_member_dialog.dart';
import 'folder_activity_screen.dart';

/// Shared folder detail screen
class SharedFolderDetailScreen extends ConsumerStatefulWidget {
  final SharedFolder folder;
  
  const SharedFolderDetailScreen({
    super.key,
    required this.folder,
  });

  @override
  ConsumerState<SharedFolderDetailScreen> createState() => _SharedFolderDetailScreenState();
}

class _SharedFolderDetailScreenState extends ConsumerState<SharedFolderDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late SharedFolder _folder;
  
  @override
  void initState() {
    super.initState();
    _folder = widget.folder;
    _tabController = TabController(length: 4, vsync: this);
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
    final members = collaboration.getFolderMembers(_folder.id);
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
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.getScaffoldBackground(isDark),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  // Background gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary.withOpacity(0.6),
                          theme.colorScheme.primary.withOpacity(0.2),
                        ],
                      ),
                    ),
                  ),
                  // Glass overlay
                  Positioned.fill(
                    child: GlassMorphism(
                      blur: 20,
                      opacity: 0.1,
                      child: Container(),
                    ),
                  ),
                  // Folder info
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                _folder.isPublic ? LucideIcons.globe : LucideIcons.folderOpen,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _folder.name,
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _folder.description,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (myRole == MemberRole.owner || myRole == MemberRole.editor) ...[
                IconButton(
                  icon: const Icon(LucideIcons.userPlus, color: Colors.white),
                  onPressed: () => _showInviteMemberDialog(),
                  tooltip: 'Invite Member',
                ),
              ],
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, color: Colors.white),
                onSelected: (value) => _handleMenuAction(value, myRole),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'activity',
                    child: ListTile(
                      leading: Icon(LucideIcons.activity),
                      title: Text('Activity'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'members',
                    child: ListTile(
                      leading: Icon(LucideIcons.users),
                      title: Text('Members'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (myRole == MemberRole.owner) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(LucideIcons.settings),
                        title: Text('Settings'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  if (myRole != MemberRole.owner) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'leave',
                      child: ListTile(
                        leading: Icon(LucideIcons.logOut, color: Colors.red),
                        title: Text('Leave Folder', style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              tabs: const [
                Tab(text: 'Articles'),
                Tab(text: 'Comments'),
                Tab(text: 'Annotations'),
                Tab(text: 'Stats'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildArticlesTab(),
            _buildCommentsTab(),
            _buildAnnotationsTab(),
            _buildStatsTab(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildArticlesTab() {
    final theme = Theme.of(context);
    
    // Mock articles for demonstration
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 10,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GlassMorphism(
            blur: 10,
            opacity: 0.1,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () {
                // Open article detail
              },
              borderRadius: BorderRadius.circular(16),
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
                            'U${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'User ${index + 1}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const Spacer(),
                        Text(
                          '2h ago',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Article Title ${index + 1}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This is a sample article excerpt that shows the beginning of the article content...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildArticleStat(
                          icon: LucideIcons.messageCircle,
                          count: 5,
                        ),
                        const SizedBox(width: 16),
                        _buildArticleStat(
                          icon: LucideIcons.highlighter,
                          count: 3,
                        ),
                        const SizedBox(width: 16),
                        _buildArticleStat(
                          icon: LucideIcons.bookmark,
                          count: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.2, end: 0);
      },
    );
  }
  
  Widget _buildCommentsTab() {
    final theme = Theme.of(context);
    final collaboration = ref.read(collaborationProvider);
    
    if (!_folder.permissions.allowComments) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.messageOff,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Comments are disabled',
              style: theme.textTheme.titleLarge,
            ),
            Text(
              'The folder owner has disabled comments',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }
    
    // Mock comments
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return _buildCommentCard(index);
      },
    );
  }
  
  Widget _buildAnnotationsTab() {
    final theme = Theme.of(context);
    
    if (!_folder.permissions.allowAnnotations) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.highlighter,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Annotations are disabled',
              style: theme.textTheme.titleLarge,
            ),
            Text(
              'The folder owner has disabled annotations',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }
    
    // Mock annotations
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) {
        return _buildAnnotationCard(index);
      },
    );
  }
  
  Widget _buildStatsTab() {
    final theme = Theme.of(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatCard(
            title: 'Members',
            value: _folder.memberCount.toString(),
            icon: LucideIcons.users,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          _buildStatCard(
            title: 'Articles',
            value: _folder.articleCount.toString(),
            icon: LucideIcons.fileText,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          _buildStatCard(
            title: 'Feeds',
            value: _folder.feedIds.length.toString(),
            icon: LucideIcons.rss,
            color: Colors.orange,
          ),
          const SizedBox(height: 16),
          _buildStatCard(
            title: 'Comments',
            value: '42',
            icon: LucideIcons.messageCircle,
            color: Colors.purple,
          ),
          const SizedBox(height: 16),
          _buildStatCard(
            title: 'Annotations',
            value: '28',
            icon: LucideIcons.highlighter,
            color: Colors.pink,
          ),
        ],
      ),
    );
  }
  
  Widget _buildArticleStat({required IconData icon, required int count}) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
        ),
        const SizedBox(width: 4),
        Text(
          count.toString(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
  
  Widget _buildCommentCard(int index) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassMorphism(
        blur: 10,
        opacity: 0.1,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                    child: Text(
                      'U${index + 1}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User ${index + 1}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '2 hours ago • on Article Title',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'This is a sample comment discussing the article content and sharing thoughts about the topic.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.heart, size: 16),
                    label: const Text('5'),
                  ),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.messageCircle, size: 16),
                    label: const Text('Reply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.2, end: 0);
  }
  
  Widget _buildAnnotationCard(int index) {
    final theme = Theme.of(context);
    final colors = [Colors.yellow, Colors.green, Colors.blue];
    final color = colors[index % colors.length];
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassMorphism(
        blur: 10,
        opacity: 0.1,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: color,
                width: 4,
              ),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.highlighter,
                      size: 16,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'User ${index + 1}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '1 hour ago',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '"This is the highlighted text from the article that the user found important or interesting."',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Note: This point is particularly relevant to our discussion about the future of technology.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: -0.2, end: 0);
  }
  
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    
    return GlassMorphism(
      blur: 10,
      opacity: 0.1,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    ),
                  ),
                  Text(
                    value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _handleMenuAction(String action, MemberRole myRole) {
    switch (action) {
      case 'activity':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FolderActivityScreen(folder: _folder),
          ),
        );
        break;
      case 'members':
        _showMembersDialog();
        break;
      case 'settings':
        // Show settings dialog
        break;
      case 'leave':
        _confirmLeaveFolder();
        break;
    }
  }
  
  void _showMembersDialog() {
    showDialog(
      context: context,
      builder: (context) => MembersListDialog(folder: _folder),
    );
  }
  
  void _showInviteMemberDialog() {
    showDialog(
      context: context,
      builder: (context) => InviteMemberDialog(folder: _folder),
    );
  }
  
  void _confirmLeaveFolder() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Folder?'),
        content: Text('Are you sure you want to leave "${_folder.name}"? You will lose access to all content in this folder.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                final collaboration = ref.read(collaborationProvider);
                await collaboration.leaveFolder(_folder.id);
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Left shared folder'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to leave folder: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}