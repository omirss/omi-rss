import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../core/models/article.dart';
import '../core/database/database.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'database_provider.dart';

// Article actions provider
final articleActionsProvider = Provider<ArticleActions>((ref) {
  return ArticleActions(ref);
});

class ArticleActions {
  final Ref ref;

  ArticleActions(this.ref);

  bool get _canSync =>
      ApiConfig.hasServer && ref.read(authProvider).isAuthenticated;

  void _syncState(String articleId, {bool? isRead, bool? isStarred}) {
    if (!_canSync) return;
    unawaited(() async {
      try {
        await ref
            .read(apiServiceProvider)
            .updateArticleState(articleId, isRead: isRead, isStarred: isStarred);
      } catch (e) {
        // Server sync is best-effort; local drift stays the source of truth
      }
    }());
  }

  void _syncMarkAllRead(String? feedId) {
    if (!_canSync) return;
    unawaited(() async {
      try {
        await ref.read(apiServiceProvider).markAllRead(feedId: feedId);
      } catch (e) {
        // Server sync is best-effort; local drift stays the source of truth
      }
    }());
  }

  Future<void> toggleStarred(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);

    if (article != null) {
      final updatedArticle = article.copyWith(
        isStarred: !article.isStarred,
      );
      await database.articleDao.insertOrUpdateArticle(updatedArticle);
      _syncState(articleId, isStarred: updatedArticle.isStarred);
    }
  }

  Future<void> markAsRead(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);

    if (article != null && !article.isRead) {
      final updatedArticle = article.copyWith(
        isRead: true,
      );
      await database.articleDao.insertOrUpdateArticle(updatedArticle);
      _syncState(articleId, isRead: true);
    }
  }

  Future<void> markAsUnread(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);

    if (article != null && article.isRead) {
      final updatedArticle = article.copyWith(
        isRead: false,
      );
      await database.articleDao.insertOrUpdateArticle(updatedArticle);
      _syncState(articleId, isRead: false);
    }
  }

  Future<void> toggleRead(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);

    if (article != null) {
      final updatedArticle = article.copyWith(
        isRead: !article.isRead,
      );
      await database.articleDao.insertOrUpdateArticle(updatedArticle);
      _syncState(articleId, isRead: updatedArticle.isRead);
    }
  }

  Future<void> archiveArticle(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);

    if (article != null) {
      final updatedArticle = article.copyWith(
        isArchived: true,
      );
      await database.articleDao.insertOrUpdateArticle(updatedArticle);
    }
  }

  Future<void> unarchiveArticle(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);

    if (article != null) {
      final updatedArticle = article.copyWith(
        isArchived: false,
      );
      await database.articleDao.insertOrUpdateArticle(updatedArticle);
    }
  }

  Future<void> deleteArticle(String articleId) async {
    final database = ref.read(databaseProvider);
    await database.articleDao.deleteArticle(articleId);
  }

  Future<void> markAllAsRead(String? feedId) async {
    final database = ref.read(databaseProvider);
    if (feedId != null) {
      await database.articleDao.markFeedAsRead(feedId);
    } else {
      await database.articleDao.markAllAsRead();
    }
    _syncMarkAllRead(feedId);
  }
}
