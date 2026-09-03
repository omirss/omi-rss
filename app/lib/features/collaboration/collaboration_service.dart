import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../core/constants/api_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/api_service.dart';

class CollaborationSession {
  final String id;
  final String folderId;
  final String hostUserId;
  final String type;
  final String? articleId;
  final List<String> participants;
  final DateTime startedAt;
  final bool isActive;

  CollaborationSession({
    required this.id,
    required this.folderId,
    required this.hostUserId,
    required this.type,
    this.articleId,
    required this.participants,
    required this.startedAt,
    this.isActive = true,
  });

  factory CollaborationSession.fromJson(Map<String, dynamic> json) {
    return CollaborationSession(
      id: json['id'],
      folderId: json['folderId'],
      hostUserId: json['hostUserId'],
      type: json['type'],
      articleId: json['articleId'],
      participants: List<String>.from(json['participants']),
      startedAt: DateTime.parse(json['startedAt']),
      isActive: json['isActive'] ?? true,
    );
  }
}

class UserPresence {
  final String userId;
  final String userName;
  final String? userAvatar;
  final String status;
  final DateTime lastActivity;
  final String? currentArticleId;
  final CursorPosition? cursorPosition;

  UserPresence({
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.status,
    required this.lastActivity,
    this.currentArticleId,
    this.cursorPosition,
  });

  factory UserPresence.fromJson(Map<String, dynamic> json) {
    return UserPresence(
      userId: json['userId'],
      userName: json['userName'],
      userAvatar: json['userAvatar'],
      status: json['status'],
      lastActivity: DateTime.parse(json['lastActivity']),
      currentArticleId: json['currentArticleId'],
      cursorPosition: json['cursorPosition'] != null
          ? CursorPosition.fromJson(json['cursorPosition'])
          : null,
    );
  }
}

class CursorPosition {
  final String articleId;
  final int paragraph;
  final int offset;

  CursorPosition({
    required this.articleId,
    required this.paragraph,
    required this.offset,
  });

  factory CursorPosition.fromJson(Map<String, dynamic> json) {
    return CursorPosition(
      articleId: json['articleId'],
      paragraph: json['paragraph'],
      offset: json['offset'],
    );
  }

  Map<String, dynamic> toJson() => {
        'articleId': articleId,
        'paragraph': paragraph,
        'offset': offset,
      };
}

class Annotation {
  final String id;
  final String articleId;
  final String userId;
  final String sessionId;
  final String type;
  final String? content;
  final String? color;
  final String? emoji;
  final AnnotationRange? range;
  final DateTime createdAt;
  final DateTime updatedAt;

  Annotation({
    required this.id,
    required this.articleId,
    required this.userId,
    required this.sessionId,
    required this.type,
    this.content,
    this.color,
    this.emoji,
    this.range,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Annotation.fromJson(Map<String, dynamic> json) {
    return Annotation(
      id: json['id'],
      articleId: json['articleId'],
      userId: json['userId'],
      sessionId: json['sessionId'],
      type: json['type'],
      content: json['content'],
      color: json['color'],
      emoji: json['emoji'],
      range: json['range'] != null
          ? AnnotationRange.fromJson(json['range'])
          : null,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

class AnnotationRange {
  final int start;
  final int end;
  final int paragraphIndex;

  AnnotationRange({
    required this.start,
    required this.end,
    required this.paragraphIndex,
  });

  factory AnnotationRange.fromJson(Map<String, dynamic> json) {
    return AnnotationRange(
      start: json['start'],
      end: json['end'],
      paragraphIndex: json['paragraphIndex'],
    );
  }

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'paragraphIndex': paragraphIndex,
      };
}

class CollaborationService extends ChangeNotifier {
  final AuthService _authService;
  final ApiService _apiService;
  IO.Socket? _socket;
  
  CollaborationSession? _currentSession;
  final Map<String, UserPresence> _folderPresence = {};
  final Map<String, List<Annotation>> _articleAnnotations = {};
  final Map<String, double> _readingProgress = {};
  bool _isConnected = false;

  CollaborationSession? get currentSession => _currentSession;
  Map<String, UserPresence> get folderPresence => _folderPresence;
  bool get isConnected => _isConnected;

  CollaborationService({
    required AuthService authService,
    required ApiService apiService,
  })  : _authService = authService,
        _apiService = apiService;

  Future<void> connect() async {
    if (_socket != null && _socket!.connected) {
      return;
    }

    final token = await _authService.getToken();
    if (token == null) return;

    _socket = IO.io(
      ApiConstants.baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      notifyListeners();
      debugPrint('Collaboration service connected');
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      notifyListeners();
      debugPrint('Collaboration service disconnected');
    });

    _setupSocketListeners();
    _socket!.connect();
  }

  void _setupSocketListeners() {
    if (_socket == null) return;

    // Session events
    _socket!.on('collaboration:session-started', (data) {
      debugPrint('Session started: $data');
      notifyListeners();
    });

    _socket!.on('collaboration:user-joined-session', (data) {
      debugPrint('User joined session: ${data['userId']}');
      if (_currentSession != null) {
        _currentSession!.participants.add(data['userId']);
        notifyListeners();
      }
    });

    _socket!.on('collaboration:user-left-session', (data) {
      debugPrint('User left session: ${data['userId']}');
      if (_currentSession != null) {
        _currentSession!.participants.remove(data['userId']);
        notifyListeners();
      }
    });

    _socket!.on('collaboration:session-ended', (data) {
      debugPrint('Session ended: ${data['sessionId']}');
      if (_currentSession?.id == data['sessionId']) {
        _currentSession = null;
        notifyListeners();
      }
    });

    // Presence events
    _socket!.on('collaboration:presence-update', (data) {
      final presence = UserPresence.fromJson(data['presence']);
      _folderPresence[data['userId']] = presence;
      notifyListeners();
    });

    // Annotation events
    _socket!.on('collaboration:annotation-created', (data) {
      final annotation = Annotation.fromJson(data['annotation']);
      _articleAnnotations.putIfAbsent(annotation.articleId, () => []);
      _articleAnnotations[annotation.articleId]!.add(annotation);
      notifyListeners();
    });

    _socket!.on('collaboration:annotation-updated', (data) {
      final annotationId = data['annotationId'];
      final updates = data['updates'];
      
      _articleAnnotations.forEach((articleId, annotations) {
        final index = annotations.indexWhere((a) => a.id == annotationId);
        if (index != -1) {
          // Update annotation with new data
          final old = annotations[index];
          annotations[index] = Annotation(
            id: old.id,
            articleId: old.articleId,
            userId: old.userId,
            sessionId: old.sessionId,
            type: old.type,
            content: updates['content'] ?? old.content,
            color: updates['color'] ?? old.color,
            emoji: updates['emoji'] ?? old.emoji,
            range: old.range,
            createdAt: old.createdAt,
            updatedAt: DateTime.now(),
          );
          notifyListeners();
        }
      });
    });

    _socket!.on('collaboration:annotation-deleted', (data) {
      final annotationId = data['annotationId'];
      _articleAnnotations.forEach((articleId, annotations) {
        annotations.removeWhere((a) => a.id == annotationId);
      });
      notifyListeners();
    });

    // Reading progress
    _socket!.on('collaboration:reading-progress', (data) {
      _readingProgress[data['userId']] = data['progress'].toDouble();
      notifyListeners();
    });

    // Cursor updates
    _socket!.on('collaboration:cursor-update', (data) {
      final userId = data['userId'];
      if (_folderPresence.containsKey(userId)) {
        final presence = _folderPresence[userId]!;
        _folderPresence[userId] = UserPresence(
          userId: presence.userId,
          userName: presence.userName,
          userAvatar: presence.userAvatar,
          status: presence.status,
          lastActivity: DateTime.now(),
          currentArticleId: presence.currentArticleId,
          cursorPosition: data['cursorPosition'] != null
              ? CursorPosition.fromJson(data['cursorPosition'])
              : null,
        );
        notifyListeners();
      }
    });

    // Typing indicators
    _socket!.on('collaboration:typing-update', (data) {
      // Handle typing indicators
      notifyListeners();
    });

    // Session invites
    _socket!.on('collaboration:session-invite', (data) {
      // Handle session invitations
      debugPrint('Received session invite: ${data['sessionId']}');
      notifyListeners();
    });
  }

  Future<CollaborationSession> createSession(
    String folderId,
    String type, {
    String? articleId,
  }) async {
    final response = await _apiService.post(
      '/collaboration/sessions',
      body: {
        'folderId': folderId,
        'type': type,
        if (articleId != null) 'articleId': articleId,
      },
    );

    _currentSession = CollaborationSession.fromJson(response['data']);
    
    // Join socket room
    _socket?.emit('collab:join-session', _currentSession!.id);
    
    notifyListeners();
    return _currentSession!;
  }

  Future<bool> joinSession(String sessionId) async {
    final response = await _apiService.post(
      '/collaboration/sessions/$sessionId/join',
    );

    if (response['success']) {
      // Join socket room
      _socket?.emit('collab:join-session', sessionId);
      return true;
    }
    return false;
  }

  Future<void> leaveSession(String sessionId) async {
    await _apiService.post('/collaboration/sessions/$sessionId/leave');
    
    // Leave socket room
    _socket?.emit('collab:leave-session', sessionId);
    
    if (_currentSession?.id == sessionId) {
      _currentSession = null;
      notifyListeners();
    }
  }

  Future<void> updatePresence(
    String folderId,
    String status, {
    String? currentArticleId,
    CursorPosition? cursorPosition,
  }) async {
    await _apiService.post(
      '/collaboration/presence',
      body: {
        'folderId': folderId,
        'status': status,
        if (currentArticleId != null) 'currentArticleId': currentArticleId,
        if (cursorPosition != null) 'cursorPosition': cursorPosition.toJson(),
      },
    );
  }

  Future<List<UserPresence>> getFolderPresence(String folderId) async {
    final response = await _apiService.get(
      '/collaboration/folders/$folderId/presence',
    );

    final presenceList = (response['data'] as List)
        .map((p) => UserPresence.fromJson(p))
        .toList();

    // Update local cache
    _folderPresence.clear();
    for (final presence in presenceList) {
      _folderPresence[presence.userId] = presence;
    }
    notifyListeners();

    return presenceList;
  }

  Future<Annotation> createAnnotation(
    String sessionId,
    String articleId,
    String type, {
    String? content,
    String? color,
    String? emoji,
    AnnotationRange? range,
  }) async {
    final response = await _apiService.post(
      '/collaboration/annotations',
      body: {
        'sessionId': sessionId,
        'articleId': articleId,
        'type': type,
        if (content != null) 'content': content,
        if (color != null) 'color': color,
        if (emoji != null) 'emoji': emoji,
        if (range != null) 'range': range.toJson(),
      },
    );

    final annotation = Annotation.fromJson(response['data']);
    
    // Emit to socket for real-time update
    _socket?.emit('collab:annotation', {
      'sessionId': sessionId,
      'type': 'created',
      'annotation': response['data'],
    });

    return annotation;
  }

  Future<List<Annotation>> getArticleAnnotations(String articleId) async {
    final response = await _apiService.get(
      '/collaboration/articles/$articleId/annotations',
    );

    final annotations = (response['data'] as List)
        .map((a) => Annotation.fromJson(a))
        .toList();

    _articleAnnotations[articleId] = annotations;
    notifyListeners();

    return annotations;
  }

  void updateCursorPosition(
    String folderId,
    CursorPosition position,
  ) {
    _socket?.emit('collab:cursor', {
      'folderId': folderId,
      'cursorPosition': position.toJson(),
    });
  }

  void broadcastReadingProgress(
    String sessionId,
    String articleId,
    double progress,
  ) {
    _apiService.post(
      '/collaboration/reading-progress',
      body: {
        'sessionId': sessionId,
        'articleId': articleId,
        'progress': progress,
      },
    );
  }

  Future<Map<String, double>> getSessionReadingProgress(String sessionId) async {
    final response = await _apiService.get(
      '/collaboration/sessions/$sessionId/reading-progress',
    );

    final progress = Map<String, double>.from(
      (response['data'] as Map).map((k, v) => MapEntry(k, v.toDouble())),
    );

    _readingProgress.clear();
    _readingProgress.addAll(progress);
    notifyListeners();

    return progress;
  }

  void joinFolderRoom(String folderId) {
    _socket?.emit('collab:join-folder', folderId);
  }

  void leaveFolderRoom(String folderId) {
    _socket?.emit('collab:leave-folder', folderId);
  }

  void sendTypingIndicator(String sessionId, bool isTyping) {
    _socket?.emit('collab:typing', {
      'sessionId': sessionId,
      'isTyping': isTyping,
    });
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }
}