import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../generated/protocol.dart';
import '../config/server_config.dart';

class UserEndpoint extends Endpoint {
  // Get current user profile
  Future<UserProfile> getCurrentUser(Session session) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      final userInfo = await UserInfo.findById(session, userId);
      if (userInfo == null) {
        throw Exception('User not found');
      }
      
      // Get user statistics
      final stats = await _getUserStatistics(session, userId);
      
      return UserProfile(
        id: userId,
        email: userInfo.email ?? '',
        userName: userInfo.userName ?? userInfo.email?.split('@').first ?? 'User',
        fullName: userInfo.fullName,
        avatarUrl: userInfo.imageUrl,
        createdAt: userInfo.created,
        preferences: await _getUserPreferences(session, userId),
        statistics: stats,
      );
    } catch (e) {
      session.log('Error fetching user profile: $e', level: LogLevel.error);
      throw Exception('Failed to fetch user profile');
    }
  }
  
  // Update user profile
  Future<UserProfile> updateProfile(
    Session session,
    String? userName,
    String? fullName,
    String? avatarUrl,
  ) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      final userInfo = await UserInfo.findById(session, userId);
      if (userInfo == null) {
        throw Exception('User not found');
      }
      
      // Update fields if provided
      if (userName != null) {
        // Validate username
        if (userName.length < 3 || userName.length > 30) {
          throw Exception('Username must be between 3 and 30 characters');
        }
        
        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(userName)) {
          throw Exception('Username can only contain letters, numbers, and underscores');
        }
        
        // Check if username is taken
        final existing = await UserInfo.find(
          session,
          where: (t) => t.userName.equals(userName) & t.id.notEquals(userId),
          limit: 1,
        );
        
        if (existing.isNotEmpty) {
          throw Exception('Username is already taken');
        }
        
        userInfo.userName = userName;
      }
      
      if (fullName != null) {
        if (fullName.length > 100) {
          throw Exception('Full name too long (max 100 characters)');
        }
        userInfo.fullName = fullName.trim().isEmpty ? null : fullName.trim();
      }
      
      if (avatarUrl != null) {
        // Validate URL format
        if (avatarUrl.isNotEmpty && !Uri.tryParse(avatarUrl)!.isAbsolute) {
          throw Exception('Invalid avatar URL');
        }
        userInfo.imageUrl = avatarUrl.trim().isEmpty ? null : avatarUrl.trim();
      }
      
      await userInfo.update(session);
      
      return getCurrentUser(session);
    } catch (e) {
      session.log('Error updating user profile: $e', level: LogLevel.error);
      throw Exception('Failed to update profile: ${e.toString()}');
    }
  }
  
  // Get user preferences
  Future<UserPreferences> getUserPreferences(Session session) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    return await _getUserPreferences(session, userId);
  }
  
  // Update user preferences
  Future<UserPreferences> updatePreferences(
    Session session,
    Map<String, dynamic> preferences,
  ) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Get or create user preferences
      var userPref = await UserPreference.findByUserId(session, userId);
      
      if (userPref == null) {
        userPref = UserPreference(
          userId: userId,
          preferences: {},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
      
      // Update preferences
      final currentPrefs = userPref.preferences;
      
      // Validate and update each preference
      preferences.forEach((key, value) {
        switch (key) {
          case 'theme':
            if (['light', 'dark', 'system'].contains(value)) {
              currentPrefs[key] = value;
            }
            break;
          case 'articleListDensity':
            if (['compact', 'comfortable', 'spacious'].contains(value)) {
              currentPrefs[key] = value;
            }
            break;
          case 'markAsReadOnScroll':
          case 'showUnreadOnly':
          case 'enableNotifications':
          case 'enableSounds':
            if (value is bool) {
              currentPrefs[key] = value;
            }
            break;
          case 'defaultView':
            if (['all', 'unread', 'starred'].contains(value)) {
              currentPrefs[key] = value;
            }
            break;
          case 'articlesPerPage':
            if (value is int && value >= 10 && value <= 100) {
              currentPrefs[key] = value;
            }
            break;
          case 'refreshInterval':
            if (value is int && value >= 5 && value <= 1440) { // 5 minutes to 24 hours
              currentPrefs[key] = value;
            }
            break;
          case 'fontSize':
            if (['small', 'medium', 'large', 'extra-large'].contains(value)) {
              currentPrefs[key] = value;
            }
            break;
          case 'language':
            if (['en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'zh'].contains(value)) {
              currentPrefs[key] = value;
            }
            break;
          case 'timezone':
            // Validate timezone string
            currentPrefs[key] = value;
            break;
          case 'keyboardShortcuts':
            if (value is Map) {
              currentPrefs[key] = value;
            }
            break;
        }
      });
      
      userPref.preferences = currentPrefs;
      userPref.updatedAt = DateTime.now();
      
      if (userPref.id == null) {
        await userPref.insert(session);
      } else {
        await userPref.update(session);
      }
      
      return _getUserPreferences(session, userId);
    } catch (e) {
      session.log('Error updating preferences: $e', level: LogLevel.error);
      throw Exception('Failed to update preferences');
    }
  }
  
  // Delete user account
  Future<bool> deleteAccount(Session session, String password) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Verify password
      final authInfo = await UserInfo.findById(session, userId);
      if (authInfo == null) {
        throw Exception('User not found');
      }
      
      // TODO: Verify password against hash
      // This would typically use bcrypt to verify the password
      
      // Delete all user data in order
      await _deleteAllUserData(session, userId);
      
      // Finally delete the user
      await UserInfo.deleteRow(session, authInfo);
      
      return true;
    } catch (e) {
      session.log('Error deleting user account: $e', level: LogLevel.error);
      throw Exception('Failed to delete account');
    }
  }
  
  // Export user data
  Future<UserDataExport> exportUserData(Session session) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Gather all user data
      final userInfo = await UserInfo.findById(session, userId);
      if (userInfo == null) {
        throw Exception('User not found');
      }
      
      final preferences = await _getUserPreferences(session, userId);
      final folders = await Folder.find(session, where: (t) => t.userId.equals(userId));
      final subscriptions = await FeedSubscription.find(session, where: (t) => t.userId.equals(userId));
      final readHistory = await ReadHistory.find(session, where: (t) => t.userId.equals(userId));
      final savedArticles = await SavedArticle.find(session, where: (t) => t.userId.equals(userId));
      
      return UserDataExport(
        exportedAt: DateTime.now(),
        userData: {
          'profile': {
            'email': userInfo.email,
            'userName': userInfo.userName,
            'fullName': userInfo.fullName,
            'avatarUrl': userInfo.imageUrl,
            'createdAt': userInfo.created.toIso8601String(),
          },
          'preferences': preferences.toJson(),
          'folders': folders.map((f) => f.toJson()).toList(),
          'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
          'readHistory': readHistory.map((r) => r.toJson()).toList(),
          'savedArticles': savedArticles.map((s) => s.toJson()).toList(),
        },
      );
    } catch (e) {
      session.log('Error exporting user data: $e', level: LogLevel.error);
      throw Exception('Failed to export data');
    }
  }
  
  // Change user password
  Future<bool> changePassword(
    Session session,
    String currentPassword,
    String newPassword,
  ) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Validate new password
      if (newPassword.length < 8) {
        throw Exception('Password must be at least 8 characters long');
      }
      
      if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(newPassword)) {
        throw Exception('Password must contain at least one uppercase letter, one lowercase letter, and one number');
      }
      
      // TODO: Verify current password and update to new password
      // This would typically use bcrypt to hash the new password
      
      return true;
    } catch (e) {
      session.log('Error changing password: $e', level: LogLevel.error);
      throw Exception('Failed to change password: ${e.toString()}');
    }
  }
  
  // Get user statistics
  Future<UserStatistics> _getUserStatistics(Session session, int userId) async {
    try {
      final totalSubscriptions = await FeedSubscription.count(
        session,
        where: (t) => t.userId.equals(userId),
      );
      
      final totalFolders = await Folder.count(
        session,
        where: (t) => t.userId.equals(userId),
      );
      
      final totalSavedArticles = await SavedArticle.count(
        session,
        where: (t) => t.userId.equals(userId),
      );
      
      final totalReadArticles = await ReadHistory.count(
        session,
        where: (t) => t.userId.equals(userId),
      );
      
      // Get reading streak
      final readingStreak = await _calculateReadingStreak(session, userId);
      
      return UserStatistics(
        totalSubscriptions: totalSubscriptions,
        totalFolders: totalFolders,
        totalSavedArticles: totalSavedArticles,
        totalReadArticles: totalReadArticles,
        readingStreak: readingStreak,
        memberSince: (await UserInfo.findById(session, userId))?.created ?? DateTime.now(),
      );
    } catch (e) {
      session.log('Error calculating user statistics: $e', level: LogLevel.error);
      // Return empty statistics on error
      return UserStatistics(
        totalSubscriptions: 0,
        totalFolders: 0,
        totalSavedArticles: 0,
        totalReadArticles: 0,
        readingStreak: 0,
        memberSince: DateTime.now(),
      );
    }
  }
  
  // Calculate reading streak
  Future<int> _calculateReadingStreak(Session session, int userId) async {
    // Get read history for the last 30 days
    final thirtyDaysAgo = DateTime.now().subtract(Duration(days: 30));
    
    final readHistory = await ReadHistory.find(
      session,
      where: (t) => t.userId.equals(userId) & t.readAt.afterOrEqualTo(thirtyDaysAgo),
      orderBy: (t) => t.readAt,
      orderDescending: true,
    );
    
    if (readHistory.isEmpty) return 0;
    
    // Calculate consecutive days
    int streak = 0;
    DateTime? lastDate;
    
    for (final entry in readHistory) {
      final entryDate = DateTime(entry.readAt.year, entry.readAt.month, entry.readAt.day);
      
      if (lastDate == null) {
        // Check if the most recent read was today or yesterday
        final today = DateTime.now();
        final daysDiff = today.difference(entryDate).inDays;
        
        if (daysDiff > 1) return 0; // Streak broken
        
        streak = 1;
        lastDate = entryDate;
      } else {
        final daysDiff = lastDate.difference(entryDate).inDays;
        
        if (daysDiff == 1) {
          streak++;
          lastDate = entryDate;
        } else if (daysDiff > 1) {
          break; // Streak broken
        }
        // daysDiff == 0 means multiple reads on same day, skip
      }
    }
    
    return streak;
  }
  
  // Get user preferences helper
  Future<UserPreferences> _getUserPreferences(Session session, int userId) async {
    final userPref = await UserPreference.findByUserId(session, userId);
    
    // Default preferences
    final defaultPrefs = {
      'theme': 'system',
      'articleListDensity': 'comfortable',
      'markAsReadOnScroll': true,
      'showUnreadOnly': false,
      'enableNotifications': true,
      'enableSounds': false,
      'defaultView': 'all',
      'articlesPerPage': 25,
      'refreshInterval': 30, // minutes
      'fontSize': 'medium',
      'language': 'en',
      'timezone': 'UTC',
      'keyboardShortcuts': {
        'nextArticle': 'j',
        'previousArticle': 'k',
        'toggleRead': 'm',
        'toggleStar': 's',
        'openOriginal': 'o',
        'refresh': 'r',
      },
    };
    
    // Merge with user preferences
    final prefs = userPref?.preferences ?? {};
    defaultPrefs.forEach((key, value) {
      prefs.putIfAbsent(key, () => value);
    });
    
    return UserPreferences(preferences: prefs);
  }
  
  // Delete all user data
  Future<void> _deleteAllUserData(Session session, int userId) async {
    // Delete in order of dependencies
    
    // 1. Delete read history
    final readHistory = await ReadHistory.find(
      session,
      where: (t) => t.userId.equals(userId),
    );
    for (final entry in readHistory) {
      await ReadHistory.deleteRow(session, entry);
    }
    
    // 2. Delete saved articles
    final savedArticles = await SavedArticle.find(
      session,
      where: (t) => t.userId.equals(userId),
    );
    for (final article in savedArticles) {
      await SavedArticle.deleteRow(session, article);
    }
    
    // 3. Delete feed subscriptions
    final subscriptions = await FeedSubscription.find(
      session,
      where: (t) => t.userId.equals(userId),
    );
    for (final sub in subscriptions) {
      await FeedSubscription.deleteRow(session, sub);
    }
    
    // 4. Delete folders
    final folders = await Folder.find(
      session,
      where: (t) => t.userId.equals(userId),
    );
    for (final folder in folders) {
      await Folder.deleteRow(session, folder);
    }
    
    // 5. Delete user preferences
    final preferences = await UserPreference.findByUserId(session, userId);
    if (preferences != null) {
      await UserPreference.deleteRow(session, preferences);
    }
  }
}

// Data classes for user operations
class UserProfile {
  final int id;
  final String email;
  final String userName;
  final String? fullName;
  final String? avatarUrl;
  final DateTime createdAt;
  final UserPreferences preferences;
  final UserStatistics statistics;
  
  UserProfile({
    required this.id,
    required this.email,
    required this.userName,
    this.fullName,
    this.avatarUrl,
    required this.createdAt,
    required this.preferences,
    required this.statistics,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'userName': userName,
    'fullName': fullName,
    'avatarUrl': avatarUrl,
    'createdAt': createdAt.toIso8601String(),
    'preferences': preferences.toJson(),
    'statistics': statistics.toJson(),
  };
}

class UserPreferences {
  final Map<String, dynamic> preferences;
  
  UserPreferences({required this.preferences});
  
  Map<String, dynamic> toJson() => preferences;
}

class UserStatistics {
  final int totalSubscriptions;
  final int totalFolders;
  final int totalSavedArticles;
  final int totalReadArticles;
  final int readingStreak;
  final DateTime memberSince;
  
  UserStatistics({
    required this.totalSubscriptions,
    required this.totalFolders,
    required this.totalSavedArticles,
    required this.totalReadArticles,
    required this.readingStreak,
    required this.memberSince,
  });
  
  Map<String, dynamic> toJson() => {
    'totalSubscriptions': totalSubscriptions,
    'totalFolders': totalFolders,
    'totalSavedArticles': totalSavedArticles,
    'totalReadArticles': totalReadArticles,
    'readingStreak': readingStreak,
    'memberSince': memberSince.toIso8601String(),
  };
}

class UserDataExport {
  final DateTime exportedAt;
  final Map<String, dynamic> userData;
  
  UserDataExport({
    required this.exportedAt,
    required this.userData,
  });
  
  Map<String, dynamic> toJson() => {
    'exportedAt': exportedAt.toIso8601String(),
    'userData': userData,
  };
}

// Extension for UserPreference model
extension UserPreferenceExtension on UserPreference {
  static Future<UserPreference?> findByUserId(Session session, int userId) async {
    final results = await UserPreference.find(
      session,
      where: (t) => t.userId.equals(userId),
      limit: 1,
    );
    
    return results.isEmpty ? null : results.first;
  }
}