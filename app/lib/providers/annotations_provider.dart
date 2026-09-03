import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../features/annotations/highlights_annotations.dart';

// Highlight manager provider
final highlightManagerProvider = Provider<HighlightManager>((ref) {
  return HighlightManager();
});

// Highlights for article provider
final articleHighlightsProvider = Provider.family<List<Highlight>, String>((ref, articleId) {
  final manager = ref.watch(highlightManagerProvider);
  return manager.getHighlights(articleId);
});

// Annotations for article provider
final articleAnnotationsProvider = Provider.family<List<Annotation>, String>((ref, articleId) {
  final manager = ref.watch(highlightManagerProvider);
  return manager.getAnnotations(articleId);
});

// Annotation settings provider
final annotationSettingsProvider = StateNotifierProvider<AnnotationSettingsNotifier, AnnotationSettings>((ref) {
  return AnnotationSettingsNotifier();
});

class AnnotationSettings {
  final Color defaultHighlightColor;
  final bool autoSave;
  final bool showAnnotationCount;
  final bool enableTextSelection;
  final bool shareHighlights;
  final HighlightMode highlightMode;
  final bool showHighlightMenu;
  final bool vibrateOnHighlight;
  
  AnnotationSettings({
    this.defaultHighlightColor = const Color(0xFFFFEB3B),
    this.autoSave = true,
    this.showAnnotationCount = true,
    this.enableTextSelection = true,
    this.shareHighlights = false,
    this.highlightMode = HighlightMode.word,
    this.showHighlightMenu = true,
    this.vibrateOnHighlight = true,
  });
  
  AnnotationSettings copyWith({
    Color? defaultHighlightColor,
    bool? autoSave,
    bool? showAnnotationCount,
    bool? enableTextSelection,
    bool? shareHighlights,
    HighlightMode? highlightMode,
    bool? showHighlightMenu,
    bool? vibrateOnHighlight,
  }) {
    return AnnotationSettings(
      defaultHighlightColor: defaultHighlightColor ?? this.defaultHighlightColor,
      autoSave: autoSave ?? this.autoSave,
      showAnnotationCount: showAnnotationCount ?? this.showAnnotationCount,
      enableTextSelection: enableTextSelection ?? this.enableTextSelection,
      shareHighlights: shareHighlights ?? this.shareHighlights,
      highlightMode: highlightMode ?? this.highlightMode,
      showHighlightMenu: showHighlightMenu ?? this.showHighlightMenu,
      vibrateOnHighlight: vibrateOnHighlight ?? this.vibrateOnHighlight,
    );
  }
}

enum HighlightMode {
  word,
  sentence,
  paragraph,
  custom,
}

class AnnotationSettingsNotifier extends StateNotifier<AnnotationSettings> {
  static const String _storageKey = 'annotation_settings';
  
  AnnotationSettingsNotifier() : super(AnnotationSettings()) {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    state = AnnotationSettings(
      defaultHighlightColor: Color(prefs.getInt('${_storageKey}_defaultColor') ?? 0xFFFFEB3B),
      autoSave: prefs.getBool('${_storageKey}_autoSave') ?? true,
      showAnnotationCount: prefs.getBool('${_storageKey}_showAnnotationCount') ?? true,
      enableTextSelection: prefs.getBool('${_storageKey}_enableTextSelection') ?? true,
      shareHighlights: prefs.getBool('${_storageKey}_shareHighlights') ?? false,
      highlightMode: HighlightMode.values[prefs.getInt('${_storageKey}_highlightMode') ?? 0],
      showHighlightMenu: prefs.getBool('${_storageKey}_showHighlightMenu') ?? true,
      vibrateOnHighlight: prefs.getBool('${_storageKey}_vibrateOnHighlight') ?? true,
    );
  }
  
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setInt('${_storageKey}_defaultColor', state.defaultHighlightColor.value);
    await prefs.setBool('${_storageKey}_autoSave', state.autoSave);
    await prefs.setBool('${_storageKey}_showAnnotationCount', state.showAnnotationCount);
    await prefs.setBool('${_storageKey}_enableTextSelection', state.enableTextSelection);
    await prefs.setBool('${_storageKey}_shareHighlights', state.shareHighlights);
    await prefs.setInt('${_storageKey}_highlightMode', state.highlightMode.index);
    await prefs.setBool('${_storageKey}_showHighlightMenu', state.showHighlightMenu);
    await prefs.setBool('${_storageKey}_vibrateOnHighlight', state.vibrateOnHighlight);
  }
  
  void setDefaultHighlightColor(Color color) {
    state = state.copyWith(defaultHighlightColor: color);
    _saveSettings();
  }
  
  void toggleAutoSave() {
    state = state.copyWith(autoSave: !state.autoSave);
    _saveSettings();
  }
  
  void toggleShowAnnotationCount() {
    state = state.copyWith(showAnnotationCount: !state.showAnnotationCount);
    _saveSettings();
  }
  
  void toggleEnableTextSelection() {
    state = state.copyWith(enableTextSelection: !state.enableTextSelection);
    _saveSettings();
  }
  
  void toggleShareHighlights() {
    state = state.copyWith(shareHighlights: !state.shareHighlights);
    _saveSettings();
  }
  
  void setHighlightMode(HighlightMode mode) {
    state = state.copyWith(highlightMode: mode);
    _saveSettings();
  }
  
  void toggleShowHighlightMenu() {
    state = state.copyWith(showHighlightMenu: !state.showHighlightMenu);
    _saveSettings();
  }
  
  void toggleVibrateOnHighlight() {
    state = state.copyWith(vibrateOnHighlight: !state.vibrateOnHighlight);
    _saveSettings();
  }
}

// Annotation actions provider
final annotationActionsProvider = Provider<AnnotationActions>((ref) {
  return AnnotationActions(ref);
});

class AnnotationActions {
  final Ref ref;
  
  AnnotationActions(this.ref);
  
  void addHighlight({
    required String articleId,
    required String text,
    required int startOffset,
    required int endOffset,
    Color? color,
    String? note,
  }) {
    final settings = ref.read(annotationSettingsProvider);
    final manager = ref.read(highlightManagerProvider);
    
    final highlight = Highlight(
      articleId: articleId,
      text: text,
      startOffset: startOffset,
      endOffset: endOffset,
      color: color ?? settings.defaultHighlightColor,
      note: note,
    );
    
    manager.addHighlight(highlight);
    
    if (settings.autoSave) {
      _saveToStorage();
    }
  }
  
  void removeHighlight(String articleId, String highlightId) {
    final manager = ref.read(highlightManagerProvider);
    manager.removeHighlight(articleId, highlightId);
    
    final settings = ref.read(annotationSettingsProvider);
    if (settings.autoSave) {
      _saveToStorage();
    }
  }
  
  void updateHighlightColor(String articleId, String highlightId, Color color) {
    final manager = ref.read(highlightManagerProvider);
    final highlights = manager.getHighlights(articleId);
    final highlight = highlights.firstWhere((h) => h.id == highlightId);
    
    manager.updateHighlight(highlight.copyWith(color: color));
    
    final settings = ref.read(annotationSettingsProvider);
    if (settings.autoSave) {
      _saveToStorage();
    }
  }
  
  void addAnnotation({
    required String articleId,
    String? highlightId,
    required String text,
    required AnnotationType type,
    List<String> tags = const [],
    bool isPrivate = false,
  }) {
    final manager = ref.read(highlightManagerProvider);
    
    final annotation = Annotation(
      articleId: articleId,
      highlightId: highlightId,
      text: text,
      type: type,
      tags: tags,
      isPrivate: isPrivate,
    );
    
    manager.addAnnotation(annotation);
    
    final settings = ref.read(annotationSettingsProvider);
    if (settings.autoSave) {
      _saveToStorage();
    }
  }
  
  void removeAnnotation(String articleId, String annotationId) {
    final manager = ref.read(highlightManagerProvider);
    manager.removeAnnotation(articleId, annotationId);
    
    final settings = ref.read(annotationSettingsProvider);
    if (settings.autoSave) {
      _saveToStorage();
    }
  }
  
  void updateAnnotation(Annotation annotation) {
    final manager = ref.read(highlightManagerProvider);
    manager.updateAnnotation(annotation);
    
    final settings = ref.read(annotationSettingsProvider);
    if (settings.autoSave) {
      _saveToStorage();
    }
  }
  
  Future<void> _saveToStorage() async {
    final manager = ref.read(highlightManagerProvider);
    final data = manager.exportData();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('highlights_annotations_data', json.encode(data));
  }
  
  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final dataString = prefs.getString('highlights_annotations_data');
    
    if (dataString != null) {
      final data = json.decode(dataString);
      final manager = ref.read(highlightManagerProvider);
      manager.importData(data);
    }
  }
  
  Future<void> exportToFile() async {
    final manager = ref.read(highlightManagerProvider);
    final data = manager.exportData();
    
    // Export logic would go here
    // This could save to a file or share via platform channels
  }
  
  List<SearchResult> search(String query) {
    final manager = ref.read(highlightManagerProvider);
    return manager.search(query);
  }
}

// Highlight statistics provider
final highlightStatisticsProvider = Provider.family<HighlightStatistics, String>((ref, articleId) {
  final highlights = ref.watch(articleHighlightsProvider(articleId));
  final annotations = ref.watch(articleAnnotationsProvider(articleId));
  
  final colorCounts = <Color, int>{};
  for (final highlight in highlights) {
    colorCounts[highlight.color] = (colorCounts[highlight.color] ?? 0) + 1;
  }
  
  final typeCounts = <AnnotationType, int>{};
  for (final annotation in annotations) {
    typeCounts[annotation.type] = (typeCounts[annotation.type] ?? 0) + 1;
  }
  
  return HighlightStatistics(
    totalHighlights: highlights.length,
    totalAnnotations: annotations.length,
    colorDistribution: colorCounts,
    typeDistribution: typeCounts,
  );
});

class HighlightStatistics {
  final int totalHighlights;
  final int totalAnnotations;
  final Map<Color, int> colorDistribution;
  final Map<AnnotationType, int> typeDistribution;
  
  HighlightStatistics({
    required this.totalHighlights,
    required this.totalAnnotations,
    required this.colorDistribution,
    required this.typeDistribution,
  });
}