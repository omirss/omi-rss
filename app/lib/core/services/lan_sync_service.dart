import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';
import 'encryption_service.dart';
import 'sync_service.dart';

/// LAN/P2P sync service for local network synchronization
class LanSyncService {
  final AppDatabase _database;
  final EncryptionService _encryption;
  final Dio _dio;
  
  // Service discovery
  MDnsClient? _mdnsClient;
  HttpServer? _httpServer;
  
  // Device info
  final String _deviceId = const Uuid().v4();
  String? _deviceName;
  String? _localIp;
  int? _serverPort;
  
  // Discovered devices
  final Map<String, LanDevice> _discoveredDevices = {};
  final _devicesController = StreamController<List<LanDevice>>.broadcast();
  
  // Sync sessions
  final Map<String, LanSyncSession> _activeSessions = {};
  
  // Configuration
  static const String _mdnsService = '_omi-rss-sync._tcp';
  static const int _defaultPort = 8765;
  static const Duration _discoveryTimeout = Duration(seconds: 30);
  
  LanSyncService({
    required AppDatabase database,
    required EncryptionService encryption,
  }) : _database = database,
       _encryption = encryption,
       _dio = Dio();

  /// Initialize LAN sync service
  Future<void> initialize({String? deviceName}) async {
    _deviceName = deviceName ?? await _getDeviceName();
    _localIp = await _getLocalIpAddress();
    
    // Start HTTP server for sync
    await _startHttpServer();
    
    // Start mDNS for service discovery
    await _startServiceDiscovery();
  }
  
  /// Get device name
  Future<String> _getDeviceName() async {
    if (Platform.isAndroid) {
      return 'Android Device';
    } else if (Platform.isIOS) {
      return 'iOS Device';
    } else if (Platform.isWindows) {
      return 'Windows PC';
    } else if (Platform.isMacOS) {
      return 'Mac';
    } else if (Platform.isLinux) {
      return 'Linux PC';
    }
    return 'Unknown Device';
  }
  
  /// Get local IP address
  Future<String?> _getLocalIpAddress() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      print('Failed to get IP address: $e');
      
      // Fallback: Find first non-loopback IPv4 address
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
      return null;
    }
  }
  
  /// Start HTTP server for sync
  Future<void> _startHttpServer() async {
    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _defaultPort,
      );
      
      _serverPort = _httpServer!.port;
      print('LAN sync server started on $_localIp:$_serverPort');
      
      _httpServer!.listen((request) async {
        try {
          await _handleHttpRequest(request);
        } catch (e) {
          print('Error handling request: $e');
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..write('Internal Server Error')
            ..close();
        }
      });
    } catch (e) {
      print('Failed to start HTTP server: $e');
      throw Exception('Failed to start LAN sync server');
    }
  }
  
  /// Handle HTTP requests
  Future<void> _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    
    // CORS headers for browser support
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    
    if (request.method == 'OPTIONS') {
      request.response.close();
      return;
    }
    
    switch (path) {
      case '/info':
        await _handleDeviceInfo(request);
        break;
        
      case '/pair':
        await _handlePairRequest(request);
        break;
        
      case '/sync/start':
        await _handleSyncStart(request);
        break;
        
      case '/sync/changes':
        await _handleSyncChanges(request);
        break;
        
      case '/sync/file':
        await _handleFileTransfer(request);
        break;
        
      default:
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not Found')
          ..close();
    }
  }
  
  /// Handle device info request
  Future<void> _handleDeviceInfo(HttpRequest request) async {
    final info = {
      'device_id': _deviceId,
      'device_name': _deviceName,
      'platform': Platform.operatingSystem,
      'version': '1.0.0',
      'capabilities': ['sync', 'file_transfer', 'encrypted'],
    };
    
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(info))
      ..close();
  }
  
  /// Handle pairing request
  Future<void> _handlePairRequest(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..close();
      return;
    }
    
    final body = await _readRequestBody(request);
    final data = jsonDecode(body);
    
    final remoteDeviceId = data['device_id'];
    final remoteDeviceName = data['device_name'];
    final pairingCode = data['pairing_code'];
    
    // Verify pairing code
    if (!_verifyPairingCode(pairingCode)) {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write('Invalid pairing code')
        ..close();
      return;
    }
    
    // Generate session key
    final sessionKey = await _encryption.generateSharingKey();
    
    // Store pairing info
    final session = LanSyncSession(
      id: const Uuid().v4(),
      localDeviceId: _deviceId,
      remoteDeviceId: remoteDeviceId,
      remoteDeviceName: remoteDeviceName,
      sessionKey: sessionKey,
      createdAt: DateTime.now(),
    );
    
    _activeSessions[remoteDeviceId] = session;
    
    // Send session info
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'session_id': session.id,
        'session_key': sessionKey.toJson(),
        'device_id': _deviceId,
        'device_name': _deviceName,
      }))
      ..close();
  }
  
  /// Start service discovery
  Future<void> _startServiceDiscovery() async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();
      
      // Advertise our service
      _advertiseService();
      
      // Discover other devices
      _discoverDevices();
    } catch (e) {
      print('Failed to start mDNS: $e');
    }
  }
  
  /// Advertise service via mDNS
  void _advertiseService() {
    if (_localIp == null || _serverPort == null) return;
    
    // Create service record
    final ptr = PTRRecord(
      _mdnsService,
      PtrRecordValue(
        domainName: '$_deviceId.$_mdnsService.local',
      ),
    );
    
    final srv = SRVRecord(
      '$_deviceId.$_mdnsService.local',
      SrvRecordValue(
        priority: 0,
        weight: 0,
        port: _serverPort!,
        target: '$_deviceId.local',
      ),
    );
    
    final txt = TXTRecord(
      '$_deviceId.$_mdnsService.local',
      TxtRecordValue(const <String, String>{
        'device_name': 'deviceName',
        'platform': Platform.operatingSystem,
        'version': '1.0.0',
      }),
    );
    
    // TODO: Implement mDNS advertising
    print('Advertising service: $_deviceId.$_mdnsService.local');
  }
  
  /// Discover devices on network
  void _discoverDevices() async {
    if (_mdnsClient == null) return;
    
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        // Query for services
        final query = PtrRecordQuery(
          name: _mdnsService,
          timeout: const Duration(seconds: 3),
        );
        
        await for (final result in _mdnsClient!.lookup(query)) {
          final deviceId = result.domainName.split('.').first;
          if (deviceId == _deviceId) continue; // Skip self
          
          // Get device details
          final srvQuery = SrvRecordQuery(
            name: result.domainName,
            timeout: const Duration(seconds: 1),
          );
          
          final txtQuery = TxtRecordQuery(
            name: result.domainName,
            timeout: const Duration(seconds: 1),
          );
          
          SRVRecord? srvRecord;
          TXTRecord? txtRecord;
          
          await for (final srv in _mdnsClient!.lookup(srvQuery)) {
            srvRecord = srv;
            break;
          }
          
          await for (final txt in _mdnsClient!.lookup(txtQuery)) {
            txtRecord = txt;
            break;
          }
          
          if (srvRecord != null) {
            final device = LanDevice(
              id: deviceId,
              name: txtRecord?.value.text['device_name'] ?? 'Unknown Device',
              address: srvRecord.value.target,
              port: srvRecord.value.port,
              platform: txtRecord?.value.text['platform'] ?? 'unknown',
              lastSeen: DateTime.now(),
            );
            
            _discoveredDevices[deviceId] = device;
            _devicesController.add(_discoveredDevices.values.toList());
          }
        }
      } catch (e) {
        print('Error discovering devices: $e');
      }
    });
  }
  
  /// Pair with device
  Future<LanSyncSession> pairWithDevice(
    LanDevice device,
    String pairingCode,
  ) async {
    try {
      final response = await _dio.post(
        'http://${device.address}:${device.port}/pair',
        data: {
          'device_id': _deviceId,
          'device_name': _deviceName,
          'pairing_code': pairingCode,
        },
      );
      
      final data = response.data;
      final sessionKey = EncryptionKey.fromJson(data['session_key']);
      
      final session = LanSyncSession(
        id: data['session_id'],
        localDeviceId: _deviceId,
        remoteDeviceId: device.id,
        remoteDeviceName: device.name,
        sessionKey: sessionKey,
        createdAt: DateTime.now(),
      );
      
      _activeSessions[device.id] = session;
      
      return session;
    } catch (e) {
      throw Exception('Failed to pair with device: $e');
    }
  }
  
  /// Sync with paired device
  Future<void> syncWithDevice(String deviceId) async {
    final session = _activeSessions[deviceId];
    if (session == null) {
      throw Exception('No active session with device');
    }
    
    final device = _discoveredDevices[deviceId];
    if (device == null) {
      throw Exception('Device not found');
    }
    
    try {
      // Get local changes
      final localChanges = await _getLocalChanges(session.lastSyncTime);
      
      // Encrypt changes
      final encryptedChanges = await _encryptChangesForSession(
        localChanges,
        session,
      );
      
      // Start sync session
      final response = await _dio.post(
        'http://${device.address}:${device.port}/sync/start',
        data: {
          'session_id': session.id,
          'device_id': _deviceId,
        },
      );
      
      // Exchange changes
      final syncResponse = await _dio.post(
        'http://${device.address}:${device.port}/sync/changes',
        data: {
          'session_id': session.id,
          'changes': encryptedChanges,
          'last_sync': session.lastSyncTime?.toIso8601String(),
        },
      );
      
      // Apply remote changes
      final remoteChanges = syncResponse.data['changes'] as List;
      await _applyRemoteChanges(remoteChanges, session);
      
      // Update last sync time
      session.lastSyncTime = DateTime.now();
      
    } catch (e) {
      throw Exception('Sync failed: $e');
    }
  }
  
  /// Transfer file to device
  Future<void> transferFile(
    String deviceId,
    String filePath,
    String remotePath,
  ) async {
    final session = _activeSessions[deviceId];
    if (session == null) {
      throw Exception('No active session with device');
    }
    
    final device = _discoveredDevices[deviceId];
    if (device == null) {
      throw Exception('Device not found');
    }
    
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found');
    }
    
    try {
      // Read and encrypt file
      final fileData = await file.readAsBytes();
      final encryptedData = await _encryption.encryptWithKey(
        fileData,
        session.sessionKey,
      );
      
      // Send file
      final formData = FormData.fromMap({
        'session_id': session.id,
        'remote_path': remotePath,
        'file': MultipartFile.fromBytes(
          encryptedData,
          filename: file.path.split('/').last,
        ),
      });
      
      await _dio.post(
        'http://${device.address}:${device.port}/sync/file',
        data: formData,
      );
    } catch (e) {
      throw Exception('File transfer failed: $e');
    }
  }
  
  /// Handle sync start request
  Future<void> _handleSyncStart(HttpRequest request) async {
    final body = await _readRequestBody(request);
    final data = jsonDecode(body);
    
    final sessionId = data['session_id'];
    final remoteDeviceId = data['device_id'];
    
    final session = _activeSessions[remoteDeviceId];
    if (session == null || session.id != sessionId) {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write('Invalid session')
        ..close();
      return;
    }
    
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'status': 'ready'}))
      ..close();
  }
  
  /// Handle sync changes request
  Future<void> _handleSyncChanges(HttpRequest request) async {
    final body = await _readRequestBody(request);
    final data = jsonDecode(body);
    
    final sessionId = data['session_id'];
    final remoteChanges = data['changes'] as List;
    final lastSync = data['last_sync'] != null
        ? DateTime.parse(data['last_sync'])
        : null;
    
    // Find session
    LanSyncSession? session;
    for (final s in _activeSessions.values) {
      if (s.id == sessionId) {
        session = s;
        break;
      }
    }
    
    if (session == null) {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write('Invalid session')
        ..close();
      return;
    }
    
    // Apply remote changes
    await _applyRemoteChanges(remoteChanges, session);
    
    // Get local changes
    final localChanges = await _getLocalChanges(lastSync);
    final encryptedChanges = await _encryptChangesForSession(
      localChanges,
      session,
    );
    
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'changes': encryptedChanges,
        'conflicts': [], // TODO: Handle conflicts
      }))
      ..close();
  }
  
  /// Handle file transfer
  Future<void> _handleFileTransfer(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..close();
      return;
    }
    
    // TODO: Implement file transfer handling
    request.response
      ..statusCode = HttpStatus.notImplemented
      ..write('File transfer not implemented')
      ..close();
  }
  
  /// Read request body
  Future<String> _readRequestBody(HttpRequest request) async {
    final completer = Completer<String>();
    final buffer = StringBuffer();
    
    request.transform(utf8.decoder).listen(
      buffer.write,
      onDone: () => completer.complete(buffer.toString()),
      onError: completer.completeError,
    );
    
    return completer.future;
  }
  
  /// Verify pairing code
  bool _verifyPairingCode(String code) {
    // Simple 6-digit code verification
    return code.length == 6 && int.tryParse(code) != null;
  }
  
  /// Generate pairing code
  String generatePairingCode() {
    final random = Random.secure();
    return (random.nextInt(900000) + 100000).toString();
  }
  
  /// Get local changes
  Future<List<SyncChange>> _getLocalChanges(DateTime? since) async {
    // Reuse sync service logic
    final changes = <SyncChange>[];
    
    // TODO: Implement change tracking
    
    return changes;
  }
  
  /// Encrypt changes for session
  Future<List<Map<String, dynamic>>> _encryptChangesForSession(
    List<SyncChange> changes,
    LanSyncSession session,
  ) async {
    final encrypted = <Map<String, dynamic>>[];
    
    for (final change in changes) {
      final encryptedData = await _encryption.encryptWithKey(
        utf8.encode(jsonEncode(change.data)),
        session.sessionKey,
      );
      
      encrypted.add({
        'id': change.id,
        'entity_type': change.entityType,
        'entity_id': change.entityId,
        'action': change.action.toString(),
        'data': base64Encode(encryptedData),
        'timestamp': change.timestamp.toIso8601String(),
      });
    }
    
    return encrypted;
  }
  
  /// Apply remote changes
  Future<void> _applyRemoteChanges(
    List<dynamic> changes,
    LanSyncSession session,
  ) async {
    for (final change in changes) {
      try {
        // Decrypt data
        final encryptedData = base64Decode(change['data']);
        final decryptedData = await _encryption.decryptWithKey(
          encryptedData,
          session.sessionKey,
        );
        
        final data = jsonDecode(utf8.decode(decryptedData));
        
        // Apply change
        // TODO: Implement change application
        
      } catch (e) {
        print('Error applying change: $e');
      }
    }
  }
  
  /// Get discovered devices stream
  Stream<List<LanDevice>> get devices => _devicesController.stream;
  
  /// Get active sessions
  List<LanSyncSession> get activeSessions => _activeSessions.values.toList();
  
  /// Dispose service
  Future<void> dispose() async {
    await _httpServer?.close();
    _mdnsClient?.stop();
    await _devicesController.close();
  }
}

/// LAN device model
class LanDevice {
  final String id;
  final String name;
  final String address;
  final int port;
  final String platform;
  final DateTime lastSeen;
  
  LanDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.platform,
    required this.lastSeen,
  });
}

/// LAN sync session
class LanSyncSession {
  final String id;
  final String localDeviceId;
  final String remoteDeviceId;
  final String remoteDeviceName;
  final EncryptionKey sessionKey;
  final DateTime createdAt;
  DateTime? lastSyncTime;
  
  LanSyncSession({
    required this.id,
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.remoteDeviceName,
    required this.sessionKey,
    required this.createdAt,
    this.lastSyncTime,
  });
}