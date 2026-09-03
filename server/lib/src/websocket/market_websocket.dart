import 'dart:async';
import 'dart:convert';
import 'package:serverpod/serverpod.dart';
import '../generated/protocol.dart';

class MarketWebSocketHandler {
  final Map<String, MarketDataSubscription> _subscriptions = {};
  final Map<String, Timer> _updateTimers = {};
  final StreamController<MarketUpdate> _marketUpdateController = StreamController.broadcast();
  
  // External market data providers
  final Map<String, MarketDataProvider> _providers = {
    'stocks': StockMarketProvider(),
    'crypto': CryptoMarketProvider(),
    'forex': ForexMarketProvider(),
    'commodities': CommoditiesMarketProvider(),
  };
  
  // Handle new WebSocket connection
  Future<void> handleConnection(
    WebSocketSession session,
    HttpRequest request,
  ) async {
    session.log('Market WebSocket connected: ${session.sessionId}');
    
    // Send initial connection acknowledgment
    await _sendMessage(session, {
      'type': 'connected',
      'sessionId': session.sessionId,
      'timestamp': DateTime.now().toIso8601String(),
      'availableMarkets': _providers.keys.toList(),
    });
    
    // Set up message handler
    session.messages.listen(
      (message) => _handleMessage(session, message),
      onError: (error) => _handleError(session, error),
      onDone: () => _handleDisconnect(session),
    );
  }
  
  // Handle incoming WebSocket message
  Future<void> _handleMessage(
    WebSocketSession session,
    String message,
  ) async {
    try {
      final data = json.decode(message) as Map<String, dynamic>;
      final messageType = data['type'] as String?;
      
      if (messageType == null) {
        await _sendError(session, 'Missing message type');
        return;
      }
      
      switch (messageType) {
        case 'subscribe':
          await _handleSubscribe(session, data);
          break;
        case 'unsubscribe':
          await _handleUnsubscribe(session, data);
          break;
        case 'ping':
          await _handlePing(session);
          break;
        case 'getSnapshot':
          await _handleGetSnapshot(session, data);
          break;
        case 'setAlert':
          await _handleSetAlert(session, data);
          break;
        case 'removeAlert':
          await _handleRemoveAlert(session, data);
          break;
        default:
          await _sendError(session, 'Unknown message type: $messageType');
      }
    } catch (e) {
      session.log('Error handling message: $e', level: LogLevel.error);
      await _sendError(session, 'Invalid message format');
    }
  }
  
  // Handle subscription request
  Future<void> _handleSubscribe(
    WebSocketSession session,
    Map<String, dynamic> data,
  ) async {
    final symbols = data['symbols'] as List<dynamic>?;
    final market = data['market'] as String?;
    final interval = data['interval'] as int? ?? 5000; // Default 5 seconds
    
    if (symbols == null || symbols.isEmpty) {
      await _sendError(session, 'No symbols provided');
      return;
    }
    
    if (market == null || !_providers.containsKey(market)) {
      await _sendError(session, 'Invalid or missing market type');
      return;
    }
    
    // Create subscription
    final subscription = MarketDataSubscription(
      sessionId: session.sessionId,
      symbols: symbols.cast<String>(),
      market: market,
      interval: interval,
      subscribedAt: DateTime.now(),
    );
    
    _subscriptions[session.sessionId] = subscription;
    
    // Start data updates
    _startDataUpdates(session, subscription);
    
    // Send confirmation
    await _sendMessage(session, {
      'type': 'subscribed',
      'symbols': symbols,
      'market': market,
      'interval': interval,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // Send initial snapshot
    await _sendSnapshot(session, subscription);
  }
  
  // Handle unsubscribe request
  Future<void> _handleUnsubscribe(
    WebSocketSession session,
    Map<String, dynamic> data,
  ) async {
    final symbols = data['symbols'] as List<dynamic>?;
    final subscription = _subscriptions[session.sessionId];
    
    if (subscription == null) {
      await _sendError(session, 'No active subscription');
      return;
    }
    
    if (symbols == null || symbols.isEmpty) {
      // Unsubscribe from all
      _stopDataUpdates(session.sessionId);
      _subscriptions.remove(session.sessionId);
      
      await _sendMessage(session, {
        'type': 'unsubscribed',
        'symbols': 'all',
        'timestamp': DateTime.now().toIso8601String(),
      });
    } else {
      // Unsubscribe from specific symbols
      subscription.symbols.removeWhere((s) => symbols.contains(s));
      
      if (subscription.symbols.isEmpty) {
        _stopDataUpdates(session.sessionId);
        _subscriptions.remove(session.sessionId);
      }
      
      await _sendMessage(session, {
        'type': 'unsubscribed',
        'symbols': symbols,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }
  
  // Handle ping message
  Future<void> _handlePing(WebSocketSession session) async {
    await _sendMessage(session, {
      'type': 'pong',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  // Handle snapshot request
  Future<void> _handleGetSnapshot(
    WebSocketSession session,
    Map<String, dynamic> data,
  ) async {
    final symbols = data['symbols'] as List<dynamic>?;
    final market = data['market'] as String?;
    
    if (symbols == null || market == null) {
      await _sendError(session, 'Missing symbols or market');
      return;
    }
    
    final provider = _providers[market];
    if (provider == null) {
      await _sendError(session, 'Invalid market type');
      return;
    }
    
    try {
      final marketData = await provider.getMarketData(symbols.cast<String>());
      
      await _sendMessage(session, {
        'type': 'snapshot',
        'market': market,
        'data': marketData.map((d) => d.toJson()).toList(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      await _sendError(session, 'Failed to fetch market data');
    }
  }
  
  // Handle price alert
  Future<void> _handleSetAlert(
    WebSocketSession session,
    Map<String, dynamic> data,
  ) async {
    final symbol = data['symbol'] as String?;
    final targetPrice = data['targetPrice'] as num?;
    final condition = data['condition'] as String?; // 'above' or 'below'
    
    if (symbol == null || targetPrice == null || condition == null) {
      await _sendError(session, 'Missing alert parameters');
      return;
    }
    
    // Store alert in database
    try {
      final alert = PriceAlert(
        userId: session.authenticatedUserId ?? 0,
        symbol: symbol,
        targetPrice: targetPrice.toDouble(),
        condition: condition,
        isActive: true,
        createdAt: DateTime.now(),
      );
      
      await alert.insert(session as Session);
      
      await _sendMessage(session, {
        'type': 'alertSet',
        'alertId': alert.id,
        'symbol': symbol,
        'targetPrice': targetPrice,
        'condition': condition,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      await _sendError(session, 'Failed to set alert');
    }
  }
  
  // Handle remove alert
  Future<void> _handleRemoveAlert(
    WebSocketSession session,
    Map<String, dynamic> data,
  ) async {
    final alertId = data['alertId'] as int?;
    
    if (alertId == null) {
      await _sendError(session, 'Missing alert ID');
      return;
    }
    
    try {
      final alert = await PriceAlert.findById(session as Session, alertId);
      
      if (alert == null || alert.userId != session.authenticatedUserId) {
        await _sendError(session, 'Alert not found');
        return;
      }
      
      await PriceAlert.deleteRow(session as Session, alert);
      
      await _sendMessage(session, {
        'type': 'alertRemoved',
        'alertId': alertId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      await _sendError(session, 'Failed to remove alert');
    }
  }
  
  // Start data updates for a subscription
  void _startDataUpdates(
    WebSocketSession session,
    MarketDataSubscription subscription,
  ) {
    // Cancel existing timer if any
    _stopDataUpdates(session.sessionId);
    
    // Create new update timer
    _updateTimers[session.sessionId] = Timer.periodic(
      Duration(milliseconds: subscription.interval),
      (_) => _sendMarketUpdate(session, subscription),
    );
  }
  
  // Stop data updates
  void _stopDataUpdates(String sessionId) {
    _updateTimers[sessionId]?.cancel();
    _updateTimers.remove(sessionId);
  }
  
  // Send market update
  Future<void> _sendMarketUpdate(
    WebSocketSession session,
    MarketDataSubscription subscription,
  ) async {
    try {
      final provider = _providers[subscription.market];
      if (provider == null) return;
      
      final updates = await provider.getMarketUpdates(subscription.symbols);
      
      if (updates.isNotEmpty) {
        await _sendMessage(session, {
          'type': 'update',
          'market': subscription.market,
          'updates': updates.map((u) => u.toJson()).toList(),
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        // Check for price alerts
        await _checkPriceAlerts(session, updates);
      }
    } catch (e) {
      session.log('Error sending market update: $e', level: LogLevel.error);
    }
  }
  
  // Send initial snapshot
  Future<void> _sendSnapshot(
    WebSocketSession session,
    MarketDataSubscription subscription,
  ) async {
    try {
      final provider = _providers[subscription.market];
      if (provider == null) return;
      
      final marketData = await provider.getMarketData(subscription.symbols);
      
      await _sendMessage(session, {
        'type': 'snapshot',
        'market': subscription.market,
        'data': marketData.map((d) => d.toJson()).toList(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      session.log('Error sending snapshot: $e', level: LogLevel.error);
    }
  }
  
  // Check price alerts
  Future<void> _checkPriceAlerts(
    WebSocketSession session,
    List<MarketUpdate> updates,
  ) async {
    if (session.authenticatedUserId == null) return;
    
    try {
      // Get active alerts for user
      final alerts = await PriceAlert.find(
        session as Session,
        where: (t) => t.userId.equals(session.authenticatedUserId!) & t.isActive.equals(true),
      );
      
      for (final update in updates) {
        for (final alert in alerts) {
          if (alert.symbol != update.symbol) continue;
          
          bool triggered = false;
          
          if (alert.condition == 'above' && update.price >= alert.targetPrice) {
            triggered = true;
          } else if (alert.condition == 'below' && update.price <= alert.targetPrice) {
            triggered = true;
          }
          
          if (triggered) {
            // Send alert notification
            await _sendMessage(session, {
              'type': 'alert',
              'alertId': alert.id,
              'symbol': alert.symbol,
              'condition': alert.condition,
              'targetPrice': alert.targetPrice,
              'currentPrice': update.price,
              'timestamp': DateTime.now().toIso8601String(),
            });
            
            // Deactivate alert
            alert.isActive = false;
            alert.triggeredAt = DateTime.now();
            await alert.update(session as Session);
          }
        }
      }
    } catch (e) {
      session.log('Error checking price alerts: $e', level: LogLevel.error);
    }
  }
  
  // Handle WebSocket error
  void _handleError(WebSocketSession session, dynamic error) {
    session.log('WebSocket error: $error', level: LogLevel.error);
    _handleDisconnect(session);
  }
  
  // Handle WebSocket disconnect
  void _handleDisconnect(WebSocketSession session) {
    session.log('Market WebSocket disconnected: ${session.sessionId}');
    
    // Clean up subscription
    _stopDataUpdates(session.sessionId);
    _subscriptions.remove(session.sessionId);
  }
  
  // Send message to client
  Future<void> _sendMessage(
    WebSocketSession session,
    Map<String, dynamic> message,
  ) async {
    try {
      session.sendMessage(json.encode(message));
    } catch (e) {
      session.log('Error sending message: $e', level: LogLevel.error);
    }
  }
  
  // Send error message
  Future<void> _sendError(
    WebSocketSession session,
    String error,
  ) async {
    await _sendMessage(session, {
      'type': 'error',
      'error': error,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  // Clean up resources
  void dispose() {
    _updateTimers.forEach((_, timer) => timer.cancel());
    _updateTimers.clear();
    _subscriptions.clear();
    _marketUpdateController.close();
  }
}

// Data classes
class MarketDataSubscription {
  final String sessionId;
  final List<String> symbols;
  final String market;
  final int interval;
  final DateTime subscribedAt;
  
  MarketDataSubscription({
    required this.sessionId,
    required this.symbols,
    required this.market,
    required this.interval,
    required this.subscribedAt,
  });
}

class MarketUpdate {
  final String symbol;
  final double price;
  final double change;
  final double changePercent;
  final int volume;
  final DateTime timestamp;
  
  MarketUpdate({
    required this.symbol,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.volume,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'price': price,
    'change': change,
    'changePercent': changePercent,
    'volume': volume,
    'timestamp': timestamp.toIso8601String(),
  };
}

class MarketData {
  final String symbol;
  final String name;
  final double price;
  final double open;
  final double high;
  final double low;
  final double previousClose;
  final int volume;
  final double marketCap;
  final DateTime lastUpdate;
  
  MarketData({
    required this.symbol,
    required this.name,
    required this.price,
    required this.open,
    required this.high,
    required this.low,
    required this.previousClose,
    required this.volume,
    required this.marketCap,
    required this.lastUpdate,
  });
  
  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'name': name,
    'price': price,
    'open': open,
    'high': high,
    'low': low,
    'previousClose': previousClose,
    'volume': volume,
    'marketCap': marketCap,
    'lastUpdate': lastUpdate.toIso8601String(),
  };
}

// Market data provider interface
abstract class MarketDataProvider {
  Future<List<MarketData>> getMarketData(List<String> symbols);
  Future<List<MarketUpdate>> getMarketUpdates(List<String> symbols);
}

// Stock market provider
class StockMarketProvider implements MarketDataProvider {
  @override
  Future<List<MarketData>> getMarketData(List<String> symbols) async {
    // In production, this would call a real stock API
    return symbols.map((symbol) => MarketData(
      symbol: symbol,
      name: 'Company $symbol',
      price: 100.0 + (symbol.hashCode % 50),
      open: 98.0 + (symbol.hashCode % 50),
      high: 102.0 + (symbol.hashCode % 50),
      low: 97.0 + (symbol.hashCode % 50),
      previousClose: 99.0 + (symbol.hashCode % 50),
      volume: 1000000 + (symbol.hashCode % 500000),
      marketCap: 1000000000.0 + (symbol.hashCode % 500000000),
      lastUpdate: DateTime.now(),
    )).toList();
  }
  
  @override
  Future<List<MarketUpdate>> getMarketUpdates(List<String> symbols) async {
    // Simulate price changes
    return symbols.map((symbol) {
      final random = DateTime.now().microsecond % 100;
      final price = 100.0 + (symbol.hashCode % 50) + (random - 50) / 100;
      final previousPrice = 100.0 + (symbol.hashCode % 50);
      final change = price - previousPrice;
      
      return MarketUpdate(
        symbol: symbol,
        price: price,
        change: change,
        changePercent: (change / previousPrice) * 100,
        volume: 1000000 + random * 1000,
        timestamp: DateTime.now(),
      );
    }).toList();
  }
}

// Crypto market provider
class CryptoMarketProvider implements MarketDataProvider {
  @override
  Future<List<MarketData>> getMarketData(List<String> symbols) async {
    // In production, this would call a real crypto API
    return symbols.map((symbol) => MarketData(
      symbol: symbol,
      name: 'Crypto $symbol',
      price: 1000.0 + (symbol.hashCode % 500),
      open: 980.0 + (symbol.hashCode % 500),
      high: 1020.0 + (symbol.hashCode % 500),
      low: 970.0 + (symbol.hashCode % 500),
      previousClose: 990.0 + (symbol.hashCode % 500),
      volume: 10000000 + (symbol.hashCode % 5000000),
      marketCap: 10000000000.0 + (symbol.hashCode % 5000000000),
      lastUpdate: DateTime.now(),
    )).toList();
  }
  
  @override
  Future<List<MarketUpdate>> getMarketUpdates(List<String> symbols) async {
    // Simulate price changes with higher volatility
    return symbols.map((symbol) {
      final random = DateTime.now().microsecond % 200;
      final price = 1000.0 + (symbol.hashCode % 500) + (random - 100) / 10;
      final previousPrice = 1000.0 + (symbol.hashCode % 500);
      final change = price - previousPrice;
      
      return MarketUpdate(
        symbol: symbol,
        price: price,
        change: change,
        changePercent: (change / previousPrice) * 100,
        volume: 10000000 + random * 10000,
        timestamp: DateTime.now(),
      );
    }).toList();
  }
}

// Forex market provider
class ForexMarketProvider implements MarketDataProvider {
  @override
  Future<List<MarketData>> getMarketData(List<String> symbols) async {
    // In production, this would call a real forex API
    return symbols.map((symbol) => MarketData(
      symbol: symbol,
      name: 'Currency Pair $symbol',
      price: 1.0 + (symbol.hashCode % 100) / 1000,
      open: 1.0 + (symbol.hashCode % 100) / 1000 - 0.001,
      high: 1.0 + (symbol.hashCode % 100) / 1000 + 0.002,
      low: 1.0 + (symbol.hashCode % 100) / 1000 - 0.002,
      previousClose: 1.0 + (symbol.hashCode % 100) / 1000 - 0.0005,
      volume: 100000000 + (symbol.hashCode % 50000000),
      marketCap: 0, // Not applicable for forex
      lastUpdate: DateTime.now(),
    )).toList();
  }
  
  @override
  Future<List<MarketUpdate>> getMarketUpdates(List<String> symbols) async {
    // Simulate price changes with forex precision
    return symbols.map((symbol) {
      final random = DateTime.now().microsecond % 20;
      final price = 1.0 + (symbol.hashCode % 100) / 1000 + (random - 10) / 10000;
      final previousPrice = 1.0 + (symbol.hashCode % 100) / 1000;
      final change = price - previousPrice;
      
      return MarketUpdate(
        symbol: symbol,
        price: price,
        change: change,
        changePercent: (change / previousPrice) * 100,
        volume: 100000000 + random * 1000000,
        timestamp: DateTime.now(),
      );
    }).toList();
  }
}

// Commodities market provider
class CommoditiesMarketProvider implements MarketDataProvider {
  @override
  Future<List<MarketData>> getMarketData(List<String> symbols) async {
    // In production, this would call a real commodities API
    return symbols.map((symbol) => MarketData(
      symbol: symbol,
      name: 'Commodity $symbol',
      price: 50.0 + (symbol.hashCode % 200),
      open: 49.0 + (symbol.hashCode % 200),
      high: 51.0 + (symbol.hashCode % 200),
      low: 48.0 + (symbol.hashCode % 200),
      previousClose: 49.5 + (symbol.hashCode % 200),
      volume: 500000 + (symbol.hashCode % 250000),
      marketCap: 0, // Not typically applicable for commodities
      lastUpdate: DateTime.now(),
    )).toList();
  }
  
  @override
  Future<List<MarketUpdate>> getMarketUpdates(List<String> symbols) async {
    // Simulate price changes
    return symbols.map((symbol) {
      final random = DateTime.now().microsecond % 40;
      final price = 50.0 + (symbol.hashCode % 200) + (random - 20) / 20;
      final previousPrice = 50.0 + (symbol.hashCode % 200);
      final change = price - previousPrice;
      
      return MarketUpdate(
        symbol: symbol,
        price: price,
        change: change,
        changePercent: (change / previousPrice) * 100,
        volume: 500000 + random * 5000,
        timestamp: DateTime.now(),
      );
    }).toList();
  }
}