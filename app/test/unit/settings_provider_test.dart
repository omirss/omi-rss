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
}
