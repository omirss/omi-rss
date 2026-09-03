import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:rss_glassmorphism_reader/core/services/ai_service.dart';
import 'package:rss_glassmorphism_reader/core/models/ai_models.dart';
import 'package:rss_glassmorphism_reader/core/models/article.dart';
import 'package:rss_glassmorphism_reader/core/database/database.dart';

@GenerateMocks([Dio, AppDatabase])
import 'ai_service_test.mocks.dart';

void main() {
  late AIService aiService;
  late MockDio mockDio;
  late MockAppDatabase mockDatabase;

  setUp(() {
    mockDio = MockDio();
    mockDatabase = MockAppDatabase();
    aiService = AIService(
      database: mockDatabase,
      dio: mockDio,
    );
  });

  group('AI Service Tests', () {
    test('should initialize providers correctly', () {
      expect(aiService, isNotNull);
      // Service should initialize with providers
    });

    group('Fact Checking', () {
      test('should perform fact checking with Snopes style analysis', () async {
        final result = await aiService.factCheck('The Earth is flat');
        
        expect(result, isNotNull);
        expect(result.verdict, isIn(['true', 'mostly_true', 'mixed', 'mostly_false', 'false', 'unverifiable']));
        expect(result.sources, isNotEmpty);
        expect(result.confidence, greaterThan(0));
      });

      test('should detect false claims', () async {
        final result = await aiService.factCheck('The moon is made of cheese');
        
        expect(result.verdict, isIn(['false', 'mostly_false']));
        expect(result.explanation, contains('false'));
      });

      test('should handle fact checking errors gracefully', () async {
        when(mockDio.post(any, data: anyNamed('data'), options: anyNamed('options')))
            .thenThrow(DioException(requestOptions: RequestOptions(path: '/')));

        final result = await aiService.factCheck('Test claim');
        
        // Should still return a result even if API fails
        expect(result, isNotNull);
      });
    });

    group('Sentiment Analysis', () {
      test('should analyze positive sentiment', () async {
        final text = 'This is absolutely amazing! I love this product so much.';
        final result = await aiService.analyzeSentiment(text);
        
        expect(result.sentiment, isIn(['positive', 'very_positive']));
        expect(result.score, greaterThan(0));
      });

      test('should analyze negative sentiment', () async {
        final text = 'This is terrible. I hate it and would never recommend it.';
        final result = await aiService.analyzeSentiment(text);
        
        expect(result.sentiment, isIn(['negative', 'very_negative']));
        expect(result.score, lessThan(0));
      });

      test('should analyze neutral sentiment', () async {
        final text = 'The product exists. It has some features.';
        final result = await aiService.analyzeSentiment(text);
        
        expect(result.sentiment, equals('neutral'));
        expect(result.score.abs(), lessThan(0.3));
      });
    });

    group('Named Entity Recognition', () {
      test('should extract person names', () async {
        final text = 'Elon Musk announced that Tesla will release a new model.';
        final entities = await aiService.extractNamedEntities(text);
        
        final persons = entities.where((e) => e.type == 'PERSON').toList();
        expect(persons, isNotEmpty);
        expect(persons.first.text, equals('Elon Musk'));
      });

      test('should extract organizations', () async {
        final text = 'Apple Inc. and Microsoft Corporation are competing in the AI space.';
        final entities = await aiService.extractNamedEntities(text);
        
        final orgs = entities.where((e) => e.type == 'ORGANIZATION').toList();
        expect(orgs.length, greaterThanOrEqualTo(2));
      });

      test('should extract locations', () async {
        final text = 'The conference will be held in San Francisco, United States.';
        final entities = await aiService.extractNamedEntities(text);
        
        final locations = entities.where((e) => e.type == 'LOCATION').toList();
        expect(locations, isNotEmpty);
      });

      test('should extract dates and money', () async {
        final text = 'On January 15, 2024, the company raised \$50 million.';
        final entities = await aiService.extractNamedEntities(text);
        
        expect(entities.any((e) => e.type == 'DATE'), isTrue);
        expect(entities.any((e) => e.type == 'MONEY'), isTrue);
      });
    });

    group('Bias Detection', () {
      test('should detect political bias', () async {
        final text = 'The liberal agenda is destroying our conservative values.';
        final result = await aiService.detectBias(text);
        
        expect(result.hasBias, isTrue);
        expect(result.biasTypes, contains(BiasType.political));
      });

      test('should detect multiple bias types', () async {
        final text = 'Women are naturally better at childcare than men, especially in Western cultures.';
        final result = await aiService.detectBias(text);
        
        expect(result.hasBias, isTrue);
        expect(result.biasTypes.length, greaterThan(1));
      });

      test('should not detect bias in neutral text', () async {
        final text = 'The study analyzed data from multiple sources.';
        final result = await aiService.detectBias(text);
        
        expect(result.hasBias, isFalse);
        expect(result.biasTypes, isEmpty);
      });
    });

    group('Multiple Perspectives', () {
      test('should generate different perspectives', () async {
        final text = 'Government increases taxes on corporations';
        final perspectives = await aiService.generatePerspectives(text);
        
        expect(perspectives, isNotEmpty);
        expect(perspectives.length, greaterThanOrEqualTo(3));
        
        // Should have different viewpoints
        final viewpoints = perspectives.map((p) => p.perspective).toSet();
        expect(viewpoints.length, equals(perspectives.length));
      });
    });

    group('Article Analysis', () {
      test('should perform comprehensive article analysis', () async {
        final article = Article(
          id: '1',
          title: 'Climate Change Impact on Global Economy',
          content: 'A comprehensive study shows that climate change will have significant economic impacts...',
          url: 'https://example.com/article',
          feedId: 'feed1',
          publishedAt: DateTime.now(),
        );

        final result = await aiService.analyzeArticle(
          article,
          analyses: [
            AIAnalysisType.summary,
            AIAnalysisType.sentiment,
            AIAnalysisType.biasDetection,
            AIAnalysisType.factChecking,
            AIAnalysisType.namedEntityRecognition,
          ],
        );

        expect(result, isNotNull);
        expect(result.articleId, equals(article.id));
        expect(result.summary, isNotNull);
        expect(result.sentiment, isNotNull);
        expect(result.biasAnalysis, isNotNull);
        expect(result.factCheck, isNotNull);
        expect(result.entities, isNotNull);
      });

      test('should cache analysis results', () async {
        final article = Article(
          id: '1',
          title: 'Test Article',
          content: 'Test content',
          url: 'https://example.com/test',
          feedId: 'feed1',
          publishedAt: DateTime.now(),
        );

        // First call
        final result1 = await aiService.analyzeArticle(article);
        
        // Second call should use cache
        final result2 = await aiService.analyzeArticle(article);
        
        expect(result1.articleId, equals(result2.articleId));
        // Verify no additional API calls were made
        verifyNever(mockDio.post(any, data: anyNamed('data')));
      });
    });

    group('Provider Fallback', () {
      test('should fallback to next provider on error', () async {
        // First provider fails
        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: argThat(
            named: 'options',
            isA<Options>().having(
              (o) => o.headers?['Authorization'],
              'auth header',
              contains('OpenAI'),
            ),
          ),
        )).thenThrow(DioException(requestOptions: RequestOptions(path: '/')));

        // Second provider succeeds
        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: argThat(
            named: 'options',
            isA<Options>().having(
              (o) => o.headers?['Authorization'],
              'auth header',
              contains('Anthropic'),
            ),
          ),
        )).thenAnswer((_) async => Response(
          data: {'summary': 'Test summary'},
          requestOptions: RequestOptions(path: '/'),
        ));

        final result = await aiService.summarize('Test content');
        
        expect(result, equals('Test summary'));
      });
    });

    group('Local AI Fallback', () {
      test('should use local models when API providers fail', () async {
        // All API providers fail
        when(mockDio.post(any, data: anyNamed('data'), options: anyNamed('options')))
            .thenThrow(DioException(requestOptions: RequestOptions(path: '/')));

        final sentiment = await aiService.analyzeSentiment('Happy text');
        
        // Should still return a result from local analysis
        expect(sentiment, isNotNull);
        expect(sentiment.sentiment, isNotNull);
      });
    });
  });
}