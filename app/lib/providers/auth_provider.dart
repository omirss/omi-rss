import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/user.dart';
import '../services/api_service.dart';
import '../ui/screens/auth/login_screen.dart';

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
    
    if (token != null && refreshToken != null) {
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
        // Token expired, try refresh
        try {
          final response = await _apiService.refreshToken(refreshToken);
          await _saveAuth(response);
        } catch (e) {
          // Refresh failed, clear auth
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
      final response = await _apiService.register(email, password, username ?? email.split('@')[0]);
      
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
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final response = await _apiService.login(email, password);
      
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
  
  Future<void> requestPasswordReset(String email) async {
    // TODO: Implement password reset when endpoint is available
    throw UnimplementedError('Password reset not yet implemented');
  }
  
  Future<void> _saveAuth(Map<String, dynamic> response) async {
    final token = response['accessToken'] as String;
    final refreshToken = response['refreshToken'] as String;
    final user = User.fromJson(response['user'] as Map<String, dynamic>);
    
    await _prefs.setString(_tokenKey, token);
    await _prefs.setString(_refreshTokenKey, refreshToken);
    
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


/// Auth guard widget
class AuthGuard extends ConsumerWidget {
  final Widget child;
  final Widget? unauthenticatedWidget;
  
  const AuthGuard({
    super.key,
    required this.child,
    this.unauthenticatedWidget,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    if (authState.isAuthenticated) {
      return child;
    }
    
    return unauthenticatedWidget ?? const LoginScreen();
  }
}