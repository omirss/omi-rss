import 'dart:convert';
import 'package:dio/dio.dart';
import '../services/ai_service.dart';

/// Google AI Provider implementation
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
    if (apiKey.isEmpty) throw Exception('Google AI API key not configured');
    
    final response = await dio.post(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
        },
      ),
      queryParameters: {
        'key': apiKey,
      },
      data: {
        'contents': [
          {
            'parts': [
              {'text': prompt + '\n\nProvide your response in JSON format.'},
            ],
          },
        ],
        'generationConfig': {
          'temperature': _getTemperature(taskType),
          'topK': 40,
          'topP': 0.95,
          'candidateCount': 1,
          'maxOutputTokens': 2048,
        },
        'safetySettings': [
          {
            'category': 'HARM_CATEGORY_HARASSMENT',
            'threshold': 'BLOCK_NONE',
          },
          {
            'category': 'HARM_CATEGORY_HATE_SPEECH',
            'threshold': 'BLOCK_NONE',
          },
          {
            'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
            'threshold': 'BLOCK_NONE',
          },
          {
            'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
            'threshold': 'BLOCK_NONE',
          },
        ],
      },
    );
    
    final content = response.data['candidates'][0]['content']['parts'][0]['text'];
    
    // Extract JSON from response
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (jsonMatch != null) {
      return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
    }
    
    // Fallback if no JSON found
    return {'response': content};
  }
  
  double _getTemperature(AITaskType taskType) {
    switch (taskType) {
      case AITaskType.summarization:
      case AITaskType.extraction:
      case AITaskType.factChecking:
        return 0.3;
      case AITaskType.generation:
        return 0.7;
      default:
        return 0.5;
    }
  }
}

/// Cohere Provider implementation
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
    if (apiKey.isEmpty) throw Exception('Cohere API key not configured');
    
    final response = await dio.post(
      'https://api.cohere.ai/v1/generate',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Cohere-Version': '2022-12-06',
        },
      ),
      data: {
        'model': model,
        'prompt': prompt + '\n\nProvide your response in JSON format only.',
        'max_tokens': 2048,
        'temperature': _getTemperature(taskType),
        'k': 0,
        'p': 0.75,
        'frequency_penalty': 0,
        'presence_penalty': 0,
        'stop_sequences': [],
        'return_likelihoods': 'NONE',
      },
    );
    
    final text = response.data['generations'][0]['text'];
    
    // Extract JSON from response
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonMatch != null) {
      return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
    }
    
    // Fallback
    return {'response': text};
  }
  
  double _getTemperature(AITaskType taskType) {
    switch (taskType) {
      case AITaskType.summarization:
      case AITaskType.extraction:
      case AITaskType.factChecking:
        return 0.3;
      case AITaskType.generation:
        return 0.7;
      default:
        return 0.5;
    }
  }
}

/// Ollama Local Provider implementation
class OllamaProvider implements AIProvider {
  final String model;
  final Dio dio;
  final String baseUrl;
  
  OllamaProvider({
    required this.model,
    required this.dio,
    this.baseUrl = 'http://localhost:11434',
  });
  
  @override
  String get name => 'Ollama';
  
  @override
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType) async {
    try {
      final response = await dio.post(
        '$baseUrl/api/generate',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'prompt': prompt + '\n\nProvide your response in JSON format only.',
          'stream': false,
          'options': {
            'temperature': _getTemperature(taskType),
            'top_k': 40,
            'top_p': 0.9,
            'num_predict': 2048,
          },
        },
      );
      
      final text = response.data['response'];
      
      // Extract JSON from response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      }
      
      // Fallback
      return {'response': text};
    } catch (e) {
      throw Exception('Ollama not running or model not available: $e');
    }
  }
  
  double _getTemperature(AITaskType taskType) {
    switch (taskType) {
      case AITaskType.summarization:
      case AITaskType.extraction:
      case AITaskType.factChecking:
        return 0.3;
      case AITaskType.generation:
        return 0.7;
      default:
        return 0.5;
    }
  }
}

/// Hugging Face Provider implementation
class HuggingFaceProvider implements AIProvider {
  final String apiKey;
  final String model;
  final Dio dio;
  
  HuggingFaceProvider({
    required this.apiKey,
    required this.model,
    required this.dio,
  });
  
  @override
  String get name => 'HuggingFace';
  
  @override
  Future<Map<String, dynamic>> complete(String prompt, AITaskType taskType) async {
    if (apiKey.isEmpty) throw Exception('Hugging Face API key not configured');
    
    final response = await dio.post(
      'https://api-inference.huggingface.co/models/$model',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'inputs': prompt + '\n\nProvide your response in JSON format only.',
        'parameters': {
          'max_new_tokens': 2048,
          'temperature': _getTemperature(taskType),
          'top_p': 0.95,
          'do_sample': true,
          'return_full_text': false,
        },
      },
    );
    
    final text = response.data[0]['generated_text'];
    
    // Extract JSON from response
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonMatch != null) {
      return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
    }
    
    // Fallback
    return {'response': text};
  }
  
  double _getTemperature(AITaskType taskType) {
    switch (taskType) {
      case AITaskType.summarization:
      case AITaskType.extraction:
      case AITaskType.factChecking:
        return 0.3;
      case AITaskType.generation:
        return 0.7;
      default:
        return 0.5;
    }
  }
}