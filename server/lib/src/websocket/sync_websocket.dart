import 'dart:async';
import 'dart:convert';
import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../protocol/protocol.dart';
import '../services/sync_service.dart';

/// WebSocket handler for real-time sync
class SyncWebSocketHandler extends WebSocketHandler {
  final Map<int, Set<WebSocketSession>> _userSessions = {};
  final Map<String, SyncSession> _syncSessions = {};
  Timer? _pingTimer;

  @override
  Future<void> handleConnection(WebSocketSession session) async {
    session.log('New sync WebSocket connection');
    
    // Start ping timer if not already running
    _pingTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      _sendPingToAll();
    });
  }

  @override
  Future<void> handleMessage(WebSocketSession session, dynamic message) async {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'] as String;
      
      switch (type) {
        case 'auth':
          await _handleAuth(session, data);
          break;
          
        case 'sync_start':
          await _handleSyncStart(session, data);
          break;
          
        case 'sync_change':
          await _handleSyncChange(session, data);
          break;
          
        case 'sync_complete':
          await _handleSyncComplete(session, data);
          break;
          
        case 'device_info':
          await _handleDeviceInfo(session, data);
          break;
          
        case 'pong':
          _updateSessionActivity(session);
          break;
          
        default:
          session.sendMessage(jsonEncode({
            'type': 'error',
            'message': 'Unknown message type: $type',
          }));
      }
    } catch (e) {
      session.log('Error handling message: $e');
      session.sendMessage(jsonEncode({
        'type': 'error',
        'message': 'Failed to process message',
      }));
    }
  }

  @override
  Future<void> handleDisconnect(WebSocketSession session) async {
    // Remove from user sessions
    final syncSession = _syncSessions[session.sessionId];
    if (syncSession != null) {
      _userSessions[syncSession.userId]?.remove(session);
      if (_userSessions[syncSession.userId]?.isEmpty ?? false) {
        _userSessions.remove(syncSession.userId);
      }
      _syncSessions.remove(session.sessionId);
      
      // Notify other devices
      await _notifyDeviceStatus(
        syncSession.userId,
        syncSession.deviceId,
        false,
      );
    }
    
    // Stop ping timer if no more sessions
    if (_userSessions.isEmpty) {
      _pingTimer?.cancel();
      _pingTimer = null;
    }
  }

  /// Handle authentication
  Future<void> _handleAuth(WebSocketSession session, Map<String, dynamic> data) async {
    final token = data['token'] as String?;
    final deviceId = data['deviceId'] as String?;
    
    if (token == null || deviceId == null) {
      session.sendMessage(jsonEncode({
        'type': 'auth_error',
        'message': 'Token and deviceId required',
      }));
      return;
    }
    
    // Verify token and get user ID
    final userId = await _verifyToken(session, token);
    if (userId == null) {
      session.sendMessage(jsonEncode({
        'type': 'auth_error',
        'message': 'Invalid token',
      }));
      session.close();
      return;
    }
    
    // Create sync session
    final syncSession = SyncSession(
      sessionId: session.sessionId,
      userId: userId,
      deviceId: deviceId,
      connectedAt: DateTime.now(),
    );
    
    _syncSessions[session.sessionId] = syncSession;
    _userSessions.putIfAbsent(userId, () => {}).add(session);
    
    session.sendMessage(jsonEncode({
      'type': 'auth_success',
      'userId': userId,
      'deviceId': deviceId,
    }));
    
    // Notify other devices
    await _notifyDeviceStatus(userId, deviceId, true);
  }

  /// Handle sync start
  Future<void> _handleSyncStart(WebSocketSession session, Map<String, dynamic> data) async {
    final syncSession = _syncSessions[session.sessionId];
    if (syncSession == null) {
      session.sendMessage(jsonEncode({
        'type': 'error',
        'message': 'Not authenticated',
      }));
      return;
    }
    
    // Notify other devices that sync is starting
    await _broadcastToUser(
      syncSession.userId,
      {
        'type': 'sync_started',
        'deviceId': syncSession.deviceId,
        'timestamp': DateTime.now().toIso8601String(),
      },
      excludeSession: session,
    );
  }

  /// Handle sync change
  Future<void> _handleSyncChange(WebSocketSession session, Map<String, dynamic> data) async {
    final syncSession = _syncSessions[session.sessionId];
    if (syncSession == null) {
      session.sendMessage(jsonEncode({
        'type': 'error',
        'message': 'Not authenticated',
      }));
      return;
    }
    
    final change = data['change'] as Map<String, dynamic>;
    
    // Process change
    final syncService = SyncService(session);
    try {
      final syncChange = SyncChange.fromJson(change);
      await syncService.processSyncChange(syncSession.userId, syncChange);
      
      // Broadcast change to other devices
      await _broadcastToUser(
        syncSession.userId,
        {
          'type': 'remote_change',
          'change': change,
          'deviceId': syncSession.deviceId,
        },
        excludeSession: session,
      );
      
      session.sendMessage(jsonEncode({
        'type': 'change_accepted',
        'changeId': change['id'],
      }));
    } catch (e) {
      session.sendMessage(jsonEncode({
        'type': 'change_rejected',
        'changeId': change['id'],
        'reason': e.toString(),
      }));
    }
  }

  /// Handle sync complete
  Future<void> _handleSyncComplete(WebSocketSession session, Map<String, dynamic> data) async {
    final syncSession = _syncSessions[session.sessionId];
    if (syncSession == null) {
      session.sendMessage(jsonEncode({
        'type': 'error',
        'message': 'Not authenticated',
      }));
      return;
    }
    
    // Notify other devices that sync is complete
    await _broadcastToUser(
      syncSession.userId,
      {
        'type': 'sync_completed',
        'deviceId': syncSession.deviceId,
        'timestamp': DateTime.now().toIso8601String(),
      },
      excludeSession: session,
    );
  }

  /// Handle device info
  Future<void> _handleDeviceInfo(WebSocketSession session, Map<String, dynamic> data) async {
    final syncSession = _syncSessions[session.sessionId];
    if (syncSession == null) {
      session.sendMessage(jsonEncode({
        'type': 'error',
        'message': 'Not authenticated',
      }));
      return;
    }
    
    syncSession.deviceInfo = data['device'] as Map<String, dynamic>;
    
    // Get all connected devices
    final connectedDevices = _getConnectedDevices(syncSession.userId);
    
    session.sendMessage(jsonEncode({
      'type': 'connected_devices',
      'devices': connectedDevices,
    }));
  }

  /// Notify device status change
  Future<void> _notifyDeviceStatus(
    int userId,
    String deviceId,
    bool isConnected,
  ) async {
    await _broadcastToUser(
      userId,
      {
        'type': isConnected ? 'device_connected' : 'device_disconnected',
        'deviceId': deviceId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Broadcast message to all sessions of a user
  Future<void> _broadcastToUser(
    int userId,
    Map<String, dynamic> message, {
    WebSocketSession? excludeSession,
  }) async {
    final sessions = _userSessions[userId];
    if (sessions == null) return;
    
    final messageJson = jsonEncode(message);
    for (final session in sessions) {
      if (session != excludeSession) {
        session.sendMessage(messageJson);
      }
    }
  }

  /// Send change notification to user
  Future<void> sendChangeNotification(
    int userId,
    SyncChange change,
  ) async {
    await _broadcastToUser(
      userId,
      {
        'type': 'remote_change',
        'change': change.toJson(),
      },
    );
  }

  /// Send conflict notification to user
  Future<void> sendConflictNotification(
    int userId,
    String conflictId,
    Map<String, dynamic> conflict,
  ) async {
    await _broadcastToUser(
      userId,
      {
        'type': 'conflict',
        'conflictId': conflictId,
        'conflict': conflict,
      },
    );
  }

  /// Get connected devices for user
  List<Map<String, dynamic>> _getConnectedDevices(int userId) {
    final sessions = _userSessions[userId];
    if (sessions == null) return [];
    
    final devices = <Map<String, dynamic>>[];
    for (final session in sessions) {
      final syncSession = _syncSessions[session.sessionId];
      if (syncSession != null && syncSession.deviceInfo != null) {
        devices.add({
          'deviceId': syncSession.deviceId,
          'deviceInfo': syncSession.deviceInfo,
          'connectedAt': syncSession.connectedAt.toIso8601String(),
        });
      }
    }
    
    return devices;
  }

  /// Send ping to all sessions
  void _sendPingToAll() {
    final ping = jsonEncode({'type': 'ping'});
    
    for (final sessions in _userSessions.values) {
      for (final session in sessions) {
        session.sendMessage(ping);
      }
    }
  }

  /// Update session activity
  void _updateSessionActivity(WebSocketSession session) {
    final syncSession = _syncSessions[session.sessionId];
    if (syncSession != null) {
      syncSession.lastActivity = DateTime.now();
    }
  }

  /// Verify authentication token
  Future<int?> _verifyToken(WebSocketSession session, String token) async {
    try {
      // In a real implementation, verify JWT token
      // For now, parse user ID from token
      final parts = token.split('-');
      if (parts.length >= 2) {
        return int.tryParse(parts[1]);
      }
    } catch (e) {
      session.log('Token verification failed: $e');
    }
    return null;
  }
}

/// Sync session info
class SyncSession {
  final String sessionId;
  final int userId;
  final String deviceId;
  final DateTime connectedAt;
  DateTime lastActivity;
  Map<String, dynamic>? deviceInfo;

  SyncSession({
    required this.sessionId,
    required this.userId,
    required this.deviceId,
    required this.connectedAt,
  }) : lastActivity = connectedAt;
}