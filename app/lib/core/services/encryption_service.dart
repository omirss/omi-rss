import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

/// End-to-end encryption service for sync data
class EncryptionService {
  late final AesGcm _aesGcm;
  SecretKey? _masterKey;
  
  // Key derivation parameters
  static const int _saltLength = 32;
  static const int _iterations = 100000;
  static const int _keyLength = 32;
  
  EncryptionService() {
    // Use Flutter-optimized cryptography
    _aesGcm = FlutterCryptography.instance.aesGcm();
  }
  
  /// Initialize with user password
  Future<void> initialize(String password) async {
    // Generate or load salt
    final salt = await _getOrCreateSalt();
    
    // Derive key from password
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: _keyLength * 8,
    );
    
    _masterKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }
  
  /// Initialize with existing key (for device-to-device sync)
  Future<void> initializeWithKey(Uint8List keyData) async {
    _masterKey = SecretKey(keyData);
  }
  
  /// Get or create salt for key derivation
  Future<List<int>> _getOrCreateSalt() async {
    // TODO: Load from secure storage
    // For now, generate new salt
    final algorithm = FlutterCryptography.instance.aesGcm();
    return algorithm.newNonce();
  }
  
  /// Encrypt data
  Future<Uint8List> encrypt(Uint8List plaintext) async {
    if (_masterKey == null) {
      throw StateError('Encryption service not initialized');
    }
    
    // Generate nonce
    final nonce = _aesGcm.newNonce();
    
    // Encrypt
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: _masterKey!,
      nonce: nonce,
    );
    
    // Combine nonce + ciphertext + mac
    final combined = Uint8List(
      nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length,
    );
    
    var offset = 0;
    combined.setAll(offset, nonce);
    offset += nonce.length;
    combined.setAll(offset, secretBox.cipherText);
    offset += secretBox.cipherText.length;
    combined.setAll(offset, secretBox.mac.bytes);
    
    return combined;
  }
  
  /// Decrypt data
  Future<Uint8List> decrypt(Uint8List ciphertext) async {
    if (_masterKey == null) {
      throw StateError('Encryption service not initialized');
    }
    
    // Extract nonce, ciphertext, and mac
    const nonceLength = 12; // AES-GCM nonce length
    const macLength = 16; // AES-GCM MAC length
    
    if (ciphertext.length < nonceLength + macLength) {
      throw ArgumentError('Invalid ciphertext');
    }
    
    final nonce = ciphertext.sublist(0, nonceLength);
    final encryptedData = ciphertext.sublist(
      nonceLength,
      ciphertext.length - macLength,
    );
    final mac = ciphertext.sublist(ciphertext.length - macLength);
    
    // Create SecretBox
    final secretBox = SecretBox(
      encryptedData,
      nonce: nonce,
      mac: Mac(mac),
    );
    
    // Decrypt
    final plaintext = await _aesGcm.decrypt(
      secretBox,
      secretKey: _masterKey!,
    );
    
    return Uint8List.fromList(plaintext);
  }
  
  /// Encrypt string
  Future<String> encryptString(String plaintext) async {
    final encrypted = await encrypt(utf8.encode(plaintext));
    return base64Encode(encrypted);
  }
  
  /// Decrypt string
  Future<String> decryptString(String ciphertext) async {
    final decrypted = await decrypt(base64Decode(ciphertext));
    return utf8.decode(decrypted);
  }
  
  /// Encrypt JSON object
  Future<Uint8List> encryptJson(Map<String, dynamic> json) async {
    final jsonString = jsonEncode(json);
    return encrypt(utf8.encode(jsonString));
  }
  
  /// Decrypt JSON object
  Future<Map<String, dynamic>> decryptJson(Uint8List ciphertext) async {
    final decrypted = await decrypt(ciphertext);
    final jsonString = utf8.decode(decrypted);
    return jsonDecode(jsonString);
  }
  
  /// Generate encryption key for sharing
  Future<EncryptionKey> generateSharingKey() async {
    final algorithm = FlutterCryptography.instance.aesGcm();
    final secretKey = await algorithm.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    
    return EncryptionKey(
      id: _generateKeyId(),
      key: Uint8List.fromList(keyBytes),
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
  }
  
  /// Encrypt data with sharing key
  Future<Uint8List> encryptWithKey(
    Uint8List plaintext,
    EncryptionKey encryptionKey,
  ) async {
    final secretKey = SecretKey(encryptionKey.key);
    
    // Generate nonce
    final nonce = _aesGcm.newNonce();
    
    // Encrypt
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    
    // Combine nonce + ciphertext + mac
    final combined = Uint8List(
      nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length,
    );
    
    var offset = 0;
    combined.setAll(offset, nonce);
    offset += nonce.length;
    combined.setAll(offset, secretBox.cipherText);
    offset += secretBox.cipherText.length;
    combined.setAll(offset, secretBox.mac.bytes);
    
    return combined;
  }
  
  /// Decrypt data with sharing key
  Future<Uint8List> decryptWithKey(
    Uint8List ciphertext,
    EncryptionKey encryptionKey,
  ) async {
    final secretKey = SecretKey(encryptionKey.key);
    
    // Extract nonce, ciphertext, and mac
    const nonceLength = 12;
    const macLength = 16;
    
    final nonce = ciphertext.sublist(0, nonceLength);
    final encryptedData = ciphertext.sublist(
      nonceLength,
      ciphertext.length - macLength,
    );
    final mac = ciphertext.sublist(ciphertext.length - macLength);
    
    // Create SecretBox
    final secretBox = SecretBox(
      encryptedData,
      nonce: nonce,
      mac: Mac(mac),
    );
    
    // Decrypt
    final plaintext = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    
    return Uint8List.fromList(plaintext);
  }
  
  /// Generate secure random bytes
  Future<Uint8List> generateRandomBytes(int length) async {
    final random = FlutterCryptography.instance.secureRandom();
    return Uint8List.fromList(await random.generateBytes(length));
  }
  
  /// Generate key ID
  String _generateKeyId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = FlutterCryptography.instance.secureRandom();
    return String.fromCharCodes(
      List.generate(16, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }
  
  /// Hash data (for integrity checks)
  Future<Uint8List> hash(Uint8List data) async {
    final sha256 = Sha256();
    final hash = await sha256.hash(data);
    return Uint8List.fromList(hash.bytes);
  }
  
  /// Verify data integrity
  Future<bool> verifyIntegrity(Uint8List data, Uint8List expectedHash) async {
    final actualHash = await hash(data);
    if (actualHash.length != expectedHash.length) return false;
    
    for (int i = 0; i < actualHash.length; i++) {
      if (actualHash[i] != expectedHash[i]) return false;
    }
    return true;
  }
  
  /// Export master key (for backup)
  Future<String> exportMasterKey() async {
    if (_masterKey == null) {
      throw StateError('No master key to export');
    }
    
    final keyBytes = await _masterKey!.extractBytes();
    return base64Encode(keyBytes);
  }
  
  /// Import master key (from backup)
  Future<void> importMasterKey(String exportedKey) async {
    final keyBytes = base64Decode(exportedKey);
    _masterKey = SecretKey(keyBytes);
  }
  
  /// Clear keys from memory
  void clearKeys() {
    _masterKey = null;
  }
}

/// Encryption key for sharing
class EncryptionKey {
  final String id;
  final Uint8List key;
  final DateTime createdAt;
  final DateTime expiresAt;
  
  EncryptionKey({
    required this.id,
    required this.key,
    required this.createdAt,
    required this.expiresAt,
  });
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'key': base64Encode(key),
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
  };
  
  factory EncryptionKey.fromJson(Map<String, dynamic> json) {
    return EncryptionKey(
      id: json['id'],
      key: base64Decode(json['key']),
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: DateTime.parse(json['expires_at']),
    );
  }
}