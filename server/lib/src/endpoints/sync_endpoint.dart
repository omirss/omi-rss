import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../protocol/protocol.dart';
import '../services/sync_service.dart';
import '../services/encryption_service.dart';

class SyncEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  /// Get sync status for device
  Future<SyncStatus> getSyncStatus(Session session, String deviceId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final lastSync = await _getLastSyncTime(session, userId, deviceId);
    final pendingChanges = await _getPendingChangesCount(session, userId, deviceId);

    return SyncStatus(
      deviceId: deviceId,
      lastSyncTime: lastSync,
      pendingChanges: pendingChanges,
      syncEnabled: true,
    );
  }

  /// Submit local changes and get remote changes
  Future<SyncResult> syncChanges(
    Session session,
    String deviceId,
    List<SyncChange> localChanges, {
    DateTime? lastSyncTime,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final syncService = SyncService(session);
    
    // Process local changes
    final conflicts = <SyncConflict>[];
    final processedChanges = <String>[];
    
    await session.db.transaction((transaction) async {
      for (final change in localChanges) {
        try {
          // Check for conflicts
          final conflict = await syncService.checkConflict(
            userId,
            change,
            transaction: transaction,
          );
          
          if (conflict != null) {
            conflicts.add(conflict);
          } else {
            // Apply change
            await syncService.applyChange(
              userId,
              change,
              transaction: transaction,
            );
            processedChanges.add(change.id);
            
            // Record sync change
            await session.db.insertRow<SyncChange>(
              change..userId = userId,
              transaction: transaction,
            );
          }
        } catch (e) {
          session.log('Error processing sync change ${change.id}: $e');
        }
      }
    });

    // Get remote changes
    final remoteChanges = await syncService.getRemoteChanges(
      userId,
      deviceId,
      lastSyncTime ?? DateTime.now().subtract(const Duration(days: 30)),
    );

    // Update last sync time
    await _updateLastSyncTime(session, userId, deviceId);

    return SyncResult(
      processedChanges: processedChanges,
      remoteChanges: remoteChanges,
      conflicts: conflicts,
      serverTime: DateTime.now(),
    );
  }

  /// Resolve sync conflict
  Future<void> resolveConflict(
    Session session,
    String conflictId,
    ConflictResolution resolution,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final syncService = SyncService(session);
    await syncService.resolveConflict(userId, conflictId, resolution);
  }

  /// Get encryption key for E2E sync
  Future<EncryptionKeyInfo> getEncryptionKey(Session session) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final encryptionService = EncryptionService();
    
    // Get or create user encryption key
    final userKey = await _getUserEncryptionKey(session, userId);
    
    if (userKey == null) {
      // Generate new key
      final newKey = encryptionService.generateKey();
      await _saveUserEncryptionKey(session, userId, newKey);
      
      return EncryptionKeyInfo(
        keyId: newKey.id,
        publicKey: newKey.publicKey,
        algorithm: 'AES-256-GCM',
        createdAt: DateTime.now(),
      );
    }

    return userKey;
  }

  /// Register device for sync
  Future<DeviceInfo> registerDevice(
    Session session,
    String deviceId,
    String deviceName,
    String platform,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Check if device already registered
    var device = await session.db.findFirstRow<UserDevice>(
      where: (t) => t.userId.equals(userId) & t.deviceId.equals(deviceId),
    );

    if (device == null) {
      // Register new device
      device = UserDevice(
        userId: userId,
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        lastActiveAt: DateTime.now(),
        createdAt: DateTime.now(),
      );
      
      device = await session.db.insertRow<UserDevice>(device);
    } else {
      // Update device info
      device.deviceName = deviceName;
      device.platform = platform;
      device.lastActiveAt = DateTime.now();
      
      device = await session.db.updateRow<UserDevice>(device);
    }

    return DeviceInfo(
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      platform: device.platform,
      lastActiveAt: device.lastActiveAt,
      isCurrentDevice: true,
    );
  }

  /// Get registered devices
  Future<List<DeviceInfo>> getDevices(Session session) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final devices = await session.db.find<UserDevice>(
      where: (t) => t.userId.equals(userId),
      orderBy: UserDevice.t.lastActiveAt.descending,
    );

    return devices.map((d) => DeviceInfo(
      deviceId: d.deviceId,
      deviceName: d.deviceName,
      platform: d.platform,
      lastActiveAt: d.lastActiveAt,
      isCurrentDevice: false, // Would need to check against current session
    )).toList();
  }

  /// Remove device
  Future<void> removeDevice(Session session, String deviceId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    await session.db.deleteWhere<UserDevice>(
      where: (t) => t.userId.equals(userId) & t.deviceId.equals(deviceId),
    );

    // Also remove sync changes from this device
    await session.db.deleteWhere<SyncChange>(
      where: (t) => t.userId.equals(userId) & t.deviceId.equals(deviceId),
    );
  }

  /// Get last sync time for device
  Future<DateTime?> _getLastSyncTime(
    Session session,
    int userId,
    String deviceId,
  ) async {
    final lastSync = await session.db.findFirstRow<SyncChange>(
      where: (t) => t.userId.equals(userId) & t.deviceId.equals(deviceId),
      orderBy: SyncChange.t.timestamp.descending,
    );
    
    return lastSync?.timestamp;
  }

  /// Update last sync time
  Future<void> _updateLastSyncTime(
    Session session,
    int userId,
    String deviceId,
  ) async {
    final device = await session.db.findFirstRow<UserDevice>(
      where: (t) => t.userId.equals(userId) & t.deviceId.equals(deviceId),
    );
    
    if (device != null) {
      device.lastActiveAt = DateTime.now();
      await session.db.updateRow<UserDevice>(device);
    }
  }

  /// Get pending changes count
  Future<int> _getPendingChangesCount(
    Session session,
    int userId,
    String deviceId,
  ) async {
    final lastSync = await _getLastSyncTime(session, userId, deviceId);
    if (lastSync == null) return 0;
    
    return await session.db.count<SyncChange>(
      where: (t) => t.userId.equals(userId) & 
          t.deviceId.notEquals(deviceId) &
          t.timestamp.afterThan(lastSync),
    );
  }

  /// Get user encryption key
  Future<EncryptionKeyInfo?> _getUserEncryptionKey(
    Session session,
    int userId,
  ) async {
    final settings = await session.db.findFirstRow<UserSettings>(
      where: (t) => t.userId.equals(userId),
    );
    
    if (settings?.encryptionKeyId == null) {
      return null;
    }
    
    return EncryptionKeyInfo(
      keyId: settings!.encryptionKeyId!,
      publicKey: settings.encryptionPublicKey!,
      algorithm: 'AES-256-GCM',
      createdAt: settings.createdAt,
    );
  }

  /// Save user encryption key
  Future<void> _saveUserEncryptionKey(
    Session session,
    int userId,
    EncryptionKey key,
  ) async {
    var settings = await session.db.findFirstRow<UserSettings>(
      where: (t) => t.userId.equals(userId),
    );
    
    if (settings == null) {
      settings = UserSettings(
        userId: userId,
        encryptionKeyId: key.id,
        encryptionPublicKey: key.publicKey,
        preferences: {},
      );
      await session.db.insertRow<UserSettings>(settings);
    } else {
      settings.encryptionKeyId = key.id;
      settings.encryptionPublicKey = key.publicKey;
      settings.updatedAt = DateTime.now();
      await session.db.updateRow<UserSettings>(settings);
    }
  }
}

// Supporting classes
class SyncStatus {
  final String deviceId;
  final DateTime? lastSyncTime;
  final int pendingChanges;
  final bool syncEnabled;

  SyncStatus({
    required this.deviceId,
    this.lastSyncTime,
    required this.pendingChanges,
    required this.syncEnabled,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'lastSyncTime': lastSyncTime?.toIso8601String(),
    'pendingChanges': pendingChanges,
    'syncEnabled': syncEnabled,
  };
}

class SyncResult {
  final List<String> processedChanges;
  final List<SyncChange> remoteChanges;
  final List<SyncConflict> conflicts;
  final DateTime serverTime;

  SyncResult({
    required this.processedChanges,
    required this.remoteChanges,
    required this.conflicts,
    required this.serverTime,
  });

  Map<String, dynamic> toJson() => {
    'processedChanges': processedChanges,
    'remoteChanges': remoteChanges.map((c) => c.toJson()).toList(),
    'conflicts': conflicts.map((c) => c.toJson()).toList(),
    'serverTime': serverTime.toIso8601String(),
  };
}

class SyncConflict {
  final String id;
  final String entityType;
  final String entityId;
  final SyncChange localChange;
  final SyncChange remoteChange;

  SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.localChange,
    required this.remoteChange,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType,
    'entityId': entityId,
    'localChange': localChange.toJson(),
    'remoteChange': remoteChange.toJson(),
  };
}

enum ConflictResolution {
  keepLocal,
  keepRemote,
  merge,
}

class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime lastActiveAt;
  final bool isCurrentDevice;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.lastActiveAt,
    required this.isCurrentDevice,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'lastActiveAt': lastActiveAt.toIso8601String(),
    'isCurrentDevice': isCurrentDevice,
  };
}

class EncryptionKeyInfo {
  final String keyId;
  final String publicKey;
  final String algorithm;
  final DateTime createdAt;

  EncryptionKeyInfo({
    required this.keyId,
    required this.publicKey,
    required this.algorithm,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'keyId': keyId,
    'publicKey': publicKey,
    'algorithm': algorithm,
    'createdAt': createdAt.toIso8601String(),
  };
}

class EncryptionKey {
  final String id;
  final String publicKey;
  final String privateKey;

  EncryptionKey({
    required this.id,
    required this.publicKey,
    required this.privateKey,
  });
}

// UserDevice model
class UserDevice extends TableRow {
  int? id;
  int userId;
  String deviceId;
  String deviceName;
  String platform;
  DateTime lastActiveAt;
  DateTime createdAt;

  UserDevice({
    this.id,
    required this.userId,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.lastActiveAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static final t = UserDeviceTable();

  @override
  String get tableName => 'user_devices';

  factory UserDevice.fromJson(Map<String, dynamic> json) {
    return UserDevice(
      id: json['id'] as int?,
      userId: json['userId'] as int,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      platform: json['platform'] as String,
      lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
      'last_active_at': lastActiveAt,
      'created_at': createdAt,
    };
  }

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'device_id':
        deviceId = value;
        return;
      case 'device_name':
        deviceName = value;
        return;
      case 'platform':
        platform = value;
        return;
      case 'last_active_at':
        lastActiveAt = value;
        return;
      case 'created_at':
        createdAt = value;
        return;
      default:
        throw UnimplementedError();
    }
  }
}

class UserDeviceTable extends Table {
  UserDeviceTable() : super(tableName: 'user_devices');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final userId = ColumnInt('user_id', this);
  late final deviceId = ColumnString('device_id', this);
  late final deviceName = ColumnString('device_name', this);
  late final platform = ColumnString('platform', this);
  late final lastActiveAt = ColumnDateTime('last_active_at', this);
  late final createdAt = ColumnDateTime('created_at', this, hasDefault: true);

  @override
  List<Column> get columns => [
    id,
    userId,
    deviceId,
    deviceName,
    platform,
    lastActiveAt,
    createdAt,
  ];
}