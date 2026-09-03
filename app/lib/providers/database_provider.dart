import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database.dart';

/// Database provider
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  
  // Close database when provider is disposed
  ref.onDispose(() {
    database.close();
  });
  
  return database;
});

/// Database initialization provider
final databaseInitializationProvider = FutureProvider<bool>((ref) async {
  final database = ref.watch(databaseProvider);
  
  // Database is initialized in the constructor
  // This provider is just to ensure it's ready
  return true;
});