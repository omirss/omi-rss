import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_glassmorphism_reader/ui/glass_theme.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_container.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_button.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_card.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_dialog.dart';
import 'package:rss_glassmorphism_reader/core/services/p2p_sync_service.dart';
import 'package:rss_glassmorphism_reader/core/models/sync_data.dart';

final p2pSyncProvider = StateNotifierProvider<P2PSyncNotifier, P2PSyncState>((ref) {
  return P2PSyncNotifier(ref.read(p2pSyncServiceProvider));
});

class P2PSyncState {
  final bool isRunning;
  final List<PeerDevice> devices;
  final SyncProgress? currentSync;
  final List<SyncConflict> conflicts;

  P2PSyncState({
    this.isRunning = false,
    this.devices = const [],
    this.currentSync,
    this.conflicts = const [],
  });

  P2PSyncState copyWith({
    bool? isRunning,
    List<PeerDevice>? devices,
    SyncProgress? currentSync,
    List<SyncConflict>? conflicts,
  }) {
    return P2PSyncState(
      isRunning: isRunning ?? this.isRunning,
      devices: devices ?? this.devices,
      currentSync: currentSync,
      conflicts: conflicts ?? this.conflicts,
    );
  }
}

class P2PSyncNotifier extends StateNotifier<P2PSyncState> {
  final P2PSyncService _syncService;

  P2PSyncNotifier(this._syncService) : super(P2PSyncState()) {
    _init();
  }

  void _init() {
    _syncService.devicesStream.listen((devices) {
      state = state.copyWith(devices: devices);
    });

    _syncService.syncProgressStream.listen((progress) {
      state = state.copyWith(currentSync: progress);
    });

    _syncService.conflictsStream.listen((conflict) {
      state = state.copyWith(
        conflicts: [...state.conflicts, conflict],
      );
    });
  }

  Future<void> toggleSync() async {
    if (state.isRunning) {
      await _syncService.stop();
      state = state.copyWith(isRunning: false);
    } else {
      await _syncService.start();
      state = state.copyWith(isRunning: true);
    }
  }

  Future<void> syncWithDevice(String deviceId) async {
    await _syncService.syncWithDevice(deviceId);
  }

  Future<void> resolveConflict(String conflictId, ConflictResolution resolution) async {
    await _syncService.resolveConflict(conflictId, resolution);
    state = state.copyWith(
      conflicts: state.conflicts.where((c) => c.id != conflictId).toList(),
    );
  }
}

class P2PSyncScreen extends ConsumerWidget {
  const P2PSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = GlassTheme.of(context);
    final syncState = ref.watch(p2pSyncProvider);
    final syncNotifier = ref.read(p2pSyncProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'P2P Sync',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GlassButton(
              onPressed: syncNotifier.toggleSync,
              variant: syncState.isRunning 
                  ? GlassButtonVariant.outlined 
                  : GlassButtonVariant.elevated,
              child: Text(syncState.isRunning ? 'Stop Sync' : 'Start Sync'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            GlassCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: syncState.isRunning 
                            ? [Colors.green, Colors.greenAccent]
                            : [Colors.grey, Colors.grey.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      syncState.isRunning ? Icons.sync : Icons.sync_disabled,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          syncState.isRunning ? 'Sync Active' : 'Sync Inactive',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          syncState.isRunning 
                              ? 'Discovering and syncing with nearby devices'
                              : 'Start sync to connect with other devices',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Current Sync Progress
            if (syncState.currentSync != null) ...[
              const Text(
                'Sync Progress',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      syncState.currentSync!.message,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: syncState.currentSync!.percentage,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        GlassColors.primaryGradient.first,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${syncState.currentSync!.current} / ${syncState.currentSync!.total}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Conflicts
            if (syncState.conflicts.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Sync Conflicts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${syncState.conflicts.length}',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...syncState.conflicts.take(3).map((conflict) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassContainer(
                  onTap: () => _showConflictDialog(context, ref, conflict),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${conflict.itemType} conflict',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Item: ${conflict.itemId}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              )).toList(),
              const SizedBox(height: 24),
            ],

            // Connected Devices
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Devices',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${syncState.devices.where((d) => d.isOnline).length} online',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Device List
            Expanded(
              child: syncState.devices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.devices_other,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            syncState.isRunning 
                                ? 'Searching for devices...'
                                : 'No devices found',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 16,
                            ),
                          ),
                          if (!syncState.isRunning) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Start sync to discover nearby devices',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: syncState.devices.length,
                      itemBuilder: (context, index) {
                        final device = syncState.devices[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: device.isOnline
                                              ? GlassColors.primaryGradient
                                              : [Colors.grey, Colors.grey.shade600],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        _getDeviceIcon(device.type),
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                device.name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              if (device.isOnline)
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: const BoxDecoration(
                                                    color: Colors.green,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${device.address}:${device.port}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.6),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (device.isOnline)
                                      GlassButton(
                                        onPressed: () => syncNotifier.syncWithDevice(device.id),
                                        variant: GlassButtonVariant.icon,
                                        child: const Icon(Icons.sync, size: 20),
                                      ),
                                  ],
                                ),
                                if (device.syncState != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildStatItem(
                                          'Feeds',
                                          device.syncState!.feedsCount.toString(),
                                        ),
                                        _buildStatItem(
                                          'Articles',
                                          device.syncState!.articlesCount.toString(),
                                        ),
                                        _buildStatItem(
                                          'Read',
                                          device.syncState!.readArticlesCount.toString(),
                                        ),
                                        _buildStatItem(
                                          'Saved',
                                          device.syncState!.savedArticlesCount.toString(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  IconData _getDeviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.mobile:
        return Icons.phone_android;
      case DeviceType.desktop:
        return Icons.computer;
      case DeviceType.web:
        return Icons.language;
      case DeviceType.extension:
        return Icons.extension;
    }
  }

  Future<void> _showConflictDialog(
    BuildContext context,
    WidgetRef ref,
    SyncConflict conflict,
  ) async {
    final result = await showGlassDialog<ConflictResolution>(
      context: context,
      title: const Text('Resolve Sync Conflict'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conflict in ${conflict.itemType}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Item ID: ${conflict.itemId}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          _buildConflictOption(
            context,
            'Keep Local Version',
            'Modified: ${_formatDate(conflict.localTimestamp)}',
            ConflictResolution.keepLocal,
          ),
          const SizedBox(height: 8),
          _buildConflictOption(
            context,
            'Keep Remote Version',
            'Modified: ${_formatDate(conflict.remoteTimestamp)}',
            ConflictResolution.keepRemote,
          ),
          const SizedBox(height: 8),
          _buildConflictOption(
            context,
            'Merge Both',
            'Combine changes from both versions',
            ConflictResolution.merge,
          ),
          const SizedBox(height: 8),
          _buildConflictOption(
            context,
            'Skip',
            'Resolve this conflict later',
            ConflictResolution.skip,
          ),
        ],
      ),
      size: GlassDialogSize.medium,
    );

    if (result != null && result != ConflictResolution.skip) {
      ref.read(p2pSyncProvider.notifier).resolveConflict(conflict.id, result);
    }
  }

  Widget _buildConflictOption(
    BuildContext context,
    String title,
    String subtitle,
    ConflictResolution resolution,
  ) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(resolution),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }
}