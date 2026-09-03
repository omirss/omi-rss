import 'dart:async';
import 'dart:convert';
import 'package:serverpod/serverpod.dart';
import '../services/collaboration_service.dart';
import '../endpoints/collaboration_endpoint.dart';

/// WebSocket handler for real-time collaboration
class CollaborationWebSocketHandler extends WebSocketHandler {
  final Map<int, Map<String, CollaborationSession>> _folderSessions = {};
  final Map<String, CollaborationSession> _sessions = {};
  Timer? _presenceTimer;

  @override
  Future<void> handleConnection(WebSocketSession session) async {
    session.log('New collaboration WebSocket connection');
    
    // Start presence timer if not already running
    _presenceTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      _updatePresence();
    });
  }

  @override
  Future<void> handleMessage(WebSocketSession session, dynamic message) async {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'] as String;
      
      switch (type) {
        case 'join_folder':
          await _handleJoinFolder(session, data);
          break;
          
        case 'leave_folder':
          await _handleLeaveFolder(session, data);
          break;
          
        case 'cursor_position':
          await _handleCursorPosition(session, data);
          break;
          
        case 'selection_change':
          await _handleSelectionChange(session, data);
          break;
          
        case 'comment_typing':
          await _handleCommentTyping(session, data);
          break;
          
        case 'annotation_preview':
          await _handleAnnotationPreview(session, data);
          break;
          
        case 'activity':
          await _handleActivity(session, data);
          break;
          
        case 'heartbeat':
          _updateSessionHeartbeat(session);
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
    final collaborationSession = _sessions[session.sessionId];
    if (collaborationSession != null) {
      // Remove from folder sessions
      for (final folderId in collaborationSession.folderIds) {
        _folderSessions[folderId]?.remove(session.sessionId);
        if (_folderSessions[folderId]?.isEmpty ?? false) {
          _folderSessions.remove(folderId);
        }
        
        // Notify folder members
        await _broadcastToFolder(
          folderId,
          {
            'type': 'member_left',
            'userId': collaborationSession.userId,
            'userName': collaborationSession.userName,
          },
          excludeSession: session,
        );
      }
      
      _sessions.remove(session.sessionId);
    }
    
    // Stop presence timer if no more sessions
    if (_sessions.isEmpty) {
      _presenceTimer?.cancel();
      _presenceTimer = null;
    }
  }

  /// Handle join folder
  Future<void> _handleJoinFolder(WebSocketSession session, Map<String, dynamic> data) async {
    final folderId = data['folderId'] as int;
    final userId = data['userId'] as int;
    final userName = data['userName'] as String;
    
    // Verify access
    final collaborationService = CollaborationService(session);
    if (!await collaborationService.hasAccess(userId, folderId)) {
      session.sendMessage(jsonEncode({
        'type': 'error',
        'message': 'Unauthorized access to folder',
      }));
      return;
    }
    
    // Create or update session
    var collaborationSession = _sessions[session.sessionId];
    if (collaborationSession == null) {
      collaborationSession = CollaborationSession(
        sessionId: session.sessionId,
        userId: userId,
        userName: userName,
        joinedAt: DateTime.now(),
      );
      _sessions[session.sessionId] = collaborationSession;
    }
    
    collaborationSession.folderIds.add(folderId);
    
    // Add to folder sessions
    _folderSessions.putIfAbsent(folderId, () => {})
        [session.sessionId] = collaborationSession;
    
    // Get current members in folder
    final members = _getActiveMembers(folderId);
    
    session.sendMessage(jsonEncode({
      'type': 'joined_folder',
      'folderId': folderId,
      'members': members,
    }));
    
    // Notify other members
    await _broadcastToFolder(
      folderId,
      {
        'type': 'member_joined',
        'userId': userId,
        'userName': userName,
      },
      excludeSession: session,
    );
  }

  /// Handle leave folder
  Future<void> _handleLeaveFolder(WebSocketSession session, Map<String, dynamic> data) async {
    final folderId = data['folderId'] as int;
    final collaborationSession = _sessions[session.sessionId];
    
    if (collaborationSession == null) return;
    
    collaborationSession.folderIds.remove(folderId);
    _folderSessions[folderId]?.remove(session.sessionId);
    
    if (_folderSessions[folderId]?.isEmpty ?? false) {
      _folderSessions.remove(folderId);
    }
    
    // Notify other members
    await _broadcastToFolder(
      folderId,
      {
        'type': 'member_left',
        'userId': collaborationSession.userId,
        'userName': collaborationSession.userName,
      },
      excludeSession: session,
    );
  }

  /// Handle cursor position update
  Future<void> _handleCursorPosition(WebSocketSession session, Map<String, dynamic> data) async {
    final collaborationSession = _sessions[session.sessionId];
    if (collaborationSession == null) return;
    
    final folderId = data['folderId'] as int;
    final articleId = data['articleId'] as int;
    final position = data['position'] as Map<String, dynamic>;
    
    if (!collaborationSession.folderIds.contains(folderId)) return;
    
    // Update session cursor
    collaborationSession.cursorPosition = CursorPosition(
      articleId: articleId,
      offset: position['offset'] as int,
      line: position['line'] as int?,
    );
    
    // Broadcast to folder members
    await _broadcastToFolder(
      folderId,
      {
        'type': 'cursor_update',
        'userId': collaborationSession.userId,
        'userName': collaborationSession.userName,
        'articleId': articleId,
        'position': position,
      },
      excludeSession: session,
    );
  }

  /// Handle selection change
  Future<void> _handleSelectionChange(WebSocketSession session, Map<String, dynamic> data) async {
    final collaborationSession = _sessions[session.sessionId];
    if (collaborationSession == null) return;
    
    final folderId = data['folderId'] as int;
    final articleId = data['articleId'] as int;
    final selection = data['selection'] as Map<String, dynamic>?;
    
    if (!collaborationSession.folderIds.contains(folderId)) return;
    
    // Update session selection
    if (selection != null) {
      collaborationSession.selection = Selection(
        articleId: articleId,
        startOffset: selection['startOffset'] as int,
        endOffset: selection['endOffset'] as int,
        text: selection['text'] as String,
      );
    } else {
      collaborationSession.selection = null;
    }
    
    // Broadcast to folder members
    await _broadcastToFolder(
      folderId,
      {
        'type': 'selection_update',
        'userId': collaborationSession.userId,
        'userName': collaborationSession.userName,
        'articleId': articleId,
        'selection': selection,
      },
      excludeSession: session,
    );
  }

  /// Handle comment typing indicator
  Future<void> _handleCommentTyping(WebSocketSession session, Map<String, dynamic> data) async {
    final collaborationSession = _sessions[session.sessionId];
    if (collaborationSession == null) return;
    
    final folderId = data['folderId'] as int;
    final articleId = data['articleId'] as int;
    final isTyping = data['isTyping'] as bool;
    
    if (!collaborationSession.folderIds.contains(folderId)) return;
    
    // Broadcast typing indicator
    await _broadcastToFolder(
      folderId,
      {
        'type': 'comment_typing',
        'userId': collaborationSession.userId,
        'userName': collaborationSession.userName,
        'articleId': articleId,
        'isTyping': isTyping,
      },
      excludeSession: session,
    );
  }

  /// Handle annotation preview
  Future<void> _handleAnnotationPreview(WebSocketSession session, Map<String, dynamic> data) async {
    final collaborationSession = _sessions[session.sessionId];
    if (collaborationSession == null) return;
    
    final folderId = data['folderId'] as int;
    final articleId = data['articleId'] as int;
    final preview = data['preview'] as Map<String, dynamic>?;
    
    if (!collaborationSession.folderIds.contains(folderId)) return;
    
    // Broadcast annotation preview
    await _broadcastToFolder(
      folderId,
      {
        'type': 'annotation_preview',
        'userId': collaborationSession.userId,
        'userName': collaborationSession.userName,
        'articleId': articleId,
        'preview': preview,
      },
      excludeSession: session,
    );
  }

  /// Handle activity update
  Future<void> _handleActivity(WebSocketSession session, Map<String, dynamic> data) async {
    final collaborationSession = _sessions[session.sessionId];
    if (collaborationSession == null) return;
    
    final folderId = data['folderId'] as int;
    final activity = data['activity'] as Map<String, dynamic>;
    
    if (!collaborationSession.folderIds.contains(folderId)) return;
    
    // Broadcast activity to folder members
    await _broadcastToFolder(
      folderId,
      {
        'type': 'activity',
        'activity': activity,
      },
    );
  }

  /// Broadcast to folder members
  Future<void> _broadcastToFolder(
    int folderId,
    Map<String, dynamic> message, {
    WebSocketSession? excludeSession,
  }) async {
    final sessions = _folderSessions[folderId];
    if (sessions == null) return;
    
    final messageJson = jsonEncode(message);
    
    for (final entry in sessions.entries) {
      final sessionId = entry.key;
      final session = _findWebSocketSession(sessionId);
      
      if (session != null && session != excludeSession) {
        session.sendMessage(messageJson);
      }
    }
  }

  /// Send new comment notification
  Future<void> sendCommentNotification(
    int folderId,
    ArticleComment comment,
  ) async {
    await _broadcastToFolder(
      folderId,
      {
        'type': 'new_comment',
        'comment': comment.toJson(),
      },
    );
  }

  /// Send new annotation notification
  Future<void> sendAnnotationNotification(
    int folderId,
    ArticleAnnotation annotation,
  ) async {
    await _broadcastToFolder(
      folderId,
      {
        'type': 'new_annotation',
        'annotation': annotation.toJson(),
      },
    );
  }

  /// Send folder update notification
  Future<void> sendFolderUpdateNotification(
    int folderId,
    Map<String, dynamic> update,
  ) async {
    await _broadcastToFolder(
      folderId,
      {
        'type': 'folder_update',
        'update': update,
      },
    );
  }

  /// Get active members in folder
  List<Map<String, dynamic>> _getActiveMembers(int folderId) {
    final sessions = _folderSessions[folderId];
    if (sessions == null) return [];
    
    return sessions.values.map((session) => {
      'userId': session.userId,
      'userName': session.userName,
      'joinedAt': session.joinedAt.toIso8601String(),
      'cursorPosition': session.cursorPosition?.toJson(),
      'selection': session.selection?.toJson(),
    }).toList();
  }

  /// Update presence for all sessions
  void _updatePresence() {
    final now = DateTime.now();
    final timeout = const Duration(seconds: 30);
    
    // Check for inactive sessions
    final inactiveSessions = <String>[];
    for (final entry in _sessions.entries) {
      if (now.difference(entry.value.lastHeartbeat) > timeout) {
        inactiveSessions.add(entry.key);
      }
    }
    
    // Remove inactive sessions
    for (final sessionId in inactiveSessions) {
      final session = _findWebSocketSession(sessionId);
      if (session != null) {
        session.close();
      }
    }
  }

  /// Update session heartbeat
  void _updateSessionHeartbeat(WebSocketSession session) {
    final collaborationSession = _sessions[session.sessionId];
    if (collaborationSession != null) {
      collaborationSession.lastHeartbeat = DateTime.now();
    }
  }

  /// Find WebSocket session by ID
  WebSocketSession? _findWebSocketSession(String sessionId) {
    // This would need to be implemented based on Serverpod's session management
    // For now, return null
    return null;
  }
}

/// Collaboration session info
class CollaborationSession {
  final String sessionId;
  final int userId;
  final String userName;
  final DateTime joinedAt;
  final Set<int> folderIds = {};
  DateTime lastHeartbeat;
  CursorPosition? cursorPosition;
  Selection? selection;

  CollaborationSession({
    required this.sessionId,
    required this.userId,
    required this.userName,
    required this.joinedAt,
  }) : lastHeartbeat = joinedAt;
}

/// Cursor position
class CursorPosition {
  final int articleId;
  final int offset;
  final int? line;

  CursorPosition({
    required this.articleId,
    required this.offset,
    this.line,
  });

  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'offset': offset,
    if (line != null) 'line': line,
  };
}

/// Text selection
class Selection {
  final int articleId;
  final int startOffset;
  final int endOffset;
  final String text;

  Selection({
    required this.articleId,
    required this.startOffset,
    required this.endOffset,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'startOffset': startOffset,
    'endOffset': endOffset,
    'text': text,
  };
}