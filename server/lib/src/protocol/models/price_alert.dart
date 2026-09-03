import 'package:serverpod/serverpod.dart';

class PriceAlert extends TableRow {
  int? id;
  int userId;
  String symbol;
  double targetPrice;
  String condition; // 'above' or 'below'
  bool isActive;
  DateTime createdAt;
  DateTime? triggeredAt;
  double? triggeredPrice;

  PriceAlert({
    this.id,
    required this.userId,
    required this.symbol,
    required this.targetPrice,
    required this.condition,
    this.isActive = true,
    DateTime? createdAt,
    this.triggeredAt,
    this.triggeredPrice,
  }) : createdAt = createdAt ?? DateTime.now();

  static final t = PriceAlertTable();

  static const db = PriceAlertRepository._();

  @override
  String get tableName => 'price_alerts';

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'symbol':
        symbol = value;
        return;
      case 'target_price':
        targetPrice = value;
        return;
      case 'condition':
        condition = value;
        return;
      case 'is_active':
        isActive = value;
        return;
      case 'created_at':
        createdAt = value;
        return;
      case 'triggered_at':
        triggeredAt = value;
        return;
      case 'triggered_price':
        triggeredPrice = value;
        return;
      default:
        throw UnimplementedError();
    }
  }

  factory PriceAlert.fromJson(Map<String, dynamic> json) {
    return PriceAlert(
      id: json['id'] as int?,
      userId: json['userId'] as int,
      symbol: json['symbol'] as String,
      targetPrice: (json['targetPrice'] as num).toDouble(),
      condition: json['condition'] as String,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      triggeredAt: json['triggeredAt'] != null
          ? DateTime.parse(json['triggeredAt'] as String)
          : null,
      triggeredPrice: json['triggeredPrice'] as double?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'symbol': symbol,
      'targetPrice': targetPrice,
      'condition': condition,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      if (triggeredAt != null) 'triggeredAt': triggeredAt!.toIso8601String(),
      if (triggeredPrice != null) 'triggeredPrice': triggeredPrice,
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'symbol': symbol,
      'target_price': targetPrice,
      'condition': condition,
      'is_active': isActive,
      'created_at': createdAt,
      'triggered_at': triggeredAt,
      'triggered_price': triggeredPrice,
    };
  }
}

class PriceAlertTable extends Table {
  PriceAlertTable() : super(tableName: 'price_alerts');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final userId = ColumnInt('user_id', this);
  late final symbol = ColumnString('symbol', this);
  late final targetPrice = ColumnDouble('target_price', this);
  late final condition = ColumnString('condition', this);
  late final isActive = ColumnBool('is_active', this, hasDefault: true);
  late final createdAt = ColumnDateTime('created_at', this, hasDefault: true);
  late final triggeredAt = ColumnDateTime('triggered_at', this);
  late final triggeredPrice = ColumnDouble('triggered_price', this);

  @override
  List<Column> get columns => [
    id,
    userId,
    symbol,
    targetPrice,
    condition,
    isActive,
    createdAt,
    triggeredAt,
    triggeredPrice,
  ];
}

class PriceAlertInclude extends IncludeObject {
  PriceAlertInclude._({
    UserInclude? user,
  }) : super(includes: {
    if (user != null) 'user': user,
  });

  static final i = PriceAlertInclude._();

  PriceAlertInclude user() {
    return PriceAlertInclude._(user: UserInclude.i);
  }
}

class PriceAlertIncludeList extends IncludeList {
  PriceAlertIncludeList([PriceAlertInclude? include]) 
    : super(include ?? PriceAlertInclude._());
}

class PriceAlertRepository {
  const PriceAlertRepository._();

  Future<List<PriceAlert>> findActiveByUserId(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    return session.db.find<PriceAlert>(
      where: (t) => t.userId.equals(userId) & t.isActive.equals(true),
      orderBy: (t) => t.createdAt,
      orderDescending: true,
      transaction: transaction,
    );
  }

  Future<List<PriceAlert>> findActiveBySymbol(
    Session session,
    String symbol, {
    Transaction? transaction,
  }) async {
    return session.db.find<PriceAlert>(
      where: (t) => t.symbol.equals(symbol) & t.isActive.equals(true),
      transaction: transaction,
    );
  }

  Future<List<PriceAlert>> findTriggeredByUserId(
    Session session,
    int userId, {
    int? limit,
    Transaction? transaction,
  }) async {
    return session.db.find<PriceAlert>(
      where: (t) => t.userId.equals(userId) & t.isActive.equals(false) & t.triggeredAt.notEquals(null),
      orderBy: (t) => t.triggeredAt,
      orderDescending: true,
      limit: limit,
      transaction: transaction,
    );
  }

  Future<int> countActiveByUserId(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    return session.db.count<PriceAlert>(
      where: (t) => t.userId.equals(userId) & t.isActive.equals(true),
      transaction: transaction,
    );
  }

  Future<void> triggerAlert(
    Session session,
    int alertId,
    double triggeredPrice, {
    Transaction? transaction,
  }) async {
    final alert = await session.db.findById<PriceAlert>(alertId);
    if (alert != null && alert.isActive) {
      alert.isActive = false;
      alert.triggeredAt = DateTime.now();
      alert.triggeredPrice = triggeredPrice;
      await session.db.updateRow(alert, transaction: transaction);
    }
  }
}