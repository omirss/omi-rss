import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncEncryptionServiceProvider = Provider((ref) => SyncEncryptionService());

class SyncEncryptionService {
  late final Key _key;
  late final IV _iv;
  late final Encrypter _encrypter;
  
  // Device-specific keys
  final Map<String, String> _deviceKeys = {};
  
  SyncEncryptionService() {
    // Generate master key (in production, this should be stored securely)
    final masterKey = sha256.convert(utf8.encode('RSS-Glassmorphism-Reader-2024')).toString();
    _key = Key.fromBase64(base64.encode(masterKey.substring(0, 32).codeUnits));
    _iv = IV.fromLength(16);
    _encrypter = Encrypter(AES(_key));
  }
  
  /// Generate a unique key for device pairing
  String generateDeviceKey(String deviceId1, String deviceId2) {
    // Sort device IDs to ensure consistent key generation
    final ids = [deviceId1, deviceId2]..sort();
    final combined = '${ids[0]}-${ids[1]}';
    
    final key = sha256.convert(utf8.encode(combined)).toString();
    _deviceKeys[combined] = key;
    
    return key;
  }
  
  /// Encrypt data for P2P transmission
  EncryptedData encryptData(Map<String, dynamic> data, String deviceKey) {
    final jsonStr = jsonEncode(data);
    final compressed = _compress(utf8.encode(jsonStr));
    
    // Create encryption key from device key
    final key = Key.fromBase64(base64.encode(deviceKey.substring(0, 32).codeUnits));
    final encrypter = Encrypter(AES(key));
    
    // Encrypt data
    final encrypted = encrypter.encrypt(base64.encode(compressed), iv: _iv);
    
    // Generate checksum
    final checksum = sha256.convert(compressed).toString();
    
    return EncryptedData(
      data: encrypted.base64,
      checksum: checksum,
      timestamp: DateTime.now(),
    );
  }
  
  /// Decrypt data from P2P transmission
  Map<String, dynamic>? decryptData(EncryptedData encryptedData, String deviceKey) {
    try {
      // Create decryption key from device key
      final key = Key.fromBase64(base64.encode(deviceKey.substring(0, 32).codeUnits));
      final encrypter = Encrypter(AES(key));
      
      // Decrypt data
      final encrypted = Encrypted.fromBase64(encryptedData.data);
      final decrypted = encrypter.decrypt(encrypted, iv: _iv);
      
      // Decompress
      final decompressed = _decompress(base64.decode(decrypted));
      
      // Verify checksum
      final checksum = sha256.convert(base64.decode(decrypted)).toString();
      if (checksum != encryptedData.checksum) {
        print('Checksum verification failed');
        return null;
      }
      
      // Parse JSON
      final jsonStr = utf8.decode(decompressed);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      print('Decryption error: $e');
      return null;
    }
  }
  
  /// Encrypt file for sync
  EncryptedFile encryptFile(Uint8List fileData, String fileName, String deviceKey) {
    // Create encryption key from device key
    final key = Key.fromBase64(base64.encode(deviceKey.substring(0, 32).codeUnits));
    final encrypter = Encrypter(AES(key));
    
    // Compress file
    final compressed = _compress(fileData);
    
    // Encrypt in chunks (for large files)
    final chunks = <String>[];
    const chunkSize = 1024 * 1024; // 1MB chunks
    
    for (int i = 0; i < compressed.length; i += chunkSize) {
      final end = (i + chunkSize < compressed.length) ? i + chunkSize : compressed.length;
      final chunk = compressed.sublist(i, end);
      
      final encrypted = encrypter.encrypt(base64.encode(chunk), iv: _iv);
      chunks.add(encrypted.base64);
    }
    
    // Generate file hash
    final hash = sha256.convert(fileData).toString();
    
    return EncryptedFile(
      fileName: fileName,
      chunks: chunks,
      totalSize: fileData.length,
      compressedSize: compressed.length,
      hash: hash,
      timestamp: DateTime.now(),
    );
  }
  
  /// Decrypt file from sync
  Uint8List? decryptFile(EncryptedFile encryptedFile, String deviceKey) {
    try {
      // Create decryption key from device key
      final key = Key.fromBase64(base64.encode(deviceKey.substring(0, 32).codeUnits));
      final encrypter = Encrypter(AES(key));
      
      // Decrypt chunks
      final decryptedChunks = <Uint8List>[];
      
      for (final chunk in encryptedFile.chunks) {
        final encrypted = Encrypted.fromBase64(chunk);
        final decrypted = encrypter.decrypt(encrypted, iv: _iv);
        decryptedChunks.add(base64.decode(decrypted));
      }
      
      // Combine chunks
      final combined = Uint8List.fromList(
        decryptedChunks.expand((chunk) => chunk).toList(),
      );
      
      // Decompress
      final decompressed = _decompress(combined);
      
      // Verify hash
      final hash = sha256.convert(decompressed).toString();
      if (hash != encryptedFile.hash) {
        print('File hash verification failed');
        return null;
      }
      
      return decompressed;
    } catch (e) {
      print('File decryption error: $e');
      return null;
    }
  }
  
  /// Generate secure pairing code
  String generatePairingCode() {
    final random = List.generate(6, (i) => 
      DateTime.now().millisecondsSinceEpoch * (i + 1) % 10
    );
    return random.join();
  }
  
  /// Verify pairing code
  bool verifyPairingCode(String code, String expectedCode) {
    return code == expectedCode;
  }
  
  /// Compress data using gzip
  Uint8List _compress(Uint8List data) {
    return gzip.encode(data);
  }
  
  /// Decompress data using gzip
  Uint8List _decompress(Uint8List data) {
    return gzip.decode(data);
  }
  
  /// Clear device keys
  void clearDeviceKeys() {
    _deviceKeys.clear();
  }
  
  /// Get stored device key
  String? getDeviceKey(String deviceId1, String deviceId2) {
    final ids = [deviceId1, deviceId2]..sort();
    final combined = '${ids[0]}-${ids[1]}';
    return _deviceKeys[combined];
  }
}

class EncryptedData {
  final String data;
  final String checksum;
  final DateTime timestamp;
  
  EncryptedData({
    required this.data,
    required this.checksum,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'data': data,
    'checksum': checksum,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory EncryptedData.fromJson(Map<String, dynamic> json) => EncryptedData(
    data: json['data'] as String,
    checksum: json['checksum'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

class EncryptedFile {
  final String fileName;
  final List<String> chunks;
  final int totalSize;
  final int compressedSize;
  final String hash;
  final DateTime timestamp;
  
  EncryptedFile({
    required this.fileName,
    required this.chunks,
    required this.totalSize,
    required this.compressedSize,
    required this.hash,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'chunks': chunks,
    'totalSize': totalSize,
    'compressedSize': compressedSize,
    'hash': hash,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory EncryptedFile.fromJson(Map<String, dynamic> json) => EncryptedFile(
    fileName: json['fileName'] as String,
    chunks: (json['chunks'] as List).cast<String>(),
    totalSize: json['totalSize'] as int,
    compressedSize: json['compressedSize'] as int,
    hash: json['hash'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}