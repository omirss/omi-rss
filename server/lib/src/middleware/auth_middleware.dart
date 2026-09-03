import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../config/server_config.dart';

class AuthMiddleware extends Middleware {
  final AuthConfig config;
  final List<String> publicEndpoints = [
    '/auth/login',
    '/auth/register',
    '/auth/refresh',
    '/auth/forgot-password',
    '/health',
  ];

  AuthMiddleware({AuthConfig? config}) 
    : config = config ?? ServerConfig.load().auth;

  @override
  Future<bool> handle(Session session, HttpRequest request) async {
    // Skip auth for public endpoints
    final path = request.uri.path;
    if (publicEndpoints.any((endpoint) => path.startsWith(endpoint))) {
      return true;
    }

    // Check for authorization header
    final authHeader = request.headers.value('authorization');
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      await _sendUnauthorized(request, 'Missing authorization header');
      return false;
    }

    // Extract and verify token
    final token = authHeader.substring(7);
    try {
      final jwt = JWT.verify(token, SecretKey(config.jwtSecret));
      final payload = jwt.payload as Map<String, dynamic>;
      
      // Check token expiration
      final exp = payload['exp'] as int?;
      if (exp == null || DateTime.fromMillisecondsSinceEpoch(exp * 1000).isBefore(DateTime.now())) {
        await _sendUnauthorized(request, 'Token expired');
        return false;
      }

      // Set user info in session
      final userId = payload['userId'] as int?;
      final email = payload['email'] as String?;
      
      if (userId == null) {
        await _sendUnauthorized(request, 'Invalid token payload');
        return false;
      }

      // Store auth info in session
      session.auth = AuthenticationInfo(
        userId: userId,
        email: email,
        scopes: payload['scopes'] as List<String>? ?? [],
      );

      // Add user ID to request attributes for downstream use
      request.headers.add('X-User-Id', userId.toString());
      
      return true;
    } catch (e) {
      session.log('JWT verification failed: $e');
      await _sendUnauthorized(request, 'Invalid token');
      return false;
    }
  }

  Future<void> _sendUnauthorized(HttpRequest request, String message) async {
    request.response
      ..statusCode = 401
      ..headers.contentType = ContentType.json
      ..write('{"error": "$message"}');
    await request.response.close();
  }
}

class AuthenticationInfo {
  final int userId;
  final String? email;
  final List<String> scopes;

  AuthenticationInfo({
    required this.userId,
    this.email,
    required this.scopes,
  });

  bool hasScope(String scope) => scopes.contains(scope);
  
  bool hasAnyScope(List<String> requiredScopes) =>
      requiredScopes.any((scope) => scopes.contains(scope));
      
  bool hasAllScopes(List<String> requiredScopes) =>
      requiredScopes.every((scope) => scopes.contains(scope));
}

// Extension to add auth info to session
extension AuthSession on Session {
  static final _authKey = 'auth_info';
  
  AuthenticationInfo? get auth => 
      storage[_authKey] as AuthenticationInfo?;
      
  set auth(AuthenticationInfo? info) {
    if (info != null) {
      storage[_authKey] = info;
    } else {
      storage.remove(_authKey);
    }
  }
  
  int? get authenticatedUserId => auth?.userId;
  
  bool get isAuthenticated => auth != null;
  
  void requireAuth() {
    if (!isAuthenticated) {
      throw UnauthorizedException('Authentication required');
    }
  }
  
  void requireScope(String scope) {
    requireAuth();
    if (!auth!.hasScope(scope)) {
      throw ForbiddenException('Insufficient permissions');
    }
  }
  
  void requireAnyScope(List<String> scopes) {
    requireAuth();
    if (!auth!.hasAnyScope(scopes)) {
      throw ForbiddenException('Insufficient permissions');
    }
  }
  
  void requireAllScopes(List<String> scopes) {
    requireAuth();
    if (!auth!.hasAllScopes(scopes)) {
      throw ForbiddenException('Insufficient permissions');
    }
  }
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
  
  @override
  String toString() => 'UnauthorizedException: $message';
}

class ForbiddenException implements Exception {
  final String message;
  ForbiddenException(this.message);
  
  @override
  String toString() => 'ForbiddenException: $message';
}

// JWT Token Generator
class JWTGenerator {
  final AuthConfig config;
  
  JWTGenerator(this.config);
  
  String generateAccessToken({
    required int userId,
    required String email,
    List<String> scopes = const [],
  }) {
    final jwt = JWT({
      'userId': userId,
      'email': email,
      'scopes': scopes,
      'type': 'access',
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now().add(config.jwtExpiration).millisecondsSinceEpoch ~/ 1000,
    });
    
    return jwt.sign(SecretKey(config.jwtSecret));
  }
  
  String generateRefreshToken({
    required int userId,
  }) {
    final jwt = JWT({
      'userId': userId,
      'type': 'refresh',
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now().add(config.refreshTokenExpiration).millisecondsSinceEpoch ~/ 1000,
    });
    
    return jwt.sign(SecretKey(config.jwtSecret));
  }
  
  Map<String, dynamic>? verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(config.jwtSecret));
      return jwt.payload as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}