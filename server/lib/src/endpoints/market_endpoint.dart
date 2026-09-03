import 'package:serverpod/serverpod.dart';
import '../protocol/protocol.dart';
import '../services/market_service.dart';

class MarketEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  // Get real-time quote
  Future<MarketQuote> getQuote(
    Session session,
    String symbol,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final marketService = session.serverpod.getSingleton<MarketService>();
    return await marketService.getQuote(symbol.toUpperCase());
  }

  // Get batch quotes
  Future<List<MarketQuote>> getBatchQuotes(
    Session session,
    List<String> symbols,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    if (symbols.isEmpty) {
      return [];
    }

    if (symbols.length > 50) {
      throw Exception('Maximum 50 symbols per request');
    }

    final marketService = session.serverpod.getSingleton<MarketService>();
    final upperSymbols = symbols.map((s) => s.toUpperCase()).toList();
    return await marketService.getBatchQuotes(upperSymbols);
  }

  // Get historical data
  Future<List<MarketCandle>> getHistoricalData(
    Session session,
    String symbol,
    DateTime from,
    DateTime to,
    String interval,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Validate interval
    final validIntervals = ['minute', 'hour', 'day', 'week', 'month'];
    if (!validIntervals.contains(interval)) {
      throw Exception('Invalid interval. Use: ${validIntervals.join(', ')}');
    }

    // Validate date range
    if (to.isBefore(from)) {
      throw Exception('Invalid date range');
    }

    final maxDays = interval == 'minute' ? 7 : 365;
    if (to.difference(from).inDays > maxDays) {
      throw Exception('Date range too large. Maximum $maxDays days for $interval interval');
    }

    final marketService = session.serverpod.getSingleton<MarketService>();
    return await marketService.getHistoricalData(
      symbol.toUpperCase(),
      from,
      to,
      interval,
    );
  }

  // Get technical indicators
  Future<TechnicalIndicators> getTechnicalIndicators(
    Session session,
    String symbol,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final marketService = session.serverpod.getSingleton<MarketService>();
    
    // Get 200 days of historical data for indicators
    final to = DateTime.now();
    final from = to.subtract(const Duration(days: 200));
    
    final candles = await marketService.getHistoricalData(
      symbol.toUpperCase(),
      from,
      to,
      'day',
    );

    if (candles.length < 20) {
      throw Exception('Insufficient data for technical analysis');
    }

    return await marketService.calculateIndicators(symbol.toUpperCase(), candles);
  }

  // Get market news
  Future<List<MarketNews>> getMarketNews(
    Session session, {
    String? symbol,
    int limit = 20,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    if (limit > 100) {
      throw Exception('Maximum limit is 100');
    }

    final marketService = session.serverpod.getSingleton<MarketService>();
    final news = await marketService.getMarketNews(
      symbol: symbol?.toUpperCase(),
    );

    return news.take(limit).toList();
  }

  // Get user's watchlist
  Future<List<MarketWatchlistItem>> getWatchlist(
    Session session,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    return await MarketWatchlistItem.db.find(
      session,
      where: (t) => t.userId.equals(userId),
      orderBy: (t) => t.position,
    );
  }

  // Add to watchlist
  Future<MarketWatchlistItem> addToWatchlist(
    Session session,
    String symbol,
    String name,
    String type,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Check if already in watchlist
    final existing = await MarketWatchlistItem.db.findFirstRow(
      session,
      where: (t) => t.userId.equals(userId) & t.symbol.equals(symbol.toUpperCase()),
    );

    if (existing != null) {
      throw Exception('Symbol already in watchlist');
    }

    // Get current position
    final count = await MarketWatchlistItem.db.count(
      session,
      where: (t) => t.userId.equals(userId),
    );

    // Get current quote
    final marketService = session.serverpod.getSingleton<MarketService>();
    final quote = await marketService.getQuote(symbol.toUpperCase());

    final item = MarketWatchlistItem(
      userId: userId,
      symbol: symbol.toUpperCase(),
      name: name,
      type: type,
      position: count,
      lastPrice: quote.price,
      addedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await MarketWatchlistItem.db.insertRow(session, item);
    return item;
  }

  // Remove from watchlist
  Future<bool> removeFromWatchlist(
    Session session,
    String symbol,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final deleted = await MarketWatchlistItem.db.deleteWhere(
      session,
      where: (t) => t.userId.equals(userId) & t.symbol.equals(symbol.toUpperCase()),
    );

    return deleted.isNotEmpty;
  }

  // Reorder watchlist
  Future<bool> reorderWatchlist(
    Session session,
    List<String> symbols,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final items = await MarketWatchlistItem.db.find(
      session,
      where: (t) => t.userId.equals(userId),
    );

    // Verify all symbols exist
    final existingSymbols = items.map((i) => i.symbol).toSet();
    final providedSymbols = symbols.map((s) => s.toUpperCase()).toSet();
    
    if (!existingSymbols.containsAll(providedSymbols) || 
        !providedSymbols.containsAll(existingSymbols)) {
      throw Exception('Symbol list mismatch');
    }

    // Update positions
    for (int i = 0; i < symbols.length; i++) {
      final item = items.firstWhere((it) => it.symbol == symbols[i].toUpperCase());
      item.position = i;
      await MarketWatchlistItem.db.updateRow(session, item);
    }

    return true;
  }

  // Get price alerts
  Future<List<MarketPriceAlert>> getPriceAlerts(
    Session session,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    return await MarketPriceAlert.db.find(
      session,
      where: (t) => t.userId.equals(userId),
      orderBy: (t) => t.createdAt,
      orderDescending: true,
    );
  }

  // Create price alert
  Future<MarketPriceAlert> createPriceAlert(
    Session session,
    String symbol,
    double targetPrice,
    String condition, // 'above' or 'below'
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    if (condition != 'above' && condition != 'below') {
      throw Exception('Condition must be "above" or "below"');
    }

    if (targetPrice <= 0) {
      throw Exception('Target price must be positive');
    }

    // Get current price
    final marketService = session.serverpod.getSingleton<MarketService>();
    final quote = await marketService.getQuote(symbol.toUpperCase());

    final alert = MarketPriceAlert(
      userId: userId,
      symbol: symbol.toUpperCase(),
      targetPrice: targetPrice,
      condition: condition,
      currentPrice: quote.price,
      isActive: true,
      isTriggered: false,
      createdAt: DateTime.now(),
    );

    await MarketPriceAlert.db.insertRow(session, alert);
    return alert;
  }

  // Delete price alert
  Future<bool> deletePriceAlert(
    Session session,
    int alertId,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final deleted = await MarketPriceAlert.db.deleteWhere(
      session,
      where: (t) => t.id.equals(alertId) & t.userId.equals(userId),
    );

    return deleted.isNotEmpty;
  }

  // Generate market RSS feed
  Future<String> generateMarketRSSFeed(
    Session session,
    List<String> symbols,
    bool includePriceAlerts,
    bool includeNews,
    bool includeTechnicalTriggers,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    if (symbols.isEmpty) {
      // Use watchlist symbols if none provided
      final watchlist = await getWatchlist(session);
      symbols = watchlist.map((w) => w.symbol).toList();
    }

    if (symbols.isEmpty) {
      throw Exception('No symbols provided and watchlist is empty');
    }

    final marketService = session.serverpod.getSingleton<MarketService>();
    final options = MarketFeedOptions(
      includePriceAlerts: includePriceAlerts,
      includeNews: includeNews,
      includeTechnicalTriggers: includeTechnicalTriggers,
      includeEarnings: false,
    );

    return await marketService.generateMarketRSSFeed(
      symbols.map((s) => s.toUpperCase()).toList(),
      options,
    );
  }

  // Search symbols
  Future<List<SymbolSearchResult>> searchSymbols(
    Session session,
    String query,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    if (query.length < 1) {
      throw Exception('Query too short');
    }

    // In a real implementation, this would search a symbol database
    // For now, return mock results
    final mockResults = [
      SymbolSearchResult(
        symbol: query.toUpperCase(),
        name: '${query.toUpperCase()} Inc.',
        type: 'stock',
        exchange: 'NASDAQ',
      ),
    ];

    return mockResults;
  }

  // Get market summary
  Future<MarketSummary> getMarketSummary(
    Session session,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final marketService = session.serverpod.getSingleton<MarketService>();
    
    // Get major indices
    final indices = await marketService.getBatchQuotes([
      'SPY',  // S&P 500
      'DIA',  // Dow Jones
      'QQQ',  // Nasdaq
      'IWM',  // Russell 2000
    ]);

    // Get top movers from user's watchlist
    final watchlist = await getWatchlist(session);
    if (watchlist.isEmpty) {
      return MarketSummary(
        indices: indices,
        topGainers: [],
        topLosers: [],
        mostActive: [],
        marketStatus: _getMarketStatus(),
      );
    }

    final quotes = await marketService.getBatchQuotes(
      watchlist.map((w) => w.symbol).toList(),
    );

    // Sort by change percent
    quotes.sort((a, b) => b.changePercent.compareTo(a.changePercent));
    
    final topGainers = quotes.where((q) => q.changePercent > 0).take(5).toList();
    final topLosers = quotes.where((q) => q.changePercent < 0).take(5).toList()
      ..sort((a, b) => a.changePercent.compareTo(b.changePercent));

    return MarketSummary(
      indices: indices,
      topGainers: topGainers,
      topLosers: topLosers,
      mostActive: [], // Would need volume data
      marketStatus: _getMarketStatus(),
    );
  }

  String _getMarketStatus() {
    final now = DateTime.now();
    final easternTime = now.toUtc().add(const Duration(hours: -5)); // EST
    
    if (easternTime.weekday == 6 || easternTime.weekday == 7) {
      return 'closed'; // Weekend
    }
    
    final marketOpen = DateTime(easternTime.year, easternTime.month, easternTime.day, 9, 30);
    final marketClose = DateTime(easternTime.year, easternTime.month, easternTime.day, 16, 0);
    
    if (easternTime.isBefore(marketOpen)) {
      return 'pre-market';
    } else if (easternTime.isAfter(marketClose)) {
      return 'after-hours';
    } else {
      return 'open';
    }
  }
}

// Supporting classes
class SymbolSearchResult {
  final String symbol;
  final String name;
  final String type;
  final String exchange;

  SymbolSearchResult({
    required this.symbol,
    required this.name,
    required this.type,
    required this.exchange,
  });

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'name': name,
    'type': type,
    'exchange': exchange,
  };
}

class MarketSummary {
  final List<MarketQuote> indices;
  final List<MarketQuote> topGainers;
  final List<MarketQuote> topLosers;
  final List<MarketQuote> mostActive;
  final String marketStatus;

  MarketSummary({
    required this.indices,
    required this.topGainers,
    required this.topLosers,
    required this.mostActive,
    required this.marketStatus,
  });

  Map<String, dynamic> toJson() => {
    'indices': indices.map((q) => q.toJson()).toList(),
    'topGainers': topGainers.map((q) => q.toJson()).toList(),
    'topLosers': topLosers.map((q) => q.toJson()).toList(),
    'mostActive': mostActive.map((q) => q.toJson()).toList(),
    'marketStatus': marketStatus,
  };
}