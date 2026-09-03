import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/paywall/paywall_service.dart';

// Paywall service provider
final paywallServiceProvider = Provider((ref) => PaywallBypassService());

// Bypass attempt provider
final paywallBypassProvider = FutureProvider.family<PaywallBypassResult, String>((ref, url) async {
  final service = ref.watch(paywallServiceProvider);
  return service.attemptBypass(url);
});

// Suggestions provider
final paywallSuggestionsProvider = FutureProvider.family<List<String>, String>((ref, url) async {
  final service = ref.watch(paywallServiceProvider);
  return service.getBypassSuggestions(url);
});