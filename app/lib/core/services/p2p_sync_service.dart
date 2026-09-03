import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:rss_glassmorphism_reader/core/models/sync_data.dart';

final p2pSyncServiceProvider = Provider((ref) => P2PSyncService());

class P2PSyncService {
  final _uuid = const Uuid();
  late final String _deviceId;
  late final String _deviceName;
  
  ServerSocket? _server;
  final Map<String, Socket> _peers = {};
  final Map<String, PeerDevice> _devices = {};
  final _deviceController = StreamController<List<PeerDevice>>.broadcast();
  final _syncProgressController = StreamController<SyncProgress>.broadcast();
  final _conflictController = StreamController<SyncConflict>.broadcast();
  
  bool _isRunning = false;
  Timer? _discoveryTimer;
  Timer? _pingTimer;
  
  // Configuration
  static const int defaultPort = 42069;
  static const Duration discoveryInterval = Duration(seconds: 5);
  static const Duration pingInterval = Duration(seconds: 30);
  static const Duration peerTimeout = Duration(minutes: 2);
  
  Stream<List<PeerDevice>> get devicesStream => _deviceController.stream;
  Stream<SyncProgress> get syncProgressStream => _syncProgressController.stream;
  Stream<SyncConflict> get conflictsStream => _conflictController.stream;
  
  P2PSyncService() {
    _deviceId = _uuid.v4();
    _deviceName = Platform.localHostname;
  }
  
  Future<void> start({int? port}) async {
    if (_isRunning) return;
    
    try {
      // Start server
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port ?? defaultPort,
      );
      
      _isRunning = true;
      
      // Listen for connections
      _server!.listen(_handleConnection);
      
      // Start discovery
      _startDiscovery();
      
      // Start ping timer
      _startPingTimer();
      
      print('P2P sync service started on port ${_server!.port}');
    } catch (e) {
      print('Failed to start P2P sync service: $e');
      throw Exception('Failed to start P2P sync: $e');
    }
  }
  
  Future<void> stop() async {
    _isRunning = false;
    
    // Cancel timers
    _discoveryTimer?.cancel();
    _pingTimer?.cancel();
    
    // Close all peer connections
    for (final socket in _peers.values) {
      socket.close();
    }
    _peers.clear();
    _devices.clear();
    
    // Close server
    await _server?.close();
    _server = null;
    
    // Close streams
    await _deviceController.close();
    await _syncProgressController.close();
    await _conflictController.close();
  }
  
  void _handleConnection(Socket socket) {
    final address = socket.remoteAddress.address;
    print('New connection from $address');
    
    socket.listen(
      (data) => _handleData(socket, data),
      onError: (error) => _handleError(socket, error),
      onDone: () => _handleDisconnect(socket),
    );
    
    // Send hello message
    _sendMessage(socket, SyncMessage(
      id: _uuid.v4(),
      fromDevice: _deviceId,
      toDevice: '',
      type: SyncMessageType.hello,
      payload: {
        'deviceName': _deviceName,
        'deviceType': _getDeviceType().name,
      },
      timestamp: DateTime.now(),
    ));
  }
  
  void _handleData(Socket socket, Uint8List data) {
    try {
      final jsonStr = utf8.decode(data);
      final json = jsonDecode(jsonStr);
      final message = SyncMessage.fromJson(json);
      
      switch (message.type) {
        case SyncMessageType.hello:
          _handleHello(socket, message);
          break;
        case SyncMessageType.sync_request:
          _handleSyncRequest(socket, message);
          break;
        case SyncMessageType.sync_response:
          _handleSyncResponse(socket, message);
          break;
        case SyncMessageType.data_chunk:
          _handleDataChunk(socket, message);
          break;
        case SyncMessageType.ping:
          _handlePing(socket, message);
          break;
        case SyncMessageType.pong:
          _handlePong(socket, message);
          break;
        default:
          break;
      }
    } catch (e) {
      print('Error handling data: $e');
    }
  }
  
  void _handleError(Socket socket, dynamic error) {
    print('Socket error: $error');
    _removeDevice(socket);
  }
  
  void _handleDisconnect(Socket socket) {
    print('Socket disconnected');
    _removeDevice(socket);
  }
  
  void _handleHello(Socket socket, SyncMessage message) {
    final device = PeerDevice(
      id: message.fromDevice,
      name: message.payload['deviceName'] ?? 'Unknown',
      address: socket.remoteAddress.address,
      port: socket.remotePort,
      lastSeen: DateTime.now(),
      isOnline: true,
      type: DeviceType.values.firstWhere(
        (t) => t.name == message.payload['deviceType'],
        orElse: () => DeviceType.desktop,
      ),
    );
    
    _peers[device.id] = socket;
    _devices[device.id] = device;
    _notifyDeviceUpdate();
    
    // Request sync state
    _sendMessage(socket, SyncMessage(
      id: _uuid.v4(),
      fromDevice: _deviceId,
      toDevice: device.id,
      type: SyncMessageType.sync_request,
      payload: {},
      timestamp: DateTime.now(),
    ));
  }
  
  void _handleSyncRequest(Socket socket, SyncMessage message) {
    // Send current sync state
    final state = _getCurrentSyncState();
    
    _sendMessage(socket, SyncMessage(
      id: _uuid.v4(),
      fromDevice: _deviceId,
      toDevice: message.fromDevice,
      type: SyncMessageType.sync_response,
      payload: state.toJson(),
      timestamp: DateTime.now(),
    ));
  }
  
  void _handleSyncResponse(Socket socket, SyncMessage message) {
    final state = SyncState.fromJson(message.payload);
    final deviceId = message.fromDevice;
    
    if (_devices.containsKey(deviceId)) {
      _devices[deviceId] = _devices[deviceId]!.copyWith(syncState: state);
      _notifyDeviceUpdate();
    }
  }
  
  void _handleDataChunk(Socket socket, SyncMessage message) {
    // Handle incoming data chunk
    final chunkId = message.payload['chunkId'] as String;
    final chunkIndex = message.payload['chunkIndex'] as int;
    final totalChunks = message.payload['totalChunks'] as int;
    final data = message.payload['data'];
    
    // Process chunk
    _processDataChunk(chunkId, chunkIndex, totalChunks, data);
    
    // Send acknowledgment
    _sendMessage(socket, SyncMessage(
      id: _uuid.v4(),
      fromDevice: _deviceId,
      toDevice: message.fromDevice,
      type: SyncMessageType.ack,
      payload: {
        'chunkId': chunkId,
        'chunkIndex': chunkIndex,
      },
      timestamp: DateTime.now(),
    ));
  }
  
  void _handlePing(Socket socket, SyncMessage message) {
    _sendMessage(socket, SyncMessage(
      id: _uuid.v4(),
      fromDevice: _deviceId,
      toDevice: message.fromDevice,
      type: SyncMessageType.pong,
      payload: {},
      timestamp: DateTime.now(),
    ));
  }
  
  void _handlePong(Socket socket, SyncMessage message) {
    final deviceId = message.fromDevice;
    if (_devices.containsKey(deviceId)) {
      _devices[deviceId] = _devices[deviceId]!.copyWith(
        lastSeen: DateTime.now(),
        isOnline: true,
      );
      _notifyDeviceUpdate();
    }
  }
  
  void _startDiscovery() {
    _discoveryTimer = Timer.periodic(discoveryInterval, (_) {
      _discoverPeers();
    });
    
    // Initial discovery
    _discoverPeers();
  }
  
  void _startPingTimer() {
    _pingTimer = Timer.periodic(pingInterval, (_) {
      _pingAllPeers();
      _checkTimeouts();
    });
  }
  
  Future<void> _discoverPeers() async {
    // Broadcast discovery message on local network
    try {
      final interfaces = await NetworkInterface.list();
      
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            // Try to connect to potential peers
            final subnet = addr.address.substring(0, addr.address.lastIndexOf('.'));
            
            for (int i = 1; i <= 254; i++) {
              final ip = '$subnet.$i';
              if (ip != addr.address) {
                _tryConnect(ip, defaultPort);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Discovery error: $e');
    }
  }
  
  Future<void> _tryConnect(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 1),
      );
      
      _handleConnection(socket);
    } catch (e) {
      // Connection failed, ignore
    }
  }
  
  void _pingAllPeers() {
    for (final entry in _peers.entries) {
      _sendMessage(entry.value, SyncMessage(
        id: _uuid.v4(),
        fromDevice: _deviceId,
        toDevice: entry.key,
        type: SyncMessageType.ping,
        payload: {},
        timestamp: DateTime.now(),
      ));
    }
  }
  
  void _checkTimeouts() {
    final now = DateTime.now();
    final expiredDevices = <String>[];
    
    for (final entry in _devices.entries) {
      if (now.difference(entry.value.lastSeen) > peerTimeout) {
        expiredDevices.add(entry.key);
      }
    }
    
    for (final deviceId in expiredDevices) {
      _devices[deviceId] = _devices[deviceId]!.copyWith(isOnline: false);
    }
    
    if (expiredDevices.isNotEmpty) {
      _notifyDeviceUpdate();
    }
  }
  
  void _sendMessage(Socket socket, SyncMessage message) {
    try {
      final json = message.toJson();
      final jsonStr = jsonEncode(json);
      final data = utf8.encode(jsonStr);
      socket.add(data);
    } catch (e) {
      print('Error sending message: $e');
    }
  }
  
  void _removeDevice(Socket socket) {
    String? deviceId;
    
    for (final entry in _peers.entries) {
      if (entry.value == socket) {
        deviceId = entry.key;
        break;
      }
    }
    
    if (deviceId != null) {
      _peers.remove(deviceId);
      _devices[deviceId] = _devices[deviceId]!.copyWith(isOnline: false);
      _notifyDeviceUpdate();
    }
  }
  
  void _notifyDeviceUpdate() {
    _deviceController.add(_devices.values.toList());
  }
  
  SyncState _getCurrentSyncState() {
    // TODO: Get actual state from database
    return SyncState(
      feedsCount: 10,
      articlesCount: 156,
      readArticlesCount: 89,
      savedArticlesCount: 23,
      lastModified: DateTime.now(),
      checksum: _calculateChecksum(),
    );
  }
  
  String _calculateChecksum() {
    // TODO: Calculate actual checksum of data
    return sha256.convert(utf8.encode('dummy-data')).toString();
  }
  
  DeviceType _getDeviceType() {
    if (Platform.isAndroid || Platform.isIOS) {
      return DeviceType.mobile;
    } else if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      return DeviceType.desktop;
    } else {
      return DeviceType.web;
    }
  }
  
  void _processDataChunk(String chunkId, int chunkIndex, int totalChunks, dynamic data) {
    // TODO: Process incoming data chunk
    _syncProgressController.add(SyncProgress(
      deviceId: chunkId,
      current: chunkIndex + 1,
      total: totalChunks,
      message: 'Syncing data...',
    ));
  }
  
  // Public API
  
  Future<void> syncWithDevice(String deviceId) async {
    final socket = _peers[deviceId];
    if (socket == null) {
      throw Exception('Device not connected');
    }
    
    // TODO: Implement full sync logic
    _sendMessage(socket, SyncMessage(
      id: _uuid.v4(),
      fromDevice: _deviceId,
      toDevice: deviceId,
      type: SyncMessageType.sync_request,
      payload: {},
      timestamp: DateTime.now(),
    ));
  }
  
  Future<void> resolveConflict(String conflictId, ConflictResolution resolution) async {
    // TODO: Implement conflict resolution
  }
  
  List<PeerDevice> get connectedDevices => 
      _devices.values.where((d) => d.isOnline).toList();
  
  bool get isRunning => _isRunning;
}

class SyncProgress {
  final String deviceId;
  final int current;
  final int total;
  final String message;
  
  SyncProgress({
    required this.deviceId,
    required this.current,
    required this.total,
    required this.message,
  });
  
  double get percentage => total > 0 ? current / total : 0.0;
}