import 'dart:convert';
import 'package:serverpod/serverpod.dart';

/// WebSocket message handler
class WebSocketHandler {
  final Map<int, Set<String>> _userSubscriptions = {};
  final Map<String, Set<int>> _channelSubscriptions = {};
  
  /// Handle incoming WebSocket message
  Future<void> handleMessage(
    Session session,
    Map<String, dynamic> message,
  ) async {
    final type = message['type'] as String?;
    if (type == null) return;
    
    try {
      switch (type) {
        case 'connect':
          await _handleConnect(session);
          break;
          
        case 'subscribe':
          await _handleSubscribe(session, message);
          break;
          
        case 'unsubscribe':
          await _handleUnsubscribe(session, message);
          break;
          
        case 'ping':
          await _handlePing(session);
          break;
          
        default:
          await _sendError(session, 'Unknown message type: $type');
      }
    } catch (e) {
      session.log('WebSocket error: $e', level: LogLevel.error);
      await _sendError(session, 'Internal error');
    }
  }
  
  /// Handle client connection
  Future<void> _handleConnect(Session session) async {
    final userId = session.auth?.userId;
    if (userId == null) {
      await _sendError(session, 'Not authenticated');
      return;
    }
    
    // Initialize user subscriptions
    _userSubscriptions[userId] ??= {};
    
    // Send connection confirmation
    await _sendMessage(session, {
      'type': 'connected',
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    session.log('WebSocket connected for user: $userId');
  }
  
  /// Handle subscription request
  Future<void> _handleSubscribe(Session session, Map<String, dynamic> message) async {
    final userId = session.auth?.userId;
    if (userId == null) return;
    
    final channel = message['channel'] as String?;
    if (channel == null) {
      await _sendError(session, 'Channel required');
      return;
    }
    
    // Add subscription
    _userSubscriptions[userId]?.add(channel);
    _channelSubscriptions[channel] ??= {};
    _channelSubscriptions[channel]!.add(userId);
    
    await _sendMessage(session, {
      'type': 'subscribed',
      'channel': channel,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    session.log('User $userId subscribed to channel: $channel');
  }
  
  /// Handle unsubscription request
  Future<void> _handleUnsubscribe(Session session, Map<String, dynamic> message) async {
    final userId = session.auth?.userId;
    if (userId == null) return;
    
    final channel = message['channel'] as String?;
    if (channel == null) {
      await _sendError(session, 'Channel required');
      return;
    }
    
    // Remove subscription
    _userSubscriptions[userId]?.remove(channel);
    _channelSubscriptions[channel]?.remove(userId);
    
    await _sendMessage(session, {
      'type': 'unsubscribed',
      'channel': channel,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    session.log('User $userId unsubscribed from channel: $channel');
  }
  
  /// Handle ping message
  Future<void> _handlePing(Session session) async {
    await _sendMessage(session, {
      'type': 'pong',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Send message to client
  Future<void> _sendMessage(Session session, Map<String, dynamic> message) async {
    try {
      await session.sendStreamMessage(jsonEncode(message));
    } catch (e) {
      session.log('Error sending WebSocket message: $e', level: LogLevel.error);
    }
  }
  
  /// Send error message to client
  Future<void> _sendError(Session session, String error) async {
    await _sendMessage(session, {
      'type': 'error',
      'error': error,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Notify feed update to subscribed users
  Future<void> notifyFeedUpdate(
    Session session,
    int feedId,
    int userId,
  ) async {
    final channel = 'feed:$feedId';
    final userChannel = 'user:updates';
    
    // Notify users subscribed to this specific feed
    await _notifyChannel(session, channel, {
      'type': 'feed_updated',
      'feedId': feedId.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // Notify the feed owner
    await _notifyUser(session, userId, userChannel, {
      'type': 'feed_updated',
      'feedId': feedId.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Notify new articles to subscribed users
  Future<void> notifyNewArticles(
    Session session,
    int feedId,
    int userId,
    int articleCount,
  ) async {
    final channel = 'feed:$feedId';
    final userChannel = 'user:updates';
    
    final message = {
      'type': 'new_articles',
      'feedId': feedId.toString(),
      'count': articleCount,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Notify users subscribed to this feed
    await _notifyChannel(session, channel, message);
    
    // Notify the feed owner
    await _notifyUser(session, userId, userChannel, message);
  }
  
  /// Notify feed added
  Future<void> notifyFeedAdded(
    Session session,
    int userId,
    int feedId,
    String feedTitle,
  ) async {
    final userChannel = 'user:updates';
    
    await _notifyUser(session, userId, userChannel, {
      'type': 'feed_added',
      'feedId': feedId.toString(),
      'title': feedTitle,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Notify feed deleted
  Future<void> notifyFeedDeleted(
    Session session,
    int userId,
    int feedId,
  ) async {
    final userChannel = 'user:updates';
    
    await _notifyUser(session, userId, userChannel, {
      'type': 'feed_deleted',
      'feedId': feedId.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Notify market update
  Future<void> notifyMarketUpdate(
    Session session,
    Map<String, dynamic> marketData,
  ) async {
    final channel = 'market:updates';
    
    await _notifyChannel(session, channel, {
      'type': 'market_update',
      'data': marketData,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Notify AI analysis ready
  Future<void> notifyAIAnalysisReady(
    Session session,
    int userId,
    int articleId,
    String analysisType,
  ) async {
    final userChannel = 'user:updates';
    
    await _notifyUser(session, userId, userChannel, {
      'type': 'ai_analysis_ready',
      'articleId': articleId.toString(),
      'analysisType': analysisType,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Send notification to all users subscribed to a channel
  Future<void> _notifyChannel(
    Session session,
    String channel,
    Map<String, dynamic> message,
  ) async {
    final subscribedUsers = _channelSubscriptions[channel] ?? {};
    
    for (final userId in subscribedUsers) {
      try {
        await session.sendStreamMessageToUser(userId, jsonEncode(message));
      } catch (e) {
        session.log('Error notifying user $userId: $e', level: LogLevel.error);
      }
    }
  }
  
  /// Send notification to specific user on a channel
  Future<void> _notifyUser(
    Session session,
    int userId,
    String channel,
    Map<String, dynamic> message,
  ) async {
    // Check if user is subscribed to this channel
    final userChannels = _userSubscriptions[userId] ?? {};
    if (!userChannels.contains(channel)) return;
    
    try {
      await session.sendStreamMessageToUser(userId, jsonEncode(message));
    } catch (e) {
      session.log('Error notifying user $userId: $e', level: LogLevel.error);
    }
  }
  
  /// Clean up user subscriptions on disconnect
  void handleDisconnect(Session session) {
    final userId = session.auth?.userId;
    if (userId == null) return;
    
    // Remove user from all channel subscriptions
    final userChannels = _userSubscriptions[userId] ?? {};
    for (final channel in userChannels) {
      _channelSubscriptions[channel]?.remove(userId);
    }
    
    // Remove user subscriptions
    _userSubscriptions.remove(userId);
    
    session.log('WebSocket disconnected for user: $userId');
  }
}

// Global WebSocket handler instance
final webSocketHandler = WebSocketHandler();