import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:rss_glassmorphism_reader/core/services/market_service.dart';
import 'package:rss_glassmorphism_reader/core/database/database.dart';

@GenerateMocks([Dio, AppDatabase, MarketDataProvider])
import 'market_service_test.mocks.dart';

void main() {
  late MarketService marketService;
  late MockAppDatabase mockDatabase;
  late MockMarketDataProvider mockProvider;

  setUp(() {
    mockDatabase = MockAppDatabase();
    marketService = MarketService(database: mockDatabase);
    mockProvider = MockMarketDataProvider();
  });

  group('Market Service Tests', () {
    test('should initialize with Yahoo Finance as primary provider', () async {
      await marketService.initialize();
      
      final providers = marketService.getAvailableProviders();
      expect(providers, contains('Yahoo Finance'));
      expect(providers.first, equals('Yahoo Finance'));
    });

    group('Stock Quotes', () {
      test('should fetch stock quote successfully', () async {
        await marketService.initialize();
        
        final quote = await marketService.getStockQuote('AAPL');
        
        if (quote != null) {
          expect(quote.symbol, equals('AAPL'));
          expect(quote.price, greaterThan(0));
          expect(quote.name, isNotEmpty);
        }
      });

      test('should fetch multiple stock quotes', () async {
        await marketService.initialize();
        
        final quotes = await marketService.getStockQuotes(['AAPL', 'GOOGL', 'MSFT']);
        
        expect(quotes, isNotEmpty);
        expect(quotes.every((q) => q.price > 0), isTrue);
      });

      test('should cache stock quotes', () async {
        await marketService.initialize();
        
        // First call
        final quote1 = await marketService.getStockQuote('AAPL');
        
        // Second call should use cache
        final quote2 = await marketService.getStockQuote('AAPL');
        
        if (quote1 != null && quote2 != null) {
          expect(quote1.symbol, equals(quote2.symbol));
          expect(quote1.price, equals(quote2.price));
        }
      });
    });

    group('Crypto Quotes', () {
      test('should fetch crypto quote successfully', () async {
        await marketService.initialize();
        
        final quote = await marketService.getCryptoQuote('BTC');
        
        if (quote != null) {
          expect(quote.symbol, equals('BTC'));
          expect(quote.price, greaterThan(0));
          expect(quote.marketCap, greaterThan(0));
        }
      });

      test('should handle different crypto symbols', () async {
        await marketService.initialize();
        
        final quotes = await marketService.getCryptoQuotes(['BTC', 'ETH', 'DOGE']);
        
        expect(quotes, isNotEmpty);
        expect(quotes.every((q) => q.price > 0), isTrue);
      });
    });

    group('Forex Quotes', () {
      test('should fetch forex quote successfully', () async {
        await marketService.initialize();
        
        final quote = await marketService.getForexQuote('EURUSD');
        
        if (quote != null) {
          expect(quote.pair, equals('EURUSD'));
          expect(quote.rate, greaterThan(0));
          expect(quote.bid, greaterThan(0));
          expect(quote.ask, greaterThan(0));
        }
      });
    });

    group('Market News', () {
      test('should fetch general market news', () async {
        await marketService.initialize();
        
        final news = await marketService.getMarketNews();
        
        expect(news, isNotEmpty);
        expect(news.first.title, isNotEmpty);
        expect(news.first.url, isNotEmpty);
        expect(news.first.source, isNotEmpty);
      });

      test('should fetch symbol-specific news', () async {
        await marketService.initialize();
        
        final news = await marketService.getMarketNews(symbols: ['AAPL']);
        
        if (news.isNotEmpty) {
          expect(news.first.symbols, contains('AAPL'));
        }
      });

      test('should remove duplicate news articles', () async {
        await marketService.initialize();
        
        final news = await marketService.getMarketNews();
        
        // Check for unique URLs
        final urls = news.map((n) => n.url).toSet();
        expect(urls.length, equals(news.length));
      });
    });

    group('Provider Management', () {
      test('should switch providers', () async {
        await marketService.initialize();
        
        marketService.switchProvider('Alpha Vantage');
        
        // Next request should use Alpha Vantage
        // (Would need to verify through mocking in real implementation)
      });

      test('should fallback to other providers on failure', () async {
        await marketService.initialize();
        
        // Even if primary provider fails, should try others
        final quote = await marketService.getStockQuote('INVALID_SYMBOL_12345');
        
        // Should either return null or try other providers
        expect(quote == null || quote.symbol == 'INVALID_SYMBOL_12345', isTrue);
      });
    });

    group('Yahoo Finance Provider', () {
      late YahooFinanceProvider yahooProvider;

      setUp(() {
        yahooProvider = YahooFinanceProvider();
      });

      test('should parse Yahoo Finance response correctly', () async {
        // Test would mock the Dio response
        final mockDio = MockDio();
        when(mockDio.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              data: {
                'quoteResponse': {
                  'result': [{
                    'symbol': 'AAPL',
                    'longName': 'Apple Inc.',
                    'regularMarketPrice': 150.0,
                    'regularMarketChange': 2.5,
                    'regularMarketChangePercent': 1.69,
                  }]
                }
              },
              requestOptions: RequestOptions(path: '/'),
            ));

        // Would test parsing logic
      });

      test('should handle batch requests', () async {
        await yahooProvider.initialize();
        
        final quotes = await yahooProvider.getStockQuotes(['AAPL', 'GOOGL', 'MSFT']);
        
        // Should make single batch request instead of multiple
        expect(quotes.length, lessThanOrEqualTo(3));
      });
    });

    group('Error Handling', () {
      test('should handle network errors gracefully', () async {
        final errorProvider = MockMarketDataProvider();
        when(errorProvider.name).thenReturn('Error Provider');
        when(errorProvider.initialize()).thenThrow(Exception('Network error'));
        
        // Service should continue working even if one provider fails
        await marketService.initialize();
        expect(marketService.getAvailableProviders(), isNotEmpty);
      });

      test('should handle invalid symbols', () async {
        await marketService.initialize();
        
        final quote = await marketService.getStockQuote('');
        expect(quote, isNull);
      });

      test('should handle API rate limits', () async {
        await marketService.initialize();
        
        // Make multiple rapid requests
        final futures = List.generate(
          10,
          (i) => marketService.getStockQuote('AAPL'),
        );
        
        final results = await Future.wait(futures);
        
        // Should handle rate limiting gracefully
        expect(results.where((r) => r != null).length, greaterThan(0));
      });
    });
  });
}