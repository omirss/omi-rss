import 'package:drift/drift.dart';

/// Bypass rules table definition (encrypted)
@DataClassName('BypassRuleEntry')
class BypassRulesTable extends Table {
  TextColumn get domain => text()();
  TextColumn get rulesEncrypted => text()(); // Encrypted JSON rules
  RealColumn get successRate => real().withDefault(const Constant(0.0))();
  DateTimeColumn get lastUsed => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  
  @override
  Set<Column> get primaryKey => {domain};
  
  @override
  List<String> get customConstraints => [
    'CHECK (success_rate >= 0 AND success_rate <= 1)',
  ];
}