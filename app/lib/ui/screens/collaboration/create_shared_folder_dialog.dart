import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/services/collaboration_service.dart';
import '../../../core/providers/collaboration_provider.dart';
import '../../../core/providers/feeds_provider.dart';
import '../../components/glass_morphism.dart';
import '../../theme/app_theme.dart';

/// Dialog for creating a shared folder
class CreateSharedFolderDialog extends ConsumerStatefulWidget {
  const CreateSharedFolderDialog({super.key});

  @override
  ConsumerState<CreateSharedFolderDialog> createState() => _CreateSharedFolderDialogState();
}

class _CreateSharedFolderDialogState extends ConsumerState<CreateSharedFolderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Set<String> _selectedFeedIds = {};
  bool _isPublic = false;
  bool _isCreating = false;
  
  // Permissions
  bool _allowContributorWrite = true;
  bool _allowEditorDelete = true;
  bool _allowEditorInvite = true;
  bool _allowComments = true;
  bool _allowAnnotations = true;
  bool _allowViewerComment = false;
  bool _allowViewerAnnotate = false;
  bool _allowDownload = true;
  bool _allowPrint = true;
  
  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final feeds = ref.watch(feedsProvider);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassMorphism(
        blur: 20,
        opacity: isDark ? 0.2 : 0.1,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 600,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
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
                        LucideIcons.folderPlus,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Shared Folder',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Share feeds and collaborate with others',
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
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic info
                        _buildSection(
                          title: 'Basic Information',
                          children: [
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Folder Name',
                                hintText: 'e.g., Tech News Collaboration',
                                prefixIcon: const Icon(LucideIcons.folder),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a folder name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Description',
                                hintText: 'Describe what this folder is about...',
                                prefixIcon: const Icon(LucideIcons.fileText),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a description';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Feed selection
                        _buildSection(
                          title: 'Select Feeds',
                          children: [
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.dividerColor.withOpacity(0.2),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: feeds.when(
                                data: (feedList) => ListView.builder(
                                  itemCount: feedList.length,
                                  itemBuilder: (context, index) {
                                    final feed = feedList[index];
                                    final isSelected = _selectedFeedIds.contains(feed.id);
                                    
                                    return CheckboxListTile(
                                      value: isSelected,
                                      onChanged: (value) {
                                        setState(() {
                                          if (value == true) {
                                            _selectedFeedIds.add(feed.id);
                                          } else {
                                            _selectedFeedIds.remove(feed.id);
                                          }
                                        });
                                      },
                                      title: Text(feed.title),
                                      subtitle: Text(
                                        feed.url,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      secondary: feed.favicon != null
                                          ? Image.network(
                                              feed.favicon!,
                                              width: 24,
                                              height: 24,
                                              errorBuilder: (_, __, ___) => Icon(
                                                LucideIcons.rss,
                                                size: 24,
                                                color: theme.colorScheme.primary,
                                              ),
                                            )
                                          : Icon(
                                              LucideIcons.rss,
                                              size: 24,
                                              color: theme.colorScheme.primary,
                                            ),
                                    );
                                  },
                                ),
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (_, __) => const Center(
                                  child: Text('Failed to load feeds'),
                                ),
                              ),
                            ),
                            if (_selectedFeedIds.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Please select at least one feed',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Visibility
                        _buildSection(
                          title: 'Visibility',
                          children: [
                            SwitchListTile(
                              value: _isPublic,
                              onChanged: (value) => setState(() => _isPublic = value),
                              title: const Text('Public Folder'),
                              subtitle: Text(
                                _isPublic
                                    ? 'Anyone can discover and join this folder'
                                    : 'Only invited members can access this folder',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                                ),
                              ),
                              secondary: Icon(
                                _isPublic ? LucideIcons.globe : LucideIcons.lock,
                                color: _isPublic ? Colors.green : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Permissions
                        _buildSection(
                          title: 'Permissions',
                          children: [
                            _buildPermissionTile(
                              title: 'Allow comments',
                              value: _allowComments,
                              onChanged: (value) => setState(() => _allowComments = value),
                            ),
                            _buildPermissionTile(
                              title: 'Allow annotations',
                              value: _allowAnnotations,
                              onChanged: (value) => setState(() => _allowAnnotations = value),
                            ),
                            _buildPermissionTile(
                              title: 'Contributors can add articles',
                              value: _allowContributorWrite,
                              onChanged: (value) => setState(() => _allowContributorWrite = value),
                            ),
                            _buildPermissionTile(
                              title: 'Editors can delete content',
                              value: _allowEditorDelete,
                              onChanged: (value) => setState(() => _allowEditorDelete = value),
                            ),
                            _buildPermissionTile(
                              title: 'Editors can invite members',
                              value: _allowEditorInvite,
                              onChanged: (value) => setState(() => _allowEditorInvite = value),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Actions
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: theme.dividerColor.withOpacity(0.1),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isCreating ? null : _createFolder,
                      icon: _isCreating
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
                          : const Icon(LucideIcons.check),
                      label: Text(_isCreating ? 'Creating...' : 'Create Folder'),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: 0.1, end: 0),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ).animate().fadeIn().slideX(begin: -0.1, end: 0);
  }
  
  Widget _buildPermissionTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
          ),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _createFolder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFeedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one feed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() => _isCreating = true);
    
    try {
      final collaboration = ref.read(collaborationProvider);
      
      final permissions = SharedFolderPermissions(
        allowContributorWrite: _allowContributorWrite,
        allowEditorDelete: _allowEditorDelete,
        allowEditorInvite: _allowEditorInvite,
        allowComments: _allowComments,
        allowAnnotations: _allowAnnotations,
        allowViewerComment: _allowViewerComment,
        allowViewerAnnotate: _allowViewerAnnotate,
        allowDownload: _allowDownload,
        allowPrint: _allowPrint,
      );
      
      await collaboration.createSharedFolder(
        name: _nameController.text,
        description: _descriptionController.text,
        feedIds: _selectedFeedIds.toList(),
        permissions: permissions,
        isPublic: _isPublic,
      );
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created shared folder: ${_nameController.text}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
}