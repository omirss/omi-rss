import 'package:freezed_annotation/freezed_annotation.dart';

part 'sync_data.freezed.dart';
part 'sync_data.g.dart';

@freezed
class SyncData with _$SyncData {
  const factory SyncData({
    required String deviceId,
    required String deviceName,
    required DateTime lastSync,
    required SyncState state,
    required Map<String, dynamic> data,
  }) = _SyncData;

  factory SyncData.fromJson(Map<String, dynamic> json) =>
      _$SyncDataFromJson(json);
}

@freezed
class SyncState with _$SyncState {
  const factory SyncState({
    required int feedsCount,
    required int articlesCount,
    required int readArticlesCount,
    required int savedArticlesCount,
    required DateTime lastModified,
    required String checksum,
  }) = _SyncState;

  factory SyncState.fromJson(Map<String, dynamic> json) =>
      _$SyncStateFromJson(json);
}

@freezed
class PeerDevice with _$PeerDevice {
  const factory PeerDevice({
    required String id,
    required String name,
    required String address,
    required int port,
    required DateTime lastSeen,
    required bool isOnline,
    required DeviceType type,
    SyncState? syncState,
  }) = _PeerDevice;

  factory PeerDevice.fromJson(Map<String, dynamic> json) =>
      _$PeerDeviceFromJson(json);
}

enum DeviceType {
  mobile,
  desktop,
  web,
  extension,
}

@freezed
class SyncMessage with _$SyncMessage {
  const factory SyncMessage({
    required String id,
    required String fromDevice,
    required String toDevice,
    required SyncMessageType type,
    required Map<String, dynamic> payload,
    required DateTime timestamp,
  }) = _SyncMessage;

  factory SyncMessage.fromJson(Map<String, dynamic> json) =>
      _$SyncMessageFromJson(json);
}

enum SyncMessageType {
  hello,
  sync_request,
  sync_response,
  data_chunk,
  ack,
  ping,
  pong,
  disconnect,
}

@freezed
class SyncConflict with _$SyncConflict {
  const factory SyncConflict({
    required String id,
    required String itemId,
    required String itemType,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required DateTime localTimestamp,
    required DateTime remoteTimestamp,
    ConflictResolution? resolution,
  }) = _SyncConflict;

  factory SyncConflict.fromJson(Map<String, dynamic> json) =>
      _$SyncConflictFromJson(json);
}

enum ConflictResolution {
  keepLocal,
  keepRemote,
  merge,
  skip,
}