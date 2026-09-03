class ApiConfig {
  // Base URLs
  static const String productionUrl = 'https://api.rss-reader.app/v1';
  static const String stagingUrl = 'https://staging-api.rss-reader.app/v1';
  static const String developmentUrl = 'http://localhost:3000/v1';
  
  // Current environment
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');
  static const bool isStaging = bool.fromEnvironment('STAGING', defaultValue: false);
  
  // Get base URL based on environment
  static String get baseUrl {
    if (isProduction && !isStaging) {
      return productionUrl;
    } else if (isStaging) {
      return stagingUrl;
    } else {
      return developmentUrl;
    }
  }
  
  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  // WebSocket URLs
  static String get wsUrl {
    final base = baseUrl.replaceFirst('http', 'ws');
    return '$base/ws';
  }
  
  // API Keys (should be stored securely in production)
  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: 'development-key',
  );
  
  // Feature flags
  static const bool enableCache = true;
  static const bool enableLogging = !isProduction;
  static const bool enableRetry = true;
  
  // Cache configuration
  static const Duration cacheMaxAge = Duration(minutes: 5);
  static const int cacheMaxSize = 100; // MB
  
  // Retry configuration
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 1);
  
  // Rate limiting
  static const int requestsPerMinute = 60;
  static const int burstSize = 10;
}