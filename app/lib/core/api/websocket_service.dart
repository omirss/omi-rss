import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:rss_glassmorphism_reader/core/api/api_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final websocketServiceProvider = Provider((ref) => WebSocketService());

class WebSocketService {
  WebSocketChannel? _channel;
  final _storage = const FlutterSecureStorage();
  
  // Stream controllers
  final _connectionStateController = StreamController<ConnectionState>.broadcast();
  final _messageController = StreamController<WebSocketMessage>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  
  // Subscriptions
  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, Function(Map<String, dynamic>)> _handlers = {};
  
  // Connection state
  bool _isConnected = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  
  // Streams
  Stream<ConnectionState> get connectionStream => _connectionStateController.stream;
  Stream<WebSocketMessage> get messageStream => _messageController.stream;
  Stream<String> get errorStream => _errorController.stream;
  
  bool get isConnected => _isConnected;
  
  // Connect to WebSocket server
  Future<void> connect() async {
    if (_isConnected) return;
    
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) {
        throw Exception('No auth token found');
      }
      
      final uri = Uri.parse('${ApiConfig.wsUrl}?token=$token');
      _channel = WebSocketChannel.connect(uri);
      
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );
      
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStateController.add(ConnectionState.connected);
      
      // Start ping timer
      _startPingTimer();
      
      // Subscribe to default channels
      await _subscribeToDefaults();
      
    } catch (e) {
      _handleError(e);
    }
  }
  
  // Disconnect from WebSocket server
  Future<void> disconnect() async {
    _cancelTimers();
    
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    
    _isConnected = false;
    _connectionStateController.add(ConnectionState.disconnected);
    
    // Clear subscriptions
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _handlers.clear();
  }
  
  // Send message
  void send(String type, Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      _errorController.add('Not connected to server');
      return;
    }
    
    final message = {
      'type': type,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    _channel!.sink.add(jsonEncode(message));
  }
  
  // Subscribe to events
  void subscribe(String event, Function(Map<String, dynamic>) handler) {
    _handlers[event] = handler;
    
    // Send subscription request
    send('subscribe', {'event': event});
  }
  
  // Unsubscribe from events
  void unsubscribe(String event) {
    _handlers.remove(event);
    
    // Send unsubscription request
    send('unsubscribe', {'event': event});
  }
  
  // Handle incoming messages
  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data);
      final message = WebSocketMessage.fromJson(json);
      
      // Handle system messages
      switch (message.type) {
        case 'ping':
          send('pong', {});
          return;
        case 'error':
          _errorController.add(message.data['message'] ?? 'Unknown error');
          return;
        case 'subscribed':
          print('Subscribed to ${message.data['event']}');
          return;
        case 'unsubscribed':
          print('Unsubscribed from ${message.data['event']}');
          return;
      }
      
      // Emit to general stream
      _messageController.add(message);
      
      // Call specific handler if exists
      final handler = _handlers[message.type];
      if (handler != null) {
        handler(message.data);
      }
      
    } catch (e) {
      _errorController.add('Failed to parse message: $e');
    }
  }
  
  // Handle errors
  void _handleError(dynamic error) {
    _errorController.add(error.toString());
    _connectionStateController.add(ConnectionState.error);
    
    // Attempt reconnection
    _scheduleReconnect();
  }
  
  // Handle disconnect
  void _handleDisconnect() {
    _isConnected = false;
    _connectionStateController.add(ConnectionState.disconnected);
    
    // Cancel ping timer
    _pingTimer?.cancel();
    
    // Attempt reconnection
    _scheduleReconnect();
  }
  
  // Schedule reconnection
  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    
    _reconnectAttempts++;
    final delay = _calculateReconnectDelay();
    
    _connectionStateController.add(ConnectionState.reconnecting);
    
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      _reconnectTimer = null;
      await connect();
    });
  }
  
  // Calculate reconnect delay with exponential backoff
  int _calculateReconnectDelay() {
    const baseDelay = 1;
    const maxDelay = 60;
    
    final delay = baseDelay * (1 << (_reconnectAttempts - 1));
    return delay.clamp(baseDelay, maxDelay);
  }
  
  // Start ping timer
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      send('ping', {});
    });
  }
  
  // Cancel timers
  void _cancelTimers() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
  }
  
  // Subscribe to default channels
  Future<void> _subscribeToDefaults() async {
    // Subscribe to user events
    subscribe('user.updated', (data) {
      // Handle user update
    });
    
    // Subscribe to feed events
    subscribe('feed.new_articles', (data) {
      // Handle new articles
    });
    
    subscribe('feed.updated', (data) {
      // Handle feed update
    });
    
    // Subscribe to sync events
    subscribe('sync.request', (data) {
      // Handle sync request
    });
  }
  
  // Dispose
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _messageController.close();
    _errorController.close();
  }
}

// WebSocket message model
class WebSocketMessage {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  WebSocketMessage({
    required this.type,
    required this.data,
    required this.timestamp,
  });
  
  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };
}

// Connection states
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

// Real-time event types
class WebSocketEvents {
  // User events
  static const userUpdated = 'user.updated';
  static const userDeleted = 'user.deleted';
  
  // Feed events
  static const feedAdded = 'feed.added';
  static const feedUpdated = 'feed.updated';
  static const feedDeleted = 'feed.deleted';
  static const feedNewArticles = 'feed.new_articles';
  static const feedError = 'feed.error';
  
  // Article events
  static const articleRead = 'article.read';
  static const articleSaved = 'article.saved';
  static const articleDeleted = 'article.deleted';
  
  // Category events
  static const categoryAdded = 'category.added';
  static const categoryUpdated = 'category.updated';
  static const categoryDeleted = 'category.deleted';
  
  // Sync events
  static const syncRequest = 'sync.request';
  static const syncData = 'sync.data';
  static const syncComplete = 'sync.complete';
  static const syncError = 'sync.error';
  
  // Notification events
  static const notification = 'notification';
  static const alert = 'alert';
}

// WebSocket providers
final wsConnectionStateProvider = StreamProvider<ConnectionState>((ref) {
  final ws = ref.watch(websocketServiceProvider);
  return ws.connectionStream;
});

final wsMessageProvider = StreamProvider<WebSocketMessage>((ref) {
  final ws = ref.watch(websocketServiceProvider);
  return ws.messageStream;
});

final wsErrorProvider = StreamProvider<String>((ref) {
  final ws = ref.watch(websocketServiceProvider);
  return ws.errorStream;
});