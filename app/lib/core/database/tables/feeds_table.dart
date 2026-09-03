import 'package:drift/drift.dart';

/// Feeds table definition
@DataClassName('FeedEntry')
class FeedsTable extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get link => text().nullable()();
  TextColumn get categoryId => text().nullable().references(CategoriesTable, #id)();
  TextColumn get faviconUrl => text().nullable()();
  DateTimeColumn get lastFetched => dateTime().nullable()();
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();
  IntColumn get updateFrequency => integer().withDefault(const Constant(3600))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get type => text().withDefault(const Constant('rss'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  
  // Additional metadata
  TextColumn get language => text().nullable()();
  TextColumn get copyright => text().nullable()();
  TextColumn get generator => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get customFields => text().nullable()(); // JSON
  
  // Feed health tracking
  IntColumn get successfulFetches => integer().withDefault(const Constant(0))();
  IntColumn get failedFetches => integer().withDefault(const Constant(0))();
  RealColumn get successRate => real().withDefault(const Constant(0.0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get lastErrorAt => dateTime().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<String> get customConstraints => [
    'CHECK (update_frequency >= 60)', // Minimum 1 minute
  ];
}

/// Import from categories table
@DataClassName('CategoryEntry')
class CategoriesTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(CategoriesTable, #id)();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {id};
}