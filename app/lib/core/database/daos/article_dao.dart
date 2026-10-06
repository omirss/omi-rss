import 'dart:convert';
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/articles_table.dart';
import '../../models/article.dart';

part 'article_dao.g.dart';

/// Data Access Object for articles
/// Public API works with the Article model; conversion to/from drift entries
/// happens internally.
@DriftAccessor(tables: [ArticlesTable])
class ArticleDao extends DatabaseAccessor<AppDatabase> with _$ArticleDaoMixin {
  ArticleDao(AppDatabase db) : super(db);

  /// Get all articles
  Future<List<Article>> getAllArticles() async {
    final rows = await _orderedArticles().get();
    return rows.map(_toModel).toList();
  }

  /// Watch all articles
  Stream<List<Article>> watchAllArticles() {
    return _orderedArticles()
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Get unread articles
  Future<List<Article>> getUnreadArticles() async {
    final rows = await _orderedArticles(
      where: (a) => a.isRead.equals(false),
    ).get();
    return rows.map(_toModel).toList();
  }

  /// Watch unread articles
  Stream<List<Article>> watchUnreadArticles() {
    return _orderedArticles(where: (a) => a.isRead.equals(false))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Get read articles
  Future<List<Article>> getReadArticles() async {
    final rows = await _orderedArticles(
      where: (a) => a.isRead.equals(true),
    ).get();
    return rows.map(_toModel).toList();
  }

  /// Watch starred articles
  Stream<List<Article>> watchStarredArticles() {
    return _orderedArticles(where: (a) => a.isStarred.equals(true))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Get article by ID
  Future<Article?> getArticle(String id) async {
    final row = await (select(articlesTable)..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Get articles by feed
  Future<List<Article>> getArticlesByFeed(String feedId) async {
    final rows = await _orderedArticles(
      where: (a) => a.feedId.equals(feedId),
    ).get();
    return rows.map(_toModel).toList();
  }

  /// Watch articles by feed
  Stream<List<Article>> watchArticlesByFeed(String feedId) {
    return _orderedArticles(where: (a) => a.feedId.equals(feedId))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Watch articles by category
  Stream<List<Article>> watchArticlesByCategory(String categoryId) {
    return _orderedArticles(
      where: (a) => a.feedId.isInQuery(
        selectOnly(feedsTable)
          ..addColumns([feedsTable.id])
          ..where(feedsTable.categoryId.equals(categoryId)),
      ),
    )
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Watch articles by folder
  Stream<List<Article>> watchArticlesByFolder(String folderId) {
    return _orderedArticles(
      where: (a) => a.feedId.isInQuery(
        selectOnly(attachedDatabase.folderFeedsTable)
          ..addColumns([attachedDatabase.folderFeedsTable.feedId])
          ..where(attachedDatabase.folderFeedsTable.folderId.equals(folderId)),
      ),
    )
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Get articles published after a date
  Future<List<Article>> getArticlesAfter(DateTime after) async {
    final rows = await _orderedArticles(
      where: (a) => a.publishedAt.isBiggerOrEqualValue(after),
    ).get();
    return rows.map(_toModel).toList();
  }

  /// Search articles (watchable)
  Stream<List<Article>> searchArticles(String query) {
    final searchQuery = '%$query%';
    return _orderedArticles(
      where: (a) =>
          a.title.like(searchQuery) |
          a.content.like(searchQuery) |
          a.summary.like(searchQuery),
    )
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Insert articles
  Future<void> insertArticles(List<Article> articles) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(
          articlesTable, articles.map(_toEntry).toList());
    });
  }

  /// Insert or update a single article
  Future<void> insertOrUpdateArticle(Article article) async {
    await into(articlesTable).insertOnConflictUpdate(_toEntry(article));
  }

  /// Upsert publisher-owned content. New articles insert as-is; for an
  /// existing article (same feed + guid) publisher fields are refreshed
  /// while client-owned state (read/starred/archived, full-content
  /// cache, AI fields) is preserved.
  Future<void> upsertPublisherArticles(List<Article> articles) async {
    await transaction(() async {
      for (final article in articles) {
        final existing = await (select(articlesTable)
              ..where((a) =>
                  a.feedId.equals(article.feedId) &
                  a.guid.equals(article.guid)))
            .getSingleOrNull();
        if (existing == null) {
          await into(articlesTable).insertOnConflictUpdate(_toEntry(article));
          continue;
        }
        await (update(articlesTable)..where((a) => a.id.equals(existing.id)))
            .write(ArticlesTableCompanion(
          title: Value(article.title),
          content: Value(article.content),
          summary: Value(article.summary),
          author: Value(article.author),
          // An undated refresh must not keep moving the article's
          // publication date: only a real publisher date overwrites.
          publishedAt: article.publishedAt == null
              ? const Value.absent()
              : Value(article.publishedAt),
          url: Value(article.url),
          imageUrl: Value(article.imageUrl),
          categories: Value(_encodeCategories(article.categories)),
          // Not every parser carries enclosures; a refresh without
          // enclosure data must not erase enclosures stored earlier.
          enclosures: article.enclosures == null
              ? const Value.absent()
              : Value(_encodeEnclosures(article.enclosures)),
          updatedAt: Value(DateTime.now()),
        ));
      }
    });
  }

  /// Upsert rows that arrived from the server. Server rows are keyed by
  /// the server's article id, but the schema also enforces
  /// UNIQUE(feed_id, guid): a locally-created row for the same item has
  /// a different id and must be reconciled, not blindly inserted.
  ///
  /// Matching by id AND by (feedId, guid), the surviving row is rekeyed
  /// to the canonical server id while client-owned state (read/starred,
  /// full-content cache, AI fields) is preserved. An article id that
  /// belongs to a different feed is rejected without partial writes.
  Future<void> upsertServerArticles(List<Article> incoming) {
    return transaction(() async {
      for (final server in incoming) {
        final byId = await (select(articlesTable)
              ..where((a) => a.id.equals(server.id)))
            .getSingleOrNull();
        final byGuid = await (select(articlesTable)
              ..where((a) =>
                  a.feedId.equals(server.feedId) &
                  a.guid.equals(server.guid)))
            .getSingleOrNull();

        if (byId != null && byId.feedId != server.feedId) {
          throw StateError(
              'Article ${server.id} belongs to another feed '
              '(${byId.feedId}, not ${server.feedId})');
        }

        final old = <Article>[
          if (byId != null) _toModel(byId),
          if (byGuid != null && byGuid.id != byId?.id) _toModel(byGuid),
        ];
        final rekeying = byGuid != null && byGuid.id != server.id;
        Article? cacheOwner;
        for (final row in old) {
          if (row.fullContent != null &&
              (cacheOwner == null ||
                  (row.fullContentFetchedAt ?? row.createdAt).isAfter(
                    cacheOwner.fullContentFetchedAt ?? cacheOwner.createdAt,
                  ))) {
            cacheOwner = row;
          }
        }
        final local = old.isEmpty ? null : old.first;
        final merged = server.copyWith(
          // One-time identity-merge policy on rekey: local read/star
          // state survives the id change. This is NOT durable two-way
          // read/star synchronization.
          isRead: server.isRead || (rekeying && old.any((a) => a.isRead)),
          isStarred:
              server.isStarred || (rekeying && old.any((a) => a.isStarred)),
          isArchived: server.isArchived || old.any((a) => a.isArchived),
          createdAt: local?.createdAt ?? server.createdAt,
          readTimeSeconds: local?.readTimeSeconds ?? server.readTimeSeconds,
          fullContent: cacheOwner?.fullContent ?? server.fullContent,
          fullContentFetchedAt:
              cacheOwner?.fullContentFetchedAt ?? server.fullContentFetchedAt,
          fullContentAvailable:
              cacheOwner != null ? true : server.fullContentAvailable,
          aiSummary: local?.aiSummary ?? server.aiSummary,
          aiTags: local?.aiTags ?? server.aiTags,
          perspectives: local?.perspectives ?? server.perspectives,
          sentimentScore: local?.sentimentScore ?? server.sentimentScore,
          biasScore: local?.biasScore ?? server.biasScore,
          customFields: local?.customFields ?? server.customFields,
          language: local?.language ?? server.language,
          rights: local?.rights ?? server.rights,
        );

        // Free the (feed_id, guid) unique key before writing the
        // canonical id. The schema has no child table referencing
        // article ids, so the delete cannot orphan anything.
        if (rekeying) {
          await (delete(articlesTable)..where((a) => a.id.equals(byGuid.id)))
              .go();
        }
        await into(articlesTable).insertOnConflictUpdate(_toEntry(merged));
      }
    });
  }

  /// Mark article as read
  Future<void> markAsRead(String articleId) {
    return (update(articlesTable)..where((a) => a.id.equals(articleId)))
      .write(ArticlesTableCompanion(
        isRead: const Value(true),
        updatedAt: Value(DateTime.now()),
      ));
  }

  /// Mark article as unread
  Future<void> markAsUnread(String articleId) {
    return (update(articlesTable)..where((a) => a.id.equals(articleId)))
      .write(ArticlesTableCompanion(
        isRead: const Value(false),
        updatedAt: Value(DateTime.now()),
      ));
  }

  /// Mark articles as read
  Future<void> markMultipleAsRead(List<String> articleIds) {
    return (update(articlesTable)..where((a) => a.id.isIn(articleIds)))
      .write(ArticlesTableCompanion(
        isRead: const Value(true),
        updatedAt: Value(DateTime.now()),
      ));
  }

  /// Mark all articles as read, optionally scoped to a feed
  Future<void> markAllAsRead({String? feedId}) {
    final query = update(articlesTable);
    if (feedId != null) {
      query.where((a) => a.feedId.equals(feedId));
    }
    return query.write(ArticlesTableCompanion(
      isRead: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Mark all articles in a feed as read
  Future<void> markFeedAsRead(String feedId) => markAllAsRead(feedId: feedId);

  /// Mark all articles in multiple feeds as read
  Future<void> markFeedsAsRead(List<String> feedIds) {
    return (update(articlesTable)..where((a) => a.feedId.isIn(feedIds)))
      .write(ArticlesTableCompanion(
        isRead: const Value(true),
        updatedAt: Value(DateTime.now()),
      ));
  }

  /// Set star status
  Future<void> setStarred(String articleId, bool starred) {
    return (update(articlesTable)..where((a) => a.id.equals(articleId)))
      .write(ArticlesTableCompanion(
        isStarred: Value(starred),
        updatedAt: Value(DateTime.now()),
      ));
  }

  /// Toggle star status
  Future<void> toggleStar(String articleId) async {
    final article = await getArticle(articleId);
    if (article != null) {
      await setStarred(articleId, !article.isStarred);
    }
  }

  /// Update article fields from a map of known keys
  Future<void> updateArticle(String articleId, Map<String, dynamic> changes) {
    bool? isRead;
    bool? isStarred;
    int? readTimeSeconds;
    String? title;
    String? content;
    String? summary;
    changes.forEach((key, value) {
      switch (key) {
        case 'isRead':
          isRead = value as bool;
          break;
        case 'isStarred':
          isStarred = value as bool;
          break;
        case 'readTimeSeconds':
        case 'estimatedReadTime':
          readTimeSeconds = value as int;
          break;
        case 'title':
          title = value as String;
          break;
        case 'content':
          content = value as String?;
          break;
        case 'summary':
          summary = value as String?;
          break;
      }
    });
    return (update(articlesTable)..where((a) => a.id.equals(articleId)))
        .write(ArticlesTableCompanion(
          isRead: isRead == null ? const Value.absent() : Value(isRead!),
          isStarred:
              isStarred == null ? const Value.absent() : Value(isStarred!),
          readTimeSeconds: readTimeSeconds == null
              ? const Value.absent()
              : Value(readTimeSeconds!),
          title: title == null ? const Value.absent() : Value(title!),
          content: content == null ? const Value.absent() : Value(content!),
          summary: summary == null ? const Value.absent() : Value(summary!),
          updatedAt: Value(DateTime.now()),
        ));
  }

  /// Update article with full content
  Future<void> updateArticleFullContent(
    String articleId,
    String fullContent,
  ) {
    return (update(articlesTable)..where((a) => a.id.equals(articleId)))
      .write(ArticlesTableCompanion(
        fullContent: Value(fullContent),
        fullContentFetchedAt: Value(DateTime.now()),
        fullContentAvailable: const Value(true),
        updatedAt: Value(DateTime.now()),
      ));
  }

  /// Delete article
  Future<int> deleteArticle(String articleId) {
    return (delete(articlesTable)..where((a) => a.id.equals(articleId))).go();
  }

  /// Delete multiple articles
  Future<int> deleteArticles(List<String> articleIds) {
    return (delete(articlesTable)..where((a) => a.id.isIn(articleIds))).go();
  }

  /// Delete old articles
  Future<int> deleteOldArticles(DateTime before, {bool keepStarred = true}) {
    var query = delete(articlesTable)
      ..where((a) => a.publishedAt.isSmallerThan(Variable(before)));

    if (keepStarred) {
      query.where((a) => a.isStarred.equals(false));
    }

    return query.go();
  }

  /// Enforce a retention cap: keep only the newest [limit] articles per
  /// feed (starred articles are always kept). Returns rows deleted.
  /// A non-positive limit would delete every unstarred article and is
  /// rejected outright.
  ///
  /// Ranking is total — `COALESCE(published_at, created_at)` with an id
  /// tiebreak — so undated articles are capped too, and Drift stream
  /// invalidation is declared so article watchers observe the deletions.
  Future<int> enforcePerFeedLimit(int limit) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be at least 1');
    }
    return customUpdate(
      '''
      DELETE FROM articles_table
      WHERE is_starred = 0
        AND id IN (
          SELECT id FROM (
            SELECT id,
                   ROW_NUMBER() OVER (
                     PARTITION BY feed_id
                     ORDER BY COALESCE(published_at, created_at) DESC, id DESC
                   ) AS position
            FROM articles_table
          ) AS ranked
          WHERE position > ?
        )
      ''',
      variables: [Variable.withInt(limit)],
      updates: {articlesTable},
      updateKind: UpdateKind.delete,
    );
  }

  /// Get unread count
  Future<int> getUnreadCount({String? feedId}) async {
    final query = selectOnly(articlesTable)
      ..addColumns([articlesTable.id.count()])
      ..where(articlesTable.isRead.equals(false));

    if (feedId != null) {
      query.where(articlesTable.feedId.equals(feedId));
    }

    return await query
        .map((row) => row.read(articlesTable.id.count())!)
        .getSingle();
  }

  /// Watch the total unread article count
  Stream<int> watchUnreadCount() {
    return _orderedArticles(where: (a) => a.isRead.equals(false))
        .watch()
        .map((rows) => rows.length);
  }

  /// Watch unread counts per folder id
  Stream<Map<String, int>> watchFolderUnreadCounts() {
    return customSelect(
      'SELECT ff.folder_id AS folder_id, COUNT(*) AS unread '
      'FROM articles_table a JOIN folder_feeds_table ff '
      'ON ff.feed_id = a.feed_id '
      'WHERE a.is_read = 0 GROUP BY ff.folder_id',
      readsFrom: {articlesTable, attachedDatabase.folderFeedsTable},
    )
        .watch()
        .map((rows) => {
              for (final row in rows)
                row.read<String>('folder_id'): row.read<int>('unread'),
            });
  }

  /// Get articles modified since a specific date (for sync)
  Future<List<Article>> getModifiedSince(DateTime? since) async {
    if (since == null) {
      return getAllArticles();
    }

    final rows = await (select(articlesTable)
          ..where((a) => a.updatedAt.isBiggerOrEqualValue(since)))
        .get();
    return rows.map(_toModel).toList();
  }

  static String? _encodeCategories(List<String>? categories) =>
      categories == null ? null : jsonEncode(categories);

  static String? _encodeEnclosures(List<Enclosure>? enclosures) =>
      enclosures == null
          ? null
          : jsonEncode(enclosures.map((e) => e.toJson()).toList());

  SimpleSelectStatement<$ArticlesTableTable, ArticleEntry> _orderedArticles(
      {Expression<bool> Function($ArticlesTableTable a)? where}) {
    final query = select(articlesTable);
    if (where != null) {
      query.where(where);
    }
    // Total ordering: undated articles fall back to created_at and the
    // id tiebreak keeps equal-timestamp groups deterministic (matching
    // the retention ranking).
    query.orderBy([
      (a) => OrderingTerm(
            expression: CustomExpression<DateTime>(
              'COALESCE(${a.publishedAt.name}, ${a.createdAt.name})',
            ),
            mode: OrderingMode.desc,
          ),
      (a) => OrderingTerm.desc(a.id),
    ]);
    return query;
  }

  Article _toModel(ArticleEntry e) {
    return Article(
      id: e.id,
      feedId: e.feedId,
      guid: e.guid,
      title: e.title,
      content: e.content,
      summary: e.summary,
      author: e.author,
      publishedAt: e.publishedAt,
      url: e.url,
      imageUrl: e.imageUrl,
      isRead: e.isRead,
      isStarred: e.isStarred,
      isArchived: e.isArchived,
      readTimeSeconds: e.readTimeSeconds,
      aiSummary: e.aiSummary,
      aiTags: e.aiTags != null
          ? (jsonDecode(e.aiTags!) as List<dynamic>).cast<String>()
          : null,
      perspectives: e.perspectivesJson != null
          ? Map<String, dynamic>.from(jsonDecode(e.perspectivesJson!)
              as Map<String, dynamic>)
          : null,
      sentimentScore: e.sentimentScore,
      biasScore: e.biasScore,
      categories: e.categories != null
          ? (jsonDecode(e.categories!) as List<dynamic>).cast<String>()
          : null,
      customFields: e.customFields != null
          ? jsonDecode(e.customFields!) as Map<String, dynamic>
          : null,
      language: e.language,
      rights: e.rights,
      fullContent: e.fullContent,
      fullContentFetchedAt: e.fullContentFetchedAt,
      fullContentAvailable: e.fullContentAvailable,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
      enclosures: e.enclosures != null
          ? (jsonDecode(e.enclosures!) as List<dynamic>)
              .map((x) =>
                  Enclosure.fromJson(Map<String, dynamic>.from(x as Map)))
              .toList()
          : null,
    );
  }

  ArticleEntry _toEntry(Article a) {
    return ArticleEntry(
      id: a.id,
      feedId: a.feedId,
      guid: a.guid,
      title: a.title,
      content: a.content,
      summary: a.summary,
      author: a.author,
      publishedAt: a.publishedAt,
      url: a.url,
      imageUrl: a.imageUrl,
      isRead: a.isRead,
      isStarred: a.isStarred,
      isArchived: a.isArchived,
      readTimeSeconds: a.readTimeSeconds,
      aiSummary: a.aiSummary,
      aiTags: a.aiTags != null ? jsonEncode(a.aiTags) : null,
      perspectivesJson:
          a.perspectives != null ? jsonEncode(a.perspectives) : null,
      sentimentScore: a.sentimentScore,
      biasScore: a.biasScore,
      categories: a.categories != null ? jsonEncode(a.categories) : null,
      customFields: a.customFields != null ? jsonEncode(a.customFields) : null,
      language: a.language,
      rights: a.rights,
      fullContent: a.fullContent,
      fullContentFetchedAt: a.fullContentFetchedAt,
      fullContentAvailable: a.fullContentAvailable,
      createdAt: a.createdAt,
      updatedAt: a.updatedAt,
      enclosures: a.enclosures != null
          ? jsonEncode(a.enclosures!.map((e) => e.toJson()).toList())
          : null,
    );
  }
}
