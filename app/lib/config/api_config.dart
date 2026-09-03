/// API Configuration
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8080/api',
  );
  
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  // WebSocket configuration
  static String get wsUrl {
    final url = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    return url.replaceFirst('/api', '/ws');
  }
}