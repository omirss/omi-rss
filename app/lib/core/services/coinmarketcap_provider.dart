import 'dart:async';
import 'package:dio/dio.dart';
import 'market_service.dart';

/// CoinMarketCap provider for cryptocurrency data
class CoinMarketCapProvider extends MarketDataProvider {
  final String apiKey;
  final Dio _dio;
  static const String baseUrl = 'https://pro-api.coinmarketcap.com/v1';

  CoinMarketCapProvider({required this.apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {'X-CMC_PRO_API_KEY': apiKey},
        ));

  @override
  String get name => 'CoinMarketCap';

  @override
  Future<void> initialize() async {
    try {
      await _dio.get('/cryptocurrency/map', queryParameters: {'limit': 1});
    } catch (e) {
      throw Exception('Invalid CoinMarketCap API key');
    }
  }

  @override
  Future<StockQuote?> getStockQuote(String symbol) async {
    // CoinMarketCap doesn't provide stock data
    return null;
  }

  @override
  Future<List<StockQuote>> getStockQuotes(List<String> symbols) async {
    // CoinMarketCap doesn't provide stock data
    return [];
  }

  @override
  Future<CryptoQuote?> getCryptoQuote(String symbol) async {
    try {
      final response = await _dio.get('/cryptocurrency/quotes/latest',
          queryParameters: {'symbol': symbol, 'convert': 'USD'});

      final data = response.data['data'];
      if (data == null) return null;

      final crypto = data[symbol];
      if (crypto == null) return null;

      final quote = crypto['quote']['USD'];

      return CryptoQuote(
        symbol: crypto['symbol'],
        name: crypto['name'],
        price: quote['price'].toDouble(),
        change24h: quote['volume_change_24h']?.toDouble() ?? 0,
        changePercent24h: quote['percent_change_24h'].toDouble(),
        high24h: 0, // Not provided in basic quote
        low24h: 0, // Not provided in basic quote
        volume24h: quote['volume_24h'].toDouble(),
        marketCap: quote['market_cap'].toDouble(),
        circulatingSupply: crypto['circulating_supply']?.toDouble() ?? 0,
        totalSupply: crypto['total_supply']?.toDouble() ?? 0,
        rank: crypto['cmc_rank'],
        timestamp: DateTime.parse(quote['last_updated']),
        extended: {
          'percent_change_1h': quote['percent_change_1h'],
          'percent_change_7d': quote['percent_change_7d'],
          'percent_change_30d': quote['percent_change_30d'],
          'market_cap_dominance': quote['market_cap_dominance'],
        },
      );
    } catch (e) {
      print('Error fetching crypto quote from CoinMarketCap: $e');
      return null;
    }
  }

  @override
  Future<List<CryptoQuote>> getCryptoQuotes(List<String> symbols) async {
    try {
      final response = await _dio.get('/cryptocurrency/quotes/latest',
          queryParameters: {'symbol': symbols.join(','), 'convert': 'USD'});

      final data = response.data['data'];
      if (data == null) return [];

      final quotes = <CryptoQuote>[];
      for (final symbol in symbols) {
        final crypto = data[symbol];
        if (crypto == null) continue;

        final quote = crypto['quote']['USD'];
        quotes.add(CryptoQuote(
          symbol: crypto['symbol'],
          name: crypto['name'],
          price: quote['price'].toDouble(),
          change24h: quote['volume_change_24h']?.toDouble() ?? 0,
          changePercent24h: quote['percent_change_24h'].toDouble(),
          high24h: 0,
          low24h: 0,
          volume24h: quote['volume_24h'].toDouble(),
          marketCap: quote['market_cap'].toDouble(),
          circulatingSupply: crypto['circulating_supply']?.toDouble() ?? 0,
          totalSupply: crypto['total_supply']?.toDouble() ?? 0,
          rank: crypto['cmc_rank'],
          timestamp: DateTime.parse(quote['last_updated']),
        ));
      }
      return quotes;
    } catch (e) {
      print('Error fetching crypto quotes from CoinMarketCap: $e');
      return [];
    }
  }

  Future<List<CryptoQuote>> getTopCryptos({int limit = 100}) async {
    try {
      final response = await _dio.get('/cryptocurrency/listings/latest',
          queryParameters: {'limit': limit, 'convert': 'USD'});

      final data = response.data['data'] as List;
      
      return data.map((crypto) {
        final quote = crypto['quote']['USD'];
        return CryptoQuote(
          symbol: crypto['symbol'],
          name: crypto['name'],
          price: quote['price'].toDouble(),
          change24h: quote['volume_change_24h']?.toDouble() ?? 0,
          changePercent24h: quote['percent_change_24h'].toDouble(),
          high24h: 0,
          low24h: 0,
          volume24h: quote['volume_24h'].toDouble(),
          marketCap: quote['market_cap'].toDouble(),
          circulatingSupply: crypto['circulating_supply']?.toDouble() ?? 0,
          totalSupply: crypto['total_supply']?.toDouble() ?? 0,
          rank: crypto['cmc_rank'],
          timestamp: DateTime.parse(quote['last_updated']),
        );
      }).toList();
    } catch (e) {
      print('Error fetching top cryptos from CoinMarketCap: $e');
      return [];
    }
  }

  @override
  Future<ForexQuote?> getForexQuote(String pair) async {
    // CoinMarketCap doesn't provide forex data
    return null;
  }

  @override
  Future<List<MarketNews>> getMarketNews({List<String>? symbols}) async {
    // CoinMarketCap doesn't provide news in their API
    return [];
  }

  @override
  Stream<StockQuote>? streamStockQuote(String symbol) {
    // CoinMarketCap doesn't provide stock data
    return null;
  }

  @override
  Stream<CryptoQuote>? streamCryptoQuote(String symbol) {
    // CoinMarketCap doesn't provide WebSocket streaming
    // You could implement polling here if needed
    return null;
  }

  @override
  void dispose() {
    _dio.close();
  }
}

/// Yahoo Finance provider for stocks and market data
class YahooFinanceProvider extends MarketDataProvider {
  final Dio _dio;
  static const String baseUrl = 'https://query1.finance.yahoo.com/v8/finance';

  YahooFinanceProvider()
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ));

  @override
  String get name => 'Yahoo Finance';

  @override
  Future<void> initialize() async {
    // No API key needed for Yahoo Finance
  }

  @override
  Future<StockQuote?> getStockQuote(String symbol) async {
    try {
      final response = await _dio.get('/chart/$symbol');
      final result = response.data['chart']['result'][0];
      final meta = result['meta'];
      final quote = result['indicators']['quote'][0];

      final currentPrice = meta['regularMarketPrice'].toDouble();
      final previousClose = meta['previousClose'].toDouble();

      return StockQuote(
        symbol: symbol,
        name: meta['longName'] ?? symbol,
        exchange: meta['exchangeName'] ?? '',
        price: currentPrice,
        change: currentPrice - previousClose,
        changePercent: ((currentPrice - previousClose) / previousClose) * 100,
        dayHigh: meta['regularMarketDayHigh'].toDouble(),
        dayLow: meta['regularMarketDayLow'].toDouble(),
        open: quote['open'].last?.toDouble() ?? 0,
        previousClose: previousClose,
        volume: meta['regularMarketVolume'],
        marketCap: meta['marketCap']?.toDouble() ?? 0,
        pe: meta['trailingPE']?.toDouble() ?? 0,
        eps: meta['epsTrailingTwelveMonths']?.toDouble() ?? 0,
        fiftyTwoWeekHigh: meta['fiftyTwoWeekHigh']?.toDouble() ?? 0,
        fiftyTwoWeekLow: meta['fiftyTwoWeekLow']?.toDouble() ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            meta['regularMarketTime'] * 1000),
        extended: {
          'beta': meta['beta'],
          'dividendYield': meta['dividendYield'],
          'priceToBook': meta['priceToBook'],
        },
      );
    } catch (e) {
      print('Error fetching stock quote from Yahoo Finance: $e');
      return null;
    }
  }

  @override
  Future<List<StockQuote>> getStockQuotes(List<String> symbols) async {
    try {
      final symbolsStr = symbols.join(',');
      final response = await Dio().get(
          'https://query1.finance.yahoo.com/v7/finance/quote?symbols=$symbolsStr');

      final quotes = response.data['quoteResponse']['result'] as List;
      
      return quotes.map((quote) {
        return StockQuote(
          symbol: quote['symbol'],
          name: quote['longName'] ?? quote['shortName'] ?? quote['symbol'],
          exchange: quote['exchange'] ?? '',
          price: quote['regularMarketPrice']?.toDouble() ?? 0,
          change: quote['regularMarketChange']?.toDouble() ?? 0,
          changePercent: quote['regularMarketChangePercent']?.toDouble() ?? 0,
          dayHigh: quote['regularMarketDayHigh']?.toDouble() ?? 0,
          dayLow: quote['regularMarketDayLow']?.toDouble() ?? 0,
          open: quote['regularMarketOpen']?.toDouble() ?? 0,
          previousClose: quote['regularMarketPreviousClose']?.toDouble() ?? 0,
          volume: quote['regularMarketVolume'] ?? 0,
          marketCap: quote['marketCap']?.toDouble() ?? 0,
          pe: quote['trailingPE']?.toDouble() ?? 0,
          eps: quote['epsTrailingTwelveMonths']?.toDouble() ?? 0,
          fiftyTwoWeekHigh: quote['fiftyTwoWeekHigh']?.toDouble() ?? 0,
          fiftyTwoWeekLow: quote['fiftyTwoWeekLow']?.toDouble() ?? 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              quote['regularMarketTime'] * 1000),
        );
      }).toList();
    } catch (e) {
      print('Error fetching stock quotes from Yahoo Finance: $e');
      return [];
    }
  }

  @override
  Future<CryptoQuote?> getCryptoQuote(String symbol) async {
    try {
      final yahooSymbol = '${symbol}-USD';
      final response = await _dio.get('/chart/$yahooSymbol');
      final result = response.data['chart']['result'][0];
      final meta = result['meta'];

      final currentPrice = meta['regularMarketPrice'].toDouble();
      final previousClose = meta['previousClose'].toDouble();

      return CryptoQuote(
        symbol: symbol,
        name: meta['longName'] ?? symbol,
        price: currentPrice,
        change24h: currentPrice - previousClose,
        changePercent24h: ((currentPrice - previousClose) / previousClose) * 100,
        high24h: meta['regularMarketDayHigh'].toDouble(),
        low24h: meta['regularMarketDayLow'].toDouble(),
        volume24h: meta['regularMarketVolume']?.toDouble() ?? 0,
        marketCap: meta['marketCap']?.toDouble() ?? 0,
        circulatingSupply: 0,
        totalSupply: 0,
        rank: 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            meta['regularMarketTime'] * 1000),
      );
    } catch (e) {
      print('Error fetching crypto quote from Yahoo Finance: $e');
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
      final yahooSymbol = '${pair}=X';
      final response = await _dio.get('/chart/$yahooSymbol');
      final result = response.data['chart']['result'][0];
      final meta = result['meta'];

      final currentPrice = meta['regularMarketPrice'].toDouble();
      final previousClose = meta['previousClose'].toDouble();

      return ForexQuote(
        pair: pair,
        rate: currentPrice,
        change: currentPrice - previousClose,
        changePercent: ((currentPrice - previousClose) / previousClose) * 100,
        bid: currentPrice,
        ask: currentPrice,
        spread: 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            meta['regularMarketTime'] * 1000),
      );
    } catch (e) {
      print('Error fetching forex quote from Yahoo Finance: $e');
      return null;
    }
  }

  @override
  Future<List<MarketNews>> getMarketNews({List<String>? symbols}) async {
    // Yahoo Finance news API requires scraping or unofficial endpoints
    return [];
  }

  @override
  Stream<StockQuote>? streamStockQuote(String symbol) {
    // Yahoo Finance doesn't provide official WebSocket API
    return null;
  }

  @override
  Stream<CryptoQuote>? streamCryptoQuote(String symbol) {
    // Yahoo Finance doesn't provide official WebSocket API
    return null;
  }

  @override
  void dispose() {
    _dio.close();
  }
}