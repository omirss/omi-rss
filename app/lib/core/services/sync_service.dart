import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';
import 'encryption_service.dart';

/// Sync service for multi-device synchronization
class SyncService {
  final AppDatabase _database;
  final EncryptionService _encryption;
  final Dio _dio;
  
  // Sync configuration
  String? _serverUrl;
  String? _deviceId;
  String? _userId;
  String? _syncToken;
  
  // WebSocket connection
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  
  // Sync state
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  final _syncController = StreamController<SyncEvent>.broadcast();
  
  // Conflict resolution
  final Map<String, ConflictResolution> _conflictResolutions = {};
  
  SyncService({
    required AppDatabase database,
    required EncryptionService encryption,
  }) : _database = database,
       _encryption = encryption,
       _dio = Dio();

  /// Initialize sync service
  Future<void> initialize({
    required String serverUrl,
    required String userId,
    required String syncToken,
  }) async {
    _serverUrl = serverUrl;
    _userId = userId;
    _syncToken = syncToken;
    
    // Generate or load device ID
    _deviceId = await _getOrCreateDeviceId();
    
    // Set up Dio interceptors
    _dio.options.baseUrl = serverUrl;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Bearer $_syncToken';
        options.headers['X-Device-ID'] = _deviceId;
        handler.next(options);
      },
    ));
    
    // Connect WebSocket for real-time sync
    await _connectWebSocket();
  }
  
  /// Get or create device ID
  Future<String> _getOrCreateDeviceId() async {
    // TODO: Load from secure storage
    return const Uuid().v4();
  }
  
  /// Connect to WebSocket for real-time sync
  Future<void> _connectWebSocket() async {
    if (_serverUrl == null || _syncToken == null) return;
    
    try {
      final wsUrl = _serverUrl!.replaceFirst('http', 'ws') + '/sync/ws';
      _wsChannel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$_syncToken&device=$_deviceId'),
      );
      
      _wsSubscription = _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onError: (error) {
          print('WebSocket error: $error');
          _reconnectWebSocket();
        },
        onDone: () {
          print('WebSocket closed');
          _reconnectWebSocket();
        },
      );
      
      // Send device info
      _sendWebSocketMessage({
        'type': 'device_info',
        'device': {
          'id': _deviceId,
          'name': 'Flutter App',
          'platform': 'mobile',
          'version': '1.0.0',
        },
      });
      
      _syncController.add(SyncEvent(
        type: SyncEventType.connected,
        message: 'Connected to sync server',
      ));
    } catch (e) {
      print('Failed to connect WebSocket: $e');
      _syncController.add(SyncEvent(
        type: SyncEventType.error,
        message: 'Failed to connect to sync server',
      ));
    }
  }
  
  /// Reconnect WebSocket after delay
  void _reconnectWebSocket() {
    Future.delayed(const Duration(seconds: 5), () {
      if (_wsChannel == null || _wsChannel!.closeCode != null) {
        _connectWebSocket();
      }
    });
  }
  
  /// Handle WebSocket messages
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String;
      
      switch (type) {
        case 'sync_required':
          _performSync();
          break;
          
        case 'remote_change':
          _handleRemoteChange(data['change']);
          break;
          
        case 'conflict':
          _handleConflict(data['conflict']);
          break;
          
        case 'device_connected':
          _syncController.add(SyncEvent(
            type: SyncEventType.deviceConnected,
            message: 'Device ${data['device']['name']} connected',
            data: data['device'],
          ));
          break;
          
        case 'device_disconnected':
          _syncController.add(SyncEvent(
            type: SyncEventType.deviceDisconnected,
            message: 'Device ${data['device']['name']} disconnected',
            data: data['device'],
          ));
          break;
      }
    } catch (e) {
      print('Error handling WebSocket message: $e');
    }
  }
  
  /// Send WebSocket message
  void _sendWebSocketMessage(Map<String, dynamic> message) {
    if (_wsChannel != null && _wsChannel!.closeCode == null) {
      _wsChannel!.sink.add(jsonEncode(message));
    }
  }
  
  /// Perform full sync
  Future<void> sync() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    _syncController.add(SyncEvent(
      type: SyncEventType.syncStarted,
      message: 'Syncing...',
    ));
    
    try {
      // Get local changes since last sync
      final localChanges = await _getLocalChanges();
      
      // Encrypt sensitive data
      final encryptedChanges = await _encryptChanges(localChanges);
      
      // Send changes to server and get remote changes
      final response = await _dio.post('/sync/changes', data: {
        'device_id': _deviceId,
        'last_sync': _lastSyncTime?.toIso8601String(),
        'changes': encryptedChanges,
      });
      
      final remoteChanges = response.data['changes'] as List;
      final conflicts = response.data['conflicts'] as List?;
      
      // Handle conflicts
      if (conflicts != null && conflicts.isNotEmpty) {
        await _resolveConflicts(conflicts);
      }
      
      // Apply remote changes
      await _applyRemoteChanges(remoteChanges);
      
      // Update last sync time
      _lastSyncTime = DateTime.now();
      await _saveLastSyncTime();
      
      _syncController.add(SyncEvent(
        type: SyncEventType.syncCompleted,
        message: 'Sync completed',
        data: {
          'uploaded': localChanges.length,
          'downloaded': remoteChanges.length,
          'conflicts': conflicts?.length ?? 0,
        },
      ));
    } catch (e) {
      print('Sync error: $e');
      _syncController.add(SyncEvent(
        type: SyncEventType.error,
        message: 'Sync failed: ${e.toString()}',
      ));
    } finally {
      _isSyncing = false;
    }
  }
  
  /// Get local changes since last sync
  Future<List<SyncChange>> _getLocalChanges() async {
    final changes = <SyncChange>[];
    
    // Get modified feeds
    final feeds = await _database.feedsDao.getModifiedSince(_lastSyncTime);
    for (final feed in feeds) {
      changes.add(SyncChange(
        id: const Uuid().v4(),
        entityType: 'feed',
        entityId: feed.id,
        action: feed.deletedAt != null ? SyncAction.delete : SyncAction.update,
        data: feed.toJson(),
        timestamp: feed.updatedAt ?? DateTime.now(),
        deviceId: _deviceId!,
      ));
    }
    
    // Get modified articles
    final articles = await _database.articlesDao.getModifiedSince(_lastSyncTime);
    for (final article in articles) {
      changes.add(SyncChange(
        id: const Uuid().v4(),
        entityType: 'article',
        entityId: article.id,
        action: article.deletedAt != null ? SyncAction.delete : SyncAction.update,
        data: article.toJson(),
        timestamp: article.updatedAt ?? DateTime.now(),
        deviceId: _deviceId!,
      ));
    }
    
    // Get modified folders
    final folders = await _database.foldersDao.getModifiedSince(_lastSyncTime);
    for (final folder in folders) {
      changes.add(SyncChange(
        id: const Uuid().v4(),
        entityType: 'folder',
        entityId: folder.id,
        action: folder.deletedAt != null ? SyncAction.delete : SyncAction.update,
        data: folder.toJson(),
        timestamp: folder.updatedAt ?? DateTime.now(),
        deviceId: _deviceId!,
      ));
    }
    
    return changes;
  }
  
  /// Encrypt sensitive changes
  Future<List<Map<String, dynamic>>> _encryptChanges(List<SyncChange> changes) async {
    final encrypted = <Map<String, dynamic>>[];
    
    for (final change in changes) {
      final encryptedData = await _encryption.encryptJson(change.data);
      encrypted.add({
        'id': change.id,
        'entity_type': change.entityType,
        'entity_id': change.entityId,
        'action': change.action.toString(),
        'data': base64Encode(encryptedData),
        'timestamp': change.timestamp.toIso8601String(),
        'device_id': change.deviceId,
      });
    }
    
    return encrypted;
  }
  
  /// Apply remote changes
  Future<void> _applyRemoteChanges(List<dynamic> changes) async {
    for (final change in changes) {
      try {
        // Decrypt data
        final encryptedData = base64Decode(change['data']);
        final decryptedData = await _encryption.decryptJson(encryptedData);
        
        final syncChange = SyncChange(
          id: change['id'],
          entityType: change['entity_type'],
          entityId: change['entity_id'],
          action: SyncAction.values.firstWhere(
            (a) => a.toString() == change['action'],
          ),
          data: decryptedData,
          timestamp: DateTime.parse(change['timestamp']),
          deviceId: change['device_id'],
        );
        
        await _applySingleChange(syncChange);
      } catch (e) {
        print('Error applying change ${change['id']}: $e');
      }
    }
  }
  
  /// Apply single change
  Future<void> _applySingleChange(SyncChange change) async {
    switch (change.entityType) {
      case 'feed':
        await _applyFeedChange(change);
        break;
      case 'article':
        await _applyArticleChange(change);
        break;
      case 'folder':
        await _applyFolderChange(change);
        break;
    }
  }
  
  /// Apply feed change
  Future<void> _applyFeedChange(SyncChange change) async {
    switch (change.action) {
      case SyncAction.create:
      case SyncAction.update:
        final feed = Feed.fromJson(change.data);
        await _database.feedsDao.insertFeed(feed);
        break;
      case SyncAction.delete:
        await _database.feedsDao.deleteFeed(change.entityId);
        break;
    }
  }
  
  /// Apply article change
  Future<void> _applyArticleChange(SyncChange change) async {
    switch (change.action) {
      case SyncAction.create:
      case SyncAction.update:
        final article = Article.fromJson(change.data);
        await _database.articlesDao.insertArticle(article);
        break;
      case SyncAction.delete:
        await _database.articlesDao.deleteArticle(change.entityId);
        break;
    }
  }
  
  /// Apply folder change
  Future<void> _applyFolderChange(SyncChange change) async {
    switch (change.action) {
      case SyncAction.create:
      case SyncAction.update:
        final folder = Folder.fromJson(change.data);
        await _database.foldersDao.insertFolder(folder);
        break;
      case SyncAction.delete:
        await _database.foldersDao.deleteFolder(change.entityId);
        break;
    }
  }
  
  /// Handle remote change notification
  Future<void> _handleRemoteChange(Map<String, dynamic> change) async {
    // Apply change immediately if not in conflict
    final syncChange = SyncChange(
      id: change['id'],
      entityType: change['entity_type'],
      entityId: change['entity_id'],
      action: SyncAction.values.firstWhere(
        (a) => a.toString() == change['action'],
      ),
      data: change['data'],
      timestamp: DateTime.parse(change['timestamp']),
      deviceId: change['device_id'],
    );
    
    await _applySingleChange(syncChange);
    
    _syncController.add(SyncEvent(
      type: SyncEventType.remoteChange,
      message: 'Remote change applied',
      data: change,
    ));
  }
  
  /// Handle conflict
  Future<void> _handleConflict(Map<String, dynamic> conflict) async {
    final conflictId = conflict['id'] as String;
    final resolution = _conflictResolutions[conflictId];
    
    if (resolution != null) {
      // Apply predetermined resolution
      await _applyConflictResolution(conflict, resolution);
    } else {
      // Notify UI to get user resolution
      _syncController.add(SyncEvent(
        type: SyncEventType.conflict,
        message: 'Conflict detected',
        data: conflict,
      ));
    }
  }
  
  /// Resolve conflicts
  Future<void> _resolveConflicts(List<dynamic> conflicts) async {
    for (final conflict in conflicts) {
      final resolution = await _getConflictResolution(conflict);
      await _applyConflictResolution(conflict, resolution);
    }
  }
  
  /// Get conflict resolution strategy
  Future<ConflictResolution> _getConflictResolution(Map<String, dynamic> conflict) async {
    // Check if we have a predetermined resolution
    final conflictId = conflict['id'] as String;
    if (_conflictResolutions.containsKey(conflictId)) {
      return _conflictResolutions[conflictId]!;
    }
    
    // Default resolution based on timestamp (last write wins)
    final localTime = DateTime.parse(conflict['local']['timestamp']);
    final remoteTime = DateTime.parse(conflict['remote']['timestamp']);
    
    return localTime.isAfter(remoteTime)
        ? ConflictResolution.keepLocal
        : ConflictResolution.keepRemote;
  }
  
  /// Apply conflict resolution
  Future<void> _applyConflictResolution(
    Map<String, dynamic> conflict,
    ConflictResolution resolution,
  ) async {
    final response = await _dio.post('/sync/resolve-conflict', data: {
      'conflict_id': conflict['id'],
      'resolution': resolution.toString(),
      'device_id': _deviceId,
    });
    
    if (response.statusCode == 200) {
      // Apply the resolved change
      final resolvedChange = response.data['change'];
      await _handleRemoteChange(resolvedChange);
    }
  }
  
  /// Set conflict resolution for future conflicts
  void setConflictResolution(String entityId, ConflictResolution resolution) {
    _conflictResolutions[entityId] = resolution;
  }
  
  /// Save last sync time
  Future<void> _saveLastSyncTime() async {
    // TODO: Save to secure storage
  }
  
  /// Get sync status
  SyncStatus get status {
    if (_isSyncing) return SyncStatus.syncing;
    if (_wsChannel != null && _wsChannel!.closeCode == null) {
      return SyncStatus.connected;
    }
    return SyncStatus.disconnected;
  }
  
  /// Get sync event stream
  Stream<SyncEvent> get events => _syncController.stream;
  
  /// Get last sync time
  DateTime? get lastSyncTime => _lastSyncTime;
  
  /// Disconnect from sync service
  void disconnect() {
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    
    _syncController.add(SyncEvent(
      type: SyncEventType.disconnected,
      message: 'Disconnected from sync server',
    ));
  }
  
  /// Dispose service
  void dispose() {
    disconnect();
    _syncController.close();
  }
}

/// Sync change model
class SyncChange {
  final String id;
  final String entityType;
  final String entityId;
  final SyncAction action;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String deviceId;
  
  SyncChange({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.data,
    required this.timestamp,
    required this.deviceId,
  });
}

/// Sync action types
enum SyncAction {
  create,
  update,
  delete,
}

/// Sync event types
enum SyncEventType {
  connected,
  disconnected,
  syncStarted,
  syncCompleted,
  remoteChange,
  conflict,
  deviceConnected,
  deviceDisconnected,
  error,
}

/// Sync event
class SyncEvent {
  final SyncEventType type;
  final String message;
  final dynamic data;
  final DateTime timestamp;
  
  SyncEvent({
    required this.type,
    required this.message,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Sync status
enum SyncStatus {
  connected,
  disconnected,
  syncing,
}

/// Conflict resolution strategies
enum ConflictResolution {
  keepLocal,
  keepRemote,
  merge,
  askUser,
}

// Extension methods for database entities
extension FeedSyncExtension on Feed {
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'description': description,
    'folder_id': folderId,
    'settings': settings,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}

extension ArticleSyncExtension on Article {
  Map<String, dynamic> toJson() => {
    'id': id,
    'feed_id': feedId,
    'title': title,
    'url': url,
    'content': content,
    'excerpt': excerpt,
    'author': author,
    'published_at': publishedAt?.toIso8601String(),
    'is_read': isRead,
    'is_starred': isStarred,
    'tags': tags,
  };
}

extension FolderSyncExtension on Folder {
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'parent_id': parentId,
    'position': position,
  };
}