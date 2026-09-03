import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart' as auth;

import 'models/feed.dart';
import 'models/article.dart';
import 'models/folder.dart';
import 'models/user_settings.dart';
import 'models/sync_change.dart';
import 'models/shared_folder.dart';
import 'models/feed_generation_rule.dart';
import 'models/ai_analysis.dart';
import 'models/market_data.dart';

export 'models/feed.dart';
export 'models/article.dart';
export 'models/folder.dart';
export 'models/user_settings.dart';
export 'models/sync_change.dart';
export 'models/shared_folder.dart';
export 'models/feed_generation_rule.dart';
export 'models/ai_analysis.dart';
export 'models/market_data.dart';

/* AUTOMATICALLY GENERATED CODE */

class Protocol extends SerializationManagerServer {
  Protocol._();

  factory Protocol() => _instance;
  static final Protocol _instance = Protocol._();

  static final targetDatabaseDefinition = DatabaseDefinition(
    tables: [
      _i2.Feed.t,
      _i3.Article.t,
      _i4.Folder.t,
      _i5.UserSettings.t,
      _i6.SyncChange.t,
      _i7.SharedFolder.t,
      _i8.FeedGenerationRule.t,
      _i9.AIAnalysis.t,
      _i10.MarketData.t,
      ..._i1.Protocol.targetDatabaseDefinition.tables,
    ],
    views: [
      ..._i1.Protocol.targetDatabaseDefinition.views,
    ],
  );

  @override
  T deserialize<T>(
    dynamic data, [
    Type? t,
  ]) {
    t ??= T;
    if (t == _i2.Feed) {
      return _i2.Feed.fromJson(data) as T;
    }
    if (t == _i3.Article) {
      return _i3.Article.fromJson(data) as T;
    }
    if (t == _i4.Folder) {
      return _i4.Folder.fromJson(data) as T;
    }
    if (t == _i5.UserSettings) {
      return _i5.UserSettings.fromJson(data) as T;
    }
    if (t == _i6.SyncChange) {
      return _i6.SyncChange.fromJson(data) as T;
    }
    if (t == _i7.SharedFolder) {
      return _i7.SharedFolder.fromJson(data) as T;
    }
    if (t == _i8.FeedGenerationRule) {
      return _i8.FeedGenerationRule.fromJson(data) as T;
    }
    if (t == _i9.AIAnalysis) {
      return _i9.AIAnalysis.fromJson(data) as T;
    }
    if (t == _i10.MarketData) {
      return _i10.MarketData.fromJson(data) as T;
    }
    if (t == _i1.UserInfo) {
      return _i1.UserInfo.fromJson(data) as T;
    }
    if (t == _i1.UserInfoPublic) {
      return _i1.UserInfoPublic.fromJson(data) as T;
    }
    if (t == _i1.UserSettingsConfig) {
      return _i1.UserSettingsConfig.fromJson(data) as T;
    }
    if (t == _i1.EmailAuth) {
      return _i1.EmailAuth.fromJson(data) as T;
    }
    if (t == List<_i2.Feed>) {
      return (data as List).map((e) => deserialize<_i2.Feed>(e)).toList() as T;
    }
    if (t == List<_i3.Article>) {
      return (data as List).map((e) => deserialize<_i3.Article>(e)).toList() as T;
    }
    if (t == List<_i4.Folder>) {
      return (data as List).map((e) => deserialize<_i4.Folder>(e)).toList() as T;
    }
    if (t == Map<String, dynamic>) {
      return (data as Map).cast<String, dynamic>() as T;
    }
    try {
      return _i1.Protocol().deserialize<T>(data, t);
    } catch (_) {}
    return super.deserialize<T>(data, t);
  }

  @override
  String? getClassNameForObject(Object data) {
    if (data is _i2.Feed) {
      return 'Feed';
    }
    if (data is _i3.Article) {
      return 'Article';
    }
    if (data is _i4.Folder) {
      return 'Folder';
    }
    if (data is _i5.UserSettings) {
      return 'UserSettings';
    }
    if (data is _i6.SyncChange) {
      return 'SyncChange';
    }
    if (data is _i7.SharedFolder) {
      return 'SharedFolder';
    }
    if (data is _i8.FeedGenerationRule) {
      return 'FeedGenerationRule';
    }
    if (data is _i9.AIAnalysis) {
      return 'AIAnalysis';
    }
    if (data is _i10.MarketData) {
      return 'MarketData';
    }
    return super.getClassNameForObject(data);
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    if (data['className'] == 'Feed') {
      return deserialize<_i2.Feed>(data['data']);
    }
    if (data['className'] == 'Article') {
      return deserialize<_i3.Article>(data['data']);
    }
    if (data['className'] == 'Folder') {
      return deserialize<_i4.Folder>(data['data']);
    }
    if (data['className'] == 'UserSettings') {
      return deserialize<_i5.UserSettings>(data['data']);
    }
    if (data['className'] == 'SyncChange') {
      return deserialize<_i6.SyncChange>(data['data']);
    }
    if (data['className'] == 'SharedFolder') {
      return deserialize<_i7.SharedFolder>(data['data']);
    }
    if (data['className'] == 'FeedGenerationRule') {
      return deserialize<_i8.FeedGenerationRule>(data['data']);
    }
    if (data['className'] == 'AIAnalysis') {
      return deserialize<_i9.AIAnalysis>(data['data']);
    }
    if (data['className'] == 'MarketData') {
      return deserialize<_i10.MarketData>(data['data']);
    }
    return super.deserializeByClassName(data);
  }
}

/* AUTOMATICALLY GENERATED CODE */

typedef _i1 = auth;
typedef _i2 = Feed;
typedef _i3 = Article;
typedef _i4 = Folder;
typedef _i5 = UserSettings;
typedef _i6 = SyncChange;
typedef _i7 = SharedFolder;
typedef _i8 = FeedGenerationRule;
typedef _i9 = AIAnalysis;
typedef _i10 = MarketData;