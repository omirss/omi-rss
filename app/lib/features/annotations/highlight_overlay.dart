import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/annotations_provider.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_button.dart';
import 'highlights_annotations.dart';

// Highlightable text widget
class HighlightableText extends ConsumerStatefulWidget {
  final String text;
  final String articleId;
  final TextStyle? style;
  final TextAlign? textAlign;
  
  const HighlightableText({
    super.key,
    required this.text,
    required this.articleId,
    this.style,
    this.textAlign,
  });
  
  @override
  ConsumerState<HighlightableText> createState() => _HighlightableTextState();
}

class _HighlightableTextState extends ConsumerState<HighlightableText> {
  TextSelection? _selection;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  
  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }
  
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
  
  void _showHighlightMenu(TextSelection selection) {
    final settings = ref.read(annotationSettingsProvider);
    if (!settings.showHighlightMenu) return;
    
    _removeOverlay();
    
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: Offset(0, -60),
          child: Material(
            color: Colors.transparent,
            child: HighlightMenu(
              selection: selection,
              text: widget.text,
              articleId: widget.articleId,
              onHighlight: (color) {
                _createHighlight(selection, color);
                _removeOverlay();
              },
              onAnnotate: () {
                _showAnnotationDialog(selection);
                _removeOverlay();
              },
              onDismiss: _removeOverlay,
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(_overlayEntry!);
    
    if (settings.vibrateOnHighlight) {
      HapticFeedback.lightImpact();
    }
  }
  
  void _createHighlight(TextSelection selection, Color color) {
    final selectedText = widget.text.substring(
      selection.start,
      selection.end,
    );
    
    ref.read(annotationActionsProvider).addHighlight(
      articleId: widget.articleId,
      text: selectedText,
      startOffset: selection.start,
      endOffset: selection.end,
      color: color,
    );
    
    setState(() {
      _selection = null;
    });
  }
  
  void _showAnnotationDialog(TextSelection selection) {
    final selectedText = widget.text.substring(
      selection.start,
      selection.end,
    );
    
    showDialog(
      context: context,
      builder: (context) => AnnotationDialog(
        selectedText: selectedText,
        onSave: (text, type, tags) {
          // First create highlight
          final highlight = Highlight(
            articleId: widget.articleId,
            text: selectedText,
            startOffset: selection.start,
            endOffset: selection.end,
            color: ref.read(annotationSettingsProvider).defaultHighlightColor,
          );
          
          ref.read(highlightManagerProvider).addHighlight(highlight);
          
          // Then add annotation
          ref.read(annotationActionsProvider).addAnnotation(
            articleId: widget.articleId,
            highlightId: highlight.id,
            text: text,
            type: type,
            tags: tags,
          );
          
          setState(() {
            _selection = null;
          });
        },
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final highlights = ref.watch(articleHighlightsProvider(widget.articleId));
    final settings = ref.watch(annotationSettingsProvider);
    
    if (!settings.enableTextSelection || highlights.isEmpty) {
      return SelectableText(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
        onSelectionChanged: settings.enableTextSelection
          ? (selection, cause) {
              if (selection != null && selection.start != selection.end) {
                setState(() {
                  _selection = selection;
                });
                _showHighlightMenu(selection);
              } else {
                _removeOverlay();
              }
            }
          : null,
      );
    }
    
    return CompositedTransformTarget(
      link: _layerLink,
      child: SelectableText.rich(
        _buildHighlightedText(highlights),
        style: widget.style,
        textAlign: widget.textAlign,
        onSelectionChanged: (selection, cause) {
          if (selection != null && selection.start != selection.end) {
            setState(() {
              _selection = selection;
            });
            _showHighlightMenu(selection);
          } else {
            _removeOverlay();
          }
        },
      ),
    );
  }
  
  TextSpan _buildHighlightedText(List<Highlight> highlights) {
    if (highlights.isEmpty) {
      return TextSpan(text: widget.text, style: widget.style);
    }
    
    final spans = <TextSpan>[];
    int currentIndex = 0;
    
    for (final highlight in highlights) {
      // Add non-highlighted text before this highlight
      if (currentIndex < highlight.startOffset) {
        spans.add(TextSpan(
          text: widget.text.substring(currentIndex, highlight.startOffset),
          style: widget.style,
        ));
      }
      
      // Add highlighted text
      spans.add(TextSpan(
        text: widget.text.substring(highlight.startOffset, highlight.endOffset),
        style: widget.style?.copyWith(
          backgroundColor: highlight.color.withOpacity(0.4),
        ) ?? TextStyle(backgroundColor: highlight.color.withOpacity(0.4)),
        recognizer: null, // Could add tap handler here
      ));
      
      currentIndex = highlight.endOffset;
    }
    
    // Add remaining text
    if (currentIndex < widget.text.length) {
      spans.add(TextSpan(
        text: widget.text.substring(currentIndex),
        style: widget.style,
      ));
    }
    
    return TextSpan(children: spans);
  }
}

// Highlight menu widget
class HighlightMenu extends ConsumerWidget {
  final TextSelection selection;
  final String text;
  final String articleId;
  final Function(Color) onHighlight;
  final VoidCallback onAnnotate;
  final VoidCallback onDismiss;
  
  const HighlightMenu({
    super.key,
    required this.selection,
    required this.text,
    required this.articleId,
    required this.onHighlight,
    required this.onAnnotate,
    required this.onDismiss,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Color options
          ...HighlightColors.colors.take(5).map((highlightColor) => 
            IconButton(
              icon: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: highlightColor.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              onPressed: () => onHighlight(highlightColor.color),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          ),
          
          const VerticalDivider(
            color: Colors.white24,
            width: 16,
            thickness: 1,
            indent: 4,
            endIndent: 4,
          ),
          
          // Annotate button
          IconButton(
            icon: const Icon(Icons.note_add, color: Colors.white, size: 20),
            onPressed: onAnnotate,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          
          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: onDismiss,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// Annotation dialog
class AnnotationDialog extends StatefulWidget {
  final String selectedText;
  final Function(String text, AnnotationType type, List<String> tags) onSave;
  
  const AnnotationDialog({
    super.key,
    required this.selectedText,
    required this.onSave,
  });
  
  @override
  State<AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<AnnotationDialog> {
  final _textController = TextEditingController();
  final _tagsController = TextEditingController();
  AnnotationType _selectedType = AnnotationType.note;
  
  @override
  void dispose() {
    _textController.dispose();
    _tagsController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Annotation',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Selected text preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${widget.selectedText}"',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            
            // Annotation type selector
            Wrap(
              spacing: 8,
              children: AnnotationType.values.map((type) => 
                ChoiceChip(
                  label: Text(_getTypeLabel(type)),
                  selected: _selectedType == type,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedType = type);
                    }
                  },
                  selectedColor: GlassTheme.primaryColor,
                  labelStyle: TextStyle(
                    color: _selectedType == type ? Colors.white : Colors.white70,
                  ),
                ),
              ).toList(),
            ),
            const SizedBox(height: 16),
            
            // Annotation text
            TextField(
              controller: _textController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter your annotation...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Tags
            TextField(
              controller: _tagsController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Tags (comma separated)',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GlassButton(
                  text: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                  variant: GlassButtonVariant.text,
                ),
                const SizedBox(width: 16),
                GlassButton(
                  text: 'Save',
                  onPressed: () {
                    final text = _textController.text.trim();
                    if (text.isNotEmpty) {
                      final tags = _tagsController.text
                          .split(',')
                          .map((t) => t.trim())
                          .where((t) => t.isNotEmpty)
                          .toList();
                      
                      widget.onSave(text, _selectedType, tags);
                      Navigator.pop(context);
                    }
                  },
                  variant: GlassButtonVariant.elevated,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  String _getTypeLabel(AnnotationType type) {
    switch (type) {
      case AnnotationType.note:
        return 'Note';
      case AnnotationType.comment:
        return 'Comment';
      case AnnotationType.question:
        return 'Question';
      case AnnotationType.idea:
        return 'Idea';
      case AnnotationType.summary:
        return 'Summary';
      case AnnotationType.definition:
        return 'Definition';
      case AnnotationType.reference:
        return 'Reference';
      case AnnotationType.correction:
        return 'Correction';
    }
  }
}