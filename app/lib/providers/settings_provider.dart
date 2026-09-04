import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Settings provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref);
});

class AppSettings {
  final bool autoUpdateFeeds;
  final int updateInterval; // minutes
  final bool enableSync;
  final bool showReadArticles;
  final int articlesPerFeed;
  final String serverUrl;

  AppSettings({
    this.autoUpdateFeeds = true,
    this.updateInterval = 30,
    this.enableSync = true,
    this.showReadArticles = true,
    this.articlesPerFeed = 50,
    this.serverUrl = '',
  });

  AppSettings copyWith({
    bool? autoUpdateFeeds,
    int? updateInterval,
    bool? enableSync,
    bool? showReadArticles,
    int? articlesPerFeed,
    String? serverUrl,
  }) {
    return AppSettings(
      autoUpdateFeeds: autoUpdateFeeds ?? this.autoUpdateFeeds,
      updateInterval: updateInterval ?? this.updateInterval,
      enableSync: enableSync ?? this.enableSync,
      showReadArticles: showReadArticles ?? this.showReadArticles,
      articlesPerFeed: articlesPerFeed ?? this.articlesPerFeed,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  final Ref ref;

  SettingsNotifier(this.ref) : super(AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('useDarkTheme');
    state = AppSettings(
      autoUpdateFeeds: prefs.getBool('autoUpdateFeeds') ?? true,
      updateInterval: prefs.getInt('updateInterval') ?? 30,
      enableSync: prefs.getBool('enableSync') ?? true,
      showReadArticles: prefs.getBool('showReadArticles') ?? true,
      articlesPerFeed: prefs.getInt('articlesPerFeed') ?? 50,
      serverUrl: ApiConfig.baseUrl,
    );
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoUpdateFeeds', state.autoUpdateFeeds);
    await prefs.setInt('updateInterval', state.updateInterval);
    await prefs.setBool('enableSync', state.enableSync);
    await prefs.setBool('showReadArticles', state.showReadArticles);
    await prefs.setInt('articlesPerFeed', state.articlesPerFeed);
  }

  void setAutoUpdateFeeds(bool value) {
    state = state.copyWith(autoUpdateFeeds: value);
    _saveSettings();
  }

  void setUpdateInterval(int minutes) {
    state = state.copyWith(updateInterval: minutes);
    _saveSettings();
  }

  void setEnableSync(bool value) {
    state = state.copyWith(enableSync: value);
    _saveSettings();
  }

  void setShowReadArticles(bool value) {
    state = state.copyWith(showReadArticles: value);
    _saveSettings();
  }

  void setArticlesPerFeed(int count) {
    state = state.copyWith(articlesPerFeed: count);
    _saveSettings();
  }

  void setServerUrl(String url) {
    state = state.copyWith(serverUrl: url);
    ApiConfig.setServerUrl(url);
    ref.read(apiServiceProvider).updateBaseUrl(ApiConfig.baseUrl);
  }

  Future<void> resetToDefaults() async {
    state = AppSettings();
    await _saveSettings();
    await ApiConfig.setServerUrl('');
    ref.read(apiServiceProvider).updateBaseUrl('');
  }
}
