import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';

import 'src/config/server_config.dart';
import 'src/endpoints/feed_endpoint.dart';
import 'src/endpoints/article_endpoint.dart';
import 'src/endpoints/folder_endpoint.dart';
import 'src/endpoints/user_endpoint.dart';
import 'src/endpoints/sync_endpoint.dart';
import 'src/endpoints/collaboration_endpoint.dart';
import 'src/endpoints/ai_endpoint.dart';
import 'src/endpoints/market_endpoint.dart';
import 'src/endpoints/generation_endpoint.dart';
import 'src/endpoints/analytics_endpoint.dart';
import 'src/services/feed_service.dart';
import 'src/services/ai_service.dart';
import 'src/services/market_service.dart';
import 'src/services/notification_service.dart';
import 'src/services/background_job_service.dart';
import 'src/websocket/sync_websocket.dart';
import 'src/websocket/collaboration_websocket.dart';
import 'src/websocket/market_websocket.dart';
import 'src/websocket/websocket_handler.dart';
import 'src/middleware/auth_middleware.dart';
import 'src/middleware/rate_limit_middleware.dart';
import 'src/middleware/logging_middleware.dart';

// This is the starting point of your Serverpod server.
void run(List<String> args) async {
  // Initialize server configuration
  final config = ServerConfig.load();
  
  // Initialize Serverpod
  final pod = Serverpod(
    args,
    Protocol(),
    Endpoints(),
    authenticationHandler: AuthenticationHandler(),
  );
  
  // Set up authentication module
  await AuthConfig.set(AuthConfig(
    sendValidationEmail: config.auth.sendValidationEmail,
    validationCodeLength: config.auth.validationCodeLength,
    passwordResetCodeLength: 6,
    extraSaltRounds: 12,
    allowUnsecureRandom: false,
    onUserCreated: (session, userInfo) async {
      // Initialize user data when account is created
      await UserEndpoint().initializeUser(session, userInfo.id!);
    },
  ));
  
  // Register services
  pod.registerSingleton<FeedService>(FeedService(pod));
  pod.registerSingleton<AIService>(AIService(config.ai));
  pod.registerSingleton<MarketService>(MarketService());
  pod.registerSingleton<NotificationService>(NotificationService(config.email));
  pod.registerSingleton<BackgroundJobService>(BackgroundJobService(pod));
  
  // Register middleware
  pod.addMiddleware(LoggingMiddleware());
  pod.addMiddleware(RateLimitMiddleware(config.rateLimit));
  pod.addMiddleware(AuthMiddleware());
  
  // Register WebSocket handlers
  pod.webSocketHandler.register(SyncWebSocketHandler());
  pod.webSocketHandler.register(CollaborationWebSocketHandler());
  pod.webSocketHandler.register(MarketWebSocketHandler());
  
  // Start background services
  final backgroundService = pod.getSingleton<BackgroundJobService>();
  await backgroundService.start();
  
  // Start the server
  await pod.start();
  
  print('🚀 Omi RSS Server started on port ${config.apiServer.port}');
  print('📡 WebSocket server on port ${config.webServer.port}');
  print('🔐 Authentication enabled: ${config.auth.sendValidationEmail}');
  print('🤖 AI providers: ${config.ai.providers.keys.join(', ')}');
}

// Main entry point
void main(List<String> args) => run(args);