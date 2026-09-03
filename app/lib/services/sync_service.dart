import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/feed.dart';
import '../core/models/article.dart';
import '../core/models/folder.dart';
import '../core/models/sync_transfer_data.dart';
import '../providers/database_provider.dart';

/// Ultra-thin sync service for P2P and file-based synchronization
class SyncService {
  final DatabaseProvider _db;
  
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  bool _isConnected = false;
  
  final _syncProgressController = StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get syncProgress => _syncProgressController.stream;
  
  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;
  
  SyncService(this._db);
  
  /// Get all data for syncing
  Future<SyncTransferData> getSyncTransferData() async {
    final feeds = await _db.getFeeds();
    final articles = await _db.getArticles();
    final folders = await _db.getFolders();
    final readStatus = await _db.getReadStatus();
    final savedArticles = await _db.getSavedArticles();
    final settings = await _db.getSettings();
    
    return SyncTransferData(
      version: '1.0',
      deviceId: await _getDeviceId(),
      timestamp: DateTime.now(),
      data: SyncTransferContent(
        feeds: feeds,
        articles: articles,
        folders: folders,
        readStatus: readStatus,
        savedArticles: savedArticles,
        settings: settings,
      ),
    );
  }
  
  /// Apply sync data from another device
  Future<void> applySyncTransferData(SyncTransferData remoteData) async {
    if (remoteData.version != '1.0') {
      throw Exception('Unsupported sync data version: ${remoteData.version}');
    }
    
    // Get local data for merging
    final localData = await getSyncTransferData();
    final merged = _mergeData(localData, remoteData);
    
    // Apply merged data to database
    await _db.transaction(() async {
      // Update feeds
      for (final feed in merged.data.feeds) {
        await _db.insertOrUpdateFeed(feed);
      }
      
      // Update articles
      for (final article in merged.data.articles) {
        await _db.insertOrUpdateArticle(article);
      }
      
      // Update folders
      for (final folder in merged.data.folders) {
        await _db.insertOrUpdateFolder(folder);
      }
      
      // Update read status
      await _db.updateReadStatus(merged.data.readStatus);
      
      // Update saved articles
      await _db.updateSavedArticles(merged.data.savedArticles);
      
      // Update settings
      await _db.updateSettings(merged.data.settings);
    });
    
    _lastSyncTime = DateTime.now();
    await _saveLastSyncTime();
  }
  
  /// Merge local and remote data
  SyncTransferData _mergeData(SyncTransferData local, SyncTransferData remote) {
    final merged = SyncTransferData(
      version: '1.0',
      deviceId: local.deviceId,
      timestamp: DateTime.now(),
      data: SyncTransferContent(
        feeds: [],
        articles: [],
        folders: [],
        readStatus: {},
        savedArticles: [],
        settings: {},
      ),
    );
    
    // Merge feeds - keep unique by URL
    final feedMap = <String, Feed>{};
    for (final feed in [...local.data.feeds, ...remote.data.feeds]) {
      final existing = feedMap[feed.url];
      if (existing == null || feed.updatedAt.isAfter(existing.updatedAt)) {
        feedMap[feed.url] = feed;
      }
    }
    merged.data.feeds = feedMap.values.toList();
    
    // Merge articles - keep unique by guid
    final articleMap = <String, Article>{};
    for (final article in [...local.data.articles, ...remote.data.articles]) {
      final existing = articleMap[article.guid];
      if (existing == null || article.updatedAt.isAfter(existing.updatedAt)) {
        articleMap[article.guid] = article;
      }
    }
    merged.data.articles = articleMap.values.toList();
    
    // Merge read status - union
    merged.data.readStatus = {
      ...local.data.readStatus,
      ...remote.data.readStatus,
    };
    
    // Merge saved articles - union
    merged.data.savedArticles = {
      ...local.data.savedArticles,
      ...remote.data.savedArticles,
    }.toList();
    
    // Merge folders
    final folderMap = <int, Folder>{};
    for (final folder in [...local.data.folders, ...remote.data.folders]) {
      final existing = folderMap[folder.id];
      if (existing == null || folder.updatedAt.isAfter(existing.updatedAt)) {
        folderMap[folder.id] = folder;
      }
    }
    merged.data.folders = folderMap.values.toList();
    
    // Merge settings - remote wins if newer
    merged.data.settings = remote.timestamp.isAfter(local.timestamp)
        ? remote.data.settings
        : local.data.settings;
    
    return merged;
  }
  
  // WebRTC P2P Sync Methods
  
  /// Create P2P connection and return connection data for QR code
  Future<P2PConnectionResult> createP2PConnection() async {
    try {
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.connecting,
        message: 'Creating connection...',
      ));
      
      // Create peer connection
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ]
      };
      
      _peerConnection = await createPeerConnection(configuration);
      
      // Create data channel
      final dataChannelInit = RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 3;
      
      _dataChannel = await _peerConnection!.createDataChannel(
        'sync',
        dataChannelInit,
      );
      
      _setupDataChannel();
      _setupPeerConnection();
      
      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      
      // Wait for ICE gathering
      await _waitForIceGathering();
      
      // Create connection data
      final connectionData = {
        'type': 'offer',
        'sdp': _peerConnection!.localDescription!.sdp,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Compress and encode
      final jsonStr = jsonEncode(connectionData);
      final compressed = _compress(jsonStr);
      final encoded = base64Encode(compressed);
      
      return P2PConnectionResult(
        connectionData: encoded,
        expiresIn: const Duration(seconds: 30),
      );
    } catch (e) {
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.error,
        message: 'Failed to create connection: $e',
      ));
      rethrow;
    }
  }
  
  /// Connect to peer using connection data
  Future<void> connectToPeer(String connectionData) async {
    try {
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.connecting,
        message: 'Connecting to peer...',
      ));
      
      // Decode and decompress
      final decoded = base64Decode(connectionData);
      final decompressed = _decompress(decoded);
      final data = jsonDecode(decompressed) as Map<String, dynamic>;
      
      // Check if expired
      final timestamp = data['timestamp'] as int;
      if (DateTime.now().millisecondsSinceEpoch - timestamp > 30000) {
        throw Exception('Connection data expired');
      }
      
      if (data['type'] == 'offer') {
        await _handleOffer(data);
      } else if (data['type'] == 'answer') {
        await _handleAnswer(data);
      }
      
      // Wait for connection
      await _waitForConnection();
      
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.syncing,
        message: 'Connected! Syncing data...',
      ));
    } catch (e) {
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.error,
        message: 'Connection failed: $e',
      ));
      rethrow;
    }
  }
  
  // File-based Sync Methods
  
  /// Export sync data to file
  Future<void> exportToFile() async {
    try {
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.exporting,
        message: 'Preparing export...',
      ));
      
      // Get sync data
      final syncData = await getSyncTransferData();
      
      // Add export metadata
      final exportData = {
        ...syncData.toJson(),
        'exportedAt': DateTime.now().toIso8601String(),
        'fileVersion': '1.0',
      };
      
      // Convert to JSON
      final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);
      final bytes = utf8.encode(jsonStr);
      
      // Generate filename
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filename = 'omi-rss-sync-$timestamp.json';
      
      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: Save to downloads and share
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$filename');
        await file.writeAsBytes(bytes);
        
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Omi RSS Sync Data',
          text: 'Exported ${syncData.data.feeds.length} feeds and ${syncData.data.articles.length} articles',
        );
      } else {
        // Desktop: Use file picker
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Sync Data',
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );
        
        if (result != null) {
          _syncProgressController.add(SyncProgress(
            status: SyncStatus.completed,
            message: 'Export completed successfully',
          ));
        }
      }
    } catch (e) {
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.error,
        message: 'Export failed: $e',
      ));
      rethrow;
    }
  }
  
  /// Import sync data from file
  Future<void> importFromFile() async {
    try {
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.importing,
        message: 'Select file to import...',
      ));
      
      // Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (result == null) return;
      
      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final jsonStr = utf8.decode(bytes);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      // Validate and import
      final syncData = SyncTransferData.fromJson(data);
      
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.syncing,
        message: 'Importing data...',
      ));
      
      await applySyncTransferData(syncData);
      
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.completed,
        message: 'Import completed successfully',
      ));
    } catch (e) {
      _syncProgressController.add(SyncProgress(
        status: SyncStatus.error,
        message: 'Import failed: $e',
      ));
      rethrow;
    }
  }
  
  // Helper methods
  
  Future<String> _getDeviceId() async {
    // Get or generate device ID
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('deviceId');
    
    if (deviceId == null) {
      deviceId = 'flutter-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999999)}';
      await prefs.setString('deviceId', deviceId);
    }
    
    return deviceId;
  }
  
  Future<void> _saveLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSyncTime', _lastSyncTime!.millisecondsSinceEpoch);
  }
  
  Future<void> loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('lastSyncTime');
    if (timestamp != null) {
      _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
  }
  
  // WebRTC helper methods
  
  void _setupDataChannel() {
    _dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _isConnected = true;
        _startSync();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _isConnected = false;
      }
    };
    
    _dataChannel!.onMessage = (message) {
      _handleMessage(message.text);
    };
  }
  
  void _setupPeerConnection() {
    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannel();
    };
    
    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _isConnected = true;
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _isConnected = false;
        _cleanup();
      }
    };
  }
  
  Future<void> _startSync() async {
    // Send sync request
    _sendMessage({
      'type': 'sync-request',
      'deviceId': await _getDeviceId(),
    });
  }
  
  void _sendMessage(Map<String, dynamic> message) {
    if (_dataChannel != null && _isConnected) {
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(message)));
    }
  }
  
  Future<void> _handleMessage(String data) async {
    try {
      final message = jsonDecode(data) as Map<String, dynamic>;
      
      switch (message['type']) {
        case 'sync-request':
          // Send our data
          final syncData = await getSyncTransferData();
          _sendMessage({
            'type': 'sync-data',
            'data': syncData.toJson(),
          });
          break;
          
        case 'sync-data':
          // Apply received data
          final remoteData = SyncTransferData.fromJson(message['data']);
          await applySyncTransferData(remoteData);
          
          // Send our data back
          final ourData = await getSyncTransferData();
          _sendMessage({
            'type': 'sync-complete',
            'data': ourData.toJson(),
          });
          
          _syncProgressController.add(SyncProgress(
            status: SyncStatus.completed,
            message: 'Sync completed successfully',
          ));
          break;
          
        case 'sync-complete':
          // Final sync
          final finalData = SyncTransferData.fromJson(message['data']);
          await applySyncTransferData(finalData);
          
          _syncProgressController.add(SyncProgress(
            status: SyncStatus.completed,
            message: 'Sync completed successfully',
          ));
          break;
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
    }
  }
  
  Future<void> _handleOffer(Map<String, dynamic> offerData) async {
    _cleanup();
    
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    };
    
    _peerConnection = await createPeerConnection(configuration);
    _setupPeerConnection();
    
    // Set remote description
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(
      offerData['sdp'],
      'offer',
    ));
    
    // Create answer
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    
    // Wait for ICE gathering
    await _waitForIceGathering();
    
    // TODO: Display answer for user to copy
    final answerData = {
      'type': 'answer',
      'sdp': _peerConnection!.localDescription!.sdp,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    debugPrint('Answer ready: ${base64Encode(_compress(jsonEncode(answerData)))}');
  }
  
  Future<void> _handleAnswer(Map<String, dynamic> answerData) async {
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(
      answerData['sdp'],
      'answer',
    ));
  }
  
  Future<void> _waitForIceGathering() async {
    final completer = Completer<void>();
    
    void checkState() {
      if (_peerConnection!.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        completer.complete();
      }
    }
    
    _peerConnection!.onIceGatheringState = (_) => checkState();
    
    // Check initial state
    checkState();
    
    // Timeout after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    
    await completer.future;
  }
  
  Future<void> _waitForConnection() async {
    final completer = Completer<void>();
    
    // Check periodically
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isConnected) {
        timer.cancel();
        completer.complete();
      } else if (_peerConnection?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        timer.cancel();
        completer.completeError('Connection failed');
      }
    });
    
    // Timeout after 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.completeError('Connection timeout');
      }
    });
    
    await completer.future;
  }
  
  void _cleanup() {
    _dataChannel?.close();
    _dataChannel = null;
    _peerConnection?.close();
    _peerConnection = null;
    _isConnected = false;
  }
  
  // Compression helpers
  Uint8List _compress(String data) {
    // For now, just convert to bytes
    // TODO: Add actual compression using archive package
    return utf8.encode(data);
  }
  
  String _decompress(Uint8List data) {
    // For now, just convert from bytes
    // TODO: Add actual decompression
    return utf8.decode(data);
  }
  
  void dispose() {
    _cleanup();
    _syncProgressController.close();
  }
}

// Models
class P2PConnectionResult {
  final String connectionData;
  final Duration expiresIn;
  
  P2PConnectionResult({
    required this.connectionData,
    required this.expiresIn,
  });
}

class SyncProgress {
  final SyncStatus status;
  final String message;
  final double? progress;
  
  SyncProgress({
    required this.status,
    required this.message,
    this.progress,
  });
}

enum SyncStatus {
  idle,
  connecting,
  syncing,
  exporting,
  importing,
  completed,
  error,
}