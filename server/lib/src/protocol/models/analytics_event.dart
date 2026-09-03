import 'package:serverpod/serverpod.dart';

class AnalyticsEvent extends TableRow {
  int? id;
  int userId;
  String eventName;
  Map<String, dynamic> properties;
  DateTime timestamp;
  String? sessionId;
  String? userAgent;
  String? ipAddress;
  String? referrer;

  AnalyticsEvent({
    this.id,
    required this.userId,
    required this.eventName,
    Map<String, dynamic>? properties,
    DateTime? timestamp,
    this.sessionId,
    this.userAgent,
    this.ipAddress,
    this.referrer,
  }) : properties = properties ?? {},
       timestamp = timestamp ?? DateTime.now();

  static final t = AnalyticsEventTable();

  static const db = AnalyticsEventRepository._();

  @override
  String get tableName => 'analytics_events';

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'event_name':
        eventName = value;
        return;
      case 'properties':
        properties = value != null ? SerializationManager.decode(value) : {};
        return;
      case 'timestamp':
        timestamp = value;
        return;
      case 'session_id':
        sessionId = value;
        return;
      case 'user_agent':
        userAgent = value;
        return;
      case 'ip_address':
        ipAddress = value;
        return;
      case 'referrer':
        referrer = value;
        return;
      default:
        throw UnimplementedError();
    }
  }

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) {
    return AnalyticsEvent(
      id: json['id'] as int?,
      userId: json['userId'] as int,
      eventName: json['eventName'] as String,
      properties: json['properties'] as Map<String, dynamic>? ?? {},
      timestamp: DateTime.parse(json['timestamp'] as String),
      sessionId: json['sessionId'] as String?,
      userAgent: json['userAgent'] as String?,
      ipAddress: json['ipAddress'] as String?,
      referrer: json['referrer'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'eventName': eventName,
      'properties': properties,
      'timestamp': timestamp.toIso8601String(),
      if (sessionId != null) 'sessionId': sessionId,
      if (userAgent != null) 'userAgent': userAgent,
      if (ipAddress != null) 'ipAddress': ipAddress,
      if (referrer != null) 'referrer': referrer,
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'event_name': eventName,
      'properties': SerializationManager.encode(properties),
      'timestamp': timestamp,
      'session_id': sessionId,
      'user_agent': userAgent,
      'ip_address': ipAddress,
      'referrer': referrer,
    };
  }
}

class AnalyticsEventTable extends Table {
  AnalyticsEventTable() : super(tableName: 'analytics_events');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final userId = ColumnInt('user_id', this);
  late final eventName = ColumnString('event_name', this);
  late final properties = ColumnSerializable('properties', this);
  late final timestamp = ColumnDateTime('timestamp', this, hasDefault: true);
  late final sessionId = ColumnString('session_id', this);
  late final userAgent = ColumnString('user_agent', this);
  late final ipAddress = ColumnString('ip_address', this);
  late final referrer = ColumnString('referrer', this);

  @override
  List<Column> get columns => [
    id,
    userId,
    eventName,
    properties,
    timestamp,
    sessionId,
    userAgent,
    ipAddress,
    referrer,
  ];
}

class AnalyticsEventInclude extends IncludeObject {
  AnalyticsEventInclude._({
    UserInclude? user,
  }) : super(includes: {
    if (user != null) 'user': user,
  });

  static final i = AnalyticsEventInclude._();

  AnalyticsEventInclude user() {
    return AnalyticsEventInclude._(user: UserInclude.i);
  }
}

class AnalyticsEventIncludeList extends IncludeList {
  AnalyticsEventIncludeList([AnalyticsEventInclude? include]) 
    : super(include ?? AnalyticsEventInclude._());
}

class AnalyticsEventRepository {
  const AnalyticsEventRepository._();

  Future<List<AnalyticsEvent>> findByUserId(
    Session session,
    int userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? eventName,
    int? limit,
    Transaction? transaction,
  }) async {
    var where = AnalyticsEventTable().userId.equals(userId);
    
    if (startDate != null) {
      where = where & AnalyticsEventTable().timestamp.afterOrEqualTo(startDate);
    }
    
    if (endDate != null) {
      where = where & AnalyticsEventTable().timestamp.beforeOrEqualTo(endDate);
    }
    
    if (eventName != null) {
      where = where & AnalyticsEventTable().eventName.equals(eventName);
    }
    
    return session.db.find<AnalyticsEvent>(
      where: (t) => where,
      orderBy: (t) => t.timestamp,
      orderDescending: true,
      limit: limit,
      transaction: transaction,
    );
  }

  Future<Map<String, int>> countEventsByName(
    Session session,
    int userId, {
    DateTime? startDate,
    DateTime? endDate,
    Transaction? transaction,
  }) async {
    // This would ideally use GROUP BY in SQL
    // For now, we'll fetch and count in memory
    final events = await findByUserId(
      session,
      userId,
      startDate: startDate,
      endDate: endDate,
      transaction: transaction,
    );
    
    final counts = <String, int>{};
    for (final event in events) {
      counts[event.eventName] = (counts[event.eventName] ?? 0) + 1;
    }
    
    return counts;
  }

  Future<List<AnalyticsEvent>> findBySessionId(
    Session session,
    String sessionId, {
    Transaction? transaction,
  }) async {
    return session.db.find<AnalyticsEvent>(
      where: (t) => t.sessionId.equals(sessionId),
      orderBy: (t) => t.timestamp,
      transaction: transaction,
    );
  }

  Future<int> countUniqueUsersByEvent(
    Session session,
    String eventName, {
    DateTime? startDate,
    DateTime? endDate,
    Transaction? transaction,
  }) async {
    var where = AnalyticsEventTable().eventName.equals(eventName);
    
    if (startDate != null) {
      where = where & AnalyticsEventTable().timestamp.afterOrEqualTo(startDate);
    }
    
    if (endDate != null) {
      where = where & AnalyticsEventTable().timestamp.beforeOrEqualTo(endDate);
    }
    
    // This would ideally use COUNT(DISTINCT user_id) in SQL
    final events = await session.db.find<AnalyticsEvent>(
      where: (t) => where,
      transaction: transaction,
    );
    
    return events.map((e) => e.userId).toSet().length;
  }
}