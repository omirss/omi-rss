import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:serverpod/serverpod.dart';
import '../config/server_config.dart';

/// JWT token generator
class JWTGenerator {
  final AuthConfig config;
  
  JWTGenerator(this.config);
  
  /// Generate access token
  String generateAccessToken({
    required int userId,
    required String email,
    required List<String> scopes,
  }) {
    final header = {
      'alg': 'HS256',
      'typ': 'JWT',
    };
    
    final now = DateTime.now();
    final expiry = now.add(Duration(hours: config.tokenLifetimeHours));
    
    final payload = {
      'userId': userId,
      'email': email,
      'scopes': scopes,
      'type': 'access',
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      'iss': 'omi-rss',
    };
    
    return _generateToken(header, payload);
  }
  
  /// Generate refresh token
  String generateRefreshToken({
    required int userId,
  }) {
    final header = {
      'alg': 'HS256',
      'typ': 'JWT',
    };
    
    final now = DateTime.now();
    final expiry = now.add(Duration(hours: config.refreshTokenLifetimeHours));
    
    final payload = {
      'userId': userId,
      'type': 'refresh',
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      'iss': 'omi-rss',
    };
    
    return _generateToken(header, payload);
  }
  
  /// Verify token and return payload
  Map<String, dynamic>? verifyToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }
      
      final headerEncoded = parts[0];
      final payloadEncoded = parts[1];
      final signatureEncoded = parts[2];
      
      // Verify signature
      final dataToSign = '$headerEncoded.$payloadEncoded';
      final expectedSignature = _base64UrlEncode(
        Hmac(sha256, utf8.encode(config.jwtSecret))
            .convert(utf8.encode(dataToSign))
            .bytes,
      );
      
      if (expectedSignature != signatureEncoded) {
        return null;
      }
      
      // Decode payload
      final payloadJson = utf8.decode(
        base64Url.decode(_base64UrlPad(payloadEncoded)),
      );
      final payload = json.decode(payloadJson) as Map<String, dynamic>;
      
      // Check expiration
      final exp = payload['exp'] as int?;
      if (exp != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        if (expiry.isBefore(DateTime.now())) {
          return null;
        }
      }
      
      return payload;
    } catch (e) {
      return null;
    }
  }
  
  /// Generate token from header and payload
  String _generateToken(Map<String, dynamic> header, Map<String, dynamic> payload) {
    final headerEncoded = _base64UrlEncode(utf8.encode(json.encode(header)));
    final payloadEncoded = _base64UrlEncode(utf8.encode(json.encode(payload)));
    
    final dataToSign = '$headerEncoded.$payloadEncoded';
    final signature = Hmac(sha256, utf8.encode(config.jwtSecret))
        .convert(utf8.encode(dataToSign));
    final signatureEncoded = _base64UrlEncode(signature.bytes);
    
    return '$headerEncoded.$payloadEncoded.$signatureEncoded';
  }
  
  /// Base64Url encode without padding
  String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
  
  /// Add padding to base64url string
  String _base64UrlPad(String input) {
    final length = input.length;
    final padding = (4 - (length % 4)) % 4;
    return input + ('=' * padding);
  }
}