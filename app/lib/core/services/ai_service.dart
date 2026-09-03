import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:logger/logger.dart';
import '../models/article.dart';
import '../models/ai_models.dart';
import '../database/database.dart';
import '../providers/ai_providers.dart';
import 'local_ai_service.dart';

/// AI service for multi-perspective analysis and content intelligence
class AIService {
  final Dio _dio;
  final AppDatabase _database;
  final Logger logger = Logger();
  
  // API providers with fallback chain
  final List<AIProvider> _providers = [];
  
  // Cache for AI results
  final Map<String, AIAnalysisResult> _analysisCache = {};
  
  // Local models
  Interpreter? _sentimentModel;
  Interpreter? _nerModel;
  Interpreter? _classificationModel;
  
  // Rate limiting
  final Map<String, DateTime> _lastApiCall = {};
  final Map<String, int> _apiCallCount = {};
  
  // Getters for database and local AI
  AppDatabase get database => _database;
  LocalAIService? get localAI => _localAI;
  LocalAIService? _localAI;
  
  AIService({
    required AppDatabase database,
    Dio? dio,
  }) : _database = database,
       _dio = dio ?? Dio() {
    _initializeProviders();
    _loadLocalModels();
  }
  
  /// Initialize AI providers with API keys
  void _initializeProviders() {
    // OpenAI GPT-4 (Primary)
    _providers.add(OpenAIProvider(
      apiKey: const String.fromEnvironment('OPENAI_API_KEY'),
      model: 'gpt-4-1106-preview',
      dio: _dio,
    ));
    
    // Anthropic Claude (Fallback 1)
    _providers.add(AnthropicProvider(
      apiKey: const String.fromEnvironment('ANTHROPIC_API_KEY'),
      model: 'claude-3-opus-20240229',
      dio: _dio,
    ));
    
    // Google Gemini (Fallback 2)
    if (const String.fromEnvironment('GOOGLE_AI_API_KEY').isNotEmpty) {
      _providers.add(GoogleAIProvider(
        apiKey: const String.fromEnvironment('GOOGLE_AI_API_KEY'),
        model: 'gemini-pro',
        dio: _dio,
      ));
    }
    
    // Cohere (Fallback 3)
    if (const String.fromEnvironment('COHERE_API_KEY').isNotEmpty) {
      _providers.add(CohereProvider(
        apiKey: const String.fromEnvironment('COHERE_API_KEY'),
        model: 'command',
        dio: _dio,
      ));
    }
    
    // Local models (Final fallback)
    _providers.add(LocalAIProvider(
      sentimentModel: _sentimentModel,
      nerModel: _nerModel,
      classificationModel: _classificationModel,
    ));
  }
  
  /// Load local TensorFlow Lite models
  Future<void> _loadLocalModels() async {
    try {
      // Initialize the local AI service
      _localAI = LocalAIService();
      await _localAI!.initialize();
      
      // Get models from local AI service
      _sentimentModel = _localAI!.sentimentModel;
      _nerModel = _localAI!.nerModel;
      _classificationModel = _localAI!.classificationModel;
      
      // Update the local provider with initialized service
      final localProviderIndex = _providers.indexWhere((p) => p is LocalAIProvider);
      if (localProviderIndex >= 0) {
        _providers[localProviderIndex] = LocalAIProvider(
          localAI: _localAI,
          sentimentModel: _sentimentModel,
          nerModel: _nerModel,
          classificationModel: _classificationModel,
        );
      }
    } catch (e) {
      logger.e('Failed to initialize local AI models', error: e);
    }
  }
  
  /// Analyze article with full AI capabilities
  Future<AIAnalysisResult> analyzeArticle(
    Article article, {
    List<AIAnalysisType> analyses = const [
      AIAnalysisType.summary,
      AIAnalysisType.perspectives,
      AIAnalysisType.bias,
      AIAnalysisType.sentiment,
      AIAnalysisType.factCheck,
    ],
  }) async {
    // Check cache
    final cacheKey = _getCacheKey(article.id, analyses);
    if (_analysisCache.containsKey(cacheKey)) {
      return _analysisCache[cacheKey]!;
    }
    
    // Prepare content
    final content = article.fullContent ?? article.content ?? article.summary ?? '';
    final title = article.title;
    
    final result = AIAnalysisResult(
      articleId: article.id,
      timestamp: DateTime.now(),
    );
    
    // Run requested analyses
    for (final analysis in analyses) {
      switch (analysis) {
        case AIAnalysisType.summary:
          result.summary = await _generateSummary(title, content);
          result.keyPoints = await _extractKeyPoints(content);
          result.tags = await _generateTags(content);
          break;
          
        case AIAnalysisType.perspectives:
          result.perspectives = await _generatePerspectives(title, content);
          break;
          
        case AIAnalysisType.bias:
          result.biasAnalysis = await _analyzeBias(title, content);
          break;
          
        case AIAnalysisType.sentiment:
          result.sentimentAnalysis = await _analyzeSentiment(content);
          break;
          
        case AIAnalysisType.factCheck:
          result.factCheckResults = await _checkFacts(content);
          break;
          
        case AIAnalysisType.entities:
          result.entities = await _extractEntities(content);
          break;
          
        case AIAnalysisType.complexity:
          result.complexity = await _analyzeComplexity(content);
          break;
      }
    }
    
    // Cache result
    _cache[cacheKey] = result;
    
    // Save to database
    await _saveAnalysisResult(result);
    
    return result;
  }
  
  /// Generate summary
  Future<AISummary> _generateSummary(String title, String content) async {
    final prompt = '''
Summarize this article in three different lengths. Be concise and capture the main points.

Title: $title

Content: $content

Provide:
1. 50-word summary
2. 100-word summary
3. 200-word summary
''';
    
    final response = await _callProvider(prompt, AITaskType.summarization);
    
    return AISummary(
      short: response['50_word'] ?? '',
      medium: response['100_word'] ?? '',
      long: response['200_word'] ?? '',
      generatedAt: DateTime.now(),
    );
  }
  
  /// Extract key points
  Future<List<String>> _extractKeyPoints(String content) async {
    final prompt = '''
Extract 3-7 key points from this article. Each point should be a concise, complete sentence.

Content: $content

Format as a numbered list.
''';
    
    final response = await _callProvider(prompt, AITaskType.extraction);
    final points = response['points'] as List<dynamic>? ?? [];
    
    return points.map((p) => p.toString()).toList();
  }
  
  /// Generate tags
  Future<List<AITag>> _generateTags(String content) async {
    final prompt = '''
Generate relevant tags for this article. Include confidence scores (0-1) for each tag.

Content: $content

Provide 5-10 tags with categories: topic, industry, location, person, organization, event
''';
    
    final response = await _callProvider(prompt, AITaskType.classification);
    final tags = response['tags'] as List<dynamic>? ?? [];
    
    return tags.map((t) => AITag(
      name: t['name'] ?? '',
      category: t['category'] ?? 'topic',
      confidence: (t['confidence'] as num?)?.toDouble() ?? 0.5,
    )).toList();
  }
  
  /// Generate multiple perspectives
  Future<MultiPerspective> _generatePerspectives(String title, String content) async {
    final perspectives = MultiPerspective();
    
    // Detect primary stance
    final stancePrompt = '''
Analyze the primary stance and perspective of this article.

Title: $title
Content: $content

Identify:
1. Political leaning (left/center/right)
2. Primary viewpoint (corporate/activist/academic/journalistic)
3. Cultural perspective
4. Key assumptions
''';
    
    final stanceResponse = await _callProvider(stancePrompt, AITaskType.analysis);
    perspectives.primaryStance = stanceResponse['stance'] ?? {};
    
    // Generate counter-perspectives
    final perspectiveTypes = [
      'conservative',
      'liberal',
      'libertarian',
      'socialist',
      'centrist',
      'international',
      'historical',
      'future_implications',
      'economic',
      'environmental',
      'social_justice',
      'scientific',
    ];
    
    for (final type in perspectiveTypes) {
      final perspectivePrompt = '''
Rewrite the key points of this article from a $type perspective. 
Be fair and intellectually honest. Provide a 100-word summary.

Original: $title
$content
''';
      
      try {
        final response = await _callProvider(perspectivePrompt, AITaskType.generation);
        perspectives.perspectives[type] = PerspectiveSummary(
          type: type,
          summary: response['summary'] ?? '',
          keyPoints: (response['key_points'] as List<dynamic>?)
            ?.map((p) => p.toString()).toList() ?? [],
          confidence: (response['confidence'] as num?)?.toDouble() ?? 0.7,
        );
      } catch (e) {
        print('Failed to generate $type perspective: $e');
      }
    }
    
    // Find related articles with different perspectives
    perspectives.relatedArticles = await _findRelatedPerspectives(title);
    
    return perspectives;
  }
  
  /// Analyze bias
  Future<BiasAnalysis> _analyzeBias(String title, String content) async {
    final prompt = '''
Analyze this article for various types of bias. Score each from 0-1 (0=none, 1=severe).

Title: $title
Content: $content

Analyze for:
1. Political bias (left/right leaning)
2. Confirmation bias
3. Selection bias
4. Framing bias
5. Emotional manipulation
6. Cherry-picking
7. False balance
8. Corporate bias
9. Nationalistic bias
10. Sensationalism

Also provide:
- Overall bias score (0-100)
- Factual density (facts per paragraph)
- Emotional language index
- Loaded terms count
- Specific examples of bias
- Suggestions for more balanced reading
''';
    
    final response = await _callProvider(prompt, AITaskType.analysis);
    
    return BiasAnalysis(
      overallScore: (response['overall_score'] as num?)?.toDouble() ?? 50,
      politicalBias: PoliticalBias(
        direction: response['political_direction'] ?? 'center',
        score: (response['political_score'] as num?)?.toDouble() ?? 0,
      ),
      biasIndicators: {
        'confirmation': (response['confirmation_bias'] as num?)?.toDouble() ?? 0,
        'selection': (response['selection_bias'] as num?)?.toDouble() ?? 0,
        'framing': (response['framing_bias'] as num?)?.toDouble() ?? 0,
        'emotional': (response['emotional_manipulation'] as num?)?.toDouble() ?? 0,
        'cherry_picking': (response['cherry_picking'] as num?)?.toDouble() ?? 0,
        'false_balance': (response['false_balance'] as num?)?.toDouble() ?? 0,
        'corporate': (response['corporate_bias'] as num?)?.toDouble() ?? 0,
        'nationalistic': (response['nationalistic_bias'] as num?)?.toDouble() ?? 0,
        'sensationalism': (response['sensationalism'] as num?)?.toDouble() ?? 0,
      },
      factualDensity: (response['factual_density'] as num?)?.toDouble() ?? 0,
      emotionalIndex: (response['emotional_index'] as num?)?.toDouble() ?? 0,
      loadedTermsCount: response['loaded_terms_count'] ?? 0,
      examples: (response['examples'] as List<dynamic>?)
        ?.map((e) => BiasExample(
          text: e['text'] ?? '',
          type: e['type'] ?? '',
          explanation: e['explanation'] ?? '',
        )).toList() ?? [],
      suggestions: (response['suggestions'] as List<dynamic>?)
        ?.map((s) => s.toString()).toList() ?? [],
    );
  }
  
  /// Analyze sentiment
  Future<SentimentAnalysis> _analyzeSentiment(String content) async {
    // Try local model first for speed
    if (_sentimentModel != null) {
      try {
        final localResult = await _runLocalSentiment(content);
        if (localResult != null) {
          return localResult;
        }
      } catch (e) {
        print('Local sentiment analysis failed: $e');
      }
    }
    
    final prompt = '''
Analyze the sentiment and emotion of this text.

Content: $content

Provide:
1. Overall sentiment score (-1 to +1, where -1=very negative, 0=neutral, +1=very positive)
2. Confidence (0-1)
3. Emotion breakdown (joy, anger, fear, sadness, surprise, disgust) with scores 0-1
4. Subjectivity score (0=objective, 1=subjective)
5. Key emotional phrases
''';
    
    final response = await _callProvider(prompt, AITaskType.analysis);
    
    return SentimentAnalysis(
      score: (response['sentiment_score'] as num?)?.toDouble() ?? 0,
      label: _getSentimentLabel(response['sentiment_score'] ?? 0),
      confidence: (response['confidence'] as num?)?.toDouble() ?? 0.5,
      emotions: {
        'joy': (response['joy'] as num?)?.toDouble() ?? 0,
        'anger': (response['anger'] as num?)?.toDouble() ?? 0,
        'fear': (response['fear'] as num?)?.toDouble() ?? 0,
        'sadness': (response['sadness'] as num?)?.toDouble() ?? 0,
        'surprise': (response['surprise'] as num?)?.toDouble() ?? 0,
        'disgust': (response['disgust'] as num?)?.toDouble() ?? 0,
      },
      subjectivity: (response['subjectivity'] as num?)?.toDouble() ?? 0.5,
      keyPhrases: (response['key_phrases'] as List<dynamic>?)
        ?.map((p) => p.toString()).toList() ?? [],
    );
  }
  
  /// Check facts
  Future<List<FactCheckResult>> _checkFacts(String content) async {
    // Extract claims
    final claimsPrompt = '''
Extract factual claims from this content that can be verified.

Content: $content

For each claim, provide:
1. The exact claim text
2. Claim type (statistic, quote, event, etc.)
3. Checkability score (0-1)
''';
    
    final claimsResponse = await _callProvider(claimsPrompt, AITaskType.extraction);
    final claims = claimsResponse['claims'] as List<dynamic>? ?? [];
    
    final results = <FactCheckResult>[];
    
    // Check each claim against fact-checking APIs
    for (final claim in claims) {
      final claimText = claim['text'] ?? '';
      if (claimText.isEmpty) continue;
      
      final factCheckResult = FactCheckResult(
        claim: claimText,
        claimType: claim['type'] ?? 'general',
        checkability: (claim['checkability'] as num?)?.toDouble() ?? 0.5,
      );
      
      // Try fact-checking services
      try {
        // Snopes API
        final snopesResult = await _checkSnopes(claimText);
        if (snopesResult != null) {
          factCheckResult.sources.add(snopesResult);
        }
        
        // FactCheck.org
        final factCheckOrgResult = await _checkFactCheckOrg(claimText);
        if (factCheckOrgResult != null) {
          factCheckResult.sources.add(factCheckOrgResult);
        }
        
        // Use AI for additional context
        final aiVerification = await _aiFactCheck(claimText);
        if (aiVerification != null) {
          factCheckResult.sources.add(aiVerification);
        }
        
        // Determine overall verdict
        factCheckResult.verdict = _determineVerdict(factCheckResult.sources);
        factCheckResult.confidence = _calculateConfidence(factCheckResult.sources);
        
      } catch (e) {
        print('Fact check failed for claim: $e');
      }
      
      results.add(factCheckResult);
    }
    
    return results;
  }
  
  /// Extract named entities
  Future<List<NamedEntity>> _extractEntities(String content) async {
    // Try local NER model first
    if (_nerModel != null) {
      try {
        final localResult = await _runLocalNER(content);
        if (localResult.isNotEmpty) {
          return localResult;
        }
      } catch (e) {
        print('Local NER failed: $e');
      }
    }
    
    final prompt = '''
Extract named entities from this text.

Content: $content

For each entity, provide:
1. Text
2. Type (person, organization, location, event, product, date, money, percentage)
3. Context
4. Confidence (0-1)
''';
    
    final response = await _callProvider(prompt, AITaskType.extraction);
    final entities = response['entities'] as List<dynamic>? ?? [];
    
    return entities.map((e) => NamedEntity(
      text: e['text'] ?? '',
      type: e['type'] ?? 'unknown',
      context: e['context'] ?? '',
      confidence: (e['confidence'] as num?)?.toDouble() ?? 0.5,
    )).toList();
  }
  
  /// Analyze text complexity
  Future<ComplexityAnalysis> _analyzeComplexity(String content) async {
    final prompt = '''
Analyze the complexity and readability of this text.

Content: $content

Provide:
1. Flesch Reading Ease score (0-100)
2. Flesch-Kincaid Grade Level
3. Average sentence length
4. Average syllables per word
5. Complex word percentage
6. Passive voice percentage
7. Adverb usage
8. Overall complexity assessment
''';
    
    final response = await _callProvider(prompt, AITaskType.analysis);
    
    return ComplexityAnalysis(
      readingEase: (response['reading_ease'] as num?)?.toDouble() ?? 50,
      gradeLevel: (response['grade_level'] as num?)?.toDouble() ?? 10,
      avgSentenceLength: (response['avg_sentence_length'] as num?)?.toDouble() ?? 20,
      avgSyllablesPerWord: (response['avg_syllables'] as num?)?.toDouble() ?? 1.5,
      complexWordPercentage: (response['complex_words'] as num?)?.toDouble() ?? 0.2,
      passiveVoicePercentage: (response['passive_voice'] as num?)?.toDouble() ?? 0.1,
      adverbUsage: (response['adverb_usage'] as num?)?.toDouble() ?? 0.05,
      assessment: response['assessment'] ?? 'moderate',
    );
  }
  
  /// Call AI provider with fallback chain
  Future<Map<String, dynamic>> _callProvider(
    String prompt,
    AITaskType taskType,
  ) async {
    // Try each provider in order
    for (final provider in _providers) {
      try {
        // Check rate limiting
        if (!_checkRateLimit(provider.name)) {
          continue;
        }
        
        final response = await provider.complete(prompt, taskType);
        
        // Update rate limit tracking
        _updateRateLimit(provider.name);
        
        return response;
      } catch (e) {
        print('Provider ${provider.name} failed: $e');
        continue;
      }
    }
    
    // All providers failed, return empty response
    return {};
  }
  
  /// Check rate limiting
  bool _checkRateLimit(String provider) {
    final lastCall = _lastApiCall[provider];
    if (lastCall != null) {
      final timeSince = DateTime.now().difference(lastCall).inSeconds;
      if (timeSince < 1) return false; // Min 1 second between calls
    }
    
    final count = _apiCallCount[provider] ?? 0;
    if (count > 100) return false; // Max 100 calls per session
    
    return true;
  }
  
  /// Update rate limit tracking
  void _updateRateLimit(String provider) {
    _lastApiCall[provider] = DateTime.now();
    _apiCallCount[provider] = (_apiCallCount[provider] ?? 0) + 1;
  }
  
  /// Get sentiment label from score
  String _getSentimentLabel(double score) {
    if (score <= -0.6) return 'very_negative';
    if (score <= -0.2) return 'negative';
    if (score <= 0.2) return 'neutral';
    if (score <= 0.6) return 'positive';
    return 'very_positive';
  }
  
  /// Find related articles with different perspectives
  Future<List<RelatedPerspective>> _findRelatedPerspectives(String title) async {
    try {
      // Extract key terms from title for better search
      final keywords = title.split(' ')
          .where((word) => word.length > 3)
          .take(5)
          .join(' ');
      
      final prompt = '''
Find articles with different perspectives on this topic:
"$title"

Keywords: $keywords

Provide 3-5 different perspectives with:
1. Source name and political lean
2. Alternative headline
3. Key differences in framing
4. URL (if known) or search terms
''';
      
      final response = await _callProvider(prompt, AITaskType.analysis);
      final perspectives = <RelatedPerspective>[];
      
      if (response['perspectives'] is List) {
        for (final p in response['perspectives']) {
          perspectives.add(RelatedPerspective(
            source: p['source'] ?? 'Unknown',
            title: p['headline'] ?? title,
            perspective: p['framing'] ?? 'Alternative view',
            politicalLean: p['lean'] ?? 'center',
            url: p['url'],
            similarity: 0.7, // Default similarity score
          ));
        }
      }
      
      // Also search using news aggregation if available
      if (perspectives.isEmpty) {
        // Fallback: Create synthetic perspectives based on common biases
        perspectives.addAll([
          RelatedPerspective(
            source: 'Progressive View',
            title: title,
            perspective: 'Focus on social justice and equity aspects',
            politicalLean: 'left',
            similarity: 0.6,
          ),
          RelatedPerspective(
            source: 'Conservative View',
            title: title,
            perspective: 'Emphasis on traditional values and limited government',
            politicalLean: 'right',
            similarity: 0.6,
          ),
          RelatedPerspective(
            source: 'Centrist Analysis',
            title: title,
            perspective: 'Balanced approach considering multiple viewpoints',
            politicalLean: 'center',
            similarity: 0.7,
          ),
        ]);
      }
      
      return perspectives;
    } catch (e) {
      logger.e('Error finding related perspectives', error: e);
      return [];
    }
  }
  
  /// Check Snopes
  Future<FactSource?> _checkSnopes(String claim) async {
    try {
      // Note: Snopes doesn't have a public API, so we'll use web scraping approach
      // In production, consider partnering with Snopes or using their RSS feeds
      
      final searchQuery = Uri.encodeQueryComponent(claim);
      final searchUrl = 'https://www.snopes.com/?s=$searchQuery';
      
      // For now, we'll use AI to simulate what Snopes might say
      final prompt = '''
Analyze this claim as a fact-checker would, using Snopes methodology:

Claim: "$claim"

Provide:
1. Rating (true/mostly-true/mixture/mostly-false/false/unproven/outdated/miscaptioned/correct-attribution/misattributed/scam/legend)
2. What's True: Key accurate elements
3. What's False: Key inaccurate elements
4. Origin: Where this claim originated
5. Context: Important context missing from the claim
''';
      
      final response = await _callProvider(prompt, AITaskType.factChecking);
      
      return FactSource(
        name: 'Snopes-style Analysis',
        verdict: _mapSnopesRating(response['rating'] ?? 'unproven'),
        explanation: _buildSnopesExplanation(response),
        sources: [searchUrl],
        confidence: 0.7, // Lower confidence since it's simulated
        checkedAt: DateTime.now(),
        metadata: {
          'whatsTrue': response['whatsTrue'],
          'whatsFalse': response['whatsFalse'],
          'origin': response['origin'],
          'context': response['context'],
        },
      );
    } catch (e) {
      logger.e('Error checking Snopes', error: e);
      return null;
    }
  }
  
  String _mapSnopesRating(String rating) {
    // Map Snopes ratings to our verdict system
    switch (rating.toLowerCase()) {
      case 'true':
      case 'correct-attribution':
        return 'true';
      case 'mostly-true':
        return 'mostly_true';
      case 'mixture':
      case 'outdated':
      case 'miscaptioned':
        return 'mixed';
      case 'mostly-false':
      case 'misattributed':
        return 'mostly_false';
      case 'false':
      case 'scam':
      case 'legend':
        return 'false';
      default:
        return 'unverifiable';
    }
  }
  
  String _buildSnopesExplanation(Map<String, dynamic> response) {
    final parts = <String>[];
    
    if (response['whatsTrue'] != null) {
      parts.add("What's True: ${response['whatsTrue']}");
    }
    if (response['whatsFalse'] != null) {
      parts.add("What's False: ${response['whatsFalse']}");
    }
    if (response['context'] != null) {
      parts.add("Context: ${response['context']}");
    }
    
    return parts.join('\n\n');
  }
  
  /// Check FactCheck.org
  Future<FactSource?> _checkFactCheckOrg(String claim) async {
    try {
      // FactCheck.org focuses on political claims
      // They provide RSS feeds but no public API
      
      final searchQuery = Uri.encodeQueryComponent(claim);
      final searchUrl = 'https://www.factcheck.org/?s=$searchQuery';
      
      // Use AI to analyze claim in FactCheck.org style
      final prompt = '''
Analyze this claim as FactCheck.org would, focusing on political accuracy:

Claim: "$claim"

Provide:
1. Verdict (accurate/mostly-accurate/half-true/mostly-inaccurate/inaccurate/unsubstantiated)
2. Key Facts: The objective facts related to this claim
3. Analysis: How the claim distorts or accurately represents these facts
4. Context: Political context and why this claim is being made
5. Supporting evidence or lack thereof
''';
      
      final response = await _callProvider(prompt, AITaskType.factChecking);
      
      return FactSource(
        name: 'FactCheck.org-style Analysis',
        verdict: _mapFactCheckRating(response['verdict'] ?? 'unsubstantiated'),
        explanation: _buildFactCheckExplanation(response),
        sources: [searchUrl],
        confidence: 0.7, // Lower confidence since it's simulated
        checkedAt: DateTime.now(),
        metadata: {
          'keyFacts': response['keyFacts'],
          'analysis': response['analysis'],
          'politicalContext': response['context'],
          'evidence': response['evidence'],
        },
      );
    } catch (e) {
      logger.e('Error checking FactCheck.org', error: e);
      return null;
    }
  }
  
  String _mapFactCheckRating(String rating) {
    // Map FactCheck.org ratings to our verdict system
    switch (rating.toLowerCase()) {
      case 'accurate':
        return 'true';
      case 'mostly-accurate':
        return 'mostly_true';
      case 'half-true':
        return 'mixed';
      case 'mostly-inaccurate':
        return 'mostly_false';
      case 'inaccurate':
        return 'false';
      default:
        return 'unverifiable';
    }
  }
  
  String _buildFactCheckExplanation(Map<String, dynamic> response) {
    final parts = <String>[];
    
    if (response['keyFacts'] != null) {
      parts.add("Key Facts: ${response['keyFacts']}");
    }
    if (response['analysis'] != null) {
      parts.add("Analysis: ${response['analysis']}");
    }
    if (response['politicalContext'] != null) {
      parts.add("Political Context: ${response['politicalContext']}");
    }
    
    return parts.join('\n\n');
  }
  
  /// AI-based fact checking
  Future<FactSource?> _aiFactCheck(String claim) async {
    final prompt = '''
Fact-check this claim using your knowledge. Be objective and cite sources where possible.

Claim: $claim

Provide:
1. Verdict (true/mostly_true/mixed/mostly_false/false/unverifiable)
2. Explanation
3. Sources or reasoning
4. Confidence (0-1)
''';
    
    final response = await _callProvider(prompt, AITaskType.factChecking);
    
    return FactSource(
      name: 'AI Analysis',
      verdict: response['verdict'] ?? 'unverifiable',
      explanation: response['explanation'] ?? '',
      sources: (response['sources'] as List<dynamic>?)
        ?.map((s) => s.toString()).toList() ?? [],
      confidence: (response['confidence'] as num?)?.toDouble() ?? 0.5,
      checkedAt: DateTime.now(),
    );
  }
  
  /// Determine overall verdict from sources
  String _determineVerdict(List<FactSource> sources) {
    if (sources.isEmpty) return 'unverifiable';
    
    final verdicts = sources.map((s) => s.verdict).toList();
    
    // Count each verdict type
    final counts = <String, int>{};
    for (final verdict in verdicts) {
      counts[verdict] = (counts[verdict] ?? 0) + 1;
    }
    
    // Find most common verdict
    var maxCount = 0;
    var finalVerdict = 'unverifiable';
    
    counts.forEach((verdict, count) {
      if (count > maxCount) {
        maxCount = count;
        finalVerdict = verdict;
      }
    });
    
    return finalVerdict;
  }
  
  /// Calculate confidence from sources
  double _calculateConfidence(List<FactSource> sources) {
    if (sources.isEmpty) return 0;
    
    final confidences = sources.map((s) => s.confidence).toList();
    return confidences.reduce((a, b) => a + b) / confidences.length;
  }
  
  /// Run local sentiment analysis
  Future<SentimentAnalysis?> _runLocalSentiment(String content) async {
    try {
      if (localAI?.sentimentModel == null) {
        // Fallback to rule-based sentiment if model not loaded
        return _ruleBasedSentiment(content);
      }
      
      // Preprocess text for TFLite model
      final processed = _preprocessText(content);
      final input = _tokenizeText(processed, maxLength: 256);
      
      // Run inference
      final output = List.filled(1 * 5, 0.0).reshape([1, 5]); // 5 sentiment classes
      localAI!.sentimentModel!.run(input, output);
      
      // Parse results
      final scores = output[0] as List<double>;
      final sentimentClasses = ['very_negative', 'negative', 'neutral', 'positive', 'very_positive'];
      
      var maxScore = 0.0;
      var sentiment = 'neutral';
      for (var i = 0; i < scores.length; i++) {
        if (scores[i] > maxScore) {
          maxScore = scores[i];
          sentiment = sentimentClasses[i];
        }
      }
      
      // Calculate overall score (-1 to 1)
      final score = (scores[3] + scores[4] - scores[0] - scores[1]).clamp(-1.0, 1.0);
      
      return SentimentAnalysis(
        sentiment: sentiment,
        score: score,
        confidence: maxScore,
        emotions: _extractEmotions(scores),
      );
    } catch (e) {
      logger.e('Error running local sentiment analysis', error: e);
      // Fallback to rule-based
      return _ruleBasedSentiment(content);
    }
  }
  
  SentimentAnalysis _ruleBasedSentiment(String content) {
    final lower = content.toLowerCase();
    
    // Simple keyword-based sentiment
    final positiveWords = ['good', 'great', 'excellent', 'amazing', 'wonderful', 'fantastic', 'love', 'best', 'happy', 'joy'];
    final negativeWords = ['bad', 'terrible', 'awful', 'horrible', 'worst', 'hate', 'angry', 'sad', 'disappointed', 'failure'];
    
    var positiveCount = 0;
    var negativeCount = 0;
    
    for (final word in positiveWords) {
      positiveCount += RegExp(r'\b' + word + r'\b').allMatches(lower).length;
    }
    for (final word in negativeWords) {
      negativeCount += RegExp(r'\b' + word + r'\b').allMatches(lower).length;
    }
    
    final totalWords = content.split(' ').length;
    final score = ((positiveCount - negativeCount) / totalWords * 10).clamp(-1.0, 1.0);
    
    String sentiment;
    if (score < -0.5) sentiment = 'very_negative';
    else if (score < -0.1) sentiment = 'negative';
    else if (score < 0.1) sentiment = 'neutral';
    else if (score < 0.5) sentiment = 'positive';
    else sentiment = 'very_positive';
    
    return SentimentAnalysis(
      sentiment: sentiment,
      score: score,
      confidence: 0.6, // Lower confidence for rule-based
      emotions: {},
    );
  }
  
  Map<String, double> _extractEmotions(List<double> scores) {
    return {
      'anger': scores[0],
      'sadness': scores[1], 
      'neutral': scores[2],
      'joy': scores[3],
      'excitement': scores[4],
    };
  }
  
  String _preprocessText(String text) {
    // Basic text preprocessing
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  
  List<List<double>> _tokenizeText(String text, {int maxLength = 256}) {
    // Simple tokenization for demo - in production use proper tokenizer
    final words = text.split(' ');
    final tokens = <double>[];
    
    for (var i = 0; i < maxLength && i < words.length; i++) {
      // Simple hash-based token ID (in production use vocabulary)
      tokens.add((words[i].hashCode % 10000).toDouble());
    }
    
    // Pad to maxLength
    while (tokens.length < maxLength) {
      tokens.add(0);
    }
    
    return [tokens];
  }
  
  /// Run local NER
  Future<List<NamedEntity>> _runLocalNER(String content) async {
    try {
      if (localAI?.nerModel == null) {
        // Fallback to rule-based NER
        return _ruleBasedNER(content);
      }
      
      // Preprocess text for TFLite model
      final sentences = content.split(RegExp(r'[.!?]+')).where((s) => s.trim().isNotEmpty).toList();
      final entities = <NamedEntity>[];
      
      for (final sentence in sentences.take(10)) { // Process first 10 sentences
        final processed = _preprocessText(sentence);
        final input = _tokenizeText(processed, maxLength: 128);
        
        // Run inference - output shape: [1, 128, 7] for 7 entity types
        final output = List.filled(1 * 128 * 7, 0.0).reshape([1, 128, 7]);
        localAI!.nerModel!.run(input, output);
        
        // Parse results
        final predictions = output[0] as List<List<double>>;
        final words = processed.split(' ');
        
        for (var i = 0; i < words.length && i < predictions.length; i++) {
          final wordPredictions = predictions[i];
          final maxIndex = _argmax(wordPredictions);
          
          if (maxIndex > 0 && wordPredictions[maxIndex] > 0.5) {
            entities.add(NamedEntity(
              text: words[i],
              type: _getEntityType(maxIndex),
              confidence: wordPredictions[maxIndex],
              startOffset: sentence.indexOf(words[i]),
              endOffset: sentence.indexOf(words[i]) + words[i].length,
            ));
          }
        }
      }
      
      // Merge adjacent entities of same type
      return _mergeEntities(entities);
    } catch (e) {
      logger.e('Error running local NER', error: e);
      // Fallback to rule-based
      return _ruleBasedNER(content);
    }
  }
  
  List<NamedEntity> _ruleBasedNER(String content) {
    final entities = <NamedEntity>[];
    
    // Person names (simple pattern)
    final personPattern = RegExp(r'\b([A-Z][a-z]+ [A-Z][a-z]+)\b');
    for (final match in personPattern.allMatches(content)) {
      entities.add(NamedEntity(
        text: match.group(0)!,
        type: 'PERSON',
        confidence: 0.7,
        startOffset: match.start,
        endOffset: match.end,
      ));
    }
    
    // Organizations (common suffixes)
    final orgPattern = RegExp(r'\b([A-Z][\w\s&]+ (?:Inc|Corp|LLC|Ltd|Company|Corporation|Group|Foundation))\b');
    for (final match in orgPattern.allMatches(content)) {
      entities.add(NamedEntity(
        text: match.group(0)!,
        type: 'ORGANIZATION',
        confidence: 0.8,
        startOffset: match.start,
        endOffset: match.end,
      ));
    }
    
    // Locations (countries and cities - simplified)
    final locationPattern = RegExp(r'\b(New York|London|Paris|Tokyo|China|United States|Germany|France)\b', caseSensitive: true);
    for (final match in locationPattern.allMatches(content)) {
      entities.add(NamedEntity(
        text: match.group(0)!,
        type: 'LOCATION',
        confidence: 0.9,
        startOffset: match.start,
        endOffset: match.end,
      ));
    }
    
    // Dates
    final datePattern = RegExp(r'\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b');
    for (final match in datePattern.allMatches(content)) {
      entities.add(NamedEntity(
        text: match.group(0)!,
        type: 'DATE',
        confidence: 0.95,
        startOffset: match.start,
        endOffset: match.end,
      ));
    }
    
    // Money
    final moneyPattern = RegExp(r'\$[\d,]+(?:\.\d{2})?\b|\b\d+\s+(?:dollars|euros|pounds|yen)\b');
    for (final match in moneyPattern.allMatches(content)) {
      entities.add(NamedEntity(
        text: match.group(0)!,
        type: 'MONEY',
        confidence: 0.9,
        startOffset: match.start,
        endOffset: match.end,
      ));
    }
    
    return entities;
  }
  
  int _argmax(List<double> list) {
    var maxIndex = 0;
    var maxValue = list[0];
    for (var i = 1; i < list.length; i++) {
      if (list[i] > maxValue) {
        maxValue = list[i];
        maxIndex = i;
      }
    }
    return maxIndex;
  }
  
  String _getEntityType(int index) {
    const types = ['O', 'PERSON', 'ORGANIZATION', 'LOCATION', 'DATE', 'TIME', 'MONEY'];
    return types[index];
  }
  
  List<NamedEntity> _mergeEntities(List<NamedEntity> entities) {
    if (entities.isEmpty) return entities;
    
    final merged = <NamedEntity>[];
    var current = entities[0];
    
    for (var i = 1; i < entities.length; i++) {
      final next = entities[i];
      
      // Merge if same type and adjacent
      if (next.type == current.type && next.startOffset - current.endOffset <= 1) {
        current = NamedEntity(
          text: '${current.text} ${next.text}',
          type: current.type,
          confidence: (current.confidence + next.confidence) / 2,
          startOffset: current.startOffset,
          endOffset: next.endOffset,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    
    merged.add(current);
    return merged;
  }
  
  /// Get cache key
  String _getCacheKey(String articleId, List<AIAnalysisType> analyses) {
    final sortedAnalyses = analyses.map((a) => a.toString()).toList()..sort();
    return '$articleId:${sortedAnalyses.join(',')}';
  }
  
  /// Save analysis result to database
  Future<void> _saveAnalysisResult(AIAnalysisResult result) async {
    try {
      final db = await database.database;
      
      // Convert result to JSON for storage
      final analysisJson = {
        'articleId': result.articleId,
        'analyses': result.analyses.map((a) => a.toString()).toList(),
        'summary': result.summary,
        'keyPoints': result.keyPoints,
        'sentiment': result.sentiment?.toJson(),
        'biasAnalysis': result.biasAnalysis?.toJson(),
        'factCheck': result.factCheck?.toJson(),
        'perspectives': result.perspectives?.map((p) => p.toJson()).toList(),
        'entities': result.entities?.map((e) => e.toJson()).toList(),
        'topics': result.topics,
        'questions': result.questions,
        'tags': result.tags,
        'readingLevel': result.readingLevel,
        'contentWarnings': result.contentWarnings,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Store in article_metadata table or create a dedicated ai_analysis table
      await db.execute('''
        INSERT OR REPLACE INTO article_metadata (article_id, key, value)
        VALUES (?, 'ai_analysis', ?)
      ''', [result.articleId, jsonEncode(analysisJson)]);
      
      // Also update the article's analyzed flag
      await db.execute('''
        UPDATE articles 
        SET ai_analyzed = 1, ai_analyzed_at = ?
        WHERE id = ?
      ''', [DateTime.now().toIso8601String(), result.articleId]);
      
      // Cache the result
      _analysisCache[_getCacheKey(result.articleId, result.analyses)] = result;
      
      logger.i('Saved AI analysis for article ${result.articleId}');
    } catch (e) {
      logger.e('Error saving AI analysis result', error: e);
    }
  }
  
  /// Generate questions from content
  Future<List<String>> generateQuestions(String content) async {
    final prompt = '''
Generate 5 thoughtful questions about this content that would help readers think deeper.

Content: $content

Make questions open-ended and thought-provoking.
''';
    
    final response = await _callProvider(prompt, AITaskType.generation);
    final questions = response['questions'] as List<dynamic>? ?? [];
    
    return questions.map((q) => q.toString()).toList();
  }
  
  /// Answer question about content
  Future<String> answerQuestion(String content, String question) async {
    final prompt = '''
Answer this question based on the provided content. If the answer isn't in the content, say so.

Content: $content

Question: $question

Provide a clear, concise answer with relevant quotes if applicable.
''';
    
    final response = await _callProvider(prompt, AITaskType.qa);
    
    return response['answer'] ?? 'Unable to answer based on the provided content.';
  }
}

/// AI analysis result
class AIAnalysisResult {
  final String articleId;
  final DateTime timestamp;
  
  AISummary? summary;
  List<String>? keyPoints;
  List<AITag>? tags;
  MultiPerspective? perspectives;
  BiasAnalysis? biasAnalysis;
  SentimentAnalysis? sentimentAnalysis;
  List<FactCheckResult>? factCheckResults;
  List<NamedEntity>? entities;
  ComplexityAnalysis? complexity;
  
  AIAnalysisResult({
    required this.articleId,
    required this.timestamp,
  });
}

/// AI summary with multiple lengths
class AISummary {
  final String short;  // 50 words
  final String medium; // 100 words
  final String long;   // 200 words
  final DateTime generatedAt;
  
  AISummary({
    required this.short,
    required this.medium,
    required this.long,
    required this.generatedAt,
  });
}

/// AI-generated tag
class AITag {
  final String name;
  final String category;
  final double confidence;
  
  AITag({
    required this.name,
    required this.category,
    required this.confidence,
  });
}

/// Multi-perspective analysis
class MultiPerspective {
  Map<String, dynamic> primaryStance = {};
  Map<String, PerspectiveSummary> perspectives = {};
  List<RelatedPerspective> relatedArticles = [];
}

/// Individual perspective summary
class PerspectiveSummary {
  final String type;
  final String summary;
  final List<String> keyPoints;
  final double confidence;
  
  PerspectiveSummary({
    required this.type,
    required this.summary,
    required this.keyPoints,
    required this.confidence,
  });
}

/// Related article with different perspective
class RelatedPerspective {
  final String title;
  final String url;
  final String source;
  final String perspectiveType;
  final double relevance;
  
  RelatedPerspective({
    required this.title,
    required this.url,
    required this.source,
    required this.perspectiveType,
    required this.relevance,
  });
}

/// Bias analysis result
class BiasAnalysis {
  final double overallScore;
  final PoliticalBias politicalBias;
  final Map<String, double> biasIndicators;
  final double factualDensity;
  final double emotionalIndex;
  final int loadedTermsCount;
  final List<BiasExample> examples;
  final List<String> suggestions;
  
  BiasAnalysis({
    required this.overallScore,
    required this.politicalBias,
    required this.biasIndicators,
    required this.factualDensity,
    required this.emotionalIndex,
    required this.loadedTermsCount,
    required this.examples,
    required this.suggestions,
  });
}

/// Political bias
class PoliticalBias {
  final String direction; // left, center, right
  final double score;     // -1 (far left) to +1 (far right)
  
  PoliticalBias({
    required this.direction,
    required this.score,
  });
}

/// Bias example
class BiasExample {
  final String text;
  final String type;
  final String explanation;
  
  BiasExample({
    required this.text,
    required this.type,
    required this.explanation,
  });
}

/// Sentiment analysis result
class SentimentAnalysis {
  final double score;        // -1 to +1
  final String label;        // very_negative, negative, neutral, positive, very_positive
  final double confidence;
  final Map<String, double> emotions;
  final double subjectivity;
  final List<String> keyPhrases;
  
  SentimentAnalysis({
    required this.score,
    required this.label,
    required this.confidence,
    required this.emotions,
    required this.subjectivity,
    required this.keyPhrases,
  });
}

/// Fact check result
class FactCheckResult {
  final String claim;
  final String claimType;
  final double checkability;
  String verdict = 'unverifiable';
  double confidence = 0;
  List<FactSource> sources = [];
  
  FactCheckResult({
    required this.claim,
    required this.claimType,
    required this.checkability,
  });
}

/// Fact checking source
class FactSource {
  final String name;
  final String verdict;
  final String explanation;
  final List<String> sources;
  final double confidence;
  final DateTime checkedAt;
  
  FactSource({
    required this.name,
    required this.verdict,
    required this.explanation,
    required this.sources,
    required this.confidence,
    required this.checkedAt,
  });
}

/// Named entity
class NamedEntity {
  final String text;
  final String type;
  final String context;
  final double confidence;
  
  NamedEntity({
    required this.text,
    required this.type,
    required this.context,
    required this.confidence,
  });
}

/// Text complexity analysis
class ComplexityAnalysis {
  final double readingEase;
  final double gradeLevel;
  final double avgSentenceLength;
  final double avgSyllablesPerWord;
  final double complexWordPercentage;
  final double passiveVoicePercentage;
  final double adverbUsage;
  final String assessment;
  
  ComplexityAnalysis({
    required this.readingEase,
    required this.gradeLevel,
    required this.avgSentenceLength,
    required this.avgSyllablesPerWord,
    required this.complexWordPercentage,
    required this.passiveVoicePercentage,
    required this.adverbUsage,
    required this.assessment,
  });
}

/// AI analysis types
enum AIAnalysisType {
  summary,
  perspectives,
  bias,
  sentiment,
  factCheck,
  entities,
  complexity,
}

/// AI task types
enum AITaskType {
  summarization,
  extraction,
  classification,
  analysis,
  generation,
  factChecking,
  qa,
}

/// Abstract AI provider
abstract class AIProvider {
  String get name;
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType);
}

/// OpenAI provider implementation
class OpenAIProvider implements AIProvider {
  final String apiKey;
  final String model;
  final Dio dio;
  
  OpenAIProvider({
    required this.apiKey,
    required this.model,
    required this.dio,
  });
  
  @override
  String get name => 'OpenAI';
  
  @override
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType) async {
    final response = await dio.post(
      'https://api.openai.com/v1/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': 'You are an AI assistant specialized in news analysis, fact-checking, and providing multiple perspectives. Always strive to be objective, thorough, and intellectually honest.',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
        'temperature': _getTemperature(taskType),
        'response_format': {'type': 'json_object'},
      },
    );
    
    final content = response.data['choices'][0]['message']['content'];
    return jsonDecode(content) as Map<String, dynamic>;
  }
  
  double _getTemperature(AITaskType taskType) {
    switch (taskType) {
      case AITaskType.summarization:
      case AITaskType.extraction:
      case AITaskType.factChecking:
        return 0.3; // Low temperature for accuracy
      case AITaskType.generation:
        return 0.7; // Higher for creativity
      default:
        return 0.5;
    }
  }
}

/// Anthropic Claude provider
class AnthropicProvider implements AIProvider {
  final String apiKey;
  final String model;
  final Dio dio;
  
  AnthropicProvider({
    required this.apiKey,
    required this.model,
    required this.dio,
  });
  
  @override
  String get name => 'Anthropic';
  
  @override
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType) async {
    final response = await dio.post(
      'https://api.anthropic.com/v1/messages',
      options: Options(
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
      ),
      data: {
        'model': model,
        'max_tokens': 4096,
        'messages': [
          {
            'role': 'user',
            'content': prompt + '\n\nProvide your response in JSON format.',
          },
        ],
      },
    );
    
    final content = response.data['content'][0]['text'];
    return jsonDecode(content) as Map<String, dynamic>;
  }
}

/// Google AI provider
class GoogleAIProvider implements AIProvider {
  final String apiKey;
  final String model;
  final Dio dio;
  
  GoogleAIProvider({
    required this.apiKey,
    required this.model,
    required this.dio,
  });
  
  @override
  String get name => 'Google';
  
  @override
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType) async {
    try {
      final endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';
      
      final response = await dio.post(
        endpoint,
        options: Options(
          headers: {
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'contents': [{
            'parts': [{
              'text': prompt,
            }],
          }],
          'generationConfig': {
            'temperature': _getTemperature(taskType),
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': _getMaxTokens(taskType),
          },
          'safetySettings': [
            {
              'category': 'HARM_CATEGORY_HARASSMENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_HATE_SPEECH',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
          ],
        },
      );
      
      final content = response.data['candidates'][0]['content']['parts'][0]['text'];
      return _parseResponse(content, taskType);
    } catch (e) {
      throw AIException('Google AI error: $e');
    }
  }
  
  double _getTemperature(AITaskType taskType) {
    switch (taskType) {
      case AITaskType.factChecking:
      case AITaskType.biasDetection:
        return 0.3;
      case AITaskType.summary:
      case AITaskType.analysis:
        return 0.5;
      case AITaskType.generation:
        return 0.7;
    }
  }
  
  int _getMaxTokens(AITaskType taskType) {
    switch (taskType) {
      case AITaskType.summary:
        return 500;
      case AITaskType.factChecking:
      case AITaskType.biasDetection:
        return 1000;
      case AITaskType.analysis:
      case AITaskType.generation:
        return 2000;
    }
  }
  
  Map<String, dynamic> _parseResponse(String content, AITaskType taskType) {
    try {
      // Try to parse as JSON first
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      // If not JSON, parse based on task type
      switch (taskType) {
        case AITaskType.summary:
          return {'summary': content};
        case AITaskType.analysis:
          return {'analysis': content};
        case AITaskType.factChecking:
          return {'verdict': 'unverifiable', 'explanation': content};
        case AITaskType.biasDetection:
          return {'hasBias': false, 'explanation': content};
        case AITaskType.generation:
          return {'generated': content};
      }
    }
  }
}

/// Cohere provider
class CohereProvider implements AIProvider {
  final String apiKey;
  final String model;
  final Dio dio;
  
  CohereProvider({
    required this.apiKey,
    required this.model,
    required this.dio,
  });
  
  @override
  String get name => 'Cohere';
  
  @override
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType) async {
    try {
      final endpoint = _getEndpoint(taskType);
      
      final response = await dio.post(
        endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: _buildRequest(prompt, taskType),
      );
      
      return _parseResponse(response.data, taskType);
    } catch (e) {
      throw AIException('Cohere error: $e');
    }
  }
  
  String _getEndpoint(AITaskType taskType) {
    const baseUrl = 'https://api.cohere.ai/v1';
    switch (taskType) {
      case AITaskType.summary:
        return '$baseUrl/summarize';
      case AITaskType.generation:
        return '$baseUrl/generate';
      default:
        return '$baseUrl/chat';
    }
  }
  
  Map<String, dynamic> _buildRequest(String prompt, AITaskType taskType) {
    switch (taskType) {
      case AITaskType.summary:
        return {
          'text': prompt,
          'model': model,
          'length': 'medium',
          'extractiveness': 'medium',
        };
      case AITaskType.generation:
        return {
          'prompt': prompt,
          'model': model,
          'max_tokens': 1000,
          'temperature': 0.7,
        };
      default:
        return {
          'message': prompt,
          'model': model,
          'temperature': _getTemperature(taskType),
          'chat_history': [],
          'connectors': [],
        };
    }
  }
  
  double _getTemperature(AITaskType taskType) {
    switch (taskType) {
      case AITaskType.factChecking:
      case AITaskType.biasDetection:
        return 0.3;
      case AITaskType.summary:
      case AITaskType.analysis:
        return 0.5;
      case AITaskType.generation:
        return 0.7;
    }
  }
  
  Map<String, dynamic> _parseResponse(Map<String, dynamic> data, AITaskType taskType) {
    switch (taskType) {
      case AITaskType.summary:
        return {'summary': data['summary'] ?? ''};
      case AITaskType.generation:
        final generations = data['generations'] as List?;
        return {'generated': generations?.isNotEmpty == true ? generations![0]['text'] : ''};
      default:
        final text = data['text'] ?? data['reply'] ?? '';
        try {
          return jsonDecode(text) as Map<String, dynamic>;
        } catch (_) {
          return _parseTextResponse(text, taskType);
        }
    }
  }
  
  Map<String, dynamic> _parseTextResponse(String text, AITaskType taskType) {
    switch (taskType) {
      case AITaskType.factChecking:
        return {'verdict': 'unverifiable', 'explanation': text};
      case AITaskType.biasDetection:
        return {'hasBias': false, 'explanation': text};
      case AITaskType.analysis:
        return {'analysis': text};
      default:
        return {'result': text};
    }
  }
}

/// Local AI provider using TensorFlow Lite
class LocalAIProvider implements AIProvider {
  final LocalAIService? localAI;
  final Interpreter? sentimentModel;
  final Interpreter? nerModel;
  final Interpreter? classificationModel;
  
  LocalAIProvider({
    this.localAI,
    this.sentimentModel,
    this.nerModel,
    this.classificationModel,
  });
  
  @override
  String get name => 'Local';
  
  @override
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType) async {
    // Use local AI service if available
    if (localAI != null) {
      try {
        switch (taskType) {
          case AITaskType.summarization:
            final summary = await localAI!.generateSummary(prompt);
            return {'summary': summary, 'confidence': 0.7};
          
          case AITaskType.analysis:
            if (prompt.contains('sentiment')) {
              final sentiment = await localAI!.analyzeSentiment(prompt);
              return {
                'sentiment_score': sentiment.confidence,
                'sentiment': sentiment.sentiment,
                'confidence': sentiment.confidence,
              };
            } else if (prompt.contains('bias')) {
              final bias = await localAI!.detectBias(prompt);
              return {
                'overall_bias': bias.overallBias,
                'detected_biases': bias.detectedBiases,
                'suggestions': bias.suggestions,
              };
            }
            break;
          
          case AITaskType.classification:
            final topics = await localAI!.classifyTopics(prompt);
            return {
              'topics': topics.allTopics,
              'primary_topic': topics.primaryTopic,
              'confidence': topics.confidence,
            };
          
          default:
            break;
        }
      } catch (e) {
        print('Local AI processing failed: $e');
      }
    }
    
    // Basic fallback implementation
    return {
      'summary': 'Local model processing not available',
      'confidence': 0.5,
    };
  }
}