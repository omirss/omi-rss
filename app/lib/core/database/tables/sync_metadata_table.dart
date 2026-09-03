import 'package:drift/drift.dart';

/// Sync metadata table definition
@DataClassName('SyncMetadataEntry')
class SyncMetadataTable extends Table {
  TextColumn get deviceId => text()();
  DateTimeColumn get lastSync => dateTime().nullable()();
  TextColumn get syncToken => text().nullable()();
  TextColumn get pendingChangesJson => text().nullable()(); // JSON object
  
  @override
  Set<Column> get primaryKey => {deviceId};
}