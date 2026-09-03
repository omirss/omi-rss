import 'package:drift/drift.dart';
import 'feeds_table.dart';

/// Articles table definition
@DataClassName('ArticleEntry')
class ArticlesTable extends Table {
  TextColumn get id => text()();
  TextColumn get feedId => text().references(FeedsTable, #id)();
  TextColumn get guid => text()();
  TextColumn get title => text()();
  TextColumn get content => text().nullable()();
  TextColumn get summary => text().nullable()();
  TextColumn get author => text().nullable()();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  TextColumn get url => text()();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isStarred => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get readTimeSeconds => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  
  // AI-generated fields
  TextColumn get aiSummary => text().nullable()();
  TextColumn get aiTags => text().nullable()(); // JSON array
  TextColumn get perspectivesJson => text().nullable()(); // JSON object
  RealColumn get sentimentScore => real().nullable()();
  RealColumn get biasScore => real().nullable()();
  
  // Metadata
  TextColumn get enclosures => text().nullable()(); // JSON array
  TextColumn get categories => text().nullable()(); // JSON array
  TextColumn get customFields => text().nullable()(); // JSON object
  TextColumn get language => text().nullable()();
  TextColumn get rights => text().nullable()();
  
  // Full-text extraction
  TextColumn get fullContent => text().nullable()();
  DateTimeColumn get fullContentFetchedAt => dateTime().nullable()();
  BoolColumn get fullContentAvailable => boolean().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {feedId, guid}, // Ensure unique articles per feed
  ];
  
  @override
  List<String> get customConstraints => [
    'CHECK (sentiment_score IS NULL OR (sentiment_score >= -1 AND sentiment_score <= 1))',
    'CHECK (bias_score IS NULL OR (bias_score >= 0 AND bias_score <= 100))',
  ];
}