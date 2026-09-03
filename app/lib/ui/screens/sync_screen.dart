import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/sync_service.dart';
import '../../providers/database_provider.dart';
import '../glass_theme.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  late final SyncService _syncService;
  final _connectionDataController = TextEditingController();
  
  SyncMode _currentMode = SyncMode.none;
  String? _connectionData;
  int _remainingSeconds = 30;
  Timer? _countdownTimer;
  
  StreamSubscription<SyncProgress>? _progressSubscription;
  SyncProgress? _currentProgress;
  
  @override
  void initState() {
    super.initState();
    final db = ref.read(databaseProvider);
    _syncService = SyncService(db);
    
    _progressSubscription = _syncService.syncProgress.listen((progress) {
      setState(() {
        _currentProgress = progress;
      });
      
      if (progress.status == SyncStatus.completed) {
        _showSuccessDialog();
        _resetSync();
      } else if (progress.status == SyncStatus.error) {
        _showErrorDialog(progress.message);
        _resetSync();
      }
    });
    
    _loadLastSyncTime();
  }
  
  @override
  void dispose() {
    _connectionDataController.dispose();
    _countdownTimer?.cancel();
    _progressSubscription?.cancel();
    _syncService.dispose();
    super.dispose();
  }
  
  Future<void> _loadLastSyncTime() async {
    await _syncService.loadLastSyncTime();
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync & Backup'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0a0a0a),
              Color(0xFF1a1a1a),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildSyncOptions(),
                const SizedBox(height: 16),
                _buildSyncContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatusCard() {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sync,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Sync Status',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _syncService.lastSyncTime != null
                  ? 'Last synced: ${_formatLastSync(_syncService.lastSyncTime!)}'
                  : 'Not synced yet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSyncOptions() {
    if (_currentMode != SyncMode.none || _currentProgress != null) {
      return const SizedBox.shrink();
    }
    
    return Column(
      children: [
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'P2P Sync',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect directly with your browser extension',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _createConnection,
                        icon: const Icon(Icons.qr_code),
                        label: const Text('Create Connection'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _joinConnection,
                        icon: const Icon(Icons.link),
                        label: const Text('Join Connection'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'File Sync',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Export/import through cloud storage',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exportData,
                        icon: const Icon(Icons.file_upload),
                        label: const Text('Export'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _importData,
                        icon: const Icon(Icons.file_download),
                        label: const Text('Import'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSyncContent() {
    if (_currentProgress != null) {
      return _buildProgressView();
    }
    
    switch (_currentMode) {
      case SyncMode.createConnection:
        return _buildQRCodeView();
      case SyncMode.joinConnection:
        return _buildJoinView();
      default:
        return const SizedBox.shrink();
    }
  }
  
  Widget _buildQRCodeView() {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Scan with Browser Extension',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            if (_connectionData != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: _connectionData!,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Connection expires in $_remainingSeconds seconds',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.orange,
                  ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              color: Colors.white.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Connection Data:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _connectionData ?? '',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _connectionData!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Connection data copied!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _resetSync,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildJoinView() {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Enter Connection Data',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _connectionDataController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Paste connection data from browser extension',
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.2),
                  ),
                ),
              ),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _resetSync,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _connectionDataController.text.isNotEmpty
                      ? _connectToPeer
                      : null,
                  child: const Text('Connect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProgressView() {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _currentProgress?.message ?? 'Processing...',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (_currentProgress?.progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _currentProgress!.progress,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Future<void> _createConnection() async {
    setState(() {
      _currentMode = SyncMode.createConnection;
    });
    
    try {
      final result = await _syncService.createP2PConnection();
      
      setState(() {
        _connectionData = result.connectionData;
        _remainingSeconds = result.expiresIn.inSeconds;
      });
      
      _startCountdown();
    } catch (e) {
      _showErrorDialog('Failed to create connection: $e');
      _resetSync();
    }
  }
  
  void _joinConnection() {
    setState(() {
      _currentMode = SyncMode.joinConnection;
    });
  }
  
  Future<void> _connectToPeer() async {
    final connectionData = _connectionDataController.text.trim();
    if (connectionData.isEmpty) return;
    
    try {
      await _syncService.connectToPeer(connectionData);
    } catch (e) {
      _showErrorDialog('Failed to connect: $e');
      _resetSync();
    }
  }
  
  Future<void> _exportData() async {
    try {
      await _syncService.exportToFile();
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }
  
  Future<void> _importData() async {
    try {
      await _syncService.importFromFile();
      // Refresh app data
      ref.invalidate(databaseProvider);
    } catch (e) {
      _showErrorDialog('Import failed: $e');
    }
  }
  
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
      });
      
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _showErrorDialog('Connection expired');
        _resetSync();
      }
    });
  }
  
  void _resetSync() {
    setState(() {
      _currentMode = SyncMode.none;
      _connectionData = null;
      _remainingSeconds = 30;
      _currentProgress = null;
    });
    _countdownTimer?.cancel();
    _connectionDataController.clear();
  }
  
  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Complete'),
        content: const Text('Your data has been synced successfully!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Refresh app data
              ref.invalidate(databaseProvider);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  String _formatLastSync(DateTime lastSync) {
    final now = DateTime.now();
    final diff = now.difference(lastSync);
    
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} hours ago';
    } else {
      return '${diff.inDays} days ago';
    }
  }
}

enum SyncMode {
  none,
  createConnection,
  joinConnection,
}

// Glass Card Widget
class GlassCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double borderRadius;
  
  const GlassCard({
    super.key,
    required this.child,
    this.color,
    this.borderRadius = 16,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ColorFilter.mode(
            Colors.white.withOpacity(0.1),
            BlendMode.overlay,
          ),
          child: child,
        ),
      ),
    );
  }
}