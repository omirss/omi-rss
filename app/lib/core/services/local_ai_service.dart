import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ml_algo/ml_algo.dart';
import 'package:ml_dataframe/ml_dataframe.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/article.dart';

/// Local AI service for offline analysis
class LocalAIService {
  // TensorFlow Lite models
  Interpreter? _sentimentModel;
  Interpreter? _biasDetectionModel;
  Interpreter? _topicClassificationModel;
  Interpreter? _summarizationModel;
  Interpreter? _nerModel;
  
  // ML-Algo models for lightweight analysis
  LinearRegressor? _readabilityModel;
  LogisticRegressor? _qualityModel;
  
  // Model metadata
  Map<String, dynamic>? _sentimentLabels;
  Map<String, dynamic>? _topicLabels;
  Map<String, dynamic>? _biasIndicators;
  
  // Tokenizer for text preprocessing
  final Map<String, int> _vocabulary = {};
  final int _maxSequenceLength = 512;
  
  bool _isInitialized = false;
  
  // Getters for models
  Interpreter? get sentimentModel => _sentimentModel;
  Interpreter? get nerModel => _nerModel;
  Interpreter? get classificationModel => _topicClassificationModel;
  
  /// Initialize all local models
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await Future.wait([
        _loadTFLiteModels(),
        _loadMLAlgoModels(),
        _loadModelMetadata(),
        _loadVocabulary(),
      ]);
      
      _isInitialized = true;
    } catch (e) {
      print('Failed to initialize local AI models: $e');
      throw LocalAIException('Failed to initialize models: $e');
    }
  }
  
  /// Load TensorFlow Lite models
  Future<void> _loadTFLiteModels() async {
    try {
      // Sentiment analysis model
      _sentimentModel = await Interpreter.fromAsset(
        'assets/models/sentiment_analysis.tflite',
        options: InterpreterOptions()..threads = 2,
      );
      
      // Bias detection model
      _biasDetectionModel = await Interpreter.fromAsset(
        'assets/models/bias_detection.tflite',
        options: InterpreterOptions()..threads = 2,
      );
      
      // Topic classification model
      _topicClassificationModel = await Interpreter.fromAsset(
        'assets/models/topic_classification.tflite',
        options: InterpreterOptions()..threads = 2,
      );
      
      // Text summarization model (smaller version)
      _summarizationModel = await Interpreter.fromAsset(
        'assets/models/text_summarization_small.tflite',
        options: InterpreterOptions()..threads = 2,
      );
      
      // Named entity recognition model
      _nerModel = await Interpreter.fromAsset(
        'assets/models/ner_model.tflite',
        options: InterpreterOptions()..threads = 2,
      );
    } catch (e) {
      print('Error loading TFLite models: $e');
    }
  }
  
  /// Load ML-Algo models
  Future<void> _loadMLAlgoModels() async {
    try {
      // Load pre-trained readability model
      final readabilityData = await rootBundle.loadString(
        'assets/models/readability_model.json',
      );
      _readabilityModel = LinearRegressor.fromJson(readabilityData);
      
      // Load quality assessment model
      final qualityData = await rootBundle.loadString(
        'assets/models/quality_model.json',
      );
      _qualityModel = LogisticRegressor.fromJson(qualityData);
    } catch (e) {
      print('Error loading ML-Algo models: $e');
    }
  }
  
  /// Load model metadata and labels
  Future<void> _loadModelMetadata() async {
    try {
      // Sentiment labels
      final sentimentData = await rootBundle.loadString(
        'assets/models/sentiment_labels.json',
      );
      _sentimentLabels = json.decode(sentimentData);
      
      // Topic labels
      final topicData = await rootBundle.loadString(
        'assets/models/topic_labels.json',
      );
      _topicLabels = json.decode(topicData);
      
      // Bias indicators
      final biasData = await rootBundle.loadString(
        'assets/models/bias_indicators.json',
      );
      _biasIndicators = json.decode(biasData);
    } catch (e) {
      print('Error loading model metadata: $e');
    }
  }
  
  /// Load vocabulary for tokenization
  Future<void> _loadVocabulary() async {
    try {
      final vocabData = await rootBundle.loadString(
        'assets/models/vocabulary.json',
      );
      final vocabMap = json.decode(vocabData) as Map<String, dynamic>;
      
      vocabMap.forEach((key, value) {
        _vocabulary[key] = value as int;
      });
    } catch (e) {
      print('Error loading vocabulary: $e');
    }
  }
  
  /// Analyze article sentiment
  Future<SentimentAnalysis> analyzeSentiment(String text) async {
    if (_sentimentModel == null) {
      throw LocalAIException('Sentiment model not loaded');
    }
    
    try {
      // Preprocess text
      final input = _preprocessText(text);
      
      // Run inference
      final output = List.filled(3, 0.0).reshape([1, 3]);
      _sentimentModel!.run(input, output);
      
      // Extract results
      final scores = output[0] as List<double>;
      final labels = ['negative', 'neutral', 'positive'];
      final maxIndex = scores.indexOf(scores.reduce((a, b) => a > b ? a : b));
      
      return SentimentAnalysis(
        sentiment: labels[maxIndex],
        confidence: scores[maxIndex],
        scores: {
          'negative': scores[0],
          'neutral': scores[1],
          'positive': scores[2],
        },
      );
    } catch (e) {
      throw LocalAIException('Sentiment analysis failed: $e');
    }
  }
  
  /// Detect bias in text
  Future<BiasAnalysis> detectBias(String text) async {
    if (_biasDetectionModel == null) {
      return _fallbackBiasDetection(text);
    }
    
    try {
      // Preprocess text
      final input = _preprocessText(text);
      
      // Run inference
      final output = List.filled(5, 0.0).reshape([1, 5]);
      _biasDetectionModel!.run(input, output);
      
      // Extract results
      final scores = output[0] as List<double>;
      final biasTypes = ['political', 'gender', 'racial', 'economic', 'religious'];
      
      final detectedBiases = <String, double>{};
      for (int i = 0; i < biasTypes.length; i++) {
        if (scores[i] > 0.3) {
          detectedBiases[biasTypes[i]] = scores[i];
        }
      }
      
      // Calculate overall bias score
      final overallBias = scores.reduce((a, b) => a + b) / scores.length;
      
      return BiasAnalysis(
        overallBias: overallBias,
        detectedBiases: detectedBiases,
        suggestions: _generateBiasSuggestions(detectedBiases),
      );
    } catch (e) {
      return _fallbackBiasDetection(text);
    }
  }
  
  /// Classify article topics
  Future<TopicClassification> classifyTopics(String text) async {
    if (_topicClassificationModel == null) {
      return _fallbackTopicClassification(text);
    }
    
    try {
      // Preprocess text
      final input = _preprocessText(text);
      
      // Run inference
      final numTopics = _topicLabels?['labels']?.length ?? 20;
      final output = List.filled(numTopics, 0.0).reshape([1, numTopics]);
      _topicClassificationModel!.run(input, output);
      
      // Extract results
      final scores = output[0] as List<double>;
      final labels = _topicLabels?['labels'] as List<String>? ?? [];
      
      final topics = <String, double>{};
      for (int i = 0; i < labels.length && i < scores.length; i++) {
        if (scores[i] > 0.3) {
          topics[labels[i]] = scores[i];
        }
      }
      
      // Sort by confidence
      final sortedTopics = topics.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      return TopicClassification(
        primaryTopic: sortedTopics.isNotEmpty ? sortedTopics.first.key : 'general',
        allTopics: topics,
        confidence: sortedTopics.isNotEmpty ? sortedTopics.first.value : 0.0,
      );
    } catch (e) {
      return _fallbackTopicClassification(text);
    }
  }
  
  /// Generate text summary
  Future<String> generateSummary(String text, {int maxLength = 150}) async {
    if (_summarizationModel == null) {
      return _fallbackSummarization(text, maxLength);
    }
    
    try {
      // For small models, we'll use extractive summarization
      final sentences = _splitIntoSentences(text);
      if (sentences.length <= 3) {
        return text;
      }
      
      // Score sentences based on importance
      final scores = await _scoreSentences(sentences);
      
      // Select top sentences
      final numSentences = (maxLength ~/ 50).clamp(2, 5);
      final selectedIndices = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final summary = selectedIndices
          .take(numSentences)
          .map((e) => sentences[e.key])
          .toList()
        ..sort((a, b) => sentences.indexOf(a).compareTo(sentences.indexOf(b)));
      
      return summary.join(' ');
    } catch (e) {
      return _fallbackSummarization(text, maxLength);
    }
  }
  
  /// Calculate text readability
  Future<ReadabilityAnalysis> analyzeReadability(String text) async {
    try {
      // Extract features
      final features = _extractReadabilityFeatures(text);
      
      if (_readabilityModel != null) {
        // Use ML model
        final dataFrame = DataFrame([features]);
        final prediction = _readabilityModel!.predict(dataFrame);
        final score = prediction.rows.first.first as double;
        
        return ReadabilityAnalysis(
          score: score.clamp(0, 100),
          level: _getReadabilityLevel(score),
          metrics: features,
        );
      } else {
        // Fallback to traditional metrics
        return _calculateTraditionalReadability(text, features);
      }
    } catch (e) {
      return _calculateTraditionalReadability(text, {});
    }
  }
  
  /// Assess content quality
  Future<QualityAssessment> assessQuality(String text) async {
    try {
      // Extract quality features
      final features = _extractQualityFeatures(text);
      
      if (_qualityModel != null) {
        // Use ML model
        final dataFrame = DataFrame([features]);
        final prediction = _qualityModel!.predict(dataFrame);
        final probability = prediction.rows.first.first as double;
        
        return QualityAssessment(
          score: (probability * 100).round(),
          isHighQuality: probability > 0.7,
          factors: _interpretQualityFactors(features, probability),
        );
      } else {
        // Fallback to rule-based assessment
        return _ruleBasedQualityAssessment(text, features);
      }
    } catch (e) {
      return _ruleBasedQualityAssessment(text, {});
    }
  }
  
  /// Generate multiple perspectives on a topic
  Future<List<Perspective>> generatePerspectives(String text) async {
    // For local models, we'll generate perspectives using templates
    // and extracted entities/topics
    
    try {
      final sentiment = await analyzeSentiment(text);
      final topics = await classifyTopics(text);
      final bias = await detectBias(text);
      
      final perspectives = <Perspective>[];
      
      // Generate perspectives based on detected bias and sentiment
      if (bias.detectedBiases.containsKey('political')) {
        perspectives.addAll(_generatePoliticalPerspectives(text, sentiment));
      }
      
      if (topics.allTopics.containsKey('technology')) {
        perspectives.addAll(_generateTechPerspectives(text));
      }
      
      if (topics.allTopics.containsKey('business')) {
        perspectives.addAll(_generateBusinessPerspectives(text));
      }
      
      // Add general perspectives
      perspectives.addAll(_generateGeneralPerspectives(text, sentiment));
      
      return perspectives.take(7).toList();
    } catch (e) {
      return _generateFallbackPerspectives(text);
    }
  }
  
  /// Preprocess text for model input
  List<List<double>> _preprocessText(String text) {
    // Simple tokenization and padding
    final tokens = text.toLowerCase().split(RegExp(r'\s+'));
    final tokenIds = <int>[];
    
    for (final token in tokens) {
      if (_vocabulary.containsKey(token)) {
        tokenIds.add(_vocabulary[token]!);
      } else {
        tokenIds.add(1); // Unknown token
      }
      
      if (tokenIds.length >= _maxSequenceLength) break;
    }
    
    // Pad sequence
    while (tokenIds.length < _maxSequenceLength) {
      tokenIds.add(0); // Padding token
    }
    
    // Convert to float array
    return [tokenIds.map((id) => id.toDouble()).toList()];
  }
  
  /// Split text into sentences
  List<String> _splitIntoSentences(String text) {
    return text.split(RegExp(r'[.!?]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  
  /// Score sentences for summarization
  Future<Map<int, double>> _scoreSentences(List<String> sentences) async {
    final scores = <int, double>{};
    
    for (int i = 0; i < sentences.length; i++) {
      double score = 0.0;
      
      // Length score (prefer medium length)
      final wordCount = sentences[i].split(' ').length;
      if (wordCount >= 10 && wordCount <= 30) {
        score += 0.3;
      }
      
      // Position score (prefer early sentences)
      score += (1 - (i / sentences.length)) * 0.2;
      
      // Keyword score
      final keywords = ['important', 'significant', 'research', 'study', 'found'];
      for (final keyword in keywords) {
        if (sentences[i].toLowerCase().contains(keyword)) {
          score += 0.1;
        }
      }
      
      scores[i] = score;
    }
    
    return scores;
  }
  
  /// Extract readability features
  Map<String, double> _extractReadabilityFeatures(String text) {
    final words = text.split(RegExp(r'\s+'));
    final sentences = _splitIntoSentences(text);
    final syllables = _countSyllables(text);
    
    return {
      'word_count': words.length.toDouble(),
      'sentence_count': sentences.length.toDouble(),
      'syllable_count': syllables.toDouble(),
      'avg_words_per_sentence': words.length / sentences.length,
      'avg_syllables_per_word': syllables / words.length,
      'complex_word_ratio': _countComplexWords(words) / words.length,
    };
  }
  
  /// Extract quality features
  Map<String, double> _extractQualityFeatures(String text) {
    final words = text.split(RegExp(r'\s+'));
    final sentences = _splitIntoSentences(text);
    
    return {
      'length': text.length.toDouble(),
      'unique_word_ratio': words.toSet().length / words.length,
      'avg_sentence_length': words.length / sentences.length,
      'punctuation_ratio': _countPunctuation(text) / text.length,
      'capitalization_ratio': _countCapitals(text) / text.length,
      'number_ratio': _countNumbers(text) / words.length,
    };
  }
  
  // Utility methods
  int _countSyllables(String text) {
    // Simplified syllable counting
    return text.split(RegExp(r'[aeiouAEIOU]+')).length - 1;
  }
  
  double _countComplexWords(List<String> words) {
    return words.where((w) => w.length > 6).length.toDouble();
  }
  
  double _countPunctuation(String text) {
    return text.split(RegExp(r'[.,!?;:]')).length - 1.0;
  }
  
  double _countCapitals(String text) {
    return text.split('').where((c) => c.toUpperCase() == c && c.toLowerCase() != c).length.toDouble();
  }
  
  double _countNumbers(String text) {
    return RegExp(r'\d+').allMatches(text).length.toDouble();
  }
  
  String _getReadabilityLevel(double score) {
    if (score >= 90) return 'Very Easy';
    if (score >= 80) return 'Easy';
    if (score >= 70) return 'Fairly Easy';
    if (score >= 60) return 'Standard';
    if (score >= 50) return 'Fairly Difficult';
    if (score >= 30) return 'Difficult';
    return 'Very Difficult';
  }
  
  // Fallback methods for when models aren't available
  BiasAnalysis _fallbackBiasDetection(String text) {
    final biasKeywords = {
      'political': ['left', 'right', 'liberal', 'conservative', 'democrat', 'republican'],
      'gender': ['men', 'women', 'male', 'female', 'gender'],
      'racial': ['race', 'ethnic', 'minority', 'diversity'],
    };
    
    final detectedBiases = <String, double>{};
    final lowerText = text.toLowerCase();
    
    biasKeywords.forEach((type, keywords) {
      int count = 0;
      for (final keyword in keywords) {
        count += RegExp(keyword).allMatches(lowerText).length;
      }
      
      if (count > 0) {
        detectedBiases[type] = (count / text.split(' ').length).clamp(0.0, 1.0);
      }
    });
    
    return BiasAnalysis(
      overallBias: detectedBiases.values.fold(0.0, (a, b) => a + b) / 3,
      detectedBiases: detectedBiases,
      suggestions: _generateBiasSuggestions(detectedBiases),
    );
  }
  
  TopicClassification _fallbackTopicClassification(String text) {
    final topicKeywords = {
      'technology': ['tech', 'software', 'ai', 'computer', 'digital', 'internet'],
      'business': ['business', 'company', 'market', 'economy', 'finance', 'stock'],
      'politics': ['politics', 'government', 'election', 'policy', 'law', 'congress'],
      'health': ['health', 'medical', 'doctor', 'disease', 'treatment', 'hospital'],
      'science': ['science', 'research', 'study', 'experiment', 'discovery'],
    };
    
    final topics = <String, double>{};
    final lowerText = text.toLowerCase();
    final wordCount = text.split(' ').length;
    
    topicKeywords.forEach((topic, keywords) {
      int count = 0;
      for (final keyword in keywords) {
        count += RegExp(keyword).allMatches(lowerText).length;
      }
      
      if (count > 0) {
        topics[topic] = (count / wordCount * 10).clamp(0.0, 1.0);
      }
    });
    
    final sortedTopics = topics.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return TopicClassification(
      primaryTopic: sortedTopics.isNotEmpty ? sortedTopics.first.key : 'general',
      allTopics: topics,
      confidence: sortedTopics.isNotEmpty ? sortedTopics.first.value : 0.0,
    );
  }
  
  String _fallbackSummarization(String text, int maxLength) {
    final sentences = _splitIntoSentences(text);
    if (sentences.isEmpty) return text;
    
    // Simple extractive summarization
    final numSentences = (maxLength ~/ 50).clamp(1, sentences.length);
    return sentences.take(numSentences).join(' ');
  }
  
  ReadabilityAnalysis _calculateTraditionalReadability(String text, Map<String, double> features) {
    // Flesch Reading Ease
    final words = text.split(RegExp(r'\s+'));
    final sentences = _splitIntoSentences(text);
    final syllables = _countSyllables(text);
    
    final avgWordsPerSentence = words.length / sentences.length;
    final avgSyllablesPerWord = syllables / words.length;
    
    final fleschScore = 206.835 - 
        1.015 * avgWordsPerSentence - 
        84.6 * avgSyllablesPerWord;
    
    return ReadabilityAnalysis(
      score: fleschScore.clamp(0, 100),
      level: _getReadabilityLevel(fleschScore),
      metrics: {
        'flesch_score': fleschScore,
        'avg_words_per_sentence': avgWordsPerSentence,
        'avg_syllables_per_word': avgSyllablesPerWord,
        ...features,
      },
    );
  }
  
  QualityAssessment _ruleBasedQualityAssessment(String text, Map<String, double> features) {
    final factors = <String, bool>{};
    int score = 50; // Base score
    
    // Length check
    if (text.length > 500) {
      score += 10;
      factors['adequate_length'] = true;
    }
    
    // Sentence variety
    final sentences = _splitIntoSentences(text);
    final sentenceLengths = sentences.map((s) => s.split(' ').length).toList();
    final avgLength = sentenceLengths.reduce((a, b) => a + b) / sentenceLengths.length;
    final variance = sentenceLengths.map((l) => (l - avgLength).abs()).reduce((a, b) => a + b) / sentenceLengths.length;
    
    if (variance > 5) {
      score += 10;
      factors['sentence_variety'] = true;
    }
    
    // Sources/citations
    if (text.contains(RegExp(r'\[\d+\]')) || text.contains(RegExp(r'\(\d{4}\)'))) {
      score += 15;
      factors['has_citations'] = true;
    }
    
    // Structure
    if (text.contains('\n\n') || text.contains('\n#')) {
      score += 10;
      factors['good_structure'] = true;
    }
    
    return QualityAssessment(
      score: score.clamp(0, 100),
      isHighQuality: score > 70,
      factors: factors,
    );
  }
  
  List<String> _generateBiasSuggestions(Map<String, double> detectedBiases) {
    final suggestions = <String>[];
    
    detectedBiases.forEach((type, score) {
      if (score > 0.5) {
        suggestions.add('High $type bias detected. Consider including diverse perspectives.');
      } else if (score > 0.3) {
        suggestions.add('Moderate $type bias detected. Review for balanced coverage.');
      }
    });
    
    return suggestions;
  }
  
  Map<String, bool> _interpretQualityFactors(Map<String, double> features, double probability) {
    return {
      'good_length': features['length']! > 500,
      'diverse_vocabulary': features['unique_word_ratio']! > 0.6,
      'proper_structure': features['punctuation_ratio']! > 0.05,
      'quality_score': probability > 0.7,
    };
  }
  
  // Perspective generation methods
  List<Perspective> _generatePoliticalPerspectives(String text, SentimentAnalysis sentiment) {
    return [
      Perspective(
        viewpoint: 'Progressive',
        summary: 'From a progressive standpoint, this highlights the need for systemic change and greater equality.',
        confidence: 0.75,
      ),
      Perspective(
        viewpoint: 'Conservative',
        summary: 'A conservative view emphasizes personal responsibility and traditional values in addressing this issue.',
        confidence: 0.75,
      ),
      Perspective(
        viewpoint: 'Centrist',
        summary: 'A moderate approach suggests finding common ground and pragmatic solutions.',
        confidence: 0.70,
      ),
    ];
  }
  
  List<Perspective> _generateTechPerspectives(String text) {
    return [
      Perspective(
        viewpoint: 'Innovation Optimist',
        summary: 'This represents exciting technological progress that will benefit society.',
        confidence: 0.80,
      ),
      Perspective(
        viewpoint: 'Privacy Advocate',
        summary: 'Important privacy and security considerations must be addressed.',
        confidence: 0.75,
      ),
    ];
  }
  
  List<Perspective> _generateBusinessPerspectives(String text) {
    return [
      Perspective(
        viewpoint: 'Investor',
        summary: 'From an investment perspective, this presents both opportunities and risks.',
        confidence: 0.70,
      ),
      Perspective(
        viewpoint: 'Consumer',
        summary: 'Consumers should consider the value proposition and long-term implications.',
        confidence: 0.75,
      ),
    ];
  }
  
  List<Perspective> _generateGeneralPerspectives(String text, SentimentAnalysis sentiment) {
    return [
      Perspective(
        viewpoint: 'Optimistic',
        summary: 'This development shows promise for positive change and improvement.',
        confidence: 0.65,
      ),
      Perspective(
        viewpoint: 'Skeptical',
        summary: 'A critical examination reveals potential challenges and limitations.',
        confidence: 0.65,
      ),
    ];
  }
  
  List<Perspective> _generateFallbackPerspectives(String text) {
    return [
      Perspective(
        viewpoint: 'General Analysis',
        summary: 'This topic presents multiple facets worth considering.',
        confidence: 0.50,
      ),
    ];
  }
}

// Data classes
class SentimentAnalysis {
  final String sentiment;
  final double confidence;
  final Map<String, double> scores;
  
  SentimentAnalysis({
    required this.sentiment,
    required this.confidence,
    required this.scores,
  });
}

class BiasAnalysis {
  final double overallBias;
  final Map<String, double> detectedBiases;
  final List<String> suggestions;
  
  BiasAnalysis({
    required this.overallBias,
    required this.detectedBiases,
    required this.suggestions,
  });
}

class TopicClassification {
  final String primaryTopic;
  final Map<String, double> allTopics;
  final double confidence;
  
  TopicClassification({
    required this.primaryTopic,
    required this.allTopics,
    required this.confidence,
  });
}

class ReadabilityAnalysis {
  final double score;
  final String level;
  final Map<String, double> metrics;
  
  ReadabilityAnalysis({
    required this.score,
    required this.level,
    required this.metrics,
  });
}

class QualityAssessment {
  final int score;
  final bool isHighQuality;
  final Map<String, bool> factors;
  
  QualityAssessment({
    required this.score,
    required this.isHighQuality,
    required this.factors,
  });
}

class Perspective {
  final String viewpoint;
  final String summary;
  final double confidence;
  
  Perspective({
    required this.viewpoint,
    required this.summary,
    required this.confidence,
  });
}

class LocalAIException implements Exception {
  final String message;
  LocalAIException(this.message);
  
  @override
  String toString() => 'LocalAIException: $message';
}