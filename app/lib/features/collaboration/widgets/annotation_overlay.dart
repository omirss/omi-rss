import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../collaboration_service.dart';

class AnnotationOverlay extends StatefulWidget {
  final String articleId;
  final String sessionId;
  final List<Annotation> annotations;
  final CollaborationService collaborationService;
  final Widget child;

  const AnnotationOverlay({
    super.key,
    required this.articleId,
    required this.sessionId,
    required this.annotations,
    required this.collaborationService,
    required this.child,
  });

  @override
  State<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends State<AnnotationOverlay> {
  OverlayEntry? _overlayEntry;
  Annotation? _selectedAnnotation;
  TextSelection? _currentSelection;

  void _showAnnotationMenu(Offset position, TextSelection selection) {
    _currentSelection = selection;
    _overlayEntry = OverlayEntry(
      builder: (context) => _AnnotationMenu(
        position: position,
        onAnnotationType: (type) {
          _createAnnotation(type);
          _hideOverlay();
        },
        onDismiss: _hideOverlay,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _currentSelection = null;
  }

  Future<void> _createAnnotation(String type) async {
    if (_currentSelection == null) return;

    try {
      switch (type) {
        case 'highlight':
          await _createHighlight();
          break;
        case 'comment':
          await _createComment();
          break;
        case 'reaction':
          await _createReaction();
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create annotation: $e')),
        );
      }
    }
  }

  Future<void> _createHighlight() async {
    final color = await _showColorPicker();
    if (color == null) return;

    await widget.collaborationService.createAnnotation(
      widget.sessionId,
      widget.articleId,
      'highlight',
      color: '#${color.value.toRadixString(16).substring(2)}',
      range: AnnotationRange(
        start: _currentSelection!.start,
        end: _currentSelection!.end,
        paragraphIndex: 0, // This should be calculated based on actual paragraph
      ),
    );
  }

  Future<void> _createComment() async {
    final comment = await _showCommentDialog();
    if (comment == null || comment.isEmpty) return;

    await widget.collaborationService.createAnnotation(
      widget.sessionId,
      widget.articleId,
      'comment',
      content: comment,
      range: AnnotationRange(
        start: _currentSelection!.start,
        end: _currentSelection!.end,
        paragraphIndex: 0,
      ),
    );
  }

  Future<void> _createReaction() async {
    final emoji = await _showEmojiPicker();
    if (emoji == null) return;

    await widget.collaborationService.createAnnotation(
      widget.sessionId,
      widget.articleId,
      'reaction',
      emoji: emoji,
      range: AnnotationRange(
        start: _currentSelection!.start,
        end: _currentSelection!.end,
        paragraphIndex: 0,
      ),
    );
  }

  Future<Color?> _showColorPicker() async {
    return showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Highlight Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Colors.yellow,
            Colors.green.shade300,
            Colors.blue.shade300,
            Colors.pink.shade200,
            Colors.orange.shade300,
            Colors.purple.shade200,
          ].map((color) {
            return InkWell(
              onTap: () => Navigator.pop(context, color),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<String?> _showCommentDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Comment'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter your comment...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showEmojiPicker() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Reaction'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: ['👍', '❤️', '🔥', '💡', '❓', '⭐'].map((emoji) {
            return InkWell(
              onTap: () => Navigator.pop(context, emoji),
              child: Text(emoji, style: const TextStyle(fontSize: 32)),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SelectableRegion(
          focusNode: FocusNode(),
          selectionControls: MaterialTextSelectionControls(),
          child: Builder(
            builder: (context) {
              return GestureDetector(
                onLongPress: () {
                  final selection = SelectableRegion.of(context).selectionOverlay?.value;
                  if (selection != null && !selection.isCollapsed) {
                    final renderBox = context.findRenderObject() as RenderBox;
                    final position = renderBox.localToGlobal(Offset.zero);
                    _showAnnotationMenu(position, selection);
                  }
                },
                child: widget.child,
              );
            },
          ),
        ),
        // Render existing annotations
        ...widget.annotations.map((annotation) {
          return _AnnotationWidget(
            annotation: annotation,
            onTap: () {
              setState(() {
                _selectedAnnotation = annotation;
              });
            },
          );
        }),
      ],
    );
  }
}

class _AnnotationMenu extends StatelessWidget {
  final Offset position;
  final Function(String) onAnnotationType;
  final VoidCallback onDismiss;

  const _AnnotationMenu({
    required this.position,
    required this.onAnnotationType,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Invisible full-screen gesture detector to dismiss
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(color: Colors.transparent),
          ),
        ),
        // The actual menu
        Positioned(
          left: position.dx,
          top: position.dy - 60,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MenuButton(
                    icon: Icons.highlight,
                    tooltip: 'Highlight',
                    onTap: () => onAnnotationType('highlight'),
                  ),
                  _MenuButton(
                    icon: Icons.comment,
                    tooltip: 'Comment',
                    onTap: () => onAnnotationType('comment'),
                  ),
                  _MenuButton(
                    icon: Icons.emoji_emotions,
                    tooltip: 'React',
                    onTap: () => onAnnotationType('reaction'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _AnnotationWidget extends StatelessWidget {
  final Annotation annotation;
  final VoidCallback onTap;

  const _AnnotationWidget({
    required this.annotation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // This is a simplified version - in a real implementation,
    // you'd need to calculate the actual position based on the text range
    return Positioned(
      left: 0,
      top: 0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: annotation.type == 'highlight'
                ? Color(int.parse(annotation.color!.substring(1), radix: 16))
                    .withOpacity(0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (annotation.type == 'comment')
                const Icon(Icons.comment, size: 16, color: Colors.blue),
              if (annotation.type == 'reaction')
                Text(annotation.emoji ?? '👍', style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class AnnotationSidebar extends StatelessWidget {
  final List<Annotation> annotations;
  final Map<String, UserPresence> userPresence;
  final Function(Annotation) onAnnotationTap;
  final Function(String) onDeleteAnnotation;

  const AnnotationSidebar({
    super.key,
    required this.annotations,
    required this.userPresence,
    required this.onAnnotationTap,
    required this.onDeleteAnnotation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.comment_bank,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Annotations (${annotations.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: annotations.length,
              itemBuilder: (context, index) {
                final annotation = annotations[index];
                final user = userPresence[annotation.userId];
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => onAnnotationTap(annotation),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundImage: user?.userAvatar != null
                                    ? NetworkImage(user!.userAvatar!)
                                    : null,
                                child: user?.userAvatar == null
                                    ? Text(
                                        user?.userName.substring(0, 1).toUpperCase() ?? '?',
                                        style: const TextStyle(fontSize: 12),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user?.userName ?? 'Unknown',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      _formatTime(annotation.createdAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildAnnotationIcon(annotation),
                            ],
                          ),
                          if (annotation.content != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              annotation.content!,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                          if (annotation.type == 'reaction') ...[
                            const SizedBox(height: 8),
                            Text(
                              annotation.emoji ?? '👍',
                              style: const TextStyle(fontSize: 24),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnotationIcon(Annotation annotation) {
    switch (annotation.type) {
      case 'highlight':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Color(int.parse(annotation.color!.substring(1), radix: 16)),
            shape: BoxShape.circle,
          ),
        );
      case 'comment':
        return const Icon(Icons.comment, size: 20);
      case 'reaction':
        return Text(annotation.emoji ?? '👍');
      default:
        return const SizedBox.shrink();
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}