import 'package:drift/drift.dart';

/// Market watchlist table definition
@DataClassName('MarketWatchlistEntry')
class MarketWatchlistTable extends Table {
  TextColumn get symbol => text()();
  TextColumn get name => text().nullable()();
  RealColumn get lastPrice => real().nullable()();
  DateTimeColumn get lastUpdated => dateTime().nullable()();
  TextColumn get alertsJson => text().nullable()(); // JSON array of alerts
  
  @override
  Set<Column> get primaryKey => {symbol};
}