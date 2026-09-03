import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/collaboration_service.dart';
import '../../../core/providers/collaboration_provider.dart';
import '../../components/glass_morphism.dart';
import '../../theme/app_theme.dart';

/// Dialog for inviting members to a folder
class InviteMemberDialog extends ConsumerStatefulWidget {
  final SharedFolder folder;
  
  const InviteMemberDialog({
    super.key,
    required this.folder,
  });

  @override
  ConsumerState<InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends ConsumerState<InviteMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  MemberRole _selectedRole = MemberRole.viewer;
  DateTime? _expiresAt;
  bool _isSending = false;
  ShareInvite? _generatedInvite;
  
  @override
  void dispose() {
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassMorphism(
        blur: 20,
        opacity: isDark ? 0.2 : 0.1,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                    child: const Icon(
                      LucideIcons.userPlus,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invite to ${widget.folder.name}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Send an invitation to join this shared folder',
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
              ).animate().fadeIn().slideY(begin: -0.1, end: 0),
              
              const SizedBox(height: 24),
              
              if (_generatedInvite == null) ...[
                // Form
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'user@example.com',
                          prefixIcon: const Icon(LucideIcons.mail),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter an email address';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ).animate().fadeIn(delay: 100.ms),
                      
                      const SizedBox(height: 16),
                      
                      // Role selection
                      Text(
                        'Select Role',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                                  ),
                                ),
                                dense: true,
                              ).animate().fadeIn(delay: (200 + role.index * 50).ms)),
                      
                      const SizedBox(height: 16),
                      
                      // Optional message
                      TextFormField(
                        controller: _messageController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Personal Message (Optional)',
                          hintText: 'Add a personal note to the invitation...',
                          prefixIcon: const Icon(LucideIcons.messageSquare),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ).animate().fadeIn(delay: 400.ms),
                      
                      const SizedBox(height: 16),
                      
                      // Expiration
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          LucideIcons.clock,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text('Invitation expires in'),
                        trailing: DropdownButton<int>(
                          value: 7,
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _expiresAt = DateTime.now().add(Duration(days: value));
                              });
                            }
                          },
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 day')),
                            DropdownMenuItem(value: 3, child: Text('3 days')),
                            DropdownMenuItem(value: 7, child: Text('7 days')),
                            DropdownMenuItem(value: 30, child: Text('30 days')),
                          ],
                        ),
                      ).animate().fadeIn(delay: 500.ms),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSending ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isSending ? null : _sendInvite,
                      icon: _isSending
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : const Icon(LucideIcons.send),
                      label: Text(_isSending ? 'Sending...' : 'Send Invite'),
                    ),
                  ],
                ).animate().fadeIn(delay: 600.ms),
              ] else ...[
                // Success state
                _buildSuccessState(),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSuccessState() {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            LucideIcons.checkCircle,
            size: 40,
            color: Colors.green,
          ),
        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
        
        const SizedBox(height: 24),
        
        Text(
          'Invitation Sent!',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ).animate().fadeIn(delay: 300.ms),
        
        const SizedBox(height: 8),
        
        Text(
          'Share the invite code below with ${_emailController.text}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
          ),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 400.ms),
        
        const SizedBox(height: 24),
        
        // Invite code display
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _generatedInvite!.token,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _generatedInvite!.token));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invite code copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                tooltip: 'Copy code',
              ),
            ],
          ),
        ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2, end: 0),
        
        const SizedBox(height: 16),
        
        // Share button
        OutlinedButton.icon(
          onPressed: () {
            Share.share(
              'Join my shared folder "${widget.folder.name}" on Omi RSS!\n\n'
              'Invite code: ${_generatedInvite!.token}\n\n'
              'Expires: ${_formatDate(_generatedInvite!.expiresAt)}',
              subject: 'Invitation to ${widget.folder.name}',
            );
          },
          icon: const Icon(LucideIcons.share2),
          label: const Text('Share Invite'),
        ).animate().fadeIn(delay: 600.ms),
        
        const SizedBox(height: 24),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _generatedInvite = null;
                  _emailController.clear();
                  _messageController.clear();
                });
              },
              child: const Text('Send Another'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ).animate().fadeIn(delay: 700.ms),
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
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
  
  Future<void> _sendInvite() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSending = true);
    
    try {
      final collaboration = ref.read(collaborationProvider);
      final invite = await collaboration.shareFolder(
        folderId: widget.folder.id,
        email: _emailController.text,
        role: _selectedRole,
        message: _messageController.text.isNotEmpty ? _messageController.text : null,
        expiresAt: _expiresAt,
      );
      
      if (mounted) {
        setState(() {
          _generatedInvite = invite;
          _isSending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send invite: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}