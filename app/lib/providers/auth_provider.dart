import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/user.dart';
import '../services/api_service.dart';

/// Auth state
class AuthState {
  final bool isAuthenticated;
  final User? user;
  final String? token;
  final String? refreshToken;
  final bool isLoading;
  final String? error;

  AuthState({
    this.isAuthenticated = false,
    this.user,
    this.token,
    this.refreshToken,
    this.isLoading = false,
    this.error,
  });

  static const Object _unset = Object();

  AuthState copyWith({
    bool? isAuthenticated,
    Object? user = _unset,
    Object? token = _unset,
    Object? refreshToken = _unset,
    bool? isLoading,
    Object? error = _unset,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: identical(user, _unset) ? this.user : user as User?,
      token: identical(token, _unset) ? this.token : token as String?,
      refreshToken:
          identical(refreshToken, _unset) ? this.refreshToken : refreshToken as String?,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

/// Auth state provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

/// Local-only mode: bypasses authentication and runs the app on the
/// local drift database alone. Persisted so a reload stays in local mode.
final localModeProvider =
    StateNotifierProvider<LocalModeNotifier, bool>((ref) {
  return LocalModeNotifier();
});

class LocalModeNotifier extends StateNotifier<bool> {
  static const String _key = 'localMode';

  LocalModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? false;
    } catch (_) {
      state = false;
    }
  }

  Future<void> enable() async {
    state = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {}
  }

  Future<void> disable() async {
    state = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}


/// Auth notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref;
  late final ApiService _apiService;
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  static const String _tokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userKey = 'auth_user';

  AuthNotifier(this.ref) : super(AuthState()) {
    _apiService = ref.read(apiServiceProvider);
    _initialize();
  }

  Future<SharedPreferences> get _prefs => _prefsFuture;

  Future<void> _initialize() async {
    final prefs = await _prefs;

    // Check for stored auth
    final token = prefs.getString(_tokenKey);
    final refreshToken = prefs.getString(_refreshTokenKey);

    if (token != null) {
      // Try to restore session
      try {
        final user = await _apiService.getCurrentUser();
        state = state.copyWith(
          isAuthenticated: true,
          user: user,
          token: token,
          refreshToken: refreshToken,
        );
      } catch (e) {
        if (refreshToken != null) {
          // Token expired, try refresh
          try {
            final response = await _apiService.refreshToken(refreshToken);
            await _saveAuth(response);
          } catch (e) {
            await _handleRestoreFailure(e, prefs, token, refreshToken);
          }
        } else {
          await _handleRestoreFailure(e, prefs, token, refreshToken);
        }
      }
    }
  }

  /// A restore failure only destroys stored credentials when the server
  /// actively rejected them (401/403). Network errors, timeouts, and 5xx
  /// responses keep the stored session for a later retry; the cached user
  /// (if any) is surfaced so the app can run offline.
  Future<void> _handleRestoreFailure(
    Object error,
    SharedPreferences prefs,
    String token,
    String? refreshToken,
  ) async {
    if (error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      await _clearAuth();
      return;
    }
    final cachedUser = _loadCachedUser(prefs);
    if (cachedUser != null) {
      state = state.copyWith(
        isAuthenticated: true,
        user: cachedUser,
        token: token,
        refreshToken: refreshToken,
      );
    }
  }

  User? _loadCachedUser(SharedPreferences prefs) {
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> register({
    String? email,
    required String password,
    String? username,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiService.register(
        username: username ?? (email != null && email.contains('@') ? email.split('@')[0] : ''),
        email: email,
        password: password,
      );

      await _saveAuth(response);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> login({
    required String emailOrUsername,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiService.login(emailOrUsername, password);

      await _saveAuth(response);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _apiService.logout();
    } catch (e) {
      // Ignore logout errors
    }
    await _clearAuth();
  }

  /// Clear stored credentials locally without contacting the server. Used
  /// on server switches and rejected refreshes.
  Future<void> clearLocalSession() async {
    await _clearAuth();
  }

  /// Replace the cached user after a profile update and persist it.
  Future<void> updateUser(User user) async {
    state = state.copyWith(user: user);
    try {
      final prefs = await _prefs;
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
    } catch (_) {
      // Caching is best-effort
    }
  }

  Future<void> requestPasswordReset(String email) async {
    await _apiService.requestPasswordReset(email);
  }

  Future<void> _saveAuth(Map<String, dynamic> response) async {
    final token = response['token'] as String?;
    final refreshToken = response['refreshToken'] as String?;
    final userJson = response['user'];

    if (token == null) {
      state = state.copyWith(
        isLoading: false,
        error: 'Authentication failed: no token returned',
      );
      return;
    }

    _apiService.rotateAuthSession();

    final prefs = await _prefs;
    await prefs.setString(_tokenKey, token);
    if (refreshToken != null) {
      await prefs.setString(_refreshTokenKey, refreshToken);
    } else {
      await prefs.remove(_refreshTokenKey);
    }

    final user = userJson is Map<String, dynamic>
        ? User.fromJson(userJson)
        : null;
    if (user != null) {
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
    }

    state = state.copyWith(
      isAuthenticated: true,
      user: user,
      token: token,
      refreshToken: refreshToken,
      isLoading: false,
      error: null,
    );
  }

  Future<void> _clearAuth() async {
    _apiService.rotateAuthSession();

    final prefs = await _prefs;
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);

    state = AuthState();
  }
  
  /// Get auth headers for API requests
  Map<String, String> getAuthHeaders() {
    if (state.token != null) {
      return {'Authorization': 'Bearer ${state.token}'};
    }
    return {};
  }
}
