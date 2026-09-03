import 'dart:io';
import 'package:yaml/yaml.dart';

class ServerConfig {
  final ApiServerConfig apiServer;
  final WebServerConfig webServer;
  final DatabaseConfig database;
  final AuthConfig auth;
  final EmailConfig email;
  final AIConfig ai;
  final RateLimitConfig rateLimit;
  final CacheConfig cache;
  final StorageConfig storage;

  ServerConfig({
    required this.apiServer,
    required this.webServer,
    required this.database,
    required this.auth,
    required this.email,
    required this.ai,
    required this.rateLimit,
    required this.cache,
    required this.storage,
  });

  static ServerConfig load() {
    // Load configuration from environment or config file
    final env = Platform.environment;
    final configFile = File('config/server_config.yaml');
    
    Map<String, dynamic> config = {};
    
    // Load from file if exists
    if (configFile.existsSync()) {
      final yamlString = configFile.readAsStringSync();
      config = loadYaml(yamlString);
    }
    
    // Override with environment variables
    return ServerConfig(
      apiServer: ApiServerConfig(
        port: int.parse(env['API_PORT'] ?? config['api_server']?['port']?.toString() ?? '8080'),
        host: env['API_HOST'] ?? config['api_server']?['host'] ?? 'localhost',
        cors: CorsConfig(
          allowedOrigins: (env['CORS_ORIGINS'] ?? config['api_server']?['cors']?['allowed_origins'] ?? '*').split(','),
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
          allowedHeaders: ['Content-Type', 'Authorization'],
        ),
      ),
      webServer: WebServerConfig(
        port: int.parse(env['WEB_PORT'] ?? config['web_server']?['port']?.toString() ?? '8081'),
        host: env['WEB_HOST'] ?? config['web_server']?['host'] ?? 'localhost',
      ),
      database: DatabaseConfig(
        host: env['DB_HOST'] ?? config['database']?['host'] ?? 'localhost',
        port: int.parse(env['DB_PORT'] ?? config['database']?['port']?.toString() ?? '5432'),
        name: env['DB_NAME'] ?? config['database']?['name'] ?? 'omi_rss',
        username: env['DB_USER'] ?? config['database']?['username'] ?? 'postgres',
        password: env['DB_PASSWORD'] ?? config['database']?['password'] ?? 'postgres',
        ssl: (env['DB_SSL'] ?? config['database']?['ssl']?.toString() ?? 'false') == 'true',
        maxConnections: int.parse(env['DB_MAX_CONNECTIONS'] ?? config['database']?['max_connections']?.toString() ?? '10'),
      ),
      auth: AuthConfig(
        jwtSecret: env['JWT_SECRET'] ?? config['auth']?['jwt_secret'] ?? 'your-secret-key-change-in-production',
        jwtExpiration: Duration(hours: int.parse(env['JWT_EXPIRATION_HOURS'] ?? config['auth']?['jwt_expiration_hours']?.toString() ?? '24')),
        refreshTokenExpiration: Duration(days: int.parse(env['REFRESH_TOKEN_DAYS'] ?? config['auth']?['refresh_token_days']?.toString() ?? '30')),
        sendValidationEmail: (env['SEND_VALIDATION_EMAIL'] ?? config['auth']?['send_validation_email']?.toString() ?? 'false') == 'true',
        validationCodeLength: int.parse(env['VALIDATION_CODE_LENGTH'] ?? config['auth']?['validation_code_length']?.toString() ?? '6'),
        bcryptRounds: int.parse(env['BCRYPT_ROUNDS'] ?? config['auth']?['bcrypt_rounds']?.toString() ?? '10'),
      ),
      email: EmailConfig(
        provider: env['EMAIL_PROVIDER'] ?? config['email']?['provider'] ?? 'smtp',
        smtp: SmtpConfig(
          host: env['SMTP_HOST'] ?? config['email']?['smtp']?['host'] ?? 'smtp.gmail.com',
          port: int.parse(env['SMTP_PORT'] ?? config['email']?['smtp']?['port']?.toString() ?? '587'),
          username: env['SMTP_USER'] ?? config['email']?['smtp']?['username'] ?? '',
          password: env['SMTP_PASSWORD'] ?? config['email']?['smtp']?['password'] ?? '',
          secure: (env['SMTP_SECURE'] ?? config['email']?['smtp']?['secure']?.toString() ?? 'true') == 'true',
        ),
        from: env['EMAIL_FROM'] ?? config['email']?['from'] ?? 'noreply@omi-rss.com',
        templates: EmailTemplates(
          welcomeSubject: 'Welcome to Omi RSS Reader',
          passwordResetSubject: 'Reset your password',
          validationSubject: 'Verify your email',
        ),
      ),
      ai: AIConfig(
        providers: {
          'openai': AIProviderConfig(
            apiKey: env['OPENAI_API_KEY'] ?? config['ai']?['providers']?['openai']?['api_key'] ?? '',
            model: env['OPENAI_MODEL'] ?? config['ai']?['providers']?['openai']?['model'] ?? 'gpt-3.5-turbo',
            maxTokens: int.parse(env['OPENAI_MAX_TOKENS'] ?? config['ai']?['providers']?['openai']?['max_tokens']?.toString() ?? '1000'),
          ),
          'anthropic': AIProviderConfig(
            apiKey: env['ANTHROPIC_API_KEY'] ?? config['ai']?['providers']?['anthropic']?['api_key'] ?? '',
            model: env['ANTHROPIC_MODEL'] ?? config['ai']?['providers']?['anthropic']?['model'] ?? 'claude-3-haiku-20240307',
            maxTokens: int.parse(env['ANTHROPIC_MAX_TOKENS'] ?? config['ai']?['providers']?['anthropic']?['max_tokens']?.toString() ?? '1000'),
          ),
        },
        defaultProvider: env['AI_DEFAULT_PROVIDER'] ?? config['ai']?['default_provider'] ?? 'openai',
      ),
      rateLimit: RateLimitConfig(
        windowMs: int.parse(env['RATE_LIMIT_WINDOW_MS'] ?? config['rate_limit']?['window_ms']?.toString() ?? '60000'),
        maxRequests: int.parse(env['RATE_LIMIT_MAX_REQUESTS'] ?? config['rate_limit']?['max_requests']?.toString() ?? '100'),
        skipSuccessfulRequests: (env['RATE_LIMIT_SKIP_SUCCESSFUL'] ?? config['rate_limit']?['skip_successful']?.toString() ?? 'false') == 'true',
        keyGenerator: env['RATE_LIMIT_KEY_GENERATOR'] ?? config['rate_limit']?['key_generator'] ?? 'ip',
      ),
      cache: CacheConfig(
        provider: env['CACHE_PROVIDER'] ?? config['cache']?['provider'] ?? 'memory',
        redis: RedisConfig(
          host: env['REDIS_HOST'] ?? config['cache']?['redis']?['host'] ?? 'localhost',
          port: int.parse(env['REDIS_PORT'] ?? config['cache']?['redis']?['port']?.toString() ?? '6379'),
          password: env['REDIS_PASSWORD'] ?? config['cache']?['redis']?['password'],
          db: int.parse(env['REDIS_DB'] ?? config['cache']?['redis']?['db']?.toString() ?? '0'),
        ),
        ttl: Duration(minutes: int.parse(env['CACHE_TTL_MINUTES'] ?? config['cache']?['ttl_minutes']?.toString() ?? '60')),
      ),
      storage: StorageConfig(
        provider: env['STORAGE_PROVIDER'] ?? config['storage']?['provider'] ?? 'local',
        local: LocalStorageConfig(
          basePath: env['STORAGE_LOCAL_PATH'] ?? config['storage']?['local']?['base_path'] ?? './storage',
        ),
        s3: S3Config(
          bucket: env['S3_BUCKET'] ?? config['storage']?['s3']?['bucket'] ?? '',
          region: env['S3_REGION'] ?? config['storage']?['s3']?['region'] ?? 'us-east-1',
          accessKey: env['S3_ACCESS_KEY'] ?? config['storage']?['s3']?['access_key'] ?? '',
          secretKey: env['S3_SECRET_KEY'] ?? config['storage']?['s3']?['secret_key'] ?? '',
        ),
      ),
    );
  }
}

class ApiServerConfig {
  final int port;
  final String host;
  final CorsConfig cors;

  ApiServerConfig({
    required this.port,
    required this.host,
    required this.cors,
  });
}

class WebServerConfig {
  final int port;
  final String host;

  WebServerConfig({
    required this.port,
    required this.host,
  });
}

class CorsConfig {
  final List<String> allowedOrigins;
  final List<String> allowedMethods;
  final List<String> allowedHeaders;

  CorsConfig({
    required this.allowedOrigins,
    required this.allowedMethods,
    required this.allowedHeaders,
  });
}

class DatabaseConfig {
  final String host;
  final int port;
  final String name;
  final String username;
  final String password;
  final bool ssl;
  final int maxConnections;

  DatabaseConfig({
    required this.host,
    required this.port,
    required this.name,
    required this.username,
    required this.password,
    required this.ssl,
    required this.maxConnections,
  });
}

class AuthConfig {
  final String jwtSecret;
  final Duration jwtExpiration;
  final Duration refreshTokenExpiration;
  final bool sendValidationEmail;
  final int validationCodeLength;
  final int bcryptRounds;

  AuthConfig({
    required this.jwtSecret,
    required this.jwtExpiration,
    required this.refreshTokenExpiration,
    required this.sendValidationEmail,
    required this.validationCodeLength,
    required this.bcryptRounds,
  });
}

class EmailConfig {
  final String provider;
  final SmtpConfig smtp;
  final String from;
  final EmailTemplates templates;

  EmailConfig({
    required this.provider,
    required this.smtp,
    required this.from,
    required this.templates,
  });
}

class SmtpConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool secure;

  SmtpConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.secure,
  });
}

class EmailTemplates {
  final String welcomeSubject;
  final String passwordResetSubject;
  final String validationSubject;

  EmailTemplates({
    required this.welcomeSubject,
    required this.passwordResetSubject,
    required this.validationSubject,
  });
}

class AIConfig {
  final Map<String, AIProviderConfig> providers;
  final String defaultProvider;

  AIConfig({
    required this.providers,
    required this.defaultProvider,
  });
}

class AIProviderConfig {
  final String apiKey;
  final String model;
  final int maxTokens;

  AIProviderConfig({
    required this.apiKey,
    required this.model,
    required this.maxTokens,
  });
}

class RateLimitConfig {
  final int windowMs;
  final int maxRequests;
  final bool skipSuccessfulRequests;
  final String keyGenerator;

  RateLimitConfig({
    required this.windowMs,
    required this.maxRequests,
    required this.skipSuccessfulRequests,
    required this.keyGenerator,
  });
}

class CacheConfig {
  final String provider;
  final RedisConfig redis;
  final Duration ttl;

  CacheConfig({
    required this.provider,
    required this.redis,
    required this.ttl,
  });
}

class RedisConfig {
  final String host;
  final int port;
  final String? password;
  final int db;

  RedisConfig({
    required this.host,
    required this.port,
    this.password,
    required this.db,
  });
}

class StorageConfig {
  final String provider;
  final LocalStorageConfig local;
  final S3Config s3;

  StorageConfig({
    required this.provider,
    required this.local,
    required this.s3,
  });
}

class LocalStorageConfig {
  final String basePath;

  LocalStorageConfig({
    required this.basePath,
  });
}

class S3Config {
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;

  S3Config({
    required this.bucket,
    required this.region,
    required this.accessKey,
    required this.secretKey,
  });
}