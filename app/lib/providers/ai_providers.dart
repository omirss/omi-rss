import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/ai_service.dart';
import '../core/database/database.dart';
import 'database_provider.dart';

/// Provider for AI service
final aiServiceProvider = Provider<AIService>((ref) {
  final database = ref.watch(databaseProvider);
  
  return AIService(
    database: database,
  );
});

/// Provider for checking if AI is configured
final aiConfiguredProvider = Provider<bool>((ref) {
  // Check if at least one AI provider has API key
  const openAiKey = String.fromEnvironment('OPENAI_API_KEY');
  const anthropicKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  const googleKey = String.fromEnvironment('GOOGLE_AI_API_KEY');
  const cohereKey = String.fromEnvironment('COHERE_API_KEY');
  
  return openAiKey.isNotEmpty ||
         anthropicKey.isNotEmpty ||
         googleKey.isNotEmpty ||
         cohereKey.isNotEmpty;
});

/// Provider for available AI providers
final availableAIProvidersProvider = Provider<List<String>>((ref) {
  final providers = <String>[];
  
  if (const String.fromEnvironment('OPENAI_API_KEY').isNotEmpty) {
    providers.add('OpenAI');
  }
  if (const String.fromEnvironment('ANTHROPIC_API_KEY').isNotEmpty) {
    providers.add('Anthropic');
  }
  if (const String.fromEnvironment('GOOGLE_AI_API_KEY').isNotEmpty) {
    providers.add('Google');
  }
  if (const String.fromEnvironment('COHERE_API_KEY').isNotEmpty) {
    providers.add('Cohere');
  }
  
  // Local models are always available
  providers.add('Local');
  
  return providers;
});