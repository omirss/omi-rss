import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/settings_table.dart';

part 'settings_dao.g.dart';

/// Data Access Object for settings
@DriftAccessor(tables: [SettingsTable])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(AppDatabase db) : super(db);
  
  /// Get all settings
  Future<List<SettingEntry>> getAllSettings() => select(settingsTable).get();
  
  /// Get setting value
  Future<String?> getSetting(String key) async {
    final setting = await (select(settingsTable)..where((s) => s.key.equals(key))).getSingleOrNull();
    return setting?.value;
  }
  
  /// Get setting with default
  Future<String> getSettingWithDefault(String key, String defaultValue) async {
    final value = await getSetting(key);
    return value ?? defaultValue;
  }
  
  /// Set setting value
  Future<void> setSetting(String key, String value) {
    return into(settingsTable).insertOnConflictUpdate(SettingEntry(
      key: key,
      value: value,
      updatedAt: DateTime.now(),
    ));
  }
  
  /// Set multiple settings
  Future<void> setSettings(Map<String, String> settings) async {
    await batch((batch) {
      for (final entry in settings.entries) {
        batch.insert(
          settingsTable,
          SettingEntry(
            key: entry.key,
            value: entry.value,
            updatedAt: DateTime.now(),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }
  
  /// Delete setting
  Future<void> deleteSetting(String key) {
    return (delete(settingsTable)..where((s) => s.key.equals(key))).go();
  }
  
  /// Get typed settings
  Future<AppSettings> getAppSettings() async {
    final settings = await getAllSettings();
    final settingsMap = {for (var s in settings) s.key: s.value};
    
    return AppSettings(
      theme: settingsMap['theme'] ?? 'default',
      updateFrequency: int.tryParse(settingsMap['updateFrequency'] ?? '') ?? 3600,
      articlesPerPage: int.tryParse(settingsMap['articlesPerPage'] ?? '') ?? 20,
      enableNotifications: settingsMap['enableNotifications'] == 'true',
      enableAutoSync: settingsMap['enableAutoSync'] == 'true',
      enableBypass: settingsMap['enableBypass'] == 'true',
      enableAI: settingsMap['enableAI'] == 'true',
      enableMarketData: settingsMap['enableMarketData'] == 'true',
      syncToken: settingsMap['syncToken'],
      deviceId: settingsMap['deviceId'],
    );
  }
  
  /// Update app settings
  Future<void> updateAppSettings(AppSettings settings) {
    return setSettings({
      'theme': settings.theme,
      'updateFrequency': settings.updateFrequency.toString(),
      'articlesPerPage': settings.articlesPerPage.toString(),
      'enableNotifications': settings.enableNotifications.toString(),
      'enableAutoSync': settings.enableAutoSync.toString(),
      'enableBypass': settings.enableBypass.toString(),
      'enableAI': settings.enableAI.toString(),
      'enableMarketData': settings.enableMarketData.toString(),
      if (settings.syncToken != null) 'syncToken': settings.syncToken!,
      if (settings.deviceId != null) 'deviceId': settings.deviceId!,
    });
  }
}

/// Application settings
class AppSettings {
  final String theme;
  final int updateFrequency;
  final int articlesPerPage;
  final bool enableNotifications;
  final bool enableAutoSync;
  final bool enableBypass;
  final bool enableAI;
  final bool enableMarketData;
  final String? syncToken;
  final String? deviceId;
  
  AppSettings({
    required this.theme,
    required this.updateFrequency,
    required this.articlesPerPage,
    required this.enableNotifications,
    required this.enableAutoSync,
    required this.enableBypass,
    required this.enableAI,
    required this.enableMarketData,
    this.syncToken,
    this.deviceId,
  });
}