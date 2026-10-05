import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/config/api_config.dart';
import 'package:rss_glassmorphism_reader/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues(const {});
    await ApiConfig.setServerUrl('');
  });

  test('B13: invalid server URLs are reported instead of silently ignored',
      () async {
    SharedPreferences.setMockInitialValues(const {});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(settingsProvider.notifier);
    await pumpEventQueue(); // let _loadSettings settle

    final rejected = await notifier.setServerUrl('not a url');
    expect(rejected, isFalse,
        reason: 'callers must be able to distinguish rejection');
    expect(container.read(settingsProvider).serverUrl, '',
        reason: 'rejected URL must not become app state');

    final accepted = await notifier.setServerUrl('http://localhost:8080');
    expect(accepted, isTrue);
    expect(
        container.read(settingsProvider).serverUrl, 'http://localhost:8080');
  });

  test('C20: re-saving an equivalent URL preserves the session', () async {
    SharedPreferences.setMockInitialValues(
        {'access_token': 't', 'refresh_token': 'r'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await pumpEventQueue(); // let _loadSettings settle

    expect(await notifier.setServerUrl('http://localhost:8080'), isTrue);
    await pumpEventQueue(); // let auth init settle after the origin change

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', 't');
    await prefs.setString('refresh_token', 'r');

    // Same origin after normalization: must not rotate auth.
    expect(await notifier.setServerUrl('http://localhost:8080/api/'),
        isTrue);
    expect(prefs.getString('access_token'), 't',
        reason: 'an unchanged origin must not clear credentials');
    expect(prefs.getString('refresh_token'), 'r');

    expect(await notifier.setServerUrl('http://otherhost:9000'), isTrue);
    expect(prefs.getString('access_token'), isNull,
        reason: 'switching origin must still clear credentials');
    expect(prefs.getString('refresh_token'), isNull);
  });

  test('C14: corrupt retention/interval preferences are clamped', () async {
    SharedPreferences.setMockInitialValues(
        {'articlesPerFeed': -1, 'updateInterval': 99999});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await pumpEventQueue(); // let _loadSettings settle

    var settings = container.read(settingsProvider);
    expect(settings.articlesPerFeed, 1,
        reason: 'a corrupt cap must never become a wipe-all retention');
    expect(settings.updateInterval, 1440);

    notifier.setArticlesPerFeed(0);
    notifier.setUpdateInterval(1);
    await pumpEventQueue();
    settings = container.read(settingsProvider);
    expect(settings.articlesPerFeed, 1);
    expect(settings.updateInterval, 5);
  });
}
