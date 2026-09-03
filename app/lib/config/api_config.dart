import 'package:shared_preferences/shared_preferences.dart';

/// API Configuration
class ApiConfig {
  static const String _serverUrlKey = 'serverUrl';
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: '',
  );

  static String? _savedServerUrl;

  /// Base URL of the server API. Empty when running in local-only mode.
  static String get baseUrl => _savedServerUrl ?? _defaultBaseUrl;

  /// True when a server is configured.
  static bool get hasServer => baseUrl.isNotEmpty;

  /// Load the persisted server URL. Must be called before the first
  /// network request (done in main).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _savedServerUrl = prefs.getString(_serverUrlKey);
  }

  /// Set and persist the server URL. An empty value returns the app to
  /// local-only mode.
  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalize(url);
    if (normalized.isEmpty) {
      _savedServerUrl = null;
      await prefs.remove(_serverUrlKey);
    } else {
      _savedServerUrl = normalized;
      await prefs.setString(_serverUrlKey, normalized);
    }
  }

  static String _normalize(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // WebSocket configuration
  static String get wsUrl {
    final url = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    return url.replaceFirst('/api', '/ws');
  }
}
