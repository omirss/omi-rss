import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rss_glassmorphism_reader/core/services/local_ai_service.dart';

class MockTensorFlowService extends Mock {
  Future<Map<String, double>> predict(List<double> input) async {
    // Mock sentiment prediction
    return {
      'positive': 0.7,
      'negative': 0.1,
      'neutral': 0.2,
    };
  }
}

void main() {
  group('LocalAIService', () {
    late LocalAIService aiService;
    
    setUp(() {
      aiService = LocalAIService();
    });
    
    group('Sentiment Analysis', () {
      test('should analyze positive sentiment', () async {
        const text = 'This is an amazing product! I love it so much.';
        
        final result = await aiService.analyzeSentiment(text);
        
        expect(result.overall, 'positive');
        expect(result.positive, greaterThan(0.5));
        expect(result.negative, lessThan(0.3));
      });
      
      test('should analyze negative sentiment', () async {
        const text = 'This is terrible. I hate it. Worst experience ever.';
        
        final result = await aiService.analyzeSentiment(text);
        
        expect(result.overall, 'negative');
        expect(result.negative, greaterThan(0.5));
        expect(result.positive, lessThan(0.3));
      });
      
      test('should analyze neutral sentiment', () async {
        const text = 'The product exists. It has features. It works.';
        
        final result = await aiService.analyzeSentiment(text);
        
        expect(result.overall, 'neutral');
        expect(result.neutral, greaterThan(0.4));
      });
      
      test('should handle empty text', () async {
        const text = '';
        
        final result = await aiService.analyzeSentiment(text);
        
        expect(result.overall, 'neutral');
        expect(result.neutral, equals(1.0));
      });
    });
    
    group('Bias Detection', () {
      test('should detect political bias', () async {
        const text = '''
        The liberal agenda is destroying our country. 
        Conservative values are under attack from the radical left.
        ''';
        
        final result = await aiService.detectBias(text);
        
        expect(result.political, greaterThan(0.5));
        expect(result.direction, contains('right'));
      });
      
      test('should detect commercial bias', () async {
        const text = '''
        Buy now! Limited time offer! This revolutionary product will change your life!
        Don't miss out on this incredible deal!
        ''';
        
        final result = await aiService.detectBias(text);
        
        expect(result.commercial, greaterThan(0.6));
      });
      
      test('should detect sensational bias', () async {
        const text = '''
        SHOCKING! You won't BELIEVE what happened next!
        This ONE WEIRD TRICK will BLOW YOUR MIND!
        ''';
        
        final result = await aiService.detectBias(text);
        
        expect(result.sensational, greaterThan(0.7));
      });
      
      test('should handle neutral text', () async {
        const text = '''
        The meeting was held on Tuesday. 
        Participants discussed the quarterly results.
        ''';
        
        final result = await aiService.detectBias(text);
        
        expect(result.political, lessThan(0.3));
        expect(result.commercial, lessThan(0.3));
        expect(result.sensational, lessThan(0.3));
      });
    });
    
    group('Topic Classification', () {
      test('should classify technology topics', () async {
        const text = '''
        Apple announced new iPhone features including AI capabilities.
        The software update includes machine learning improvements.
        ''';
        
        final result = await aiService.classifyTopics(text);
        
        expect(result.topics, contains('technology'));
        expect(result.confidence['technology'], greaterThan(0.7));
      });
      
      test('should classify multiple topics', () async {
        const text = '''
        The tech company's stock price surged after announcing 
        breakthrough medical AI that can diagnose diseases.
        ''';
        
        final result = await aiService.classifyTopics(text);
        
        expect(result.topics.length, greaterThanOrEqualTo(2));
        expect(result.topics, contains('technology'));
        expect(result.topics, contains('health'));
      });
      
      test('should handle short text', () async {
        const text = 'Breaking news';
        
        final result = await aiService.classifyTopics(text);
        
        expect(result.topics, contains('news'));
      });
    });
    
    group('Perspective Generation', () {
      test('should generate multiple perspectives', () async {
        const text = '''
        The government announced new climate change policies
        that will increase taxes on carbon emissions.
        ''';
        
        final result = await aiService.generatePerspectives(text);
        
        expect(result.perspectives.length, greaterThanOrEqualTo(2));
        expect(result.perspectives.any((p) => p.viewpoint.contains('environmental')), true);
        expect(result.perspectives.any((p) => p.viewpoint.contains('economic')), true);
      });
      
      test('should include key points for each perspective', () async {
        const text = 'New technology regulations will affect social media companies.';
        
        final result = await aiService.generatePerspectives(text);
        
        for (final perspective in result.perspectives) {
          expect(perspective.keyPoints, isNotEmpty);
          expect(perspective.summary, isNotEmpty);
        }
      });
    });
    
    group('Fact Checking', () {
      test('should identify verifiable claims', () async {
        const text = '''
        The Earth is round. Water boils at 100 degrees Celsius.
        The population of Earth is over 8 billion people.
        ''';
        
        final result = await aiService.factCheck(text);
        
        expect(result.claims, isNotEmpty);
        expect(result.verifiedClaims, greaterThan(0));
      });
      
      test('should flag potential misinformation', () async {
        const text = '''
        Scientists have proven that the Earth is flat.
        Vaccines contain microchips for tracking.
        ''';
        
        final result = await aiService.factCheck(text);
        
        expect(result.potentialMisinformation, greaterThan(0));
        expect(result.confidence, lessThan(0.5));
      });
    });
    
    group('Text Processing', () {
      test('should normalize text correctly', () {
        const text = 'HELLO   World!!!   This is a    TEST.';
        final normalized = aiService.normalizeText(text);
        
        expect(normalized, 'hello world this is a test');
      });
      
      test('should extract key phrases', () async {
        const text = '''
        Artificial intelligence is transforming healthcare.
        Machine learning algorithms detect diseases early.
        ''';
        
        final phrases = await aiService.extractKeyPhrases(text);
        
        expect(phrases, contains('artificial intelligence'));
        expect(phrases, contains('machine learning'));
        expect(phrases, contains('healthcare'));
      });
      
      test('should calculate readability score', () async {
        const simpleText = 'The cat sat on the mat. It was happy.';
        const complexText = '''
        The implementation of sophisticated algorithmic methodologies
        necessitates comprehensive evaluation of multifaceted parameters.
        ''';
        
        final simpleScore = await aiService.calculateReadability(simpleText);
        final complexScore = await aiService.calculateReadability(complexText);
        
        expect(simpleScore, greaterThan(complexScore));
        expect(simpleScore, greaterThan(0.7));
        expect(complexScore, lessThan(0.5));
      });
    });
  });
}