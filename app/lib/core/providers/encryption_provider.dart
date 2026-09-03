import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/encryption_service.dart';

/// Provider for encryption service
final encryptionProvider = Provider<EncryptionService>((ref) {
  final service = EncryptionService();
  
  // Initialize with a default password for demo
  // In production, this would come from secure storage after user authentication
  service.initialize('demo-password-123');
  
  return service;
});