import 'package:serverpod/serverpod.dart';

class FeedSubscription extends TableRow {
  int? id;
  int userId;
  int feedId;
  int? folderId;
  Map<String, dynamic>? customSettings;
  DateTime subscribedAt;
  DateTime? lastReadAt;

  FeedSubscription({
    this.id,
    required this.userId,
    required this.feedId,
    this.folderId,
    this.customSettings,
    DateTime? subscribedAt,
    this.lastReadAt,
  }) : subscribedAt = subscribedAt ?? DateTime.now();

  static final t = FeedSubscriptionTable();

  static const db = FeedSubscriptionRepository._();

  @override
  String get tableName => 'feed_subscriptions';

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'feed_id':
        feedId = value;
        return;
      case 'folder_id':
        folderId = value;
        return;
      case 'custom_settings':
        customSettings = value != null ? SerializationManager.decode(value) : null;
        return;
      case 'subscribed_at':
        subscribedAt = value;
        return;
      case 'last_read_at':
        lastReadAt = value;
        return;
      default:
        throw UnimplementedError();
    }
  }

  factory FeedSubscription.fromJson(Map<String, dynamic> json) {
    return FeedSubscription(
      id: json['id'] as int?,
      userId: json['userId'] as int,
      feedId: json['feedId'] as int,
      folderId: json['folderId'] as int?,
      customSettings: json['customSettings'] as Map<String, dynamic>?,
      subscribedAt: DateTime.parse(json['subscribedAt'] as String),
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.parse(json['lastReadAt'] as String)
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'feedId': feedId,
      if (folderId != null) 'folderId': folderId,
      if (customSettings != null) 'customSettings': customSettings,
      'subscribedAt': subscribedAt.toIso8601String(),
      if (lastReadAt != null) 'lastReadAt': lastReadAt!.toIso8601String(),
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'feed_id': feedId,
      'folder_id': folderId,
      'custom_settings': customSettings != null ? SerializationManager.encode(customSettings!) : null,
      'subscribed_at': subscribedAt,
      'last_read_at': lastReadAt,
    };
  }
}

class FeedSubscriptionTable extends Table {
  FeedSubscriptionTable() : super(tableName: 'feed_subscriptions');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final userId = ColumnInt('user_id', this);
  late final feedId = ColumnInt('feed_id', this);
  late final folderId = ColumnInt('folder_id', this);
  late final customSettings = ColumnSerializable('custom_settings', this);
  late final subscribedAt = ColumnDateTime('subscribed_at', this, hasDefault: true);
  late final lastReadAt = ColumnDateTime('last_read_at', this);

  @override
  List<Column> get columns => [
    id,
    userId,
    feedId,
    folderId,
    customSettings,
    subscribedAt,
    lastReadAt,
  ];
}

class FeedSubscriptionInclude extends IncludeObject {
  FeedSubscriptionInclude._({
    UserInclude? user,
    FeedInclude? feed,
    FolderInclude? folder,
  }) : super(includes: {
    if (user != null) 'user': user,
    if (feed != null) 'feed': feed,
    if (folder != null) 'folder': folder,
  });

  static final i = FeedSubscriptionInclude._();

  FeedSubscriptionInclude user() {
    return FeedSubscriptionInclude._(user: UserInclude.i);
  }

  FeedSubscriptionInclude feed({FeedInclude? include}) {
    return FeedSubscriptionInclude._(feed: include ?? FeedInclude.i);
  }

  FeedSubscriptionInclude folder() {
    return FeedSubscriptionInclude._(folder: FolderInclude.i);
  }
}

class FeedSubscriptionIncludeList extends IncludeList {
  FeedSubscriptionIncludeList([FeedSubscriptionInclude? include]) 
    : super(include ?? FeedSubscriptionInclude._());
}

class FeedSubscriptionRepository {
  const FeedSubscriptionRepository._();

  Future<List<FeedSubscription>> findByUserId(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    return session.db.find<FeedSubscription>(
      where: (t) => t.userId.equals(userId),
      transaction: transaction,
    );
  }

  Future<FeedSubscription?> findByUserAndFeed(
    Session session,
    int userId,
    int feedId, {
    Transaction? transaction,
  }) async {
    final subscriptions = await session.db.find<FeedSubscription>(
      where: (t) => t.userId.equals(userId) & t.feedId.equals(feedId),
      limit: 1,
      transaction: transaction,
    );
    return subscriptions.isNotEmpty ? subscriptions.first : null;
  }

  Future<List<FeedSubscription>> findByFolderId(
    Session session,
    int userId,
    int folderId, {
    Transaction? transaction,
  }) async {
    return session.db.find<FeedSubscription>(
      where: (t) => t.userId.equals(userId) & t.folderId.equals(folderId),
      transaction: transaction,
    );
  }

  Future<int> countByUserId(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    return session.db.count<FeedSubscription>(
      where: (t) => t.userId.equals(userId),
      transaction: transaction,
    );
  }
}