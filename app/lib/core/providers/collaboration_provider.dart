import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/collaboration_service.dart';
import '../services/encryption_service.dart';
import '../database/database.dart';
import 'database_provider.dart';
import 'encryption_provider.dart';

/// Provider for collaboration service
final collaborationProvider = Provider<CollaborationService>((ref) {
  final database = ref.watch(databaseProvider);
  final encryption = ref.watch(encryptionProvider);
  
  final service = CollaborationService(
    database: database,
    encryption: encryption,
  );
  
  // Initialize with mock user ID
  service.initialize('current-user-id');
  
  return service;
});

/// Provider for shared folders stream
final sharedFoldersStreamProvider = StreamProvider<List<SharedFolder>>((ref) {
  final collaboration = ref.watch(collaborationProvider);
  
  // Return a stream of shared folders
  return Stream.periodic(const Duration(seconds: 1), (_) {
    return collaboration.sharedFolders;
  });
});

/// Provider for folder members
final folderMembersProvider = Provider.family<List<FolderMember>, String>((ref, folderId) {
  final collaboration = ref.watch(collaborationProvider);
  return collaboration.getFolderMembers(folderId);
});

/// Provider for folder activity stream
final folderActivityStreamProvider = StreamProvider.family<List<FolderActivity>, String>((ref, folderId) {
  final collaboration = ref.watch(collaborationProvider);
  return collaboration.getFolderActivity(folderId);
});

/// Provider for sharing events stream
final sharingEventsStreamProvider = StreamProvider<SharingEvent>((ref) {
  final collaboration = ref.watch(collaborationProvider);
  return collaboration.events;
});