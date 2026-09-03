import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/article.dart';
import '../core/database/database.dart';
import 'database_provider.dart';

// Article actions provider
final articleActionsProvider = Provider<ArticleActions>((ref) {
  return ArticleActions(ref);
});

class ArticleActions {
  final Ref ref;
  
  ArticleActions(this.ref);
  
  Future<void> toggleStarred(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);
    
    if (article != null) {
      final updatedArticle = article.copyWith(
        isStarred: !article.isStarred,
      );
      await database.articleDao.updateArticle(updatedArticle);
    }
  }
  
  Future<void> markAsRead(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);
    
    if (article != null && !article.isRead) {
      final updatedArticle = article.copyWith(
        isRead: true,
      );
      await database.articleDao.updateArticle(updatedArticle);
    }
  }
  
  Future<void> markAsUnread(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);
    
    if (article != null && article.isRead) {
      final updatedArticle = article.copyWith(
        isRead: false,
      );
      await database.articleDao.updateArticle(updatedArticle);
    }
  }
  
  Future<void> toggleRead(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);
    
    if (article != null) {
      final updatedArticle = article.copyWith(
        isRead: !article.isRead,
      );
      await database.articleDao.updateArticle(updatedArticle);
    }
  }
  
  Future<void> archiveArticle(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);
    
    if (article != null) {
      final updatedArticle = article.copyWith(
        isArchived: true,
      );
      await database.articleDao.updateArticle(updatedArticle);
    }
  }
  
  Future<void> unarchiveArticle(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);
    
    if (article != null) {
      final updatedArticle = article.copyWith(
        isArchived: false,
      );
      await database.articleDao.updateArticle(updatedArticle);
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
  }
}