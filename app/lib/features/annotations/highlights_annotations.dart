import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

// Highlight model
class Highlight {
  final String id;
  final String articleId;
  final String text;
  final int startOffset;
  final int endOffset;
  final Color color;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? note;
  
  Highlight({
    String? id,
    required this.articleId,
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.color,
    DateTime? createdAt,
    this.updatedAt,
    this.note,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();
  
  Highlight copyWith({
    String? id,
    String? articleId,
    String? text,
    int? startOffset,
    int? endOffset,
    Color? color,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? note,
  }) {
    return Highlight(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      text: text ?? this.text,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      note: note ?? this.note,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'articleId': articleId,
      'text': text,
      'startOffset': startOffset,
      'endOffset': endOffset,
      'color': color.value,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'note': note,
    };
  }
  
  factory Highlight.fromJson(Map<String, dynamic> json) {
    return Highlight(
      id: json['id'],
      articleId: json['articleId'],
      text: json['text'],
      startOffset: json['startOffset'],
      endOffset: json['endOffset'],
      color: Color(json['color']),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      note: json['note'],
    );
  }
}

// Annotation model
class Annotation {
  final String id;
  final String articleId;
  final String? highlightId;
  final String text;
  final AnnotationType type;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> tags;
  final bool isPrivate;
  final String? replyToId;
  
  Annotation({
    String? id,
    required this.articleId,
    this.highlightId,
    required this.text,
    required this.type,
    DateTime? createdAt,
    this.updatedAt,
    this.tags = const [],
    this.isPrivate = false,
    this.replyToId,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();
  
  Annotation copyWith({
    String? id,
    String? articleId,
    String? highlightId,
    String? text,
    AnnotationType? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    bool? isPrivate,
    String? replyToId,
  }) {
    return Annotation(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      highlightId: highlightId ?? this.highlightId,
      text: text ?? this.text,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      isPrivate: isPrivate ?? this.isPrivate,
      replyToId: replyToId ?? this.replyToId,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'articleId': articleId,
      'highlightId': highlightId,
      'text': text,
      'type': type.toString(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'tags': tags,
      'isPrivate': isPrivate,
      'replyToId': replyToId,
    };
  }
  
  factory Annotation.fromJson(Map<String, dynamic> json) {
    return Annotation(
      id: json['id'],
      articleId: json['articleId'],
      highlightId: json['highlightId'],
      text: json['text'],
      type: AnnotationType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => AnnotationType.note,
      ),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      tags: List<String>.from(json['tags'] ?? []),
      isPrivate: json['isPrivate'] ?? false,
      replyToId: json['replyToId'],
    );
  }
}

enum AnnotationType {
  note,
  comment,
  question,
  idea,
  summary,
  definition,
  reference,
  correction,
}

// Highlight colors
class HighlightColors {
  static const List<HighlightColor> colors = [
    HighlightColor('Yellow', Color(0xFFFFEB3B)),
    HighlightColor('Green', Color(0xFF4CAF50)),
    HighlightColor('Blue', Color(0xFF2196F3)),
    HighlightColor('Purple', Color(0xFF9C27B0)),
    HighlightColor('Pink', Color(0xFFE91E63)),
    HighlightColor('Orange', Color(0xFFFF9800)),
    HighlightColor('Red', Color(0xFFF44336)),
    HighlightColor('Cyan', Color(0xFF00BCD4)),
  ];
}

class HighlightColor {
  final String name;
  final Color color;
  
  const HighlightColor(this.name, this.color);
}

// Highlight manager
class HighlightManager {
  final Map<String, List<Highlight>> _articleHighlights = {};
  final Map<String, List<Annotation>> _articleAnnotations = {};
  
  // Add highlight
  void addHighlight(Highlight highlight) {
    _articleHighlights.putIfAbsent(highlight.articleId, () => []);
    _articleHighlights[highlight.articleId]!.add(highlight);
    _sortHighlights(highlight.articleId);
  }
  
  // Remove highlight
  void removeHighlight(String articleId, String highlightId) {
    _articleHighlights[articleId]?.removeWhere((h) => h.id == highlightId);
    // Also remove associated annotations
    _articleAnnotations[articleId]?.removeWhere((a) => a.highlightId == highlightId);
  }
  
  // Update highlight
  void updateHighlight(Highlight highlight) {
    final highlights = _articleHighlights[highlight.articleId];
    if (highlights != null) {
      final index = highlights.indexWhere((h) => h.id == highlight.id);
      if (index != -1) {
        highlights[index] = highlight.copyWith(updatedAt: DateTime.now());
        _sortHighlights(highlight.articleId);
      }
    }
  }
  
  // Get highlights for article
  List<Highlight> getHighlights(String articleId) {
    return _articleHighlights[articleId] ?? [];
  }
  
  // Add annotation
  void addAnnotation(Annotation annotation) {
    _articleAnnotations.putIfAbsent(annotation.articleId, () => []);
    _articleAnnotations[annotation.articleId]!.add(annotation);
  }
  
  // Remove annotation
  void removeAnnotation(String articleId, String annotationId) {
    _articleAnnotations[articleId]?.removeWhere((a) => a.id == annotationId);
  }
  
  // Update annotation
  void updateAnnotation(Annotation annotation) {
    final annotations = _articleAnnotations[annotation.articleId];
    if (annotations != null) {
      final index = annotations.indexWhere((a) => a.id == annotation.id);
      if (index != -1) {
        annotations[index] = annotation.copyWith(updatedAt: DateTime.now());
      }
    }
  }
  
  // Get annotations for article
  List<Annotation> getAnnotations(String articleId) {
    return _articleAnnotations[articleId] ?? [];
  }
  
  // Get annotations for highlight
  List<Annotation> getHighlightAnnotations(String articleId, String highlightId) {
    return getAnnotations(articleId).where((a) => a.highlightId == highlightId).toList();
  }
  
  // Sort highlights by position
  void _sortHighlights(String articleId) {
    _articleHighlights[articleId]?.sort((a, b) => a.startOffset.compareTo(b.startOffset));
  }
  
  // Search highlights and annotations
  List<SearchResult> search(String query) {
    final results = <SearchResult>[];
    final lowerQuery = query.toLowerCase();
    
    // Search highlights
    for (final entry in _articleHighlights.entries) {
      for (final highlight in entry.value) {
        if (highlight.text.toLowerCase().contains(lowerQuery) ||
            (highlight.note?.toLowerCase().contains(lowerQuery) ?? false)) {
          results.add(SearchResult(
            type: SearchResultType.highlight,
            articleId: entry.key,
            itemId: highlight.id,
            text: highlight.text,
            matchedText: highlight.note,
          ));
        }
      }
    }
    
    // Search annotations
    for (final entry in _articleAnnotations.entries) {
      for (final annotation in entry.value) {
        if (annotation.text.toLowerCase().contains(lowerQuery) ||
            annotation.tags.any((tag) => tag.toLowerCase().contains(lowerQuery))) {
          results.add(SearchResult(
            type: SearchResultType.annotation,
            articleId: entry.key,
            itemId: annotation.id,
            text: annotation.text,
            matchedText: annotation.tags.join(', '),
          ));
        }
      }
    }
    
    return results;
  }
  
  // Export highlights and annotations
  Map<String, dynamic> exportData() {
    return {
      'highlights': _articleHighlights.map((key, value) => 
        MapEntry(key, value.map((h) => h.toJson()).toList())
      ),
      'annotations': _articleAnnotations.map((key, value) => 
        MapEntry(key, value.map((a) => a.toJson()).toList())
      ),
      'exportedAt': DateTime.now().toIso8601String(),
    };
  }
  
  // Import highlights and annotations
  void importData(Map<String, dynamic> data) {
    // Clear existing data
    _articleHighlights.clear();
    _articleAnnotations.clear();
    
    // Import highlights
    final highlights = data['highlights'] as Map<String, dynamic>?;
    if (highlights != null) {
      for (final entry in highlights.entries) {
        final highlightList = (entry.value as List)
            .map((h) => Highlight.fromJson(h))
            .toList();
        _articleHighlights[entry.key] = highlightList;
      }
    }
    
    // Import annotations
    final annotations = data['annotations'] as Map<String, dynamic>?;
    if (annotations != null) {
      for (final entry in annotations.entries) {
        final annotationList = (entry.value as List)
            .map((a) => Annotation.fromJson(a))
            .toList();
        _articleAnnotations[entry.key] = annotationList;
      }
    }
  }
}

// Search result model
class SearchResult {
  final SearchResultType type;
  final String articleId;
  final String itemId;
  final String text;
  final String? matchedText;
  
  SearchResult({
    required this.type,
    required this.articleId,
    required this.itemId,
    required this.text,
    this.matchedText,
  });
}

enum SearchResultType {
  highlight,
  annotation,
}

// Text selection helper
class TextSelectionHelper {
  static TextSelection? getWordSelection(String text, int offset) {
    if (offset < 0 || offset >= text.length) return null;
    
    // Find word boundaries
    int start = offset;
    int end = offset;
    
    // Move start to beginning of word
    while (start > 0 && !_isWordBoundary(text[start - 1])) {
      start--;
    }
    
    // Move end to end of word
    while (end < text.length && !_isWordBoundary(text[end])) {
      end++;
    }
    
    if (start == end) return null;
    
    return TextSelection(baseOffset: start, extentOffset: end);
  }
  
  static TextSelection? getSentenceSelection(String text, int offset) {
    if (offset < 0 || offset >= text.length) return null;
    
    // Find sentence boundaries
    int start = offset;
    int end = offset;
    
    // Move start to beginning of sentence
    while (start > 0 && !_isSentenceBoundary(text[start - 1])) {
      start--;
    }
    
    // Move end to end of sentence
    while (end < text.length && !_isSentenceBoundary(text[end])) {
      end++;
    }
    
    // Include the sentence ending punctuation
    if (end < text.length && _isSentenceBoundary(text[end])) {
      end++;
    }
    
    return TextSelection(baseOffset: start, extentOffset: end);
  }
  
  static TextSelection? getParagraphSelection(String text, int offset) {
    if (offset < 0 || offset >= text.length) return null;
    
    // Find paragraph boundaries
    int start = offset;
    int end = offset;
    
    // Move start to beginning of paragraph
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    
    // Move end to end of paragraph
    while (end < text.length && text[end] != '\n') {
      end++;
    }
    
    return TextSelection(baseOffset: start, extentOffset: end);
  }
  
  static bool _isWordBoundary(String char) {
    return RegExp(r'[\s\.,;:!?\-\(\)\[\]{}"\']').hasMatch(char);
  }
  
  static bool _isSentenceBoundary(String char) {
    return RegExp(r'[.!?]').hasMatch(char);
  }
}