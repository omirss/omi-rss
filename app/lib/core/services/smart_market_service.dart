import 'dart:async';
import 'package:dio/dio.dart';
import '../database/database.dart';

/// Smart market service with aggressive caching and batch optimization
class SmartMarketService {
  final AppDatabase _database;
  final Dio _dio;
  
  // Cache configuration
  static const Duration _cacheExpiry = Duration(minutes: 5);
  static const Duration _extendedCacheExpiry = Duration(minutes: 15); // For less important data
  static const int _batchSize = 20; // Max symbols per request
  
  // In-memory cache
  final Map<String, _CachedQuote> _cache = {};
  final Map<String, DateTime> _lastFetch = {};
  
  // Request queue for batching
  final List<_QuoteRequest> _pendingRequests = [];
  Timer? _batchTimer;
  
  // Rate limiting
  DateTime _lastApiCall = DateTime.now();
  int _callsThisMinute = 0;
  
  SmartMarketService({required AppDatabase database})
      : _database = database,
        _dio = Dio(BaseOptions(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ));

  /// Get quote with smart caching and batching
  Future<MarketQuote?> getQuote(String symbol, {bool priority = false}) async {
    // Check cache first
    final cached = _getCachedQuote(symbol);
    if (cached != null && !priority) {
      return cached;
    }
    
    // Add to batch queue
    final completer = Completer<MarketQuote?>();
    _pendingRequests.add(_QuoteRequest(symbol, completer, priority));
    
    // Start batch timer if not running
    _batchTimer ??= Timer(const Duration(milliseconds: 100), _processBatch);
    
    return completer.future;
  }
  
  /// Get multiple quotes efficiently
  Future<Map<String, MarketQuote>> getQuotes(List<String> symbols) async {
    final results = <String, MarketQuote>{};
    final needed = <String>[];
    
    // Check cache for each symbol
    for (final symbol in symbols) {
      final cached = _getCachedQuote(symbol);
      if (cached != null) {
        results[symbol] = cached;
      } else {
        needed.add(symbol);
      }
    }
    
    // Batch fetch remaining
    if (needed.isNotEmpty) {
      final fetched = await _batchFetchQuotes(needed);
      results.addAll(fetched);
    }
    
    return results;
  }
  
  /// Extract and fetch stock mentions from article
  Future<Map<String, MarketQuote>> getArticleMentions(String content) async {
    final tickers = _extractTickers(content);
    if (tickers.isEmpty) return {};
    
    // Limit to top 10 to avoid API abuse
    final limitedTickers = tickers.take(10).toList();
    return getQuotes(limitedTickers);
  }
  
  /// Get cached quote if still valid
  MarketQuote? _getCachedQuote(String symbol) {
    final cached = _cache[symbol];
    if (cached == null) return null;
    
    final age = DateTime.now().difference(cached.timestamp);
    final expiry = cached.priority ? _cacheExpiry : _extendedCacheExpiry;
    
    if (age < expiry) {
      return cached.quote;
    }
    
    // Clean expired cache
    _cache.remove(symbol);
    return null;
  }
  
  /// Process pending batch requests
  Future<void> _processBatch() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    
    if (_pendingRequests.isEmpty) return;
    
    // Group by priority
    final priority = _pendingRequests.where((r) => r.priority).toList();
    final normal = _pendingRequests.where((r) => !r.priority).toList();
    _pendingRequests.clear();
    
    // Process priority first
    if (priority.isNotEmpty) {
      await _processBatchGroup(priority);
    }
    
    // Then normal
    if (normal.isNotEmpty) {
      await _processBatchGroup(normal);
    }
  }
  
  Future<void> _processBatchGroup(List<_QuoteRequest> requests) async {
    // Remove duplicates
    final uniqueSymbols = <String, List<Completer<MarketQuote?>>>{};
    for (final request in requests) {
      uniqueSymbols.putIfAbsent(request.symbol, () => []).add(request.completer);
    }
    
    // Batch into chunks
    final symbols = uniqueSymbols.keys.toList();
    for (var i = 0; i < symbols.length; i += _batchSize) {
      final batch = symbols.skip(i).take(_batchSize).toList();
      final results = await _batchFetchQuotes(batch);
      
      // Resolve completers
      for (final symbol in batch) {
        final quote = results[symbol];
        final completers = uniqueSymbols[symbol]!;
        for (final completer in completers) {
          completer.complete(quote);
        }
      }
    }
  }
  
  /// Batch fetch quotes from Yahoo Finance
  Future<Map<String, MarketQuote>> _batchFetchQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    
    // Rate limiting
    await _enforceRateLimit();
    
    try {
      final symbolsStr = symbols.join(',');
      final response = await _dio.get(
        'https://query1.finance.yahoo.com/v7/finance/quote',
        queryParameters: {'symbols': symbolsStr},
      );
      
      final results = <String, MarketQuote>{};
      final quotes = response.data['quoteResponse']['result'] as List;
      
      for (final quote in quotes) {
        final symbol = quote['symbol'];
        final marketQuote = MarketQuote(
          symbol: symbol,
          name: quote['longName'] ?? quote['shortName'] ?? symbol,
          price: quote['regularMarketPrice']?.toDouble() ?? 0,
          change: quote['regularMarketChange']?.toDouble() ?? 0,
          changePercent: quote['regularMarketChangePercent']?.toDouble() ?? 0,
          dayHigh: quote['regularMarketDayHigh']?.toDouble() ?? 0,
          dayLow: quote['regularMarketDayLow']?.toDouble() ?? 0,
          volume: quote['regularMarketVolume'] ?? 0,
          marketCap: quote['marketCap']?.toDouble() ?? 0,
          timestamp: DateTime.now(),
        );
        
        results[symbol] = marketQuote;
        
        // Cache the result
        _cache[symbol] = _CachedQuote(marketQuote, DateTime.now(), false);
      }
      
      return results;
    } catch (e) {
      print('Error fetching quotes: $e');
      return {};
    }
  }
  
  /// Extract stock tickers from content
  List<String> _extractTickers(String content) {
    final tickers = <String>{};
    
    // Common patterns:
    // $AAPL, AAPL, (AAPL), NASDAQ:AAPL, NYSE:AAPL
    final patterns = [
      RegExp(r'\$([A-Z]{1,5})\b'),                    // $AAPL
      RegExp(r'\b([A-Z]{2,5})\b(?=\s+(?:stock|shares|price))'), // AAPL stock
      RegExp(r'\(([A-Z]{1,5})\)'),                    // (AAPL)
      RegExp(r'(?:NASDAQ|NYSE|TSX):\s*([A-Z]{1,5})'), // NASDAQ:AAPL
    ];
    
    for (final pattern in patterns) {
      final matches = pattern.allMatches(content);
      for (final match in matches) {
        final ticker = match.group(1);
        if (ticker != null && _isValidTicker(ticker)) {
          tickers.add(ticker);
        }
      }
    }
    
    // Common crypto patterns
    final cryptoPattern = RegExp(r'\b(BTC|ETH|BNB|XRP|ADA|DOGE|SOL|DOT|MATIC|AVAX)\b');
    final cryptoMatches = cryptoPattern.allMatches(content.toUpperCase());
    for (final match in cryptoMatches) {
      tickers.add(match.group(0)!);
    }
    
    return tickers.toList();
  }
  
  bool _isValidTicker(String ticker) {
    // Basic validation
    if (ticker.length < 1 || ticker.length > 5) return false;
    if (!RegExp(r'^[A-Z]+$').hasMatch(ticker)) return false;
    
    // Exclude common words that match pattern
    const excluded = ['AI', 'US', 'UK', 'EU', 'CEO', 'IPO', 'GDP', 'API', 'USD'];
    if (excluded.contains(ticker)) return false;
    
    return true;
  }
  
  /// Enforce rate limiting
  Future<void> _enforceRateLimit() async {
    final now = DateTime.now();
    
    // Reset counter every minute
    if (now.difference(_lastApiCall).inMinutes >= 1) {
      _callsThisMinute = 0;
    }
    
    // Yahoo doesn't have strict limits, but be respectful
    if (_callsThisMinute >= 30) {
      final waitTime = Duration(minutes: 1) - now.difference(_lastApiCall);
      if (waitTime.isNegative == false) {
        await Future.delayed(waitTime);
      }
      _callsThisMinute = 0;
    }
    
    _lastApiCall = now;
    _callsThisMinute++;
  }
  
  /// Clear cache
  void clearCache() {
    _cache.clear();
    _lastFetch.clear();
  }
  
  /// Preload quotes for watchlist
  Future<void> preloadWatchlist(List<String> symbols) async {
    if (symbols.isEmpty) return;
    
    // Check what needs updating
    final needsUpdate = symbols.where((symbol) {
      final cached = _getCachedQuote(symbol);
      return cached == null;
    }).toList();
    
    if (needsUpdate.isNotEmpty) {
      await getQuotes(needsUpdate);
    }
  }
}

/// Market quote model
class MarketQuote {
  final String symbol;
  final String name;
  final double price;
  final double change;
  final double changePercent;
  final double dayHigh;
  final double dayLow;
  final int volume;
  final double marketCap;
  final DateTime timestamp;
  
  MarketQuote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.dayHigh,
    required this.dayLow,
    required this.volume,
    required this.marketCap,
    required this.timestamp,
  });
  
  bool get isPositive => change >= 0;
  
  String get formattedPrice => '\$${price.toStringAsFixed(2)}';
  
  String get formattedChange => '${isPositive ? '+' : ''}${change.toStringAsFixed(2)}';
  
  String get formattedChangePercent => '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%';
}

/// Cached quote with metadata
class _CachedQuote {
  final MarketQuote quote;
  final DateTime timestamp;
  final bool priority;
  
  _CachedQuote(this.quote, this.timestamp, this.priority);
}

/// Quote request for batching
class _QuoteRequest {
  final String symbol;
  final Completer<MarketQuote?> completer;
  final bool priority;
  
  _QuoteRequest(this.symbol, this.completer, this.priority);
}