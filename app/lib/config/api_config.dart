import 'package:shared_preferences/shared_preferences.dart';

/// API Configuration
class ApiConfig {
  static const String _serverUrlKey = 'serverUrl';
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: '',
  );

  static String? _savedServerUrl;

  /// Base URL of the server (no trailing "/" or "/api" suffix).
  /// Empty when running in local-only mode.
  static String get baseUrl => _savedServerUrl ?? _defaultBaseUrl;

  /// Base URL for all API calls: the server root with a single "/api" prefix.
  static String get apiBaseUrl => baseUrl.isEmpty ? '' : '$baseUrl/api';

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
    final normalized = normalizeUrl(url);
    if (normalized.isEmpty) {
      _savedServerUrl = null;
      await prefs.remove(_serverUrlKey);
    } else {
      _savedServerUrl = normalized;
      await prefs.setString(_serverUrlKey, normalized);
    }
  }

  /// Normalize a user-entered server URL: trims whitespace and strips any
  /// trailing "/" and "/api" suffix so the "/api" prefix is applied exactly once.
  static String normalizeUrl(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    while (normalized.toLowerCase().endsWith('/api')) {
      normalized = normalized.substring(0, normalized.length - 4);
      while (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
    }
    return normalized;
  }

  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // WebSocket configuration
  static String get wsUrl {
    return baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
  }
}
