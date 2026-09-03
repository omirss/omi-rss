import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/services/collaboration_service.dart';
import '../../../core/providers/collaboration_provider.dart';
import '../../components/glass_morphism.dart';
import '../../theme/app_theme.dart';

/// Dialog showing folder members
class MembersListDialog extends ConsumerStatefulWidget {
  final SharedFolder folder;
  
  const MembersListDialog({
    super.key,
    required this.folder,
  });

  @override
  ConsumerState<MembersListDialog> createState() => _MembersListDialogState();
}

class _MembersListDialogState extends ConsumerState<MembersListDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final collaboration = ref.watch(collaborationProvider);
    final members = collaboration.getFolderMembers(widget.folder.id);
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
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassMorphism(
        blur: 20,
        opacity: isDark ? 0.2 : 0.1,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 500,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.dividerColor.withOpacity(0.1),
                    ),
                  ),
                ),
                child: Row(
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
                      child: const Icon(
                        LucideIcons.users,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Folder Members',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${members.length} members',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.1, end: 0),
              
              // Members list
              Flexible(
                child: members.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Text(
                            'No members yet',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.textTheme.bodyLarge?.color?.withOpacity(0.6),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          return _buildMemberTile(
                            member,
                            myRole,
                            index,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildMemberTile(FolderMember member, MemberRole myRole, int index) {
    final theme = Theme.of(context);
    final collaboration = ref.read(collaborationProvider);
    final isMe = member.userId == collaboration.currentUserId;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassMorphism(
        blur: 10,
        opacity: 0.05,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: _getRoleColor(member.role).withOpacity(0.2),
                child: member.avatarUrl != null
                    ? ClipOval(
                        child: Image.network(
                          member.avatarUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildAvatarFallback(member),
                        ),
                      )
                    : _buildAvatarFallback(member),
              ),
              const SizedBox(width: 16),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          member.userName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'You',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      member.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          size: 12,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Joined ${_formatDate(member.joinedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Role badge and actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRoleBadge(member.role),
                  if (myRole == MemberRole.owner && !isMe) ...[
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Icon(
                        LucideIcons.moreVertical,
                        size: 16,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                      ),
                      onSelected: (value) => _handleMemberAction(value, member),
                      itemBuilder: (context) => [
                        if (member.role != MemberRole.owner) ...[
                          const PopupMenuItem(
                            value: 'change_role',
                            child: ListTile(
                              leading: Icon(LucideIcons.userCog),
                              title: Text('Change Role'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'transfer_ownership',
                            child: ListTile(
                              leading: Icon(LucideIcons.crown),
                              title: Text('Transfer Ownership'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuDivider(),
                        ],
                        const PopupMenuItem(
                          value: 'remove',
                          child: ListTile(
                            leading: Icon(LucideIcons.userX, color: Colors.red),
                            title: Text('Remove', style: TextStyle(color: Colors.red)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.1, end: 0);
  }
  
  Widget _buildAvatarFallback(FolderMember member) {
    return Text(
      member.userName.substring(0, 2).toUpperCase(),
      style: TextStyle(
        color: _getRoleColor(member.role),
        fontWeight: FontWeight.bold,
      ),
    );
  }
  
  Widget _buildRoleBadge(MemberRole role) {
    final theme = Theme.of(context);
    final color = _getRoleColor(role);
    final label = _getRoleLabel(role);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (role == MemberRole.owner)
            Icon(
              LucideIcons.crown,
              size: 12,
              color: color,
            ),
          if (role == MemberRole.owner) const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getRoleColor(MemberRole role) {
    switch (role) {
      case MemberRole.owner:
        return Colors.purple;
      case MemberRole.editor:
        return Colors.blue;
      case MemberRole.contributor:
        return Colors.green;
      case MemberRole.viewer:
        return Colors.grey;
    }
  }
  
  String _getRoleLabel(MemberRole role) {
    switch (role) {
      case MemberRole.owner:
        return 'Owner';
      case MemberRole.editor:
        return 'Editor';
      case MemberRole.contributor:
        return 'Contributor';
      case MemberRole.viewer:
        return 'Viewer';
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else {
      return '${(difference.inDays / 365).floor()} years ago';
    }
  }
  
  void _handleMemberAction(String action, FolderMember member) async {
    final collaboration = ref.read(collaborationProvider);
    
    switch (action) {
      case 'change_role':
        _showChangeRoleDialog(member);
        break;
      case 'transfer_ownership':
        _confirmTransferOwnership(member);
        break;
      case 'remove':
        _confirmRemoveMember(member);
        break;
    }
  }
  
  void _showChangeRoleDialog(FolderMember member) {
    showDialog(
      context: context,
      builder: (context) => _ChangeRoleDialog(
        folder: widget.folder,
        member: member,
      ),
    );
  }
  
  void _confirmTransferOwnership(FolderMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Ownership?'),
        content: Text(
          'Are you sure you want to transfer ownership to ${member.userName}? '
          'You will become an Editor and cannot undo this action.',
        ),
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
                await collaboration.transferOwnership(
                  folderId: widget.folder.id,
                  newOwnerId: member.userId,
                );
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ownership transferred successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to transfer ownership: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }
  
  void _confirmRemoveMember(FolderMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text('Are you sure you want to remove ${member.userName} from this folder?'),
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
                await collaboration.removeMember(
                  folderId: widget.folder.id,
                  userId: member.userId,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Member removed successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to remove member: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _ChangeRoleDialog extends ConsumerStatefulWidget {
  final SharedFolder folder;
  final FolderMember member;
  
  const _ChangeRoleDialog({
    required this.folder,
    required this.member,
  });

  @override
  ConsumerState<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends ConsumerState<_ChangeRoleDialog> {
  late MemberRole _selectedRole;
  
  @override
  void initState() {
    super.initState();
    _selectedRole = widget.member.role;
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: const Text('Change Role'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select a new role for ${widget.member.userName}:'),
          const SizedBox(height: 16),
          ...MemberRole.values
              .where((role) => role != MemberRole.owner)
              .map((role) => RadioListTile<MemberRole>(
                    value: role,
                    groupValue: _selectedRole,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedRole = value);
                      }
                    },
                    title: Text(_getRoleLabel(role)),
                    subtitle: Text(
                      _getRoleDescription(role),
                      style: theme.textTheme.bodySmall,
                    ),
                  )),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedRole == widget.member.role
              ? null
              : () async {
                  Navigator.of(context).pop();
                  try {
                    final collaboration = ref.read(collaborationProvider);
                    await collaboration.updateMemberRole(
                      folderId: widget.folder.id,
                      userId: widget.member.userId,
                      newRole: _selectedRole,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Role updated successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update role: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
          child: const Text('Update Role'),
        ),
      ],
    );
  }
  
  String _getRoleLabel(MemberRole role) {
    switch (role) {
      case MemberRole.owner:
        return 'Owner';
      case MemberRole.editor:
        return 'Editor';
      case MemberRole.contributor:
        return 'Contributor';
      case MemberRole.viewer:
        return 'Viewer';
    }
  }
  
  String _getRoleDescription(MemberRole role) {
    switch (role) {
      case MemberRole.owner:
        return 'Full control over the folder';
      case MemberRole.editor:
        return 'Can add, edit, and delete content';
      case MemberRole.contributor:
        return 'Can add new content';
      case MemberRole.viewer:
        return 'Can only view content';
    }
  }
}