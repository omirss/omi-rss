import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../core/models/article.dart';
import '../../core/models/feed.dart';

abstract class ArticleExporter {
  Future<File> exportArticles(List<Article> articles, String outputPath);
  String get fileExtension;
  String get exportName;
}

class NotionExporter implements ArticleExporter {
  @override
  String get fileExtension => 'csv';
  
  @override
  String get exportName => 'Notion';
  
  @override
  Future<File> exportArticles(List<Article> articles, String outputPath) async {
    final buffer = StringBuffer();
    
    // Notion CSV header
    buffer.writeln('Title,URL,Author,Published Date,Tags,Content,Summary,Read Status,Starred');
    
    // Add articles
    for (final article in articles) {
      final row = [
        _escapeCsvField(article.title),
        _escapeCsvField(article.url),
        _escapeCsvField(article.author ?? ''),
        _formatDate(article.publishedAt),
        _escapeCsvField(article.categories.join('; ')),
        _escapeCsvField(_stripHtml(article.fullContent ?? article.content ?? '')),
        _escapeCsvField(article.summary ?? ''),
        article.isRead ? 'Read' : 'Unread',
        article.isStarred ? 'Yes' : 'No',
      ];
      
      buffer.writeln(row.join(','));
    }
    
    final file = File(outputPath);
    await file.writeAsString(buffer.toString());
    return file;
  }
  
  String _escapeCsvField(String field) {
    // Escape quotes and wrap in quotes if contains comma, newline, or quotes
    if (field.contains(',') || field.contains('\n') || field.contains('"')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }
  
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }
  
  String _stripHtml(String html) {
    // Basic HTML stripping
    return html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
  }
}

class ObsidianExporter implements ArticleExporter {
  @override
  String get fileExtension => 'md';
  
  @override
  String get exportName => 'Obsidian';
  
  @override
  Future<File> exportArticles(List<Article> articles, String outputPath) async {
    // For Obsidian, we'll create a directory with individual markdown files
    final directory = Directory(outputPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    // Create an index file
    final indexBuffer = StringBuffer();
    indexBuffer.writeln('# RSS Articles Export');
    indexBuffer.writeln('');
    indexBuffer.writeln('Exported on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    indexBuffer.writeln('');
    indexBuffer.writeln('## Articles');
    indexBuffer.writeln('');
    
    // Export each article as a separate markdown file
    for (final article in articles) {
      final filename = _sanitizeFilename(article.title);
      final filepath = '${directory.path}/$filename.md';
      
      await _exportSingleArticle(article, filepath);
      
      // Add to index
      indexBuffer.writeln('- [[${filename}]] - ${_formatDate(article.publishedAt)}');
    }
    
    // Save index file
    final indexFile = File('${directory.path}/README.md');
    await indexFile.writeAsString(indexBuffer.toString());
    
    return indexFile;
  }
  
  Future<void> _exportSingleArticle(Article article, String filepath) async {
    final buffer = StringBuffer();
    
    // Frontmatter
    buffer.writeln('---');
    buffer.writeln('title: "${article.title.replaceAll('"', '\\"')}"');
    buffer.writeln('url: ${article.url}');
    if (article.author != null) {
      buffer.writeln('author: ${article.author}');
    }
    if (article.publishedAt != null) {
      buffer.writeln('published: ${article.publishedAt!.toIso8601String()}');
    }
    buffer.writeln('tags: [${article.categories.map((c) => '"$c"').join(', ')}]');
    buffer.writeln('read: ${article.isRead}');
    buffer.writeln('starred: ${article.isStarred}');
    buffer.writeln('feed: ${article.feedTitle ?? 'Unknown'}');
    buffer.writeln('---');
    buffer.writeln('');
    
    // Title
    buffer.writeln('# ${article.title}');
    buffer.writeln('');
    
    // Metadata
    buffer.writeln('> **URL:** ${article.url}');
    if (article.author != null) {
      buffer.writeln('> **Author:** ${article.author}');
    }
    buffer.writeln('> **Published:** ${_formatDate(article.publishedAt)}');
    buffer.writeln('> **Feed:** ${article.feedTitle ?? 'Unknown'}');
    buffer.writeln('');
    
    // Tags
    if (article.categories.isNotEmpty) {
      buffer.writeln('## Tags');
      buffer.writeln('');
      for (final tag in article.categories) {
        buffer.writeln('#$tag ');
      }
      buffer.writeln('');
    }
    
    // Summary
    if (article.summary != null && article.summary!.isNotEmpty) {
      buffer.writeln('## Summary');
      buffer.writeln('');
      buffer.writeln(article.summary);
      buffer.writeln('');
    }
    
    // Content
    buffer.writeln('## Content');
    buffer.writeln('');
    final content = article.fullContent ?? article.content ?? 'No content available';
    buffer.writeln(_convertHtmlToMarkdown(content));
    buffer.writeln('');
    
    // Notes section
    buffer.writeln('## Notes');
    buffer.writeln('');
    buffer.writeln('<!-- Add your notes here -->');
    buffer.writeln('');
    
    // Links
    buffer.writeln('## Links');
    buffer.writeln('');
    buffer.writeln('- [Original Article](${article.url})');
    
    final file = File(filepath);
    await file.writeAsString(buffer.toString());
  }
  
  String _sanitizeFilename(String title) {
    // Remove invalid characters for filenames
    return title
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .substring(0, title.length > 100 ? 100 : title.length);
  }
  
  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown date';
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }
  
  String _convertHtmlToMarkdown(String html) {
    // Basic HTML to Markdown conversion
    String markdown = html;
    
    // Headers
    markdown = markdown.replaceAllMapped(
      RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false),
      (match) => '# ${match.group(1)}\n\n'
    );
    markdown = markdown.replaceAllMapped(
      RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false),
      (match) => '## ${match.group(1)}\n\n'
    );
    markdown = markdown.replaceAllMapped(
      RegExp(r'<h3[^>]*>(.*?)</h3>', caseSensitive: false),
      (match) => '### ${match.group(1)}\n\n'
    );
    
    // Bold and italic
    markdown = markdown.replaceAllMapped(
      RegExp(r'<strong[^>]*>(.*?)</strong>', caseSensitive: false),
      (match) => '**${match.group(1)}**'
    );
    markdown = markdown.replaceAllMapped(
      RegExp(r'<b[^>]*>(.*?)</b>', caseSensitive: false),
      (match) => '**${match.group(1)}**'
    );
    markdown = markdown.replaceAllMapped(
      RegExp(r'<em[^>]*>(.*?)</em>', caseSensitive: false),
      (match) => '*${match.group(1)}*'
    );
    markdown = markdown.replaceAllMapped(
      RegExp(r'<i[^>]*>(.*?)</i>', caseSensitive: false),
      (match) => '*${match.group(1)}*'
    );
    
    // Links
    markdown = markdown.replaceAllMapped(
      RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>', caseSensitive: false),
      (match) => '[${match.group(2)}](${match.group(1)})'
    );
    
    // Images
    markdown = markdown.replaceAllMapped(
      RegExp(r'<img[^>]+src="([^"]+)"[^>]*alt="([^"]*)"[^>]*>', caseSensitive: false),
      (match) => '![${match.group(2)}](${match.group(1)})'
    );
    
    // Lists
    markdown = markdown.replaceAllMapped(
      RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false),
      (match) => '- ${match.group(1)}\n'
    );
    
    // Paragraphs
    markdown = markdown.replaceAllMapped(
      RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false),
      (match) => '${match.group(1)}\n\n'
    );
    
    // Blockquotes
    markdown = markdown.replaceAllMapped(
      RegExp(r'<blockquote[^>]*>(.*?)</blockquote>', caseSensitive: false),
      (match) => '> ${match.group(1)?.replaceAll('\n', '\n> ')}\n\n'
    );
    
    // Code blocks
    markdown = markdown.replaceAllMapped(
      RegExp(r'<pre[^>]*><code[^>]*>(.*?)</code></pre>', caseSensitive: false),
      (match) => '```\n${match.group(1)}\n```\n\n'
    );
    
    // Inline code
    markdown = markdown.replaceAllMapped(
      RegExp(r'<code[^>]*>(.*?)</code>', caseSensitive: false),
      (match) => '`${match.group(1)}`'
    );
    
    // Line breaks
    markdown = markdown.replaceAll('<br>', '\n');
    markdown = markdown.replaceAll('<br/>', '\n');
    markdown = markdown.replaceAll('<br />', '\n');
    
    // Remove remaining HTML tags
    markdown = markdown.replaceAll(RegExp(r'<[^>]*>'), '');
    
    // HTML entities
    markdown = markdown
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–');
    
    // Clean up excessive newlines
    markdown = markdown.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    return markdown.trim();
  }
}

class ExportService {
  final NotionExporter notionExporter;
  final ObsidianExporter obsidianExporter;
  
  ExportService({
    NotionExporter? notionExporter,
    ObsidianExporter? obsidianExporter,
  }) : notionExporter = notionExporter ?? NotionExporter(),
       obsidianExporter = obsidianExporter ?? ObsidianExporter();
  
  Future<File> exportToNotion(List<Article> articles, String outputPath) async {
    return await notionExporter.exportArticles(articles, outputPath);
  }
  
  Future<File> exportToObsidian(List<Article> articles, String outputPath) async {
    return await obsidianExporter.exportArticles(articles, outputPath);
  }
  
  // Export feeds with their articles
  Future<void> exportFeedsToObsidian(
    Map<Feed, List<Article>> feedsWithArticles, 
    String outputPath,
  ) async {
    final directory = Directory(outputPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    // Create main index
    final indexBuffer = StringBuffer();
    indexBuffer.writeln('# RSS Feeds Export');
    indexBuffer.writeln('');
    indexBuffer.writeln('Exported on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    indexBuffer.writeln('');
    indexBuffer.writeln('## Feeds');
    indexBuffer.writeln('');
    
    // Export each feed
    for (final entry in feedsWithArticles.entries) {
      final feed = entry.key;
      final articles = entry.value;
      
      final feedDirName = _sanitizeFilename(feed.title);
      final feedDir = Directory('${directory.path}/$feedDirName');
      if (!await feedDir.exists()) {
        await feedDir.create();
      }
      
      // Export articles for this feed
      await obsidianExporter.exportArticles(articles, feedDir.path);
      
      // Add to main index
      indexBuffer.writeln('- [[${feedDirName}/README|${feed.title}]] (${articles.length} articles)');
    }
    
    // Save main index
    final mainIndex = File('${directory.path}/README.md');
    await mainIndex.writeAsString(indexBuffer.toString());
  }
  
  String _sanitizeFilename(String name) {
    return name
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .substring(0, name.length > 50 ? 50 : name.length);
  }
}