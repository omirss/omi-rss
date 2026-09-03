import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'market_service.dart';

/// Polygon.io provider for real-time market data
class PolygonProvider extends MarketDataProvider {
  final String apiKey;
  final Dio _dio;
  WebSocketChannel? _wsChannel;
  final Map<String, StreamController<StockQuote>> _stockStreams = {};
  final Map<String, StreamController<CryptoQuote>> _cryptoStreams = {};
  static const String baseUrl = 'https://api.polygon.io';
  static const String wsUrl = 'wss://socket.polygon.io';

  PolygonProvider({required this.apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          queryParameters: {'apikey': apiKey},
        ));

  @override
  String get name => 'Polygon.io';

  @override
  Future<void> initialize() async {
    try {
      await _dio.get('/v2/aggs/ticker/AAPL/prev');
    } catch (e) {
      throw Exception('Invalid Polygon.io API key');
    }
  }

  @override
  Future<StockQuote?> getStockQuote(String symbol) async {
    try {
      final [snapshotResponse, detailsResponse] = await Future.wait([
        _dio.get('/v2/snapshot/locale/us/markets/stocks/tickers/$symbol'),
        _dio.get('/v3/reference/tickers/$symbol'),
      ]);

      final snapshot = snapshotResponse.data['ticker'];
      final details = detailsResponse.data['results'];

      if (snapshot == null) return null;

      final day = snapshot['day'];
      final prevDay = snapshot['prevDay'];
      final min = snapshot['min'];

      return StockQuote(
        symbol: symbol,
        name: details?['name'] ?? symbol,
        exchange: details?['primary_exchange'] ?? '',
        price: min?['c']?.toDouble() ?? day['c'].toDouble(),
        change: (day['c'] - prevDay['c']).toDouble(),
        changePercent: ((day['c'] - prevDay['c']) / prevDay['c'] * 100).toDouble(),
        dayHigh: day['h'].toDouble(),
        dayLow: day['l'].toDouble(),
        open: day['o'].toDouble(),
        previousClose: prevDay['c'].toDouble(),
        volume: day['v'].toInt(),
        marketCap: details?['market_cap']?.toDouble() ?? 0,
        pe: 0,
        eps: 0,
        fiftyTwoWeekHigh: 0,
        fiftyTwoWeekLow: 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(snapshot['updated']),
        extended: {
          'vwap': day['vw'],
          'transactions': day['n'],
        },
      );
    } catch (e) {
      print('Error fetching stock quote from Polygon: $e');
      return null;
    }
  }

  @override
  Future<List<StockQuote>> getStockQuotes(List<String> symbols) async {
    try {
      final response = await _dio.get('/v2/snapshot/locale/us/markets/stocks/tickers',
          queryParameters: {'tickers': symbols.join(',')});

      final tickers = response.data['tickers'] as List;
      return tickers.map((ticker) {
        final day = ticker['day'];
        final prevDay = ticker['prevDay'];
        final min = ticker['min'];

        return StockQuote(
          symbol: ticker['ticker'],
          name: ticker['ticker'],
          exchange: '',
          price: min?['c']?.toDouble() ?? day['c'].toDouble(),
          change: (day['c'] - prevDay['c']).toDouble(),
          changePercent: ((day['c'] - prevDay['c']) / prevDay['c'] * 100).toDouble(),
          dayHigh: day['h'].toDouble(),
          dayLow: day['l'].toDouble(),
          open: day['o'].toDouble(),
          previousClose: prevDay['c'].toDouble(),
          volume: day['v'].toInt(),
          marketCap: 0,
          pe: 0,
          eps: 0,
          fiftyTwoWeekHigh: 0,
          fiftyTwoWeekLow: 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(ticker['updated']),
        );
      }).toList();
    } catch (e) {
      print('Error fetching stock quotes from Polygon: $e');
      return [];
    }
  }

  @override
  Future<CryptoQuote?> getCryptoQuote(String symbol) async {
    try {
      final response = await _dio.get('/v2/snapshot/locale/global/markets/crypto/tickers/X:${symbol}USD');
      final ticker = response.data['ticker'];

      if (ticker == null) return null;

      final day = ticker['day'];
      final prevDay = ticker['prevDay'];
      final min = ticker['min'];

      return CryptoQuote(
        symbol: symbol,
        name: symbol,
        price: min?['c']?.toDouble() ?? day['c'].toDouble(),
        change24h: (day['c'] - prevDay['c']).toDouble(),
        changePercent24h: ((day['c'] - prevDay['c']) / prevDay['c'] * 100).toDouble(),
        high24h: day['h'].toDouble(),
        low24h: day['l'].toDouble(),
        volume24h: day['v'].toDouble(),
        marketCap: 0,
        circulatingSupply: 0,
        totalSupply: 0,
        rank: 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(ticker['updated']),
      );
    } catch (e) {
      print('Error fetching crypto quote from Polygon: $e');
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
    if (pair.length != 6) return null;
    final from = pair.substring(0, 3);
    final to = pair.substring(3);

    try {
      final response = await _dio.get('/v2/snapshot/locale/global/markets/forex/tickers/C:$from$to');
      final ticker = response.data['ticker'];

      if (ticker == null) return null;

      final day = ticker['day'];
      final prevDay = ticker['prevDay'];
      final min = ticker['min'];

      final rate = min?['c']?.toDouble() ?? day['c'].toDouble();
      return ForexQuote(
        pair: pair,
        rate: rate,
        change: (day['c'] - prevDay['c']).toDouble(),
        changePercent: ((day['c'] - prevDay['c']) / prevDay['c'] * 100).toDouble(),
        bid: rate,
        ask: rate,
        spread: 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(ticker['updated']),
      );
    } catch (e) {
      print('Error fetching forex quote from Polygon: $e');
      return null;
    }
  }

  @override
  Future<List<MarketNews>> getMarketNews({List<String>? symbols}) async {
    try {
      final params = <String, dynamic>{
        'limit': 50,
        'order': 'desc',
      };

      if (symbols != null && symbols.isNotEmpty) {
        params['ticker'] = symbols.join(',');
      }

      final response = await _dio.get('/v2/reference/news', queryParameters: params);
      final articles = response.data['results'] as List;

      return articles.map((article) {
        return MarketNews(
          id: article['id'],
          title: article['title'],
          summary: article['description'] ?? '',
          url: article['article_url'],
          source: article['publisher']['name'],
          symbols: (article['tickers'] as List?)?.cast<String>() ?? [],
          publishedAt: DateTime.parse(article['published_utc']),
          imageUrl: article['image_url'],
        );
      }).toList();
    } catch (e) {
      print('Error fetching market news from Polygon: $e');
      return [];
    }
  }

  void _connectWebSocket() {
    if (_wsChannel != null) return;

    _wsChannel = WebSocketChannel.connect(
      Uri.parse('$wsUrl/stocks'),
    );

    // Authenticate
    _wsChannel!.sink.add(jsonEncode({
      'action': 'auth',
      'params': apiKey,
    }));

    _wsChannel!.stream.listen((message) {
      final data = jsonDecode(message) as List;
      
      for (final msg in data) {
        switch (msg['ev']) {
          case 'status':
            if (msg['status'] == 'auth_success') {
              print('Polygon WebSocket authenticated');
            }
            break;
            
          case 'T': // Trade
            final symbol = msg['sym'];
            final price = msg['p'].toDouble();
            final volume = msg['s'];
            final timestamp = DateTime.fromMillisecondsSinceEpoch(msg['t']);
            
            if (_stockStreams.containsKey(symbol)) {
              final quote = StockQuote(
                symbol: symbol,
                name: symbol,
                exchange: msg['x'] ?? '',
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
            break;
            
          case 'XQ': // Crypto quote
            final symbol = msg['pair'].replaceAll('USD', '');
            final price = msg['lp'].toDouble();
            final timestamp = DateTime.fromMillisecondsSinceEpoch(msg['t']);
            
            if (_cryptoStreams.containsKey(symbol)) {
              final quote = CryptoQuote(
                symbol: symbol,
                name: symbol,
                price: price,
                change24h: 0,
                changePercent24h: 0,
                high24h: price,
                low24h: price,
                volume24h: 0,
                marketCap: 0,
                circulatingSupply: 0,
                totalSupply: 0,
                rank: 0,
                timestamp: timestamp,
              );
              _cryptoStreams[symbol]!.add(quote);
            }
            break;
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
      'action': 'subscribe',
      'params': 'T.$symbol',
    }));
  }

  void _subscribeToCrypto(String symbol) {
    _wsChannel?.sink.add(jsonEncode({
      'action': 'subscribe',
      'params': 'XQ.${symbol}USD',
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