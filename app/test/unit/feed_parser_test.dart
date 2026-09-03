import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/services/feed_parser_service.dart';

void main() {
  group('FeedParserService', () {
    late FeedParserService parser;
    
    setUp(() {
      parser = FeedParserService();
    });
    
    group('RSS 2.0 Parsing', () {
      test('should parse valid RSS 2.0 feed', () async {
        const rssContent = '''
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Test RSS Feed</title>
            <link>https://example.com</link>
            <description>Test RSS feed description</description>
            <item>
              <title>Test Article 1</title>
              <link>https://example.com/article1</link>
              <description>This is test article 1</description>
              <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
              <guid>https://example.com/article1</guid>
            </item>
            <item>
              <title>Test Article 2</title>
              <link>https://example.com/article2</link>
              <description>This is test article 2</description>
              <pubDate>Tue, 02 Jan 2024 12:00:00 GMT</pubDate>
              <guid>https://example.com/article2</guid>
            </item>
          </channel>
        </rss>
        ''';
        
        final result = await parser.parseFeed(rssContent, 'https://example.com/feed.xml');
        
        expect(result.isSuccess, true);
        expect(result.feed?.title, 'Test RSS Feed');
        expect(result.feed?.description, 'Test RSS feed description');
        expect(result.articles.length, 2);
        expect(result.articles[0].title, 'Test Article 1');
        expect(result.articles[1].title, 'Test Article 2');
      });
      
      test('should handle RSS feed without optional elements', () async {
        const rssContent = '''
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Minimal RSS Feed</title>
            <link>https://example.com</link>
            <item>
              <title>Article without description</title>
              <link>https://example.com/article</link>
            </item>
          </channel>
        </rss>
        ''';
        
        final result = await parser.parseFeed(rssContent, 'https://example.com/feed.xml');
        
        expect(result.isSuccess, true);
        expect(result.articles.length, 1);
        expect(result.articles[0].title, 'Article without description');
        expect(result.articles[0].summary, isEmpty);
      });
    });
    
    group('Atom Parsing', () {
      test('should parse valid Atom feed', () async {
        const atomContent = '''
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Test Atom Feed</title>
          <link href="https://example.com"/>
          <updated>2024-01-01T12:00:00Z</updated>
          <entry>
            <title>Test Entry 1</title>
            <link href="https://example.com/entry1"/>
            <id>https://example.com/entry1</id>
            <updated>2024-01-01T12:00:00Z</updated>
            <summary>This is test entry 1</summary>
          </entry>
          <entry>
            <title>Test Entry 2</title>
            <link href="https://example.com/entry2"/>
            <id>https://example.com/entry2</id>
            <updated>2024-01-02T12:00:00Z</updated>
            <content type="html">This is test entry 2 content</content>
          </entry>
        </feed>
        ''';
        
        final result = await parser.parseFeed(atomContent, 'https://example.com/atom.xml');
        
        expect(result.isSuccess, true);
        expect(result.feed?.title, 'Test Atom Feed');
        expect(result.articles.length, 2);
        expect(result.articles[0].title, 'Test Entry 1');
        expect(result.articles[1].title, 'Test Entry 2');
      });
    });
    
    group('JSON Feed Parsing', () {
      test('should parse valid JSON feed', () async {
        const jsonContent = '''
        {
          "version": "https://jsonfeed.org/version/1.1",
          "title": "Test JSON Feed",
          "home_page_url": "https://example.com",
          "feed_url": "https://example.com/feed.json",
          "description": "Test JSON feed description",
          "items": [
            {
              "id": "1",
              "title": "Test Item 1",
              "url": "https://example.com/item1",
              "content_text": "This is test item 1",
              "date_published": "2024-01-01T12:00:00Z"
            },
            {
              "id": "2",
              "title": "Test Item 2",
              "url": "https://example.com/item2",
              "content_html": "<p>This is test item 2</p>",
              "date_published": "2024-01-02T12:00:00Z"
            }
          ]
        }
        ''';
        
        final result = await parser.parseFeed(jsonContent, 'https://example.com/feed.json');
        
        expect(result.isSuccess, true);
        expect(result.feed?.title, 'Test JSON Feed');
        expect(result.feed?.description, 'Test JSON feed description');
        expect(result.articles.length, 2);
        expect(result.articles[0].title, 'Test Item 1');
        expect(result.articles[1].title, 'Test Item 2');
      });
    });
    
    group('Error Handling', () {
      test('should handle invalid XML', () async {
        const invalidXml = '<rss><channel><title>Unclosed tag';
        
        final result = await parser.parseFeed(invalidXml, 'https://example.com/feed.xml');
        
        expect(result.isSuccess, false);
        expect(result.error, isNotNull);
      });
      
      test('should handle invalid JSON', () async {
        const invalidJson = '{"title": "Missing closing brace"';
        
        final result = await parser.parseFeed(invalidJson, 'https://example.com/feed.json');
        
        expect(result.isSuccess, false);
        expect(result.error, isNotNull);
      });
      
      test('should handle empty content', () async {
        final result = await parser.parseFeed('', 'https://example.com/feed.xml');
        
        expect(result.isSuccess, false);
        expect(result.error, isNotNull);
      });
      
      test('should handle unsupported feed format', () async {
        const htmlContent = '<html><body>Not a feed</body></html>';
        
        final result = await parser.parseFeed(htmlContent, 'https://example.com/page.html');
        
        expect(result.isSuccess, false);
        expect(result.error, contains('Unsupported feed format'));
      });
    });
    
    group('Feed Type Detection', () {
      test('should detect RSS feed', () {
        const rssContent = '<?xml version="1.0"?><rss version="2.0">';
        expect(parser.detectFeedType(rssContent), FeedType.rss);
      });
      
      test('should detect Atom feed', () {
        const atomContent = '<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">';
        expect(parser.detectFeedType(atomContent), FeedType.atom);
      });
      
      test('should detect JSON feed', () {
        const jsonContent = '{"version": "https://jsonfeed.org/version/1.1"}';
        expect(parser.detectFeedType(jsonContent), FeedType.json);
      });
      
      test('should return unknown for unsupported content', () {
        const htmlContent = '<html><body>Not a feed</body></html>';
        expect(parser.detectFeedType(htmlContent), FeedType.unknown);
      });
    });
  });
}