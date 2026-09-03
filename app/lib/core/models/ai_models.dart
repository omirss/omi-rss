import 'dart:convert';

/// Result of AI analysis on an article
class AIAnalysisResult {
  final String articleId;
  final List<AIAnalysisType> analyses;
  final String? summary;
  final List<String>? keyPoints;
  final SentimentAnalysis? sentiment;
  final BiasAnalysis? biasAnalysis;
  final FactCheckResult? factCheck;
  final List<RelatedPerspective>? perspectives;
  final List<NamedEntity>? entities;
  final List<String>? topics;
  final List<String>? questions;
  final List<String>? tags;
  final String? readingLevel;
  final List<String>? contentWarnings;

  AIAnalysisResult({
    required this.articleId,
    required this.analyses,
    this.summary,
    this.keyPoints,
    this.sentiment,
    this.biasAnalysis,
    this.factCheck,
    this.perspectives,
    this.entities,
    this.topics,
    this.questions,
    this.tags,
    this.readingLevel,
    this.contentWarnings,
  });

  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'analyses': analyses.map((a) => a.toString()).toList(),
    'summary': summary,
    'keyPoints': keyPoints,
    'sentiment': sentiment?.toJson(),
    'biasAnalysis': biasAnalysis?.toJson(),
    'factCheck': factCheck?.toJson(),
    'perspectives': perspectives?.map((p) => p.toJson()).toList(),
    'entities': entities?.map((e) => e.toJson()).toList(),
    'topics': topics,
    'questions': questions,
    'tags': tags,
    'readingLevel': readingLevel,
    'contentWarnings': contentWarnings,
  };
}

/// Types of AI analysis available
enum AIAnalysisType {
  summary,
  sentiment,
  biasDetection,
  factChecking,
  namedEntityRecognition,
  topicExtraction,
  perspectiveAnalysis,
  questionGeneration,
}

/// AI task types for provider routing
enum AITaskType {
  summary,
  analysis,
  factChecking,
  biasDetection,
  generation,
}

/// Sentiment analysis result
class SentimentAnalysis {
  final String sentiment; // very_negative, negative, neutral, positive, very_positive
  final double score; // -1.0 to 1.0
  final double confidence;
  final Map<String, double> emotions; // anger, joy, sadness, etc.

  SentimentAnalysis({
    required this.sentiment,
    required this.score,
    required this.confidence,
    required this.emotions,
  });

  Map<String, dynamic> toJson() => {
    'sentiment': sentiment,
    'score': score,
    'confidence': confidence,
    'emotions': emotions,
  };

  factory SentimentAnalysis.fromJson(Map<String, dynamic> json) => SentimentAnalysis(
    sentiment: json['sentiment'],
    score: json['score'],
    confidence: json['confidence'],
    emotions: Map<String, double>.from(json['emotions']),
  );
}

/// Bias analysis result
class BiasAnalysis {
  final bool hasBias;
  final List<BiasType> biasTypes;
  final String explanation;
  final double confidence;
  final Map<String, String> examples;

  BiasAnalysis({
    required this.hasBias,
    required this.biasTypes,
    required this.explanation,
    required this.confidence,
    required this.examples,
  });

  Map<String, dynamic> toJson() => {
    'hasBias': hasBias,
    'biasTypes': biasTypes.map((b) => b.toString()).toList(),
    'explanation': explanation,
    'confidence': confidence,
    'examples': examples,
  };

  factory BiasAnalysis.fromJson(Map<String, dynamic> json) => BiasAnalysis(
    hasBias: json['hasBias'],
    biasTypes: (json['biasTypes'] as List).map((b) => BiasType.values.firstWhere((t) => t.toString() == b)).toList(),
    explanation: json['explanation'],
    confidence: json['confidence'],
    examples: Map<String, String>.from(json['examples']),
  );
}

/// Types of bias that can be detected
enum BiasType {
  political,
  commercial,
  sensational,
  cultural,
  gender,
  racial,
  religious,
  confirmation,
}

/// Fact checking result
class FactCheckResult {
  final String verdict; // true, mostly_true, mixed, mostly_false, false, unverifiable
  final List<FactSource> sources;
  final String explanation;
  final double confidence;
  final List<String> claims;

  FactCheckResult({
    required this.verdict,
    required this.sources,
    required this.explanation,
    required this.confidence,
    required this.claims,
  });

  Map<String, dynamic> toJson() => {
    'verdict': verdict,
    'sources': sources.map((s) => s.toJson()).toList(),
    'explanation': explanation,
    'confidence': confidence,
    'claims': claims,
  };

  factory FactCheckResult.fromJson(Map<String, dynamic> json) => FactCheckResult(
    verdict: json['verdict'],
    sources: (json['sources'] as List).map((s) => FactSource.fromJson(s)).toList(),
    explanation: json['explanation'],
    confidence: json['confidence'],
    claims: List<String>.from(json['claims']),
  );
}

/// Fact checking source
class FactSource {
  final String name;
  final String verdict;
  final String explanation;
  final List<String> sources;
  final double confidence;
  final DateTime checkedAt;
  final Map<String, dynamic>? metadata;

  FactSource({
    required this.name,
    required this.verdict,
    required this.explanation,
    required this.sources,
    required this.confidence,
    required this.checkedAt,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'verdict': verdict,
    'explanation': explanation,
    'sources': sources,
    'confidence': confidence,
    'checkedAt': checkedAt.toIso8601String(),
    'metadata': metadata,
  };

  factory FactSource.fromJson(Map<String, dynamic> json) => FactSource(
    name: json['name'],
    verdict: json['verdict'],
    explanation: json['explanation'],
    sources: List<String>.from(json['sources']),
    confidence: json['confidence'],
    checkedAt: DateTime.parse(json['checkedAt']),
    metadata: json['metadata'],
  );
}

/// Related article with different perspective
class RelatedPerspective {
  final String source;
  final String title;
  final String perspective;
  final String politicalLean; // left, center-left, center, center-right, right
  final String? url;
  final double similarity;

  RelatedPerspective({
    required this.source,
    required this.title,
    required this.perspective,
    required this.politicalLean,
    this.url,
    required this.similarity,
  });

  Map<String, dynamic> toJson() => {
    'source': source,
    'title': title,
    'perspective': perspective,
    'politicalLean': politicalLean,
    'url': url,
    'similarity': similarity,
  };

  factory RelatedPerspective.fromJson(Map<String, dynamic> json) => RelatedPerspective(
    source: json['source'],
    title: json['title'],
    perspective: json['perspective'],
    politicalLean: json['politicalLean'],
    url: json['url'],
    similarity: json['similarity'],
  );
}

/// Named entity extracted from text
class NamedEntity {
  final String text;
  final String type; // PERSON, ORGANIZATION, LOCATION, DATE, TIME, MONEY, etc.
  final double confidence;
  final int startOffset;
  final int endOffset;

  NamedEntity({
    required this.text,
    required this.type,
    required this.confidence,
    required this.startOffset,
    required this.endOffset,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'type': type,
    'confidence': confidence,
    'startOffset': startOffset,
    'endOffset': endOffset,
  };

  factory NamedEntity.fromJson(Map<String, dynamic> json) => NamedEntity(
    text: json['text'],
    type: json['type'],
    confidence: json['confidence'],
    startOffset: json['startOffset'],
    endOffset: json['endOffset'],
  );
}

/// AI provider interface
abstract class AIProvider {
  String get name;
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType);
}

/// AI exception for error handling
class AIException implements Exception {
  final String message;
  final String? provider;
  final dynamic originalError;

  AIException(this.message, {this.provider, this.originalError});

  @override
  String toString() => 'AIException: $message${provider != null ? ' (Provider: $provider)' : ''}';
}

/// Extension for list reshaping (for TensorFlow operations)
extension ListReshape<T> on List<T> {
  List<dynamic> reshape(List<int> shape) {
    if (shape.length == 1) {
      return this;
    }
    
    var result = <dynamic>[];
    var size = shape.skip(1).reduce((a, b) => a * b);
    
    for (var i = 0; i < length; i += size) {
      result.add(sublist(i, i + size).reshape(shape.skip(1).toList()));
    }
    
    return result;
  }
}