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
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['userName'] as String?,
      fullName: json['fullName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      preferences: json['preferences'] as Map<String, dynamic>?,
      statistics: json['statistics'] != null 
          ? UserStatistics.fromJson(json['statistics'] as Map<String, dynamic>)
          : null,
    );
  }
  
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
  
  User copyWith({
    int? id,
    String? email,
    String? username,
    String? fullName,
    String? avatarUrl,
    DateTime? createdAt,
    Map<String, dynamic>? preferences,
    UserStatistics? statistics,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      preferences: preferences ?? this.preferences,
      statistics: statistics ?? this.statistics,
    );
  }
}

/// User statistics
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
  
  factory UserStatistics.fromJson(Map<String, dynamic> json) {
    return UserStatistics(
      totalSubscriptions: json['totalSubscriptions'] as int,
      totalFolders: json['totalFolders'] as int,
      totalSavedArticles: json['totalSavedArticles'] as int,
      totalReadArticles: json['totalReadArticles'] as int,
      readingStreak: json['readingStreak'] as int,
      memberSince: DateTime.parse(json['memberSince'] as String),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'totalSubscriptions': totalSubscriptions,
      'totalFolders': totalFolders,
      'totalSavedArticles': totalSavedArticles,
      'totalReadArticles': totalReadArticles,
      'readingStreak': readingStreak,
      'memberSince': memberSince.toIso8601String(),
    };
  }
}

/// User preferences
class UserPreferences {
  final String theme;
  final String articleListDensity;
  final bool markAsReadOnScroll;
  final bool showUnreadOnly;
  final bool enableNotifications;
  final bool enableSounds;
  final String defaultView;
  final int articlesPerPage;
  final int refreshInterval;
  final String fontSize;
  final String language;
  final String timezone;
  final Map<String, String> keyboardShortcuts;
  
  UserPreferences({
    this.theme = 'system',
    this.articleListDensity = 'comfortable',
    this.markAsReadOnScroll = true,
    this.showUnreadOnly = false,
    this.enableNotifications = true,
    this.enableSounds = false,
    this.defaultView = 'all',
    this.articlesPerPage = 25,
    this.refreshInterval = 30,
    this.fontSize = 'medium',
    this.language = 'en',
    this.timezone = 'UTC',
    Map<String, String>? keyboardShortcuts,
  }) : keyboardShortcuts = keyboardShortcuts ?? {
          'nextArticle': 'j',
          'previousArticle': 'k',
          'toggleRead': 'm',
          'toggleStar': 's',
          'openOriginal': 'o',
          'refresh': 'r',
        };
  
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      theme: json['theme'] as String? ?? 'system',
      articleListDensity: json['articleListDensity'] as String? ?? 'comfortable',
      markAsReadOnScroll: json['markAsReadOnScroll'] as bool? ?? true,
      showUnreadOnly: json['showUnreadOnly'] as bool? ?? false,
      enableNotifications: json['enableNotifications'] as bool? ?? true,
      enableSounds: json['enableSounds'] as bool? ?? false,
      defaultView: json['defaultView'] as String? ?? 'all',
      articlesPerPage: json['articlesPerPage'] as int? ?? 25,
      refreshInterval: json['refreshInterval'] as int? ?? 30,
      fontSize: json['fontSize'] as String? ?? 'medium',
      language: json['language'] as String? ?? 'en',
      timezone: json['timezone'] as String? ?? 'UTC',
      keyboardShortcuts: (json['keyboardShortcuts'] as Map<String, dynamic>?)
          ?.cast<String, String>(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'articleListDensity': articleListDensity,
      'markAsReadOnScroll': markAsReadOnScroll,
      'showUnreadOnly': showUnreadOnly,
      'enableNotifications': enableNotifications,
      'enableSounds': enableSounds,
      'defaultView': defaultView,
      'articlesPerPage': articlesPerPage,
      'refreshInterval': refreshInterval,
      'fontSize': fontSize,
      'language': language,
      'timezone': timezone,
      'keyboardShortcuts': keyboardShortcuts,
    };
  }
  
  UserPreferences copyWith({
    String? theme,
    String? articleListDensity,
    bool? markAsReadOnScroll,
    bool? showUnreadOnly,
    bool? enableNotifications,
    bool? enableSounds,
    String? defaultView,
    int? articlesPerPage,
    int? refreshInterval,
    String? fontSize,
    String? language,
    String? timezone,
    Map<String, String>? keyboardShortcuts,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      articleListDensity: articleListDensity ?? this.articleListDensity,
      markAsReadOnScroll: markAsReadOnScroll ?? this.markAsReadOnScroll,
      showUnreadOnly: showUnreadOnly ?? this.showUnreadOnly,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      enableSounds: enableSounds ?? this.enableSounds,
      defaultView: defaultView ?? this.defaultView,
      articlesPerPage: articlesPerPage ?? this.articlesPerPage,
      refreshInterval: refreshInterval ?? this.refreshInterval,
      fontSize: fontSize ?? this.fontSize,
      language: language ?? this.language,
      timezone: timezone ?? this.timezone,
      keyboardShortcuts: keyboardShortcuts ?? this.keyboardShortcuts,
    );
  }
}