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
  
  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    String? token,
    String? refreshToken,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
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
  late final SharedPreferences _prefs;
  late final ApiService _apiService;
  
  static const String _tokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userKey = 'auth_user';
  
  AuthNotifier(this.ref) : super(AuthState()) {
    _apiService = ref.read(apiServiceProvider);
    _initialize();
  }
  
  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Check for stored auth
    final token = _prefs.getString(_tokenKey);
    final refreshToken = _prefs.getString(_refreshTokenKey);
    
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
            // Refresh failed, clear auth
            await _clearAuth();
          }
        } else {
          await _clearAuth();
        }
      }
    }
  }
  
  Future<void> register({
    required String email,
    required String password,
    String? username,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final response = await _apiService.register(
        username: username ?? email.split('@')[0],
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

  /// Replace the cached user after a profile update and persist it.
  Future<void> updateUser(User user) async {
    state = state.copyWith(user: user);
    try {
      await _prefs.setString(_userKey, jsonEncode(user.toJson()));
    } catch (_) {
      // Caching is best-effort
    }
  }
  
  Future<void> requestPasswordReset(String email) async {
    // TODO: Implement password reset when endpoint is available
    throw UnimplementedError('Password reset not yet implemented');
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
    
    await _prefs.setString(_tokenKey, token);
    if (refreshToken != null) {
      await _prefs.setString(_refreshTokenKey, refreshToken);
    } else {
      await _prefs.remove(_refreshTokenKey);
    }
    
    final user = userJson is Map<String, dynamic>
        ? User.fromJson(userJson)
        : null;
    if (user != null) {
      await _prefs.setString(_userKey, jsonEncode(user.toJson()));
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
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove(_userKey);
    
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
