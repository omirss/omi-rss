import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:serverpod/serverpod.dart';
import '../protocol/protocol.dart';

class AIService {
  final Session session;
  final Dio _dio;
  late final String? _openAIKey;
  late final String? _anthropicKey;
  late final String? _geminiKey;
  late final String? _cohereKey;
  
  AIService(this.session) : _dio = Dio() {
    final config = session.serverpod.config;
    _openAIKey = config['ai']?['openai']?['apiKey'];
    _anthropicKey = config['ai']?['anthropic']?['apiKey'];
    _geminiKey = config['ai']?['google']?['apiKey'];
    _cohereKey = config['ai']?['cohere']?['apiKey'];
  }

  Future<AIAnalysis> analyzeArticle(Article article) async {
    try {
      // Try OpenAI first
      if (_openAIKey != null) {
        return await _analyzeWithOpenAI(article);
      }
      
      // Fallback to Anthropic
      if (_anthropicKey != null) {
        return await _analyzeWithAnthropic(article);
      }
      
      // Fallback to Gemini
      if (_geminiKey != null) {
        return await _analyzeWithGemini(article);
      }
      
      // Fallback to Cohere
      if (_cohereKey != null) {
        return await _analyzeWithCohere(article);
      }
      
      throw Exception('No AI provider configured');
    } catch (e) {
      session.log('AI analysis error: $e');
      rethrow;
    }
  }

  Future<AIAnalysis> _analyzeWithOpenAI(Article article) async {
    final response = await _dio.post(
      'https://api.openai.com/v1/chat/completions',
      options: Options(headers: {
        'Authorization': 'Bearer $_openAIKey',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': 'gpt-4-turbo-preview',
        'messages': [
          {
            'role': 'system',
            'content': '''You are an expert news analyst. Analyze the following article and provide:
1. A summary (50-100 words)
2. Key points (3-5 bullet points)
3. Multiple perspectives (at least 7 different viewpoints)
4. Bias detection (identify any biases present)
5. Fact-checking claims (identify key claims and their veracity)
6. Sentiment analysis
7. Related topics

Format your response as JSON.'''
          },
          {
            'role': 'user',
            'content': 'Title: ${article.title}\n\nContent: ${article.content ?? article.description}'
          }
        ],
        'temperature': 0.7,
        'response_format': {'type': 'json_object'}
      },
    );

    final data = response.data['choices'][0]['message']['content'];
    final analysis = json.decode(data);
    
    return AIAnalysis(
      articleId: article.id!,
      summary: analysis['summary'],
      keyPoints: List<String>.from(analysis['keyPoints'] ?? []),
      perspectives: _parsePerspectives(analysis['perspectives']),
      biasAnalysis: _parseBiasAnalysis(analysis['biasAnalysis']),
      factChecks: _parseFactChecks(analysis['factChecks']),
      sentiment: _parseSentiment(analysis['sentiment']),
      relatedTopics: List<String>.from(analysis['relatedTopics'] ?? []),
      analyzedAt: DateTime.now(),
      provider: 'openai',
    );
  }

  Future<AIAnalysis> _analyzeWithAnthropic(Article article) async {
    final response = await _dio.post(
      'https://api.anthropic.com/v1/messages',
      options: Options(headers: {
        'x-api-key': _anthropicKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': 'claude-3-opus-20240229',
        'messages': [
          {
            'role': 'user',
            'content': '''Analyze this article and provide a JSON response with:
- summary (50-100 words)
- keyPoints (3-5 bullet points)
- perspectives (7+ different viewpoints with stance and explanation)
- biasAnalysis (detected biases with examples)
- factChecks (key claims with verification status)
- sentiment (overall and by aspect)
- relatedTopics

Title: ${article.title}
Content: ${article.content ?? article.description}'''
          }
        ],
        'max_tokens': 4000,
      },
    );

    final content = response.data['content'][0]['text'];
    final analysis = json.decode(content);
    
    return AIAnalysis(
      articleId: article.id!,
      summary: analysis['summary'],
      keyPoints: List<String>.from(analysis['keyPoints'] ?? []),
      perspectives: _parsePerspectives(analysis['perspectives']),
      biasAnalysis: _parseBiasAnalysis(analysis['biasAnalysis']),
      factChecks: _parseFactChecks(analysis['factChecks']),
      sentiment: _parseSentiment(analysis['sentiment']),
      relatedTopics: List<String>.from(analysis['relatedTopics'] ?? []),
      analyzedAt: DateTime.now(),
      provider: 'anthropic',
    );
  }

  Future<AIAnalysis> _analyzeWithGemini(Article article) async {
    final response = await _dio.post(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$_geminiKey',
      data: {
        'contents': [
          {
            'parts': [
              {
                'text': '''Analyze this article and provide a JSON response with:
- summary (50-100 words)
- keyPoints (3-5 bullet points)
- perspectives (7+ different viewpoints)
- biasAnalysis (detected biases)
- factChecks (key claims verification)
- sentiment (analysis)
- relatedTopics

Title: ${article.title}
Content: ${article.content ?? article.description}'''
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'topK': 40,
          'topP': 0.95,
        }
      },
    );

    final text = response.data['candidates'][0]['content']['parts'][0]['text'];
    final analysis = json.decode(text);
    
    return AIAnalysis(
      articleId: article.id!,
      summary: analysis['summary'],
      keyPoints: List<String>.from(analysis['keyPoints'] ?? []),
      perspectives: _parsePerspectives(analysis['perspectives']),
      biasAnalysis: _parseBiasAnalysis(analysis['biasAnalysis']),
      factChecks: _parseFactChecks(analysis['factChecks']),
      sentiment: _parseSentiment(analysis['sentiment']),
      relatedTopics: List<String>.from(analysis['relatedTopics'] ?? []),
      analyzedAt: DateTime.now(),
      provider: 'gemini',
    );
  }

  Future<AIAnalysis> _analyzeWithCohere(Article article) async {
    final response = await _dio.post(
      'https://api.cohere.ai/v1/generate',
      options: Options(headers: {
        'Authorization': 'Bearer $_cohereKey',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': 'command',
        'prompt': '''Analyze this article and provide a JSON response with:
- summary (50-100 words)
- keyPoints (3-5 bullet points)
- perspectives (7+ different viewpoints)
- biasAnalysis (detected biases)
- factChecks (key claims verification)
- sentiment (analysis)
- relatedTopics

Title: ${article.title}
Content: ${article.content ?? article.description}

Respond only with valid JSON.''',
        'max_tokens': 2000,
        'temperature': 0.7,
      },
    );

    final text = response.data['generations'][0]['text'];
    final analysis = json.decode(text);
    
    return AIAnalysis(
      articleId: article.id!,
      summary: analysis['summary'],
      keyPoints: List<String>.from(analysis['keyPoints'] ?? []),
      perspectives: _parsePerspectives(analysis['perspectives']),
      biasAnalysis: _parseBiasAnalysis(analysis['biasAnalysis']),
      factChecks: _parseFactChecks(analysis['factChecks']),
      sentiment: _parseSentiment(analysis['sentiment']),
      relatedTopics: List<String>.from(analysis['relatedTopics'] ?? []),
      analyzedAt: DateTime.now(),
      provider: 'cohere',
    );
  }

  List<AIPerspective> _parsePerspectives(dynamic perspectivesData) {
    if (perspectivesData == null) return [];
    
    final perspectives = <AIPerspective>[];
    if (perspectivesData is List) {
      for (final p in perspectivesData) {
        perspectives.add(AIPerspective(
          viewpoint: p['viewpoint'] ?? 'Unknown',
          stance: p['stance'] ?? '',
          explanation: p['explanation'] ?? '',
          confidence: (p['confidence'] ?? 0.5).toDouble(),
        ));
      }
    }
    return perspectives;
  }

  AIBiasAnalysis _parseBiasAnalysis(dynamic biasData) {
    if (biasData == null) {
      return AIBiasAnalysis(
        overallBias: 0.5,
        biasTypes: [],
        examples: [],
        recommendations: [],
      );
    }

    return AIBiasAnalysis(
      overallBias: (biasData['overallBias'] ?? 0.5).toDouble(),
      biasTypes: List<String>.from(biasData['biasTypes'] ?? []),
      examples: List<String>.from(biasData['examples'] ?? []),
      recommendations: List<String>.from(biasData['recommendations'] ?? []),
    );
  }

  List<AIFactCheck> _parseFactChecks(dynamic factCheckData) {
    if (factCheckData == null) return [];
    
    final factChecks = <AIFactCheck>[];
    if (factCheckData is List) {
      for (final f in factCheckData) {
        factChecks.add(AIFactCheck(
          claim: f['claim'] ?? '',
          verdict: f['verdict'] ?? 'unverified',
          evidence: f['evidence'] ?? '',
          confidence: (f['confidence'] ?? 0.5).toDouble(),
          sources: List<String>.from(f['sources'] ?? []),
        ));
      }
    }
    return factChecks;
  }

  AISentiment _parseSentiment(dynamic sentimentData) {
    if (sentimentData == null) {
      return AISentiment(
        overall: 0.5,
        positive: 0.33,
        negative: 0.33,
        neutral: 0.34,
        emotions: {},
      );
    }

    return AISentiment(
      overall: (sentimentData['overall'] ?? 0.5).toDouble(),
      positive: (sentimentData['positive'] ?? 0.33).toDouble(),
      negative: (sentimentData['negative'] ?? 0.33).toDouble(),
      neutral: (sentimentData['neutral'] ?? 0.34).toDouble(),
      emotions: Map<String, double>.from(sentimentData['emotions'] ?? {}),
    );
  }

  // Fact checking with external APIs
  Future<List<AIFactCheck>> checkFactsWithExternalAPIs(List<String> claims) async {
    final factChecks = <AIFactCheck>[];
    
    // TODO: Implement Snopes API integration
    // TODO: Implement FactCheck.org API integration
    // TODO: Implement PolitiFact API integration
    
    // For now, return AI-based fact checking
    for (final claim in claims) {
      factChecks.add(AIFactCheck(
        claim: claim,
        verdict: 'unverified',
        evidence: 'External fact-checking APIs not yet integrated',
        confidence: 0.0,
        sources: [],
      ));
    }
    
    return factChecks;
  }

  // Question answering
  Future<String> answerQuestion(Article article, String question) async {
    try {
      if (_openAIKey != null) {
        final response = await _dio.post(
          'https://api.openai.com/v1/chat/completions',
          options: Options(headers: {
            'Authorization': 'Bearer $_openAIKey',
            'Content-Type': 'application/json',
          }),
          data: {
            'model': 'gpt-4-turbo-preview',
            'messages': [
              {
                'role': 'system',
                'content': 'Answer questions about the article concisely and accurately.'
              },
              {
                'role': 'user',
                'content': '''Article: ${article.title}
${article.content ?? article.description}

Question: $question'''
              }
            ],
            'temperature': 0.5,
            'max_tokens': 500,
          },
        );

        return response.data['choices'][0]['message']['content'];
      }
      
      throw Exception('No AI provider available for Q&A');
    } catch (e) {
      session.log('Q&A error: $e');
      return 'Unable to answer question at this time.';
    }
  }
}