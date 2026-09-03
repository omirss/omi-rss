import 'dart:io';
import 'package:serverpod/serverpod.dart';
import 'package:intl/intl.dart';

class LoggingMiddleware extends Middleware {
  final LogLevel minLevel;
  final bool logRequestBody;
  final bool logResponseBody;
  final int maxBodyLength;
  final Set<String> excludePaths;
  final Set<String> redactHeaders;
  
  LoggingMiddleware({
    this.minLevel = LogLevel.info,
    this.logRequestBody = false,
    this.logResponseBody = false,
    this.maxBodyLength = 1000,
    Set<String>? excludePaths,
    Set<String>? redactHeaders,
  }) : excludePaths = excludePaths ?? {'/health', '/metrics'},
       redactHeaders = redactHeaders ?? {'authorization', 'cookie', 'x-api-key'};

  @override
  Future<bool> handle(Session session, HttpRequest request) async {
    // Skip logging for excluded paths
    if (excludePaths.contains(request.uri.path)) {
      return true;
    }
    
    final startTime = DateTime.now();
    final requestId = _generateRequestId();
    
    // Store request ID for correlation
    request.headers.add('X-Request-Id', requestId);
    
    // Log request
    await _logRequest(session, request, requestId);
    
    // Add response logging hook
    request.response.done.then((_) {
      final duration = DateTime.now().difference(startTime);
      _logResponse(session, request, requestId, duration);
    }).catchError((error) {
      _logError(session, request, requestId, error);
    });
    
    return true;
  }
  
  String _generateRequestId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${_randomString(8)}';
  }
  
  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (index) => 
      chars[(DateTime.now().microsecondsSinceEpoch + index) % chars.length]
    ).join();
  }
  
  Future<void> _logRequest(Session session, HttpRequest request, String requestId) async {
    final logEntry = RequestLogEntry(
      requestId: requestId,
      timestamp: DateTime.now(),
      method: request.method,
      path: request.uri.path,
      query: request.uri.queryParameters,
      headers: _sanitizeHeaders(request.headers),
      remoteAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
      userAgent: request.headers.value('user-agent') ?? 'unknown',
    );
    
    // Log request body if enabled
    if (logRequestBody && request.method != 'GET') {
      try {
        final body = await _readBody(request);
        if (body != null) {
          logEntry.body = _truncateBody(body);
        }
      } catch (e) {
        session.log('Failed to read request body: $e', level: LogLevel.warning);
      }
    }
    
    // Log based on level
    if (minLevel == LogLevel.debug) {
      session.log(logEntry.toDetailedString(), level: LogLevel.debug);
    } else {
      session.log(logEntry.toString(), level: LogLevel.info);
    }
  }
  
  void _logResponse(Session session, HttpRequest request, String requestId, Duration duration) {
    final logEntry = ResponseLogEntry(
      requestId: requestId,
      timestamp: DateTime.now(),
      statusCode: request.response.statusCode,
      duration: duration,
      contentLength: request.response.contentLength,
    );
    
    // Determine log level based on status code
    final level = _getLogLevelForStatus(request.response.statusCode);
    
    if (level == LogLevel.error || minLevel == LogLevel.debug) {
      session.log(logEntry.toDetailedString(), level: level);
    } else {
      session.log(logEntry.toString(), level: level);
    }
  }
  
  void _logError(Session session, HttpRequest request, String requestId, dynamic error) {
    final logEntry = ErrorLogEntry(
      requestId: requestId,
      timestamp: DateTime.now(),
      error: error.toString(),
      stackTrace: error is Error ? error.stackTrace?.toString() : null,
      path: request.uri.path,
    );
    
    session.log(logEntry.toString(), level: LogLevel.error);
  }
  
  Map<String, String> _sanitizeHeaders(HttpHeaders headers) {
    final sanitized = <String, String>{};
    
    headers.forEach((name, values) {
      final lowerName = name.toLowerCase();
      if (redactHeaders.contains(lowerName)) {
        sanitized[name] = '[REDACTED]';
      } else {
        sanitized[name] = values.join(', ');
      }
    });
    
    return sanitized;
  }
  
  Future<String?> _readBody(HttpRequest request) async {
    try {
      final contentType = request.headers.contentType;
      if (contentType == null) return null;
      
      // Only read text-based content types
      if (!contentType.mimeType.contains('json') && 
          !contentType.mimeType.contains('text') &&
          !contentType.mimeType.contains('xml')) {
        return '[Binary Content]';
      }
      
      final body = await request.transform(utf8.decoder).join();
      return body.isEmpty ? null : body;
    } catch (e) {
      return '[Error reading body: $e]';
    }
  }
  
  String _truncateBody(String body) {
    if (body.length <= maxBodyLength) {
      return body;
    }
    return '${body.substring(0, maxBodyLength)}... [truncated]';
  }
  
  LogLevel _getLogLevelForStatus(int statusCode) {
    if (statusCode >= 500) return LogLevel.error;
    if (statusCode >= 400) return LogLevel.warning;
    return LogLevel.info;
  }
}

class RequestLogEntry {
  final String requestId;
  final DateTime timestamp;
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;
  final String remoteAddress;
  final String userAgent;
  String? body;
  
  RequestLogEntry({
    required this.requestId,
    required this.timestamp,
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.remoteAddress,
    required this.userAgent,
    this.body,
  });
  
  @override
  String toString() {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
    return '[${formatter.format(timestamp)}] $method $path - $remoteAddress - $requestId';
  }
  
  String toDetailedString() {
    final buffer = StringBuffer();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
    
    buffer.writeln('=== REQUEST ===');
    buffer.writeln('Request ID: $requestId');
    buffer.writeln('Timestamp: ${formatter.format(timestamp)}');
    buffer.writeln('Method: $method');
    buffer.writeln('Path: $path');
    
    if (query.isNotEmpty) {
      buffer.writeln('Query: ${query.entries.map((e) => '${e.key}=${e.value}').join('&')}');
    }
    
    buffer.writeln('Remote Address: $remoteAddress');
    buffer.writeln('User Agent: $userAgent');
    
    buffer.writeln('Headers:');
    headers.forEach((key, value) {
      buffer.writeln('  $key: $value');
    });
    
    if (body != null) {
      buffer.writeln('Body: $body');
    }
    
    return buffer.toString();
  }
}

class ResponseLogEntry {
  final String requestId;
  final DateTime timestamp;
  final int statusCode;
  final Duration duration;
  final int? contentLength;
  
  ResponseLogEntry({
    required this.requestId,
    required this.timestamp,
    required this.statusCode,
    required this.duration,
    this.contentLength,
  });
  
  @override
  String toString() {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
    return '[${formatter.format(timestamp)}] Response $statusCode - ${duration.inMilliseconds}ms - $requestId';
  }
  
  String toDetailedString() {
    final buffer = StringBuffer();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
    
    buffer.writeln('=== RESPONSE ===');
    buffer.writeln('Request ID: $requestId');
    buffer.writeln('Timestamp: ${formatter.format(timestamp)}');
    buffer.writeln('Status Code: $statusCode');
    buffer.writeln('Duration: ${duration.inMilliseconds}ms');
    
    if (contentLength != null) {
      buffer.writeln('Content Length: $contentLength bytes');
    }
    
    return buffer.toString();
  }
}

class ErrorLogEntry {
  final String requestId;
  final DateTime timestamp;
  final String error;
  final String? stackTrace;
  final String path;
  
  ErrorLogEntry({
    required this.requestId,
    required this.timestamp,
    required this.error,
    this.stackTrace,
    required this.path,
  });
  
  @override
  String toString() {
    final buffer = StringBuffer();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
    
    buffer.writeln('=== ERROR ===');
    buffer.writeln('Request ID: $requestId');
    buffer.writeln('Timestamp: ${formatter.format(timestamp)}');
    buffer.writeln('Path: $path');
    buffer.writeln('Error: $error');
    
    if (stackTrace != null) {
      buffer.writeln('Stack Trace:');
      buffer.writeln(stackTrace);
    }
    
    return buffer.toString();
  }
}

// Structured logging formatter for production environments
class StructuredLogger {
  static String formatLog(Map<String, dynamic> data) {
    // For production, output as JSON for log aggregation systems
    return json.encode(data);
  }
  
  static Map<String, dynamic> requestToMap(RequestLogEntry entry) {
    return {
      'type': 'request',
      'request_id': entry.requestId,
      'timestamp': entry.timestamp.toIso8601String(),
      'method': entry.method,
      'path': entry.path,
      'query': entry.query,
      'remote_address': entry.remoteAddress,
      'user_agent': entry.userAgent,
      if (entry.body != null) 'body': entry.body,
    };
  }
  
  static Map<String, dynamic> responseToMap(ResponseLogEntry entry) {
    return {
      'type': 'response',
      'request_id': entry.requestId,
      'timestamp': entry.timestamp.toIso8601String(),
      'status_code': entry.statusCode,
      'duration_ms': entry.duration.inMilliseconds,
      if (entry.contentLength != null) 'content_length': entry.contentLength,
    };
  }
  
  static Map<String, dynamic> errorToMap(ErrorLogEntry entry) {
    return {
      'type': 'error',
      'request_id': entry.requestId,
      'timestamp': entry.timestamp.toIso8601String(),
      'path': entry.path,
      'error': entry.error,
      if (entry.stackTrace != null) 'stack_trace': entry.stackTrace,
    };
  }
}

// Performance monitoring middleware
class PerformanceMonitoringMiddleware extends Middleware {
  final Map<String, EndpointMetrics> _metrics = {};
  final Duration metricsWindow;
  Timer? _cleanupTimer;
  
  PerformanceMonitoringMiddleware({
    this.metricsWindow = const Duration(minutes: 5),
  }) {
    // Start cleanup timer
    _cleanupTimer = Timer.periodic(Duration(minutes: 1), (_) => _cleanup());
  }
  
  @override
  Future<bool> handle(Session session, HttpRequest request) async {
    final startTime = DateTime.now();
    final path = request.uri.path;
    
    // Track request
    final metrics = _metrics.putIfAbsent(path, () => EndpointMetrics(path));
    metrics.recordRequest();
    
    // Hook into response
    request.response.done.then((_) {
      final duration = DateTime.now().difference(startTime);
      metrics.recordResponse(request.response.statusCode, duration);
    }).catchError((error) {
      metrics.recordError();
    });
    
    return true;
  }
  
  Map<String, dynamic> getMetrics() {
    final result = <String, dynamic>{};
    
    _metrics.forEach((path, metrics) {
      result[path] = metrics.toMap();
    });
    
    return result;
  }
  
  void _cleanup() {
    final cutoff = DateTime.now().subtract(metricsWindow);
    
    _metrics.forEach((path, metrics) {
      metrics.cleanup(cutoff);
    });
    
    // Remove endpoints with no recent activity
    _metrics.removeWhere((path, metrics) => metrics.isEmpty);
  }
  
  void dispose() {
    _cleanupTimer?.cancel();
  }
}

class EndpointMetrics {
  final String path;
  final List<MetricEntry> _entries = [];
  
  EndpointMetrics(this.path);
  
  void recordRequest() {
    _entries.add(MetricEntry(
      timestamp: DateTime.now(),
      type: MetricType.request,
    ));
  }
  
  void recordResponse(int statusCode, Duration duration) {
    _entries.add(MetricEntry(
      timestamp: DateTime.now(),
      type: MetricType.response,
      statusCode: statusCode,
      duration: duration,
    ));
  }
  
  void recordError() {
    _entries.add(MetricEntry(
      timestamp: DateTime.now(),
      type: MetricType.error,
    ));
  }
  
  void cleanup(DateTime cutoff) {
    _entries.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
  }
  
  bool get isEmpty => _entries.isEmpty;
  
  Map<String, dynamic> toMap() {
    final responses = _entries.where((e) => e.type == MetricType.response);
    final errors = _entries.where((e) => e.type == MetricType.error);
    
    final durations = responses
        .where((e) => e.duration != null)
        .map((e) => e.duration!.inMilliseconds)
        .toList();
    
    return {
      'total_requests': _entries.where((e) => e.type == MetricType.request).length,
      'total_responses': responses.length,
      'total_errors': errors.length,
      'avg_duration_ms': durations.isEmpty ? 0 : durations.reduce((a, b) => a + b) ~/ durations.length,
      'min_duration_ms': durations.isEmpty ? 0 : durations.reduce((a, b) => a < b ? a : b),
      'max_duration_ms': durations.isEmpty ? 0 : durations.reduce((a, b) => a > b ? a : b),
      'status_codes': _getStatusCodeBreakdown(responses),
    };
  }
  
  Map<String, int> _getStatusCodeBreakdown(Iterable<MetricEntry> responses) {
    final breakdown = <String, int>{};
    
    for (final response in responses) {
      if (response.statusCode != null) {
        final key = '${response.statusCode ~/ 100}xx';
        breakdown[key] = (breakdown[key] ?? 0) + 1;
      }
    }
    
    return breakdown;
  }
}

class MetricEntry {
  final DateTime timestamp;
  final MetricType type;
  final int? statusCode;
  final Duration? duration;
  
  MetricEntry({
    required this.timestamp,
    required this.type,
    this.statusCode,
    this.duration,
  });
}

enum MetricType {
  request,
  response,
  error,
}