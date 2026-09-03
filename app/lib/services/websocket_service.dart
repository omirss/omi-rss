import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../providers/api_feed_provider.dart';
import 'package:logger/logger.dart';

/// WebSocket service for real-time updates
class WebSocketService {
  final Ref _ref;
  final Logger _logger = Logger();
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _pingInterval = Duration(seconds: 30);
  
  WebSocketService(this._ref);
  
  bool get isConnected => _isConnected;
  
  /// Connect to WebSocket server
  Future<void> connect() async {
    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated || authState.token == null) {
      _logger.w('Cannot connect to WebSocket: Not authenticated');
      return;
    }
    
    try {
      _disconnect(); // Clean up any existing connection
      
      final wsUrl = '${ApiConfig.wsUrl}?token=${authState.token}';
      _logger.i('Connecting to WebSocket: ${ApiConfig.wsUrl}');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );
      
      // Send initial connection message
      _sendMessage({
        'type': 'connect',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _isConnected = true;
      _reconnectAttempts = 0;
      
      // Start ping timer to keep connection alive
      _startPingTimer();
      
      _logger.i('WebSocket connected successfully');
    } catch (e) {
      _logger.e('WebSocket connection error: $e');
      _scheduleReconnect();
    }
  }
  
  /// Disconnect from WebSocket
  void disconnect() {
    _logger.i('Disconnecting WebSocket');
    _disconnect();
  }
  
  void _disconnect() {
    _isConnected = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close(status.goingAway);
    _channel = null;
  }
  
  /// Send message to server
  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(jsonEncode(message));
      } catch (e) {
        _logger.e('Error sending message: $e');
      }
    }
  }
  
  /// Subscribe to feed updates
  void subscribeFeedUpdates(String feedId) {
    _sendMessage({
      'type': 'subscribe',
      'channel': 'feed:$feedId',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Unsubscribe from feed updates
  void unsubscribeFeedUpdates(String feedId) {
    _sendMessage({
      'type': 'unsubscribe',
      'channel': 'feed:$feedId',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Subscribe to all user updates
  void subscribeUserUpdates() {
    _sendMessage({
      'type': 'subscribe',
      'channel': 'user:updates',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Handle incoming messages
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      _logger.d('WebSocket message received: ${message['type']}');
      
      switch (message['type']) {
        case 'connected':
          _logger.i('WebSocket connection confirmed');
          subscribeUserUpdates(); // Auto-subscribe to user updates
          break;
          
        case 'feed_updated':
          _handleFeedUpdate(message);
          break;
          
        case 'new_articles':
          _handleNewArticles(message);
          break;
          
        case 'feed_added':
          _handleFeedAdded(message);
          break;
          
        case 'feed_deleted':
          _handleFeedDeleted(message);
          break;
          
        case 'market_update':
          _handleMarketUpdate(message);
          break;
          
        case 'ai_analysis_ready':
          _handleAIAnalysisReady(message);
          break;
          
        case 'pong':
          // Ping response received
          break;
          
        case 'error':
          _logger.e('WebSocket error: ${message['error']}');
          break;
          
        default:
          _logger.w('Unknown message type: ${message['type']}');
      }
    } catch (e) {
      _logger.e('Error handling WebSocket message: $e');
    }
  }
  
  /// Handle feed update
  void _handleFeedUpdate(Map<String, dynamic> message) {
    final feedId = message['feedId'] as String?;
    if (feedId != null) {
      // Invalidate the feed cache to trigger a refresh
      _ref.invalidate(apiFeedsProvider);
      _ref.invalidate(apiArticlesProvider(ArticleQuery(feedId: int.tryParse(feedId))));
      
      _logger.i('Feed updated: $feedId');
    }
  }
  
  /// Handle new articles
  void _handleNewArticles(Map<String, dynamic> message) {
    final feedId = message['feedId'] as String?;
    final count = message['count'] as int?;
    
    if (feedId != null) {
      // Invalidate articles cache
      _ref.invalidate(apiArticlesProvider(ArticleQuery(feedId: int.tryParse(feedId))));
      
      _logger.i('New articles available for feed $feedId: $count articles');
      
      // TODO: Show notification to user
    }
  }
  
  /// Handle feed added
  void _handleFeedAdded(Map<String, dynamic> message) {
    // Invalidate feeds cache
    _ref.invalidate(apiFeedsProvider);
    _logger.i('New feed added');
  }
  
  /// Handle feed deleted
  void _handleFeedDeleted(Map<String, dynamic> message) {
    final feedId = message['feedId'] as String?;
    if (feedId != null) {
      // Invalidate feeds cache
      _ref.invalidate(apiFeedsProvider);
      _logger.i('Feed deleted: $feedId');
    }
  }
  
  /// Handle market update
  void _handleMarketUpdate(Map<String, dynamic> message) {
    // TODO: Update market data provider when implemented
    _logger.i('Market update received');
  }
  
  /// Handle AI analysis ready
  void _handleAIAnalysisReady(Map<String, dynamic> message) {
    final articleId = message['articleId'] as String?;
    if (articleId != null) {
      // TODO: Update AI analysis provider when implemented
      _logger.i('AI analysis ready for article: $articleId');
    }
  }
  
  /// Handle connection error
  void _handleError(error) {
    _logger.e('WebSocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }
  
  /// Handle connection closed
  void _handleDone() {
    _logger.w('WebSocket connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }
  
  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.e('Max reconnection attempts reached');
      return;
    }
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectAttempts++;
      _logger.i('Attempting to reconnect (attempt $_reconnectAttempts)');
      connect();
    });
  }
  
  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_isConnected) {
        _sendMessage({
          'type': 'ping',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }
  
  /// Dispose of resources
  void dispose() {
    disconnect();
  }
}

/// WebSocket service provider
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService(ref);
  
  // Auto-connect when authenticated
  ref.listen<AuthState>(authProvider, (previous, next) {
    if (!previous!.isAuthenticated && next.isAuthenticated) {
      service.connect();
    } else if (previous.isAuthenticated && !next.isAuthenticated) {
      service.disconnect();
    }
  });
  
  // Cleanup on dispose
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});

/// WebSocket connection state provider
final webSocketConnectedProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(webSocketServiceProvider);
  
  return Stream.periodic(const Duration(seconds: 1), (_) {
    return service.isConnected;
  });
});