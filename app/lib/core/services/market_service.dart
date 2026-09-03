import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../database/database.dart';

/// Market data models
class StockQuote {
  final String symbol;
  final String name;
  final String exchange;
  final double price;
  final double change;
  final double changePercent;
  final double dayHigh;
  final double dayLow;
  final double open;
  final double previousClose;
  final int volume;
  final double marketCap;
  final double pe;
  final double eps;
  final double fiftyTwoWeekHigh;
  final double fiftyTwoWeekLow;
  final DateTime timestamp;
  final Map<String, dynamic> extended;

  StockQuote({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.dayHigh,
    required this.dayLow,
    required this.open,
    required this.previousClose,
    required this.volume,
    required this.marketCap,
    required this.pe,
    required this.eps,
    required this.fiftyTwoWeekHigh,
    required this.fiftyTwoWeekLow,
    required this.timestamp,
    this.extended = const {},
  });
}

class CryptoQuote {
  final String symbol;
  final String name;
  final double price;
  final double change24h;
  final double changePercent24h;
  final double high24h;
  final double low24h;
  final double volume24h;
  final double marketCap;
  final double circulatingSupply;
  final double totalSupply;
  final int rank;
  final DateTime timestamp;
  final Map<String, dynamic> extended;

  CryptoQuote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change24h,
    required this.changePercent24h,
    required this.high24h,
    required this.low24h,
    required this.volume24h,
    required this.marketCap,
    required this.circulatingSupply,
    required this.totalSupply,
    required this.rank,
    required this.timestamp,
    this.extended = const {},
  });
}

class ForexQuote {
  final String pair;
  final double rate;
  final double change;
  final double changePercent;
  final double bid;
  final double ask;
  final double spread;
  final DateTime timestamp;

  ForexQuote({
    required this.pair,
    required this.rate,
    required this.change,
    required this.changePercent,
    required this.bid,
    required this.ask,
    required this.spread,
    required this.timestamp,
  });
}

class MarketNews {
  final String id;
  final String title;
  final String summary;
  final String url;
  final String source;
  final List<String> symbols;
  final DateTime publishedAt;
  final String? imageUrl;
  final double? sentiment;

  MarketNews({
    required this.id,
    required this.title,
    required this.summary,
    required this.url,
    required this.source,
    required this.symbols,
    required this.publishedAt,
    this.imageUrl,
    this.sentiment,
  });
}

/// Market data provider interface
abstract class MarketDataProvider {
  String get name;
  Future<void> initialize();
  Future<StockQuote?> getStockQuote(String symbol);
  Future<List<StockQuote>> getStockQuotes(List<String> symbols);
  Future<CryptoQuote?> getCryptoQuote(String symbol);
  Future<List<CryptoQuote>> getCryptoQuotes(List<String> symbols);
  Future<ForexQuote?> getForexQuote(String pair);
  Future<List<MarketNews>> getMarketNews({List<String>? symbols});
  Stream<StockQuote>? streamStockQuote(String symbol);
  Stream<CryptoQuote>? streamCryptoQuote(String symbol);
  void dispose();
}

/// Alpha Vantage provider
class AlphaVantageProvider extends MarketDataProvider {
  final String apiKey;
  final Dio _dio;
  static const String baseUrl = 'https://www.alphavantage.co/query';

  AlphaVantageProvider({required this.apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          queryParameters: {'apikey': apiKey},
        ));

  @override
  String get name => 'Alpha Vantage';

  @override
  Future<void> initialize() async {
    // Test API key
    try {
      await _dio.get('', queryParameters: {
        'function': 'TIME_SERIES_INTRADAY',
        'symbol': 'AAPL',
        'interval': '5min',
      });
    } catch (e) {
      throw Exception('Invalid Alpha Vantage API key');
    }
  }

  @override
  Future<StockQuote?> getStockQuote(String symbol) async {
    try {
      final response = await _dio.get('', queryParameters: {
        'function': 'GLOBAL_QUOTE',
        'symbol': symbol,
      });

      final data = response.data['Global Quote'];
      if (data == null) return null;

      return StockQuote(
        symbol: data['01. symbol'],
        name: symbol, // Alpha Vantage doesn't provide company names
        exchange: '',
        price: double.parse(data['05. price']),
        change: double.parse(data['09. change']),
        changePercent: double.parse(data['10. change percent'].replaceAll('%', '')),
        dayHigh: double.parse(data['03. high']),
        dayLow: double.parse(data['04. low']),
        open: double.parse(data['02. open']),
        previousClose: double.parse(data['08. previous close']),
        volume: int.parse(data['06. volume']),
        marketCap: 0, // Not provided
        pe: 0, // Not provided
        eps: 0, // Not provided
        fiftyTwoWeekHigh: 0, // Not provided
        fiftyTwoWeekLow: 0, // Not provided
        timestamp: DateTime.now(),
      );
    } catch (e) {
      print('Error fetching stock quote from Alpha Vantage: $e');
      return null;
    }
  }

  @override
  Future<List<StockQuote>> getStockQuotes(List<String> symbols) async {
    final quotes = <StockQuote>[];
    for (final symbol in symbols) {
      final quote = await getStockQuote(symbol);
      if (quote != null) quotes.add(quote);
      await Future.delayed(const Duration(milliseconds: 200)); // Rate limiting
    }
    return quotes;
  }

  @override
  Future<CryptoQuote?> getCryptoQuote(String symbol) async {
    try {
      final response = await _dio.get('', queryParameters: {
        'function': 'CURRENCY_EXCHANGE_RATE',
        'from_currency': symbol,
        'to_currency': 'USD',
      });

      final data = response.data['Realtime Currency Exchange Rate'];
      if (data == null) return null;

      return CryptoQuote(
        symbol: data['1. From_Currency Code'],
        name: data['2. From_Currency Name'],
        price: double.parse(data['5. Exchange Rate']),
        change24h: 0, // Not provided
        changePercent24h: 0, // Not provided
        high24h: 0, // Not provided
        low24h: 0, // Not provided
        volume24h: 0, // Not provided
        marketCap: 0, // Not provided
        circulatingSupply: 0, // Not provided
        totalSupply: 0, // Not provided
        rank: 0, // Not provided
        timestamp: DateTime.parse(data['6. Last Refreshed']),
      );
    } catch (e) {
      print('Error fetching crypto quote from Alpha Vantage: $e');
      return null;
    }
  }

  @override
  Future<List<CryptoQuote>> getCryptoQuotes(List<String> symbols) async {
    final quotes = <CryptoQuote>[];
    for (final symbol in symbols) {
      final quote = await getCryptoQuote(symbol);
      if (quote != null) quotes.add(quote);
      await Future.delayed(const Duration(milliseconds: 200)); // Rate limiting
    }
    return quotes;
  }

  @override
  Future<ForexQuote?> getForexQuote(String pair) async {
    if (pair.length != 6) return null;
    final from = pair.substring(0, 3);
    final to = pair.substring(3);

    try {
      final response = await _dio.get('', queryParameters: {
        'function': 'CURRENCY_EXCHANGE_RATE',
        'from_currency': from,
        'to_currency': to,
      });

      final data = response.data['Realtime Currency Exchange Rate'];
      if (data == null) return null;

      final rate = double.parse(data['5. Exchange Rate']);
      return ForexQuote(
        pair: pair,
        rate: rate,
        change: 0, // Not provided
        changePercent: 0, // Not provided
        bid: rate,
        ask: rate,
        spread: 0,
        timestamp: DateTime.parse(data['6. Last Refreshed']),
      );
    } catch (e) {
      print('Error fetching forex quote from Alpha Vantage: $e');
      return null;
    }
  }

  @override
  Future<List<MarketNews>> getMarketNews({List<String>? symbols}) async {
    // Alpha Vantage doesn't provide news
    return [];
  }

  @override
  Stream<StockQuote>? streamStockQuote(String symbol) {
    // Alpha Vantage doesn't support WebSocket streaming
    return null;
  }

  @override
  Stream<CryptoQuote>? streamCryptoQuote(String symbol) {
    // Alpha Vantage doesn't support WebSocket streaming
    return null;
  }

  @override
  void dispose() {
    _dio.close();
  }
}

/// Finnhub provider
class FinnhubProvider extends MarketDataProvider {
  final String apiKey;
  final Dio _dio;
  WebSocketChannel? _wsChannel;
  final Map<String, StreamController<StockQuote>> _stockStreams = {};
  final Map<String, StreamController<CryptoQuote>> _cryptoStreams = {};
  static const String baseUrl = 'https://finnhub.io/api/v1';
  static const String wsUrl = 'wss://ws.finnhub.io';

  FinnhubProvider({required this.apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {'X-Finnhub-Token': apiKey},
        ));

  @override
  String get name => 'Finnhub';

  @override
  Future<void> initialize() async {
    // Test API key
    try {
      await _dio.get('/stock/profile2', queryParameters: {'symbol': 'AAPL'});
    } catch (e) {
      throw Exception('Invalid Finnhub API key');
    }
  }

  @override
  Future<StockQuote?> getStockQuote(String symbol) async {
    try {
      final [quoteResponse, profileResponse] = await Future.wait([
        _dio.get('/quote', queryParameters: {'symbol': symbol}),
        _dio.get('/stock/profile2', queryParameters: {'symbol': symbol}),
      ]);

      final quote = quoteResponse.data;
      final profile = profileResponse.data;

      if (quote == null || quote['c'] == 0) return null;

      return StockQuote(
        symbol: symbol,
        name: profile['name'] ?? symbol,
        exchange: profile['exchange'] ?? '',
        price: quote['c'].toDouble(),
        change: quote['d']?.toDouble() ?? 0,
        changePercent: quote['dp']?.toDouble() ?? 0,
        dayHigh: quote['h'].toDouble(),
        dayLow: quote['l'].toDouble(),
        open: quote['o'].toDouble(),
        previousClose: quote['pc'].toDouble(),
        volume: 0, // Not in basic quote
        marketCap: profile['marketCapitalization']?.toDouble() ?? 0,
        pe: 0, // Would need to fetch metrics
        eps: 0, // Would need to fetch metrics
        fiftyTwoWeekHigh: 0, // Would need to fetch metrics
        fiftyTwoWeekLow: 0, // Would need to fetch metrics
        timestamp: DateTime.fromMillisecondsSinceEpoch(quote['t'] * 1000),
      );
    } catch (e) {
      print('Error fetching stock quote from Finnhub: $e');
      return null;
    }
  }

  @override
  Future<List<StockQuote>> getStockQuotes(List<String> symbols) async {
    final quotes = <StockQuote>[];
    for (final symbol in symbols) {
      final quote = await getStockQuote(symbol);
      if (quote != null) quotes.add(quote);
    }
    return quotes;
  }

  @override
  Future<CryptoQuote?> getCryptoQuote(String symbol) async {
    try {
      final response = await _dio.get('/crypto/candle', queryParameters: {
        'symbol': 'BINANCE:${symbol}USDT',
        'resolution': 'D',
        'count': 1,
      });

      final data = response.data;
      if (data == null || data['s'] != 'ok') return null;

      final close = data['c'].last.toDouble();
      final open = data['o'].last.toDouble();
      final high = data['h'].last.toDouble();
      final low = data['l'].last.toDouble();

      return CryptoQuote(
        symbol: symbol,
        name: symbol, // Finnhub doesn't provide crypto names
        price: close,
        change24h: close - open,
        changePercent24h: ((close - open) / open) * 100,
        high24h: high,
        low24h: low,
        volume24h: data['v'].last.toDouble(),
        marketCap: 0, // Not provided
        circulatingSupply: 0, // Not provided
        totalSupply: 0, // Not provided
        rank: 0, // Not provided
        timestamp: DateTime.fromMillisecondsSinceEpoch(data['t'].last * 1000),
      );
    } catch (e) {
      print('Error fetching crypto quote from Finnhub: $e');
      return null;
    }
  }

  @override
  Future<List<CryptoQuote>> getCryptoQuotes(List<String> symbols) async {
    final quotes = <CryptoQuote>[];
    for (final symbol in symbols) {
      final quote = await getCryptoQuote(symbol);
      if (quote != null) quotes.add(quote);
    }
    return quotes;
  }

  @override
  Future<ForexQuote?> getForexQuote(String pair) async {
    try {
      final response = await _dio.get('/forex/candle', queryParameters: {
        'symbol': 'OANDA:${pair.substring(0, 3)}_${pair.substring(3)}',
        'resolution': 'D',
        'count': 1,
      });

      final data = response.data;
      if (data == null || data['s'] != 'ok') return null;

      final close = data['c'].last.toDouble();
      final open = data['o'].last.toDouble();

      return ForexQuote(
        pair: pair,
        rate: close,
        change: close - open,
        changePercent: ((close - open) / open) * 100,
        bid: close,
        ask: close,
        spread: 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(data['t'].last * 1000),
      );
    } catch (e) {
      print('Error fetching forex quote from Finnhub: $e');
      return null;
    }
  }

  @override
  Future<List<MarketNews>> getMarketNews({List<String>? symbols}) async {
    try {
      final category = symbols != null && symbols.isNotEmpty ? 'company' : 'general';
      final params = <String, dynamic>{'category': category};
      
      if (symbols != null && symbols.isNotEmpty) {
        params['symbol'] = symbols.first;
      }

      final response = await _dio.get('/news', queryParameters: params);
      final articles = response.data as List;

      return articles.map((article) {
        return MarketNews(
          id: article['id'].toString(),
          title: article['headline'],
          summary: article['summary'],
          url: article['url'],
          source: article['source'],
          symbols: symbols ?? [],
          publishedAt: DateTime.fromMillisecondsSinceEpoch(article['datetime'] * 1000),
          imageUrl: article['image'],
        );
      }).toList();
    } catch (e) {
      print('Error fetching market news from Finnhub: $e');
      return [];
    }
  }

  void _connectWebSocket() {
    if (_wsChannel != null) return;

    _wsChannel = WebSocketChannel.connect(
      Uri.parse('$wsUrl?token=$apiKey'),
    );

    _wsChannel!.stream.listen((message) {
      final data = jsonDecode(message);
      if (data['type'] == 'trade') {
        final trades = data['data'] as List;
        for (final trade in trades) {
          final symbol = trade['s'];
          final price = trade['p'].toDouble();
          final volume = trade['v'];
          final timestamp = DateTime.fromMillisecondsSinceEpoch(trade['t']);

          // Update stock streams
          if (_stockStreams.containsKey(symbol)) {
            // Create a partial quote with real-time price
            final quote = StockQuote(
              symbol: symbol,
              name: symbol,
              exchange: '',
              price: price,
              change: 0,
              changePercent: 0,
              dayHigh: price,
              dayLow: price,
              open: price,
              previousClose: 0,
              volume: volume,
              marketCap: 0,
              pe: 0,
              eps: 0,
              fiftyTwoWeekHigh: 0,
              fiftyTwoWeekLow: 0,
              timestamp: timestamp,
            );
            _stockStreams[symbol]!.add(quote);
          }
        }
      }
    }, onError: (error) {
      print('WebSocket error: $error');
      _reconnectWebSocket();
    }, onDone: () {
      print('WebSocket connection closed');
      _reconnectWebSocket();
    });
  }

  void _reconnectWebSocket() {
    _wsChannel?.sink.close();
    _wsChannel = null;
    Future.delayed(const Duration(seconds: 5), () {
      if (_stockStreams.isNotEmpty || _cryptoStreams.isNotEmpty) {
        _connectWebSocket();
        // Re-subscribe to all symbols
        _stockStreams.keys.forEach(_subscribeToStock);
        _cryptoStreams.keys.forEach(_subscribeToCrypto);
      }
    });
  }

  void _subscribeToStock(String symbol) {
    _wsChannel?.sink.add(jsonEncode({
      'type': 'subscribe',
      'symbol': symbol,
    }));
  }

  void _subscribeToCrypto(String symbol) {
    _wsChannel?.sink.add(jsonEncode({
      'type': 'subscribe',
      'symbol': 'BINANCE:${symbol}USDT',
    }));
  }

  @override
  Stream<StockQuote>? streamStockQuote(String symbol) {
    if (!_stockStreams.containsKey(symbol)) {
      _stockStreams[symbol] = StreamController<StockQuote>.broadcast();
      if (_wsChannel == null) {
        _connectWebSocket();
      }
      _subscribeToStock(symbol);
    }
    return _stockStreams[symbol]!.stream;
  }

  @override
  Stream<CryptoQuote>? streamCryptoQuote(String symbol) {
    if (!_cryptoStreams.containsKey(symbol)) {
      _cryptoStreams[symbol] = StreamController<CryptoQuote>.broadcast();
      if (_wsChannel == null) {
        _connectWebSocket();
      }
      _subscribeToCrypto(symbol);
    }
    return _cryptoStreams[symbol]!.stream;
  }

  @override
  void dispose() {
    _dio.close();
    _wsChannel?.sink.close();
    for (final controller in _stockStreams.values) {
      controller.close();
    }
    for (final controller in _cryptoStreams.values) {
      controller.close();
    }
  }
}

/// Yahoo Finance provider
class YahooFinanceProvider extends MarketDataProvider {
  final Dio _dio;
  static const String baseUrl = 'https://query1.finance.yahoo.com';
  static const String baseUrl2 = 'https://query2.finance.yahoo.com';
  
  YahooFinanceProvider()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  @override
  String get name => 'Yahoo Finance';

  @override
  Future<void> initialize() async {
    // Test API access (Yahoo Finance doesn't require API key)
    try {
      await _dio.get('$baseUrl/v8/finance/quote?symbols=AAPL');
    } catch (e) {
      throw Exception('Unable to connect to Yahoo Finance');
    }
  }

  @override
  Future<StockQuote?> getStockQuote(String symbol) async {
    try {
      final response = await _dio.get(
        '$baseUrl/v8/finance/quote',
        queryParameters: {'symbols': symbol},
      );

      final data = response.data;
      if (data['quoteResponse'] == null || 
          data['quoteResponse']['result'] == null ||
          data['quoteResponse']['result'].isEmpty) {
        return null;
      }

      final quote = data['quoteResponse']['result'][0];
      
      return StockQuote(
        symbol: quote['symbol'] ?? symbol,
        name: quote['longName'] ?? quote['shortName'] ?? symbol,
        exchange: quote['exchange'] ?? '',
        price: (quote['regularMarketPrice'] ?? 0).toDouble(),
        change: (quote['regularMarketChange'] ?? 0).toDouble(),
        changePercent: (quote['regularMarketChangePercent'] ?? 0).toDouble(),
        dayHigh: (quote['regularMarketDayHigh'] ?? 0).toDouble(),
        dayLow: (quote['regularMarketDayLow'] ?? 0).toDouble(),
        open: (quote['regularMarketOpen'] ?? 0).toDouble(),
        previousClose: (quote['regularMarketPreviousClose'] ?? 0).toDouble(),
        volume: quote['regularMarketVolume'] ?? 0,
        marketCap: (quote['marketCap'] ?? 0).toDouble(),
        pe: (quote['trailingPE'] ?? 0).toDouble(),
        eps: (quote['epsTrailingTwelveMonths'] ?? 0).toDouble(),
        fiftyTwoWeekHigh: (quote['fiftyTwoWeekHigh'] ?? 0).toDouble(),
        fiftyTwoWeekLow: (quote['fiftyTwoWeekLow'] ?? 0).toDouble(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (quote['regularMarketTime'] ?? 0) * 1000,
        ),
        extended: {
          'bid': quote['bid'],
          'ask': quote['ask'],
          'bidSize': quote['bidSize'],
          'askSize': quote['askSize'],
          'dividendYield': quote['dividendYield'],
          'beta': quote['beta'],
          'priceToBook': quote['priceToBook'],
        },
      );
    } catch (e) {
      print('Error fetching stock quote from Yahoo Finance: $e');
      return null;
    }
  }

  @override
  Future<List<StockQuote>> getStockQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return [];
    
    try {
      // Yahoo Finance supports batch requests
      final response = await _dio.get(
        '$baseUrl/v8/finance/quote',
        queryParameters: {'symbols': symbols.join(',')},
      );

      final data = response.data;
      if (data['quoteResponse'] == null || 
          data['quoteResponse']['result'] == null) {
        return [];
      }

      final quotes = <StockQuote>[];
      for (final quoteData in data['quoteResponse']['result']) {
        final quote = StockQuote(
          symbol: quoteData['symbol'],
          name: quoteData['longName'] ?? quoteData['shortName'] ?? quoteData['symbol'],
          exchange: quoteData['exchange'] ?? '',
          price: (quoteData['regularMarketPrice'] ?? 0).toDouble(),
          change: (quoteData['regularMarketChange'] ?? 0).toDouble(),
          changePercent: (quoteData['regularMarketChangePercent'] ?? 0).toDouble(),
          dayHigh: (quoteData['regularMarketDayHigh'] ?? 0).toDouble(),
          dayLow: (quoteData['regularMarketDayLow'] ?? 0).toDouble(),
          open: (quoteData['regularMarketOpen'] ?? 0).toDouble(),
          previousClose: (quoteData['regularMarketPreviousClose'] ?? 0).toDouble(),
          volume: quoteData['regularMarketVolume'] ?? 0,
          marketCap: (quoteData['marketCap'] ?? 0).toDouble(),
          pe: (quoteData['trailingPE'] ?? 0).toDouble(),
          eps: (quoteData['epsTrailingTwelveMonths'] ?? 0).toDouble(),
          fiftyTwoWeekHigh: (quoteData['fiftyTwoWeekHigh'] ?? 0).toDouble(),
          fiftyTwoWeekLow: (quoteData['fiftyTwoWeekLow'] ?? 0).toDouble(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (quoteData['regularMarketTime'] ?? 0) * 1000,
          ),
        );
        quotes.add(quote);
      }
      
      return quotes;
    } catch (e) {
      print('Error fetching stock quotes from Yahoo Finance: $e');
      return [];
    }
  }

  @override
  Future<CryptoQuote?> getCryptoQuote(String symbol) async {
    try {
      // Yahoo Finance uses different symbols for crypto (e.g., BTC-USD)
      final yahooSymbol = symbol.contains('-') ? symbol : '$symbol-USD';
      
      final response = await _dio.get(
        '$baseUrl/v8/finance/quote',
        queryParameters: {'symbols': yahooSymbol},
      );

      final data = response.data;
      if (data['quoteResponse'] == null || 
          data['quoteResponse']['result'] == null ||
          data['quoteResponse']['result'].isEmpty) {
        return null;
      }

      final quote = data['quoteResponse']['result'][0];
      
      return CryptoQuote(
        symbol: symbol,
        name: quote['longName'] ?? quote['shortName'] ?? symbol,
        price: (quote['regularMarketPrice'] ?? 0).toDouble(),
        change24h: (quote['regularMarketChange'] ?? 0).toDouble(),
        changePercent24h: (quote['regularMarketChangePercent'] ?? 0).toDouble(),
        high24h: (quote['regularMarketDayHigh'] ?? 0).toDouble(),
        low24h: (quote['regularMarketDayLow'] ?? 0).toDouble(),
        volume24h: (quote['regularMarketVolume'] ?? 0).toDouble(),
        marketCap: (quote['marketCap'] ?? 0).toDouble(),
        circulatingSupply: (quote['circulatingSupply'] ?? 0).toDouble(),
        totalSupply: 0, // Not provided by Yahoo
        rank: 0, // Not provided by Yahoo
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (quote['regularMarketTime'] ?? 0) * 1000,
        ),
      );
    } catch (e) {
      print('Error fetching crypto quote from Yahoo Finance: $e');
      return null;
    }
  }

  @override
  Future<List<CryptoQuote>> getCryptoQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return [];
    
    try {
      // Convert symbols to Yahoo format
      final yahooSymbols = symbols.map((s) => 
        s.contains('-') ? s : '$s-USD'
      ).toList();
      
      final response = await _dio.get(
        '$baseUrl/v8/finance/quote',
        queryParameters: {'symbols': yahooSymbols.join(',')},
      );

      final data = response.data;
      if (data['quoteResponse'] == null || 
          data['quoteResponse']['result'] == null) {
        return [];
      }

      final quotes = <CryptoQuote>[];
      for (final quoteData in data['quoteResponse']['result']) {
        // Extract original symbol from Yahoo symbol
        final originalSymbol = quoteData['symbol'].replaceAll('-USD', '');
        
        final quote = CryptoQuote(
          symbol: originalSymbol,
          name: quoteData['longName'] ?? quoteData['shortName'] ?? originalSymbol,
          price: (quoteData['regularMarketPrice'] ?? 0).toDouble(),
          change24h: (quoteData['regularMarketChange'] ?? 0).toDouble(),
          changePercent24h: (quoteData['regularMarketChangePercent'] ?? 0).toDouble(),
          high24h: (quoteData['regularMarketDayHigh'] ?? 0).toDouble(),
          low24h: (quoteData['regularMarketDayLow'] ?? 0).toDouble(),
          volume24h: (quoteData['regularMarketVolume'] ?? 0).toDouble(),
          marketCap: (quoteData['marketCap'] ?? 0).toDouble(),
          circulatingSupply: (quoteData['circulatingSupply'] ?? 0).toDouble(),
          totalSupply: 0,
          rank: 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (quoteData['regularMarketTime'] ?? 0) * 1000,
          ),
        );
        quotes.add(quote);
      }
      
      return quotes;
    } catch (e) {
      print('Error fetching crypto quotes from Yahoo Finance: $e');
      return [];
    }
  }

  @override
  Future<ForexQuote?> getForexQuote(String pair) async {
    try {
      // Yahoo Finance uses format like EURUSD=X for forex
      final yahooSymbol = '$pair=X';
      
      final response = await _dio.get(
        '$baseUrl/v8/finance/quote',
        queryParameters: {'symbols': yahooSymbol},
      );

      final data = response.data;
      if (data['quoteResponse'] == null || 
          data['quoteResponse']['result'] == null ||
          data['quoteResponse']['result'].isEmpty) {
        return null;
      }

      final quote = data['quoteResponse']['result'][0];
      final rate = (quote['regularMarketPrice'] ?? 0).toDouble();
      
      return ForexQuote(
        pair: pair,
        rate: rate,
        change: (quote['regularMarketChange'] ?? 0).toDouble(),
        changePercent: (quote['regularMarketChangePercent'] ?? 0).toDouble(),
        bid: (quote['bid'] ?? rate).toDouble(),
        ask: (quote['ask'] ?? rate).toDouble(),
        spread: ((quote['ask'] ?? rate) - (quote['bid'] ?? rate)).toDouble(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (quote['regularMarketTime'] ?? 0) * 1000,
        ),
      );
    } catch (e) {
      print('Error fetching forex quote from Yahoo Finance: $e');
      return null;
    }
  }

  @override
  Future<List<MarketNews>> getMarketNews({List<String>? symbols}) async {
    try {
      // Yahoo Finance RSS feeds for news
      final url = symbols != null && symbols.isNotEmpty
          ? 'https://feeds.finance.yahoo.com/rss/2.0/headline?s=${symbols.join(",")}&region=US&lang=en-US'
          : 'https://feeds.finance.yahoo.com/rss/2.0/topstories';
      
      final response = await _dio.get(url);
      
      // Parse RSS feed (simplified - in production use proper XML parser)
      final news = <MarketNews>[];
      final content = response.data.toString();
      final items = content.split('<item>').skip(1);
      
      for (final item in items) {
        try {
          final title = _extractTag(item, 'title');
          final link = _extractTag(item, 'link');
          final description = _extractTag(item, 'description');
          final pubDate = _extractTag(item, 'pubDate');
          
          if (title != null && link != null) {
            news.add(MarketNews(
              id: link.hashCode.toString(),
              title: title,
              summary: description ?? '',
              url: link,
              source: 'Yahoo Finance',
              symbols: symbols ?? [],
              publishedAt: _parseRssDate(pubDate),
            ));
          }
        } catch (e) {
          // Skip malformed items
        }
      }
      
      return news.take(20).toList(); // Limit to 20 items
    } catch (e) {
      print('Error fetching market news from Yahoo Finance: $e');
      return [];
    }
  }

  String? _extractTag(String content, String tag) {
    final regex = RegExp('<$tag><!\\[CDATA\\[(.+?)\\]\\]></$tag>|<$tag>(.+?)</$tag>');
    final match = regex.firstMatch(content);
    if (match != null) {
      return match.group(1) ?? match.group(2);
    }
    return null;
  }

  DateTime _parseRssDate(String? dateStr) {
    if (dateStr == null) return DateTime.now();
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      // Try alternative parsing
      return DateTime.now();
    }
  }

  @override
  Stream<StockQuote>? streamStockQuote(String symbol) {
    // Yahoo Finance doesn't provide WebSocket streaming
    // Could implement polling-based pseudo-streaming if needed
    return null;
  }

  @override
  Stream<CryptoQuote>? streamCryptoQuote(String symbol) {
    // Yahoo Finance doesn't provide WebSocket streaming
    return null;
  }

  @override
  void dispose() {
    _dio.close();
  }
}

/// Market service with provider management
class MarketService {
  final AppDatabase _database;
  final List<MarketDataProvider> _providers = [];
  MarketDataProvider? _primaryProvider;
  final Map<String, StockQuote> _stockCache = {};
  final Map<String, CryptoQuote> _cryptoCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 1);

  MarketService({required AppDatabase database}) : _database = database;

  Future<void> initialize() async {
    // Load API keys from settings
    // For now, using placeholder keys
    _providers.addAll([
      YahooFinanceProvider(), // No API key required
      AlphaVantageProvider(apiKey: 'YOUR_ALPHA_VANTAGE_KEY'),
      FinnhubProvider(apiKey: 'YOUR_FINNHUB_KEY'),
    ]);

    // Initialize providers
    for (final provider in _providers) {
      try {
        await provider.initialize();
        _primaryProvider ??= provider;
      } catch (e) {
        print('Failed to initialize ${provider.name}: $e');
      }
    }

    if (_primaryProvider == null) {
      throw Exception('No market data providers available');
    }
  }

  Future<StockQuote?> getStockQuote(String symbol) async {
    // Check cache
    if (_stockCache.containsKey(symbol)) {
      final timestamp = _cacheTimestamps[symbol];
      if (timestamp != null && 
          DateTime.now().difference(timestamp) < _cacheExpiry) {
        return _stockCache[symbol];
      }
    }

    // Try primary provider first
    var quote = await _primaryProvider!.getStockQuote(symbol);
    
    // Fallback to other providers
    if (quote == null) {
      for (final provider in _providers) {
        if (provider != _primaryProvider) {
          quote = await provider.getStockQuote(symbol);
          if (quote != null) break;
        }
      }
    }

    // Cache the result
    if (quote != null) {
      _stockCache[symbol] = quote;
      _cacheTimestamps[symbol] = DateTime.now();
    }

    return quote;
  }

  Future<List<StockQuote>> getStockQuotes(List<String> symbols) async {
    final quotes = <StockQuote>[];
    
    // Batch fetch if supported, otherwise fetch individually
    for (final symbol in symbols) {
      final quote = await getStockQuote(symbol);
      if (quote != null) quotes.add(quote);
    }
    
    return quotes;
  }

  Future<CryptoQuote?> getCryptoQuote(String symbol) async {
    // Check cache
    if (_cryptoCache.containsKey(symbol)) {
      final timestamp = _cacheTimestamps['crypto_$symbol'];
      if (timestamp != null && 
          DateTime.now().difference(timestamp) < _cacheExpiry) {
        return _cryptoCache[symbol];
      }
    }

    // Try primary provider first
    var quote = await _primaryProvider!.getCryptoQuote(symbol);
    
    // Fallback to other providers
    if (quote == null) {
      for (final provider in _providers) {
        if (provider != _primaryProvider) {
          quote = await provider.getCryptoQuote(symbol);
          if (quote != null) break;
        }
      }
    }

    // Cache the result
    if (quote != null) {
      _cryptoCache[symbol] = quote;
      _cacheTimestamps['crypto_$symbol'] = DateTime.now();
    }

    return quote;
  }

  Future<List<CryptoQuote>> getCryptoQuotes(List<String> symbols) async {
    final quotes = <CryptoQuote>[];
    
    for (final symbol in symbols) {
      final quote = await getCryptoQuote(symbol);
      if (quote != null) quotes.add(quote);
    }
    
    return quotes;
  }

  Future<ForexQuote?> getForexQuote(String pair) async {
    // Try primary provider first
    var quote = await _primaryProvider!.getForexQuote(pair);
    
    // Fallback to other providers
    if (quote == null) {
      for (final provider in _providers) {
        if (provider != _primaryProvider) {
          quote = await provider.getForexQuote(pair);
          if (quote != null) break;
        }
      }
    }

    return quote;
  }

  Future<List<MarketNews>> getMarketNews({List<String>? symbols}) async {
    final allNews = <MarketNews>[];
    
    // Aggregate news from all providers
    for (final provider in _providers) {
      try {
        final news = await provider.getMarketNews(symbols: symbols);
        allNews.addAll(news);
      } catch (e) {
        print('Error fetching news from ${provider.name}: $e');
      }
    }

    // Remove duplicates based on URL
    final uniqueNews = <String, MarketNews>{};
    for (final article in allNews) {
      uniqueNews[article.url] = article;
    }

    // Sort by date
    final sortedNews = uniqueNews.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    return sortedNews;
  }

  Stream<StockQuote>? streamStockQuote(String symbol) {
    // Try to get stream from providers
    for (final provider in _providers) {
      final stream = provider.streamStockQuote(symbol);
      if (stream != null) return stream;
    }
    return null;
  }

  Stream<CryptoQuote>? streamCryptoQuote(String symbol) {
    // Try to get stream from providers
    for (final provider in _providers) {
      final stream = provider.streamCryptoQuote(symbol);
      if (stream != null) return stream;
    }
    return null;
  }

  void switchProvider(String providerName) {
    final provider = _providers.firstWhere(
      (p) => p.name == providerName,
      orElse: () => _primaryProvider!,
    );
    _primaryProvider = provider;
  }

  List<String> getAvailableProviders() {
    return _providers.map((p) => p.name).toList();
  }

  void dispose() {
    for (final provider in _providers) {
      provider.dispose();
    }
  }
}