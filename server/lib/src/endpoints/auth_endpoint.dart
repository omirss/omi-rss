import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import 'package:bcrypt/bcrypt.dart';
import '../config/server_config.dart';
import '../middleware/auth_middleware.dart';
import '../utils/jwt_generator.dart';
import '../generated/protocol.dart';

class AuthEndpoint extends Endpoint {
  final ServerConfig config = ServerConfig.load();
  late final JWTGenerator jwtGenerator;
  
  AuthEndpoint() {
    jwtGenerator = JWTGenerator(config.auth);
  }
  
  /// Register a new user
  Future<AuthResponse> register(
    Session session,
    String email,
    String password,
    String? username,
  ) async {
    try {
      // Validate email
      if (!_isValidEmail(email)) {
        throw Exception('Invalid email format');
      }
      
      // Validate password
      if (password.length < 8) {
        throw Exception('Password must be at least 8 characters long');
      }
      
      // Check if user already exists
      final existingUser = await UserInfo.db.findByEmail(session, email);
      if (existingUser != null) {
        throw Exception('Email already registered');
      }
      
      // Check username availability
      if (username != null) {
        final existingUsername = await UserInfo.db.findByUsername(session, username);
        if (existingUsername != null) {
          throw Exception('Username already taken');
        }
      }
      
      // Hash password
      final hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());
      
      // Create user
      final user = UserInfo(
        userIdentifier: email,
        email: email,
        userName: username ?? email.split('@').first,
        fullName: null,
        created: DateTime.now(),
        imageUrl: null,
        scopeNames: ['user'],
        blocked: false,
      );
      
      await user.insert(session);
      
      // Store password hash
      await _storePasswordHash(session, user.id!, hashedPassword);
      
      // Generate tokens
      final accessToken = jwtGenerator.generateAccessToken(
        userId: user.id!,
        email: user.email!,
        scopes: ['user'],
      );
      
      final refreshToken = jwtGenerator.generateRefreshToken(
        userId: user.id!,
      );
      
      // Send welcome email if configured
      if (config.auth.sendValidationEmail) {
        await _sendWelcomeEmail(session, user);
      }
      
      return AuthResponse(
        token: accessToken,
        refreshToken: refreshToken,
        user: User(
          id: user.id!,
          email: user.email!,
          username: user.userName,
          fullName: user.fullName,
          avatarUrl: user.imageUrl,
          createdAt: user.created,
          preferences: {},
          statistics: UserStatistics(
            totalSubscriptions: 0,
            totalFolders: 0,
            totalSavedArticles: 0,
            totalReadArticles: 0,
            readingStreak: 0,
            memberSince: user.created,
          ),
        ),
      );
    } catch (e) {
      session.log('Registration error: $e', level: LogLevel.error);
      throw Exception('Registration failed: ${e.toString()}');
    }
  }
  
  /// Login user
  Future<AuthResponse> login(
    Session session,
    String email,
    String password,
  ) async {
    try {
      // Find user by email
      final user = await UserInfo.db.findByEmail(session, email);
      if (user == null) {
        throw Exception('Invalid credentials');
      }
      
      // Check if user is blocked
      if (user.blocked) {
        throw Exception('Account is blocked');
      }
      
      // Verify password
      final passwordHash = await _getPasswordHash(session, user.id!);
      if (passwordHash == null || !BCrypt.checkpw(password, passwordHash)) {
        throw Exception('Invalid credentials');
      }
      
      // Get user statistics
      final stats = await _getUserStatistics(session, user.id!);
      
      // Get user preferences
      final prefs = await _getUserPreferences(session, user.id!);
      
      // Generate tokens
      final accessToken = jwtGenerator.generateAccessToken(
        userId: user.id!,
        email: user.email!,
        scopes: user.scopeNames ?? ['user'],
      );
      
      final refreshToken = jwtGenerator.generateRefreshToken(
        userId: user.id!,
      );
      
      // Update last login
      await _updateLastLogin(session, user.id!);
      
      return AuthResponse(
        token: accessToken,
        refreshToken: refreshToken,
        user: User(
          id: user.id!,
          email: user.email!,
          username: user.userName ?? user.email!.split('@').first,
          fullName: user.fullName,
          avatarUrl: user.imageUrl,
          createdAt: user.created,
          preferences: prefs.toJson(),
          statistics: stats,
        ),
      );
    } catch (e) {
      session.log('Login error: $e', level: LogLevel.error);
      throw Exception('Login failed: ${e.toString()}');
    }
  }
  
  /// Refresh token
  Future<AuthResponse> refreshToken(
    Session session,
    String refreshToken,
  ) async {
    try {
      // Verify refresh token
      final payload = jwtGenerator.verifyToken(refreshToken);
      if (payload == null || payload['type'] != 'refresh') {
        throw Exception('Invalid refresh token');
      }
      
      final userId = payload['userId'] as int;
      
      // Get user
      final user = await UserInfo.db.findById(session, userId);
      if (user == null || user.blocked) {
        throw Exception('Invalid user');
      }
      
      // Get user statistics
      final stats = await _getUserStatistics(session, user.id!);
      
      // Get user preferences
      final prefs = await _getUserPreferences(session, user.id!);
      
      // Generate new tokens
      final accessToken = jwtGenerator.generateAccessToken(
        userId: user.id!,
        email: user.email!,
        scopes: user.scopeNames ?? ['user'],
      );
      
      final newRefreshToken = jwtGenerator.generateRefreshToken(
        userId: user.id!,
      );
      
      return AuthResponse(
        token: accessToken,
        refreshToken: newRefreshToken,
        user: User(
          id: user.id!,
          email: user.email!,
          username: user.userName ?? user.email!.split('@').first,
          fullName: user.fullName,
          avatarUrl: user.imageUrl,
          createdAt: user.created,
          preferences: prefs.toJson(),
          statistics: stats,
        ),
      );
    } catch (e) {
      session.log('Token refresh error: $e', level: LogLevel.error);
      throw Exception('Token refresh failed: ${e.toString()}');
    }
  }
  
  /// Logout user
  Future<void> logout(Session session) async {
    session.requireAuth();
    
    // Invalidate any server-side sessions if needed
    // For JWT, this is mainly for logging purposes
    session.log('User ${session.authenticatedUserId} logged out');
  }
  
  /// Request password reset
  Future<void> forgotPassword(
    Session session,
    String email,
  ) async {
    try {
      // Find user by email
      final user = await UserInfo.db.findByEmail(session, email);
      if (user == null) {
        // Don't reveal if email exists
        return;
      }
      
      // Generate reset token
      final resetToken = _generateResetToken();
      final tokenHash = BCrypt.hashpw(resetToken, BCrypt.gensalt());
      
      // Store reset token
      await _storeResetToken(session, user.id!, tokenHash);
      
      // Send reset email
      await _sendPasswordResetEmail(session, user, resetToken);
    } catch (e) {
      session.log('Forgot password error: $e', level: LogLevel.error);
      // Don't reveal errors to prevent email enumeration
    }
  }
  
  /// Reset password
  Future<void> resetPassword(
    Session session,
    String token,
    String newPassword,
  ) async {
    try {
      // Validate new password
      if (newPassword.length < 8) {
        throw Exception('Password must be at least 8 characters long');
      }
      
      // Find user with valid reset token
      final userId = await _validateResetToken(session, token);
      if (userId == null) {
        throw Exception('Invalid or expired reset token');
      }
      
      // Hash new password
      final hashedPassword = BCrypt.hashpw(newPassword, BCrypt.gensalt());
      
      // Update password
      await _updatePassword(session, userId, hashedPassword);
      
      // Clear reset token
      await _clearResetToken(session, userId);
      
      // Send confirmation email
      final user = await UserInfo.db.findById(session, userId);
      if (user != null) {
        await _sendPasswordChangedEmail(session, user);
      }
    } catch (e) {
      session.log('Reset password error: $e', level: LogLevel.error);
      throw Exception('Password reset failed: ${e.toString()}');
    }
  }
  
  /// Validate email format
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
  
  /// Generate reset token
  String _generateResetToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(32, (index) => 
      chars[DateTime.now().microsecondsSinceEpoch % chars.length]
    ).join();
  }
  
  // Database helper methods
  Future<void> _storePasswordHash(Session session, int userId, String hash) async {
    // Store in user_passwords table
    await session.db.execute(
      'INSERT INTO user_passwords (user_id, password_hash) VALUES (@userId, @hash)',
      parameters: {
        'userId': userId,
        'hash': hash,
      },
    );
  }
  
  Future<String?> _getPasswordHash(Session session, int userId) async {
    final result = await session.db.query(
      'SELECT password_hash FROM user_passwords WHERE user_id = @userId',
      parameters: {'userId': userId},
    );
    
    if (result.isNotEmpty) {
      return result.first['password_hash'] as String?;
    }
    return null;
  }
  
  Future<void> _updatePassword(Session session, int userId, String hash) async {
    await session.db.execute(
      'UPDATE user_passwords SET password_hash = @hash WHERE user_id = @userId',
      parameters: {
        'userId': userId,
        'hash': hash,
      },
    );
  }
  
  Future<void> _storeResetToken(Session session, int userId, String tokenHash) async {
    final expiresAt = DateTime.now().add(Duration(hours: 1));
    
    await session.db.execute(
      '''INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) 
         VALUES (@userId, @tokenHash, @expiresAt)
         ON CONFLICT (user_id) DO UPDATE SET 
         token_hash = @tokenHash, expires_at = @expiresAt''',
      parameters: {
        'userId': userId,
        'tokenHash': tokenHash,
        'expiresAt': expiresAt,
      },
    );
  }
  
  Future<int?> _validateResetToken(Session session, String token) async {
    final result = await session.db.query(
      '''SELECT user_id, token_hash FROM password_reset_tokens 
         WHERE expires_at > NOW()''',
    );
    
    for (final row in result) {
      final tokenHash = row['token_hash'] as String;
      if (BCrypt.checkpw(token, tokenHash)) {
        return row['user_id'] as int;
      }
    }
    
    return null;
  }
  
  Future<void> _clearResetToken(Session session, int userId) async {
    await session.db.execute(
      'DELETE FROM password_reset_tokens WHERE user_id = @userId',
      parameters: {'userId': userId},
    );
  }
  
  Future<void> _updateLastLogin(Session session, int userId) async {
    await session.db.execute(
      'UPDATE serverpod_user_info SET last_login = NOW() WHERE id = @userId',
      parameters: {'userId': userId},
    );
  }
  
  Future<UserStatistics> _getUserStatistics(Session session, int userId) async {
    // Implementation from user_endpoint.dart
    return UserStatistics(
      totalSubscriptions: 0,
      totalFolders: 0,
      totalSavedArticles: 0,
      totalReadArticles: 0,
      readingStreak: 0,
      memberSince: DateTime.now(),
    );
  }
  
  Future<UserPreferences> _getUserPreferences(Session session, int userId) async {
    // Implementation from user_endpoint.dart
    return UserPreferences();
  }
  
  // Email methods
  Future<void> _sendWelcomeEmail(Session session, UserInfo user) async {
    // TODO: Implement email sending
    session.log('Would send welcome email to ${user.email}');
  }
  
  Future<void> _sendPasswordResetEmail(Session session, UserInfo user, String token) async {
    // TODO: Implement email sending
    session.log('Would send password reset email to ${user.email}');
  }
  
  Future<void> _sendPasswordChangedEmail(Session session, UserInfo user) async {
    // TODO: Implement email sending
    session.log('Would send password changed email to ${user.email}');
  }
}

/// Auth response model
class AuthResponse {
  final String token;
  final String refreshToken;
  final User user;
  
  AuthResponse({
    required this.token,
    required this.refreshToken,
    required this.user,
  });
  
  Map<String, dynamic> toJson() => {
    'token': token,
    'refreshToken': refreshToken,
    'user': user.toJson(),
  };
}

/// User model
class User {
  final int id;
  final String email;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final DateTime createdAt;
  final Map<String, dynamic>? preferences;
  final UserStatistics? statistics;
  
  User({
    required this.id,
    required this.email,
    this.username,
    this.fullName,
    this.avatarUrl,
    required this.createdAt,
    this.preferences,
    this.statistics,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'userName': username,
      'fullName': fullName,
      'avatarUrl': avatarUrl,
      'createdAt': createdAt.toIso8601String(),
      'preferences': preferences,
      'statistics': statistics?.toJson(),
    };
  }
}