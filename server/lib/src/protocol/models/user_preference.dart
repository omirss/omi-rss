import 'package:serverpod/serverpod.dart';

class UserPreference extends TableRow {
  int? id;
  int userId;
  Map<String, dynamic> preferences;
  DateTime createdAt;
  DateTime updatedAt;

  UserPreference({
    this.id,
    required this.userId,
    Map<String, dynamic>? preferences,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : preferences = preferences ?? {},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static final t = UserPreferenceTable();

  static const db = UserPreferenceRepository._();

  @override
  String get tableName => 'user_preferences';

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'preferences':
        preferences = value != null ? SerializationManager.decode(value) : {};
        return;
      case 'created_at':
        createdAt = value;
        return;
      case 'updated_at':
        updatedAt = value;
        return;
      default:
        throw UnimplementedError();
    }
  }

  factory UserPreference.fromJson(Map<String, dynamic> json) {
    return UserPreference(
      id: json['id'] as int?,
      userId: json['userId'] as int,
      preferences: json['preferences'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'preferences': preferences,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'preferences': SerializationManager.encode(preferences),
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  // Helper methods for common preferences
  String get theme => preferences['theme'] as String? ?? 'system';
  set theme(String value) => preferences['theme'] = value;

  String get articleListDensity => preferences['articleListDensity'] as String? ?? 'comfortable';
  set articleListDensity(String value) => preferences['articleListDensity'] = value;

  bool get markAsReadOnScroll => preferences['markAsReadOnScroll'] as bool? ?? true;
  set markAsReadOnScroll(bool value) => preferences['markAsReadOnScroll'] = value;

  bool get showUnreadOnly => preferences['showUnreadOnly'] as bool? ?? false;
  set showUnreadOnly(bool value) => preferences['showUnreadOnly'] = value;

  bool get enableNotifications => preferences['enableNotifications'] as bool? ?? true;
  set enableNotifications(bool value) => preferences['enableNotifications'] = value;

  bool get enableSounds => preferences['enableSounds'] as bool? ?? false;
  set enableSounds(bool value) => preferences['enableSounds'] = value;

  String get defaultView => preferences['defaultView'] as String? ?? 'all';
  set defaultView(String value) => preferences['defaultView'] = value;

  int get articlesPerPage => preferences['articlesPerPage'] as int? ?? 25;
  set articlesPerPage(int value) => preferences['articlesPerPage'] = value;

  int get refreshInterval => preferences['refreshInterval'] as int? ?? 30;
  set refreshInterval(int value) => preferences['refreshInterval'] = value;

  String get fontSize => preferences['fontSize'] as String? ?? 'medium';
  set fontSize(String value) => preferences['fontSize'] = value;

  String get language => preferences['language'] as String? ?? 'en';
  set language(String value) => preferences['language'] = value;

  String get timezone => preferences['timezone'] as String? ?? 'UTC';
  set timezone(String value) => preferences['timezone'] = value;

  Map<String, String> get keyboardShortcuts => 
      (preferences['keyboardShortcuts'] as Map<String, dynamic>?)?.cast<String, String>() ?? {
        'nextArticle': 'j',
        'previousArticle': 'k',
        'toggleRead': 'm',
        'toggleStar': 's',
        'openOriginal': 'o',
        'refresh': 'r',
      };
  set keyboardShortcuts(Map<String, String> value) => preferences['keyboardShortcuts'] = value;
}

class UserPreferenceTable extends Table {
  UserPreferenceTable() : super(tableName: 'user_preferences');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final userId = ColumnInt('user_id', this);
  late final preferences = ColumnSerializable('preferences', this);
  late final createdAt = ColumnDateTime('created_at', this, hasDefault: true);
  late final updatedAt = ColumnDateTime('updated_at', this, hasDefault: true);

  @override
  List<Column> get columns => [
    id,
    userId,
    preferences,
    createdAt,
    updatedAt,
  ];
}

class UserPreferenceInclude extends IncludeObject {
  UserPreferenceInclude._({
    UserInclude? user,
  }) : super(includes: {
    if (user != null) 'user': user,
  });

  static final i = UserPreferenceInclude._();

  UserPreferenceInclude user() {
    return UserPreferenceInclude._(user: UserInclude.i);
  }
}

class UserPreferenceRepository {
  const UserPreferenceRepository._();

  Future<UserPreference?> findByUserId(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    final prefs = await session.db.find<UserPreference>(
      where: (t) => t.userId.equals(userId),
      limit: 1,
      transaction: transaction,
    );
    return prefs.isNotEmpty ? prefs.first : null;
  }

  Future<UserPreference> getOrCreateForUser(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    var pref = await findByUserId(session, userId, transaction: transaction);
    
    if (pref == null) {
      pref = UserPreference(userId: userId);
      await session.db.insertRow(pref, transaction: transaction);
    }
    
    return pref;
  }

  Future<void> updatePreference(
    Session session,
    int userId,
    String key,
    dynamic value, {
    Transaction? transaction,
  }) async {
    final pref = await getOrCreateForUser(session, userId, transaction: transaction);
    pref.preferences[key] = value;
    pref.updatedAt = DateTime.now();
    await session.db.updateRow(pref, transaction: transaction);
  }

  Future<void> updatePreferences(
    Session session,
    int userId,
    Map<String, dynamic> updates, {
    Transaction? transaction,
  }) async {
    final pref = await getOrCreateForUser(session, userId, transaction: transaction);
    pref.preferences.addAll(updates);
    pref.updatedAt = DateTime.now();
    await session.db.updateRow(pref, transaction: transaction);
  }
}