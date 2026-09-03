import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/translation/translation_service.dart';
import '../core/models/article.dart';

// Translation service provider
final translationServiceProvider = Provider<TranslationService>((ref) {
  return TranslationService();
});

// Translation cache provider
final translationCacheProvider = Provider<TranslationCache>((ref) {
  return TranslationCache(maxCacheSize: 50);
});

// Translation settings provider
final translationSettingsProvider = StateNotifierProvider<TranslationSettingsNotifier, TranslationSettings>((ref) {
  return TranslationSettingsNotifier();
});

class TranslationSettings {
  final String? preferredLanguage;
  final bool autoDetectLanguage;
  final bool translateTitles;
  final bool translateContent;
  final bool translateSummaries;
  final bool showOriginalText;
  final bool cacheTranslations;
  final String? activeProviderId;
  
  TranslationSettings({
    this.preferredLanguage,
    this.autoDetectLanguage = true,
    this.translateTitles = true,
    this.translateContent = true,
    this.translateSummaries = true,
    this.showOriginalText = false,
    this.cacheTranslations = true,
    this.activeProviderId,
  });
  
  TranslationSettings copyWith({
    String? preferredLanguage,
    bool? autoDetectLanguage,
    bool? translateTitles,
    bool? translateContent,
    bool? translateSummaries,
    bool? showOriginalText,
    bool? cacheTranslations,
    String? activeProviderId,
  }) {
    return TranslationSettings(
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      autoDetectLanguage: autoDetectLanguage ?? this.autoDetectLanguage,
      translateTitles: translateTitles ?? this.translateTitles,
      translateContent: translateContent ?? this.translateContent,
      translateSummaries: translateSummaries ?? this.translateSummaries,
      showOriginalText: showOriginalText ?? this.showOriginalText,
      cacheTranslations: cacheTranslations ?? this.cacheTranslations,
      activeProviderId: activeProviderId ?? this.activeProviderId,
    );
  }
}

class TranslationSettingsNotifier extends StateNotifier<TranslationSettings> {
  static const String _storageKey = 'translation_settings';
  
  TranslationSettingsNotifier() : super(TranslationSettings()) {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    state = TranslationSettings(
      preferredLanguage: prefs.getString('${_storageKey}_preferredLanguage'),
      autoDetectLanguage: prefs.getBool('${_storageKey}_autoDetectLanguage') ?? true,
      translateTitles: prefs.getBool('${_storageKey}_translateTitles') ?? true,
      translateContent: prefs.getBool('${_storageKey}_translateContent') ?? true,
      translateSummaries: prefs.getBool('${_storageKey}_translateSummaries') ?? true,
      showOriginalText: prefs.getBool('${_storageKey}_showOriginalText') ?? false,
      cacheTranslations: prefs.getBool('${_storageKey}_cacheTranslations') ?? true,
      activeProviderId: prefs.getString('${_storageKey}_activeProviderId'),
    );
  }
  
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (state.preferredLanguage != null) {
      await prefs.setString('${_storageKey}_preferredLanguage', state.preferredLanguage!);
    } else {
      await prefs.remove('${_storageKey}_preferredLanguage');
    }
    
    await prefs.setBool('${_storageKey}_autoDetectLanguage', state.autoDetectLanguage);
    await prefs.setBool('${_storageKey}_translateTitles', state.translateTitles);
    await prefs.setBool('${_storageKey}_translateContent', state.translateContent);
    await prefs.setBool('${_storageKey}_translateSummaries', state.translateSummaries);
    await prefs.setBool('${_storageKey}_showOriginalText', state.showOriginalText);
    await prefs.setBool('${_storageKey}_cacheTranslations', state.cacheTranslations);
    
    if (state.activeProviderId != null) {
      await prefs.setString('${_storageKey}_activeProviderId', state.activeProviderId!);
    }
  }
  
  void setPreferredLanguage(String? language) {
    state = state.copyWith(preferredLanguage: language);
    _saveSettings();
  }
  
  void toggleAutoDetectLanguage() {
    state = state.copyWith(autoDetectLanguage: !state.autoDetectLanguage);
    _saveSettings();
  }
  
  void toggleTranslateTitles() {
    state = state.copyWith(translateTitles: !state.translateTitles);
    _saveSettings();
  }
  
  void toggleTranslateContent() {
    state = state.copyWith(translateContent: !state.translateContent);
    _saveSettings();
  }
  
  void toggleTranslateSummaries() {
    state = state.copyWith(translateSummaries: !state.translateSummaries);
    _saveSettings();
  }
  
  void toggleShowOriginalText() {
    state = state.copyWith(showOriginalText: !state.showOriginalText);
    _saveSettings();
  }
  
  void toggleCacheTranslations() {
    state = state.copyWith(cacheTranslations: !state.cacheTranslations);
    _saveSettings();
  }
  
  void setActiveProviderId(String? providerId) {
    state = state.copyWith(activeProviderId: providerId);
    _saveSettings();
  }
}

// Translated article provider
final translatedArticleProvider = FutureProvider.family<TranslatedArticle?, String>((ref, articleId) async {
  final settings = ref.watch(translationSettingsProvider);
  
  if (settings.preferredLanguage == null) {
    return null;
  }
  
  // Check cache first
  if (settings.cacheTranslations) {
    final cache = ref.read(translationCacheProvider);
    final cached = cache.get(articleId, settings.preferredLanguage!);
    if (cached != null) {
      return cached;
    }
  }
  
  // Get article (this would come from your article provider)
  // For now, returning null as placeholder
  return null;
});

// Translation manager
final translationManagerProvider = Provider<TranslationManager>((ref) {
  return TranslationManager(ref);
});

class TranslationManager {
  final Ref ref;
  
  TranslationManager(this.ref);
  
  Future<void> setupGoogleTranslate(String apiKey) async {
    final service = ref.read(translationServiceProvider);
    final provider = GoogleTranslateProvider(apiKey: apiKey);
    
    service.addProvider('google', provider);
    service.setActiveProvider('google');
    
    ref.read(translationSettingsProvider.notifier).setActiveProviderId('google');
  }
  
  Future<void> setupLibreTranslate(String baseUrl, {String? apiKey}) async {
    final service = ref.read(translationServiceProvider);
    final provider = LibreTranslateProvider(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    
    service.addProvider('libre', provider);
    service.setActiveProvider('libre');
    
    ref.read(translationSettingsProvider.notifier).setActiveProviderId('libre');
  }
  
  Future<TranslatedArticle?> translateArticle(Article article) async {
    final settings = ref.read(translationSettingsProvider);
    final service = ref.read(translationServiceProvider);
    final cache = ref.read(translationCacheProvider);
    
    if (settings.preferredLanguage == null) {
      return null;
    }
    
    // Check cache
    if (settings.cacheTranslations) {
      final cached = cache.get(article.id, settings.preferredLanguage!);
      if (cached != null) {
        return cached;
      }
    }
    
    try {
      final translated = await service.translateArticle(
        article,
        settings.preferredLanguage!,
        translateTitle: settings.translateTitles,
        translateContent: settings.translateContent,
        translateSummary: settings.translateSummaries,
      );
      
      // Cache translation
      if (settings.cacheTranslations) {
        cache.add(article.id, settings.preferredLanguage!, translated);
      }
      
      return translated;
    } catch (e) {
      throw Exception('Translation failed: $e');
    }
  }
  
  Future<List<SupportedLanguage>> getSupportedLanguages() async {
    final service = ref.read(translationServiceProvider);
    return await service.getSupportedLanguages();
  }
  
  Future<String> detectLanguage(String text) async {
    final service = ref.read(translationServiceProvider);
    return await service.detectLanguage(text);
  }
  
  void clearCache() {
    final cache = ref.read(translationCacheProvider);
    cache.clear();
  }
}

// Language detection provider
final languageDetectionProvider = FutureProvider.family<String, String>((ref, text) async {
  final manager = ref.read(translationManagerProvider);
  
  try {
    return await manager.detectLanguage(text);
  } catch (e) {
    return 'unknown';
  }
});

// Supported languages provider
final supportedLanguagesProvider = FutureProvider<List<SupportedLanguage>>((ref) async {
  final manager = ref.read(translationManagerProvider);
  
  try {
    return await manager.getSupportedLanguages();
  } catch (e) {
    // Return common languages as fallback
    return [
      SupportedLanguage(code: 'en', name: 'English', nativeName: 'English'),
      SupportedLanguage(code: 'es', name: 'Spanish', nativeName: 'Español'),
      SupportedLanguage(code: 'fr', name: 'French', nativeName: 'Français'),
      SupportedLanguage(code: 'de', name: 'German', nativeName: 'Deutsch'),
      SupportedLanguage(code: 'it', name: 'Italian', nativeName: 'Italiano'),
      SupportedLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português'),
      SupportedLanguage(code: 'ru', name: 'Russian', nativeName: 'Русский'),
      SupportedLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語'),
      SupportedLanguage(code: 'ko', name: 'Korean', nativeName: '한국어'),
      SupportedLanguage(code: 'zh', name: 'Chinese', nativeName: '中文'),
      SupportedLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية', isRTL: true),
      SupportedLanguage(code: 'he', name: 'Hebrew', nativeName: 'עברית', isRTL: true),
    ];
  }
});