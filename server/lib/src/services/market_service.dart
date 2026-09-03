import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:serverpod/serverpod.dart';
import '../protocol/protocol.dart';

class MarketService {
  final Session session;
  final Dio _dio;
  late final String? _alphaVantageKey;
  late final String? _finnhubKey;
  late final String? _polygonKey;
  late final String? _yahooFinanceKey;
  
  final Map<String, MarketQuote> _quoteCache = {};
  final Map<String, DateTime> _cacheExpiry = {};
  static const _cacheDuration = Duration(minutes: 1);
  
  // WebSocket connections
  StreamController<MarketQuote>? _finnhubStream;
  StreamController<MarketQuote>? _polygonStream;
  
  MarketService(this.session) : _dio = Dio() {
    final config = session.serverpod.config;
    _alphaVantageKey = config['market']?['alphaVantage']?['apiKey'];
    _finnhubKey = config['market']?['finnhub']?['apiKey'];
    _polygonKey = config['market']?['polygon']?['apiKey'];
    _yahooFinanceKey = config['market']?['yahoo']?['apiKey'];
  }

  // Get real-time quote
  Future<MarketQuote> getQuote(String symbol) async {
    // Check cache first
    if (_quoteCache.containsKey(symbol)) {
      final expiry = _cacheExpiry[symbol];
      if (expiry != null && expiry.isAfter(DateTime.now())) {
        return _quoteCache[symbol]!;
      }
    }

    try {
      // Try multiple providers in order
      MarketQuote? quote;
      
      if (_finnhubKey != null) {
        quote = await _getQuoteFromFinnhub(symbol);
      }
      
      if (quote == null && _alphaVantageKey != null) {
        quote = await _getQuoteFromAlphaVantage(symbol);
      }
      
      if (quote == null && _yahooFinanceKey != null) {
        quote = await _getQuoteFromYahoo(symbol);
      }
      
      if (quote != null) {
        _cacheQuote(symbol, quote);
        return quote;
      }
      
      throw Exception('Unable to fetch quote for $symbol');
    } catch (e) {
      session.log('Market quote error for $symbol: $e');
      rethrow;
    }
  }

  // Get batch quotes
  Future<List<MarketQuote>> getBatchQuotes(List<String> symbols) async {
    final quotes = <MarketQuote>[];
    
    // Check cache first
    final uncachedSymbols = <String>[];
    for (final symbol in symbols) {
      if (_quoteCache.containsKey(symbol)) {
        final expiry = _cacheExpiry[symbol];
        if (expiry != null && expiry.isAfter(DateTime.now())) {
          quotes.add(_quoteCache[symbol]!);
          continue;
        }
      }
      uncachedSymbols.add(symbol);
    }
    
    if (uncachedSymbols.isEmpty) return quotes;
    
    // Fetch uncached quotes
    if (_yahooFinanceKey != null && uncachedSymbols.length > 1) {
      // Yahoo Finance supports batch requests
      final batchQuotes = await _getBatchQuotesFromYahoo(uncachedSymbols);
      quotes.addAll(batchQuotes);
    } else {
      // Fetch individually
      for (final symbol in uncachedSymbols) {
        try {
          final quote = await getQuote(symbol);
          quotes.add(quote);
        } catch (e) {
          session.log('Failed to fetch quote for $symbol: $e');
        }
      }
    }
    
    return quotes;
  }

  // Get historical data
  Future<List<MarketCandle>> getHistoricalData(
    String symbol,
    DateTime from,
    DateTime to,
    String interval,
  ) async {
    try {
      if (_polygonKey != null) {
        return await _getHistoricalFromPolygon(symbol, from, to, interval);
      }
      
      if (_alphaVantageKey != null) {
        return await _getHistoricalFromAlphaVantage(symbol, from, to, interval);
      }
      
      throw Exception('No provider available for historical data');
    } catch (e) {
      session.log('Historical data error for $symbol: $e');
      rethrow;
    }
  }

  // Calculate technical indicators
  Future<TechnicalIndicators> calculateIndicators(
    String symbol,
    List<MarketCandle> candles,
  ) async {
    try {
      final closes = candles.map((c) => c.close).toList();
      
      return TechnicalIndicators(
        symbol: symbol,
        sma20: _calculateSMA(closes, 20),
        sma50: _calculateSMA(closes, 50),
        sma200: _calculateSMA(closes, 200),
        ema12: _calculateEMA(closes, 12),
        ema26: _calculateEMA(closes, 26),
        rsi: _calculateRSI(closes, 14),
        macd: _calculateMACD(closes),
        bollingerBands: _calculateBollingerBands(closes, 20),
        volume: candles.isNotEmpty ? candles.last.volume : 0,
        calculatedAt: DateTime.now(),
      );
    } catch (e) {
      session.log('Indicator calculation error: $e');
      rethrow;
    }
  }

  // Get market news
  Future<List<MarketNews>> getMarketNews({String? symbol}) async {
    try {
      final news = <MarketNews>[];
      
      if (_finnhubKey != null) {
        news.addAll(await _getNewsFromFinnhub(symbol));
      }
      
      if (_polygonKey != null) {
        news.addAll(await _getNewsFromPolygon(symbol));
      }
      
      // Sort by date and remove duplicates
      news.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return _removeDuplicateNews(news);
    } catch (e) {
      session.log('Market news error: $e');
      return [];
    }
  }

  // Convert market events to RSS feed
  Future<String> generateMarketRSSFeed(
    List<String> symbols,
    MarketFeedOptions options,
  ) async {
    final items = <String>[];
    
    // Get quotes and news for all symbols
    for (final symbol in symbols) {
      try {
        final quote = await getQuote(symbol);
        
        // Price alert item
        if (options.includePriceAlerts) {
          final priceItem = _generatePriceAlertItem(quote);
          if (priceItem != null) items.add(priceItem);
        }
        
        // News items
        if (options.includeNews) {
          final news = await getMarketNews(symbol: symbol);
          items.addAll(news.take(5).map(_generateNewsItem));
        }
        
        // Technical trigger items
        if (options.includeTechnicalTriggers) {
          final historicalData = await getHistoricalData(
            symbol,
            DateTime.now().subtract(Duration(days: 30)),
            DateTime.now(),
            'daily',
          );
          final indicators = await calculateIndicators(symbol, historicalData);
          final triggerItem = _generateTechnicalTriggerItem(quote, indicators);
          if (triggerItem != null) items.add(triggerItem);
        }
      } catch (e) {
        session.log('Error generating RSS for $symbol: $e');
      }
    }
    
    // Build RSS feed
    return '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Market Data Feed</title>
    <description>Real-time market data and alerts</description>
    <link>https://example.com/market</link>
    <lastBuildDate>${DateTime.now().toUtc().toIso8601String()}</lastBuildDate>
    ${items.join('\n    ')}
  </channel>
</rss>''';
  }

  // Private helper methods
  Future<MarketQuote> _getQuoteFromFinnhub(String symbol) async {
    final response = await _dio.get(
      'https://finnhub.io/api/v1/quote',
      queryParameters: {
        'symbol': symbol,
        'token': _finnhubKey,
      },
    );
    
    final data = response.data;
    return MarketQuote(
      symbol: symbol,
      price: data['c'].toDouble(),
      change: data['d'].toDouble(),
      changePercent: data['dp'].toDouble(),
      high: data['h'].toDouble(),
      low: data['l'].toDouble(),
      open: data['o'].toDouble(),
      previousClose: data['pc'].toDouble(),
      volume: 0, // Finnhub doesn't provide volume in quote endpoint
      timestamp: DateTime.now(),
      provider: 'finnhub',
    );
  }

  Future<MarketQuote> _getQuoteFromAlphaVantage(String symbol) async {
    final response = await _dio.get(
      'https://www.alphavantage.co/query',
      queryParameters: {
        'function': 'GLOBAL_QUOTE',
        'symbol': symbol,
        'apikey': _alphaVantageKey,
      },
    );
    
    final quote = response.data['Global Quote'];
    final price = double.parse(quote['05. price']);
    final previousClose = double.parse(quote['08. previous close']);
    
    return MarketQuote(
      symbol: symbol,
      price: price,
      change: double.parse(quote['09. change']),
      changePercent: double.parse(quote['10. change percent'].replaceAll('%', '')),
      high: double.parse(quote['03. high']),
      low: double.parse(quote['04. low']),
      open: double.parse(quote['02. open']),
      previousClose: previousClose,
      volume: int.parse(quote['06. volume']),
      timestamp: DateTime.now(),
      provider: 'alphavantage',
    );
  }

  Future<MarketQuote> _getQuoteFromYahoo(String symbol) async {
    // Simplified Yahoo Finance implementation
    // In production, you'd use a proper Yahoo Finance API or library
    throw UnimplementedError('Yahoo Finance integration pending');
  }

  Future<List<MarketQuote>> _getBatchQuotesFromYahoo(List<String> symbols) async {
    // Batch implementation for Yahoo Finance
    throw UnimplementedError('Yahoo Finance batch quotes pending');
  }

  Future<List<MarketCandle>> _getHistoricalFromPolygon(
    String symbol,
    DateTime from,
    DateTime to,
    String interval,
  ) async {
    final response = await _dio.get(
      'https://api.polygon.io/v2/aggs/ticker/$symbol/range/1/$interval/${from.millisecondsSinceEpoch}/${to.millisecondsSinceEpoch}',
      queryParameters: {
        'apiKey': _polygonKey,
        'adjusted': true,
        'sort': 'asc',
      },
    );
    
    final results = response.data['results'] as List;
    return results.map((r) => MarketCandle(
      timestamp: DateTime.fromMillisecondsSinceEpoch(r['t']),
      open: r['o'].toDouble(),
      high: r['h'].toDouble(),
      low: r['l'].toDouble(),
      close: r['c'].toDouble(),
      volume: r['v'],
    )).toList();
  }

  Future<List<MarketCandle>> _getHistoricalFromAlphaVantage(
    String symbol,
    DateTime from,
    DateTime to,
    String interval,
  ) async {
    // Alpha Vantage historical data implementation
    throw UnimplementedError('Alpha Vantage historical data pending');
  }

  Future<List<MarketNews>> _getNewsFromFinnhub(String? symbol) async {
    final params = {
      'token': _finnhubKey,
      'category': 'general',
    };
    
    if (symbol != null) {
      params['symbol'] = symbol;
    }
    
    final response = await _dio.get(
      'https://finnhub.io/api/v1/news',
      queryParameters: params,
    );
    
    final articles = response.data as List;
    return articles.map((a) => MarketNews(
      id: a['id'].toString(),
      headline: a['headline'],
      summary: a['summary'],
      url: a['url'],
      source: a['source'],
      publishedAt: DateTime.fromMillisecondsSinceEpoch(a['datetime'] * 1000),
      symbols: symbol != null ? [symbol] : [],
      sentiment: 0.0,
    )).toList();
  }

  Future<List<MarketNews>> _getNewsFromPolygon(String? symbol) async {
    final params = {
      'apiKey': _polygonKey,
      'limit': 10,
    };
    
    if (symbol != null) {
      params['ticker'] = symbol;
    }
    
    final response = await _dio.get(
      'https://api.polygon.io/v2/reference/news',
      queryParameters: params,
    );
    
    final results = response.data['results'] as List;
    return results.map((r) => MarketNews(
      id: r['id'],
      headline: r['title'],
      summary: r['description'] ?? '',
      url: r['article_url'],
      source: r['publisher']['name'],
      publishedAt: DateTime.parse(r['published_utc']),
      symbols: List<String>.from(r['tickers'] ?? []),
      sentiment: 0.0,
    )).toList();
  }

  // Technical indicator calculations
  double _calculateSMA(List<double> values, int period) {
    if (values.length < period) return 0.0;
    
    final slice = values.sublist(values.length - period);
    return slice.reduce((a, b) => a + b) / period;
  }

  double _calculateEMA(List<double> values, int period) {
    if (values.length < period) return 0.0;
    
    final multiplier = 2.0 / (period + 1);
    double ema = _calculateSMA(values.sublist(0, period), period);
    
    for (int i = period; i < values.length; i++) {
      ema = ((values[i] - ema) * multiplier) + ema;
    }
    
    return ema;
  }

  double _calculateRSI(List<double> values, int period) {
    if (values.length < period + 1) return 50.0;
    
    final gains = <double>[];
    final losses = <double>[];
    
    for (int i = 1; i < values.length; i++) {
      final change = values[i] - values[i - 1];
      if (change > 0) {
        gains.add(change);
        losses.add(0);
      } else {
        gains.add(0);
        losses.add(-change);
      }
    }
    
    final avgGain = gains.sublist(gains.length - period).reduce((a, b) => a + b) / period;
    final avgLoss = losses.sublist(losses.length - period).reduce((a, b) => a + b) / period;
    
    if (avgLoss == 0) return 100.0;
    
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  MACDResult _calculateMACD(List<double> values) {
    final ema12 = _calculateEMA(values, 12);
    final ema26 = _calculateEMA(values, 26);
    final macdLine = ema12 - ema26;
    
    // Simplified - in production you'd calculate the signal line properly
    final signalLine = macdLine * 0.9;
    final histogram = macdLine - signalLine;
    
    return MACDResult(
      macdLine: macdLine,
      signalLine: signalLine,
      histogram: histogram,
    );
  }

  BollingerBands _calculateBollingerBands(List<double> values, int period) {
    final sma = _calculateSMA(values, period);
    
    if (values.length < period) {
      return BollingerBands(upper: sma, middle: sma, lower: sma);
    }
    
    final slice = values.sublist(values.length - period);
    final variance = slice.map((v) => (v - sma) * (v - sma)).reduce((a, b) => a + b) / period;
    final stdDev = variance > 0 ? variance : 0;
    final stdDevSqrt = stdDev > 0 ? (stdDev as double) : 0.0;
    
    return BollingerBands(
      upper: sma + (2 * stdDevSqrt),
      middle: sma,
      lower: sma - (2 * stdDevSqrt),
    );
  }

  void _cacheQuote(String symbol, MarketQuote quote) {
    _quoteCache[symbol] = quote;
    _cacheExpiry[symbol] = DateTime.now().add(_cacheDuration);
  }

  List<MarketNews> _removeDuplicateNews(List<MarketNews> news) {
    final seen = <String>{};
    return news.where((n) => seen.add(n.headline)).toList();
  }

  String? _generatePriceAlertItem(MarketQuote quote) {
    // Generate RSS item for significant price changes
    if (quote.changePercent.abs() > 5) {
      final direction = quote.changePercent > 0 ? 'up' : 'down';
      return '''<item>
      <title>${quote.symbol} ${direction} ${quote.changePercent.abs().toStringAsFixed(2)}%</title>
      <description>${quote.symbol} is trading at \$${quote.price.toStringAsFixed(2)}, ${direction} ${quote.changePercent.abs().toStringAsFixed(2)}% from previous close</description>
      <link>https://example.com/quote/${quote.symbol}</link>
      <guid>${quote.symbol}-${DateTime.now().millisecondsSinceEpoch}</guid>
      <pubDate>${DateTime.now().toUtc().toIso8601String()}</pubDate>
    </item>''';
    }
    return null;
  }

  String _generateNewsItem(MarketNews news) {
    return '''<item>
      <title>${_escapeXml(news.headline)}</title>
      <description>${_escapeXml(news.summary)}</description>
      <link>${news.url}</link>
      <guid>${news.id}</guid>
      <pubDate>${news.publishedAt.toUtc().toIso8601String()}</pubDate>
    </item>''';
  }

  String? _generateTechnicalTriggerItem(MarketQuote quote, TechnicalIndicators indicators) {
    // Generate RSS item for technical triggers
    final triggers = <String>[];
    
    if (indicators.rsi > 70) {
      triggers.add('RSI overbought (${indicators.rsi.toStringAsFixed(2)})');
    } else if (indicators.rsi < 30) {
      triggers.add('RSI oversold (${indicators.rsi.toStringAsFixed(2)})');
    }
    
    if (quote.price > indicators.sma200 && indicators.sma50 > indicators.sma200) {
      triggers.add('Bullish trend confirmed');
    }
    
    if (triggers.isNotEmpty) {
      return '''<item>
      <title>${quote.symbol} Technical Alert</title>
      <description>${triggers.join(', ')}</description>
      <link>https://example.com/analysis/${quote.symbol}</link>
      <guid>${quote.symbol}-tech-${DateTime.now().millisecondsSinceEpoch}</guid>
      <pubDate>${DateTime.now().toUtc().toIso8601String()}</pubDate>
    </item>''';
    }
    return null;
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  void dispose() {
    _finnhubStream?.close();
    _polygonStream?.close();
  }
}

// Supporting classes
class MarketFeedOptions {
  final bool includePriceAlerts;
  final bool includeNews;
  final bool includeTechnicalTriggers;
  final bool includeEarnings;
  final double priceAlertThreshold;
  
  MarketFeedOptions({
    this.includePriceAlerts = true,
    this.includeNews = true,
    this.includeTechnicalTriggers = true,
    this.includeEarnings = true,
    this.priceAlertThreshold = 5.0,
  });
}

class MACDResult {
  final double macdLine;
  final double signalLine;
  final double histogram;
  
  MACDResult({
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });
}

class BollingerBands {
  final double upper;
  final double middle;
  final double lower;
  
  BollingerBands({
    required this.upper,
    required this.middle,
    required this.lower,
  });
}