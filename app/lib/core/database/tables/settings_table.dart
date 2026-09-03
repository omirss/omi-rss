import 'package:drift/drift.dart';

/// Settings table definition
@DataClassName('SettingEntry')
class SettingsTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {key};
}