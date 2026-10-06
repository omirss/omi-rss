import 'dart:async';
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

  /// Monotonic session counter. Every auth entry point captures the
  /// current value and re-checks it after each await: a delayed
  /// completion (login, restore, logout, refresh) may only write state
  /// or preferences while it still owns the newest session. This is
  /// what stops an old network result from overwriting or clearing a
  /// newer login.
  int _session = 0;

  AuthNotifier(this.ref) : super(AuthState()) {
    _apiService = ref.read(apiServiceProvider);
    _initialize();
  }

  Future<SharedPreferences> get _prefs => _prefsFuture;

  bool _owns(int session) => mounted && _session == session;

  Future<void> _initialize() async {
    final session = _session;
    final prefs = await _prefs;
    if (!_owns(session)) return;

    // Check for stored auth
    final token = prefs.getString(_tokenKey);
    final refreshToken = prefs.getString(_refreshTokenKey);

    if (token != null) {
      // Try to restore session
      try {
        final user = await _apiService.getCurrentUser();
        if (!_owns(session)) return;
        state = state.copyWith(
          isAuthenticated: true,
          user: user,
          token: token,
          refreshToken: refreshToken,
        );
      } catch (e) {
        if (!_owns(session)) return;
        if (refreshToken != null) {
          // Token expired, try refresh
          try {
            final response = await _apiService.refreshToken(refreshToken);
            if (!_owns(session)) return;
            await _saveRefreshedAuth(response, session);
          } catch (e) {
            if (!_owns(session)) return;
            await _handleRestoreFailure(e, prefs, token, refreshToken, session);
          }
        } else {
          await _handleRestoreFailure(e, prefs, token, refreshToken, session);
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
    int session,
  ) async {
    if (!_owns(session)) return;
    if (error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      await _clearAuth(session);
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
    // Rotate up front: an in-flight refresh or restore from any
    // previous session must not observe or overwrite this one.
    final session = ++_session;
    _apiService.rotateAuthSession();
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiService.register(
        username: username ?? (email != null && email.contains('@') ? email.split('@')[0] : ''),
        email: email,
        password: password,
      );

      await _saveAuth(response, session);
    } catch (e) {
      if (!_owns(session)) rethrow;
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
    final session = ++_session;
    _apiService.rotateAuthSession();
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiService.login(emailOrUsername, password);

      await _saveAuth(response, session);
    } catch (e) {
      if (!_owns(session)) rethrow;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    // Clear the local session BEFORE awaiting the network: a slow or
    // hung server call must not delay rotation, and a concurrent new
    // login must never be cleared by this logout's completion.
    final session = ++_session;
    _apiService.rotateAuthSession();
    final prefs = await _prefs;
    final oldToken = prefs.getString(_tokenKey);
    final oldBaseUrl = _apiService.baseUrl;
    if (!_owns(session)) return;

    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
    if (!mounted) return;
    state = AuthState();

    // Best-effort server logout with the PREVIOUS session's token and
    // origin; failures are ignored by design.
    if (oldToken != null && oldBaseUrl.isNotEmpty) {
      unawaited(_apiService.logoutWithToken(oldToken, oldBaseUrl));
    }
  }

  /// Clear stored credentials locally without contacting the server. Used
  /// on server switches and rejected refreshes.
  Future<void> clearLocalSession() async {
    final session = ++_session;
    _apiService.rotateAuthSession();
    await _clearAuth(session);
  }

  /// Publish rotated tokens (from the API layer's refresh flight) to the
  /// in-memory state so header builders and the UI see the current
  /// access token without a restart. Preference writes were already
  /// done by the flight under its own ownership checks.
  void applyRotatedTokens({required String token, String? refreshToken}) {
    if (!mounted || !state.isAuthenticated) return;
    state = state.copyWith(
      token: token,
      refreshToken: refreshToken ?? state.refreshToken,
    );
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

  Future<void> _saveAuth(Map<String, dynamic> response, int session) async {
    final token = response['token'] as String?;
    final refreshToken = response['refreshToken'] as String?;
    final userJson = response['user'];

    if (token == null || token.isEmpty) {
      // A success response without a token means authentication did
      // not happen; surface it as an error instead of resolving the
      // login/register future normally.
      throw const ApiException('Authentication failed: no token returned');
    }

    final prefs = await _prefs;
    // A login that started before a newer login/logout/server switch
    // must not install its credentials over the newer session.
    if (!_owns(session)) return;

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

  /// Persist rotated credentials from a token-only refresh response.
  /// Refresh payloads carry no user; keep the current or cached user
  /// instead of storing an authenticated state with no user.
  Future<void> _saveRefreshedAuth(
      Map<String, dynamic> response, int session) async {
    final token = response['token'] as String?;
    final refreshToken = response['refreshToken'] as String?;

    if (token == null || token.isEmpty) {
      throw const ApiException('Authentication failed: no token returned');
    }

    final prefs = await _prefs;
    if (!_owns(session)) return;
    await prefs.setString(_tokenKey, token);
    if (refreshToken != null) {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }

    final user = state.user ??
        _loadCachedUser(prefs) ??
        await _apiService.getCurrentUser();
    if (!_owns(session)) return;
    state = state.copyWith(
      isAuthenticated: true,
      user: user,
      token: token,
      refreshToken: refreshToken,
      isLoading: false,
      error: null,
    );
  }

  Future<void> _clearAuth([int? session]) async {
    if (session != null && !_owns(session)) return;

    final prefs = await _prefs;
    if (session != null && !_owns(session)) return;
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);

    if (mounted) {
      state = AuthState();
    }
  }
  
  /// Get auth headers for API requests
  Map<String, String> getAuthHeaders() {
    if (state.token != null) {
      return {'Authorization': 'Bearer ${state.token}'};
    }
    return {};
  }
}
