import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues(const {});
    await ApiConfig.setServerUrl('');
  });

  test('B14: stored invalid server URL is discarded on load', () async {
    SharedPreferences.setMockInitialValues({'serverUrl': 'not a url'});
    await ApiConfig.load();

    expect(ApiConfig.hasServer, isFalse);
    expect(ApiConfig.baseUrl, '');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('serverUrl'), isNull,
        reason: 'the invalid stored value must be removed');
  });

  test('B14: stored URL with embedded credentials is discarded on load',
      () async {
    SharedPreferences.setMockInitialValues(
        {'serverUrl': 'http://user:pass@example.com'});
    await ApiConfig.load();

    expect(ApiConfig.hasServer, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('serverUrl'), isNull);
  });

  test('B14: valid stored URL is normalized on load', () async {
    SharedPreferences.setMockInitialValues({'serverUrl': 'https://a.example/'});
    await ApiConfig.load();

    expect(ApiConfig.baseUrl, 'https://a.example');
  });

  test('B14: nothing stored keeps local-only mode', () async {
    SharedPreferences.setMockInitialValues(const {});
    await ApiConfig.load();

    expect(ApiConfig.baseUrl, '');
    expect(ApiConfig.hasServer, isFalse);
  });
}
