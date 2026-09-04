import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

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
  static String get baseUrl {
    final saved = _savedServerUrl;
    if (saved != null && saved.isNotEmpty) return saved;
    if (_defaultBaseUrl.isNotEmpty) return _defaultBaseUrl;
    if (kIsWeb) {
      final String? origin = html.window.location.origin;
      if (origin != null && origin.isNotEmpty && !origin.startsWith('about:')) {
        return origin;
      }
    }
    return '';
  }

  /// Base URL for all API calls: the server root with a single "/api" prefix.
  static String get apiBaseUrl => baseUrl.isEmpty ? '' : '$baseUrl/api';

  /// True when a server is configured.
  static bool get hasServer => baseUrl.isNotEmpty;

  /// Load the persisted server URL. Must be called before the first
  /// network request (done in main).
  ///
  /// SharedPreferences on the web JSON-encodes every value; a legacy or
  /// hand-edited localStorage entry that is not valid JSON makes
  /// SharedPreferences.getInstance() throw, which would abort bootstrap
  /// before runApp. Repair such entries and never let this fail.
  static Future<void> load() async {
    final prefs = await _prefsOrRepair();
    try {
      _savedServerUrl = prefs?.getString(_serverUrlKey);
    } catch (_) {
      _savedServerUrl = null;
    }
  }

  static Future<SharedPreferences?> _prefsOrRepair() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      await _repairWebPreferences();
      try {
        return await SharedPreferences.getInstance();
      } catch (_) {
        return null;
      }
    }
  }

  /// Re-encode raw (non-JSON) `flutter.*` localStorage values so the
  /// preferences store becomes readable again. Values are preserved.
  static Future<void> _repairWebPreferences() async {
    if (!kIsWeb) return;
    try {
      final storage = html.window.localStorage;
      final keys = storage.keys
          .where((k) => k.startsWith('flutter.'))
          .toList(growable: false);
      for (final key in keys) {
        final raw = storage[key];
        if (raw == null) continue;
        try {
          jsonDecode(raw);
        } catch (_) {
          storage[key] = jsonEncode(raw);
        }
      }
    } catch (_) {
      // Storage unavailable: continue with defaults
    }
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
}
