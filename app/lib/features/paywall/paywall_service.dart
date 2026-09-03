import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';

class PaywallBypassService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Attempt to bypass paywall ethically
  Future<PaywallBypassResult> attemptBypass(String url) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/paywall/bypass'),
      headers: headers,
      body: json.encode({'url': url}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return PaywallBypassResult.fromJson(data);
    } else {
      throw Exception('Failed to bypass paywall');
    }
  }

  // Get bypass suggestions
  Future<List<String>> getBypassSuggestions(String url) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/paywall/suggestions?url=${Uri.encodeComponent(url)}'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<String>.from(data['suggestions']);
    } else {
      throw Exception('Failed to get suggestions');
    }
  }
}

class PaywallBypassResult {
  final bool success;
  final String? method;
  final String? content;
  final String? title;
  final String? author;
  final String? excerpt;
  final String? imageUrl;
  final String? error;

  PaywallBypassResult({
    required this.success,
    this.method,
    this.content,
    this.title,
    this.author,
    this.excerpt,
    this.imageUrl,
    this.error,
  });

  factory PaywallBypassResult.fromJson(Map<String, dynamic> json) {
    return PaywallBypassResult(
      success: json['success'],
      method: json['method'],
      content: json['content'],
      title: json['title'],
      author: json['author'],
      excerpt: json['excerpt'],
      imageUrl: json['imageUrl'],
      error: json['error'],
    );
  }
}