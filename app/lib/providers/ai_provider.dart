import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/ai_service.dart';
import '../core/database/database.dart';
import 'database_provider.dart';

/// AI Service provider
final aiServiceProvider = Provider<AIService>((ref) {
  final database = ref.watch(databaseProvider);
  return AIService(database: database);
});

/// AI analysis state for a specific article
final articleAIAnalysisProvider = StateNotifierProvider.family<
    ArticleAIAnalysisNotifier, AsyncValue<AIAnalysisResult?>, String>(
  (ref, articleId) => ArticleAIAnalysisNotifier(
    ref: ref,
    articleId: articleId,
  ),
);

/// Notifier for article AI analysis
class ArticleAIAnalysisNotifier extends StateNotifier<AsyncValue<AIAnalysisResult?>> {
  final Ref ref;
  final String articleId;
  
  ArticleAIAnalysisNotifier({
    required this.ref,
    required this.articleId,
  }) : super(const AsyncValue.loading()) {
    _loadCachedAnalysis();
  }
  
  Future<void> _loadCachedAnalysis() async {
    try {
      // TODO: Load from database cache
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
  
  Future<void> analyze({
    required List<AIAnalysisType> types,
  }) async {
    state = const AsyncValue.loading();
    
    try {
      final aiService = ref.read(aiServiceProvider);
      // TODO: Get article from database
      // final article = await ref.read(databaseProvider).getArticle(articleId);
      
      // For now, create a dummy article
      final article = Article(
        id: articleId,
        feedId: 'feed1',
        guid: 'guid1',
        title: 'Sample Article',
        url: 'https://example.com',
        content: 'Sample content',
      );
      
      final result = await aiService.analyzeArticle(
        article,
        analyses: types,
      );
      
      state = AsyncValue.data(result);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
  
  void clearAnalysis() {
    state = const AsyncValue.data(null);
  }
}

/// Provider for AI-generated questions
final aiQuestionsProvider = FutureProvider.family<List<String>, String>(
  (ref, content) async {
    final aiService = ref.watch(aiServiceProvider);
    return await aiService.generateQuestions(content);
  },
);

/// Provider for AI question answering
final aiAnswerProvider = FutureProvider.family<String, AiQuestionParams>(
  (ref, params) async {
    final aiService = ref.watch(aiServiceProvider);
    return await aiService.answerQuestion(params.content, params.question);
  },
);

/// Parameters for AI question answering
class AiQuestionParams {
  final String content;
  final String question;
  
  AiQuestionParams({
    required this.content,
    required this.question,
  });
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiQuestionParams &&
          runtimeType == other.runtimeType &&
          content == other.content &&
          question == other.question;
  
  @override
  int get hashCode => content.hashCode ^ question.hashCode;
}

/// Provider for AI settings
final aiSettingsProvider = StateNotifierProvider<AISettingsNotifier, AISettings>(
  (ref) => AISettingsNotifier(),
);

/// AI settings
class AISettings {
  final bool enableAI;
  final bool autoAnalyze;
  final bool showPerspectives;
  final bool showBiasDetection;
  final bool showFactCheck;
  final bool showSentiment;
  final bool cacheResults;
  final int cacheExpiryHours;
  final List<String> preferredProviders;
  
  AISettings({
    this.enableAI = true,
    this.autoAnalyze = false,
    this.showPerspectives = true,
    this.showBiasDetection = true,
    this.showFactCheck = true,
    this.showSentiment = true,
    this.cacheResults = true,
    this.cacheExpiryHours = 24,
    this.preferredProviders = const ['OpenAI', 'Anthropic', 'Google', 'Local'],
  });
  
  AISettings copyWith({
    bool? enableAI,
    bool? autoAnalyze,
    bool? showPerspectives,
    bool? showBiasDetection,
    bool? showFactCheck,
    bool? showSentiment,
    bool? cacheResults,
    int? cacheExpiryHours,
    List<String>? preferredProviders,
  }) {
    return AISettings(
      enableAI: enableAI ?? this.enableAI,
      autoAnalyze: autoAnalyze ?? this.autoAnalyze,
      showPerspectives: showPerspectives ?? this.showPerspectives,
      showBiasDetection: showBiasDetection ?? this.showBiasDetection,
      showFactCheck: showFactCheck ?? this.showFactCheck,
      showSentiment: showSentiment ?? this.showSentiment,
      cacheResults: cacheResults ?? this.cacheResults,
      cacheExpiryHours: cacheExpiryHours ?? this.cacheExpiryHours,
      preferredProviders: preferredProviders ?? this.preferredProviders,
    );
  }
}

/// Notifier for AI settings
class AISettingsNotifier extends StateNotifier<AISettings> {
  AISettingsNotifier() : super(AISettings()) {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    // TODO: Load from shared preferences
  }
  
  Future<void> _saveSettings() async {
    // TODO: Save to shared preferences
  }
  
  void setEnableAI(bool value) {
    state = state.copyWith(enableAI: value);
    _saveSettings();
  }
  
  void setAutoAnalyze(bool value) {
    state = state.copyWith(autoAnalyze: value);
    _saveSettings();
  }
  
  void setShowPerspectives(bool value) {
    state = state.copyWith(showPerspectives: value);
    _saveSettings();
  }
  
  void setShowBiasDetection(bool value) {
    state = state.copyWith(showBiasDetection: value);
    _saveSettings();
  }
  
  void setShowFactCheck(bool value) {
    state = state.copyWith(showFactCheck: value);
    _saveSettings();
  }
  
  void setShowSentiment(bool value) {
    state = state.copyWith(showSentiment: value);
    _saveSettings();
  }
  
  void setCacheResults(bool value) {
    state = state.copyWith(cacheResults: value);
    _saveSettings();
  }
  
  void setCacheExpiryHours(int hours) {
    state = state.copyWith(cacheExpiryHours: hours);
    _saveSettings();
  }
  
  void setPreferredProviders(List<String> providers) {
    state = state.copyWith(preferredProviders: providers);
    _saveSettings();
  }
}

/// Temporary Article model for AI provider
class Article {
  final String id;
  final String feedId;
  final String guid;
  final String title;
  final String url;
  final String? content;
  final String? excerpt;
  final String? author;
  final DateTime? publishedAt;
  final Feed? feed;
  
  Article({
    required this.id,
    required this.feedId,
    required this.guid,
    required this.title,
    required this.url,
    this.content,
    this.excerpt,
    this.author,
    this.publishedAt,
    this.feed,
  });
}

/// Temporary Feed model
class Feed {
  final String id;
  final String title;
  final String url;
  
  Feed({
    required this.id,
    required this.title,
    required this.url,
  });
}