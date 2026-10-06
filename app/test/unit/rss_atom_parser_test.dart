import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/parsers/atom_parser.dart';
import 'package:rss_glassmorphism_reader/core/parsers/rss_parser.dart';
import 'package:rss_glassmorphism_reader/services/feed_parser_service.dart';

typedef _Handler = ResponseBody Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final _Handler handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future? cancelFuture) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioFor(String body) {
  return Dio()..httpClientAdapter = _FakeAdapter((o) {
      return ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: ['application/atom+xml'],
      });
    });
}

const _feedUrl = 'https://example.com/blog/feed.xml';

const _atomWithOffsets = '''
<feed xmlns="http://www.w3.org/2005/Atom">
<title>Parity</title>
<link rel="alternate" href="https://example.com/"/>
<entry><title>Offset entry</title><id>e1</id>
<link rel="alternate" href="/posts/1"/>
<published>2026-10-04T12:00:00+02:00</published>
<updated>2026-10-05T08:30:00-05:00</updated></entry>
</feed>
''';

void main() {
  test('B05: AtomParser and FeedParserService agree on UTC instants',
      () async {
    final articles = await AtomParser()
        .parseArticles(_atomWithOffsets, 'feed-1', feedUrl: _feedUrl);
    final service = FeedParserService(dio: _dioFor(_atomWithOffsets));
    final parsed = await service.parseFeed(_feedUrl);

    expect(articles, hasLength(1));
    expect(parsed.items, hasLength(1));
    expect(
      parsed.items.first.publishedAt!.toUtc(),
      articles.first.publishedAt!.toUtc(),
      reason: 'both parser paths must normalize offsets to the same '
          'UTC instant',
    );
    expect(parsed.items.first.publishedAt!.toUtc(),
        DateTime.utc(2026, 10, 4, 10, 0, 0));
  });

  test('B05: Atom fallback dates without offsets stay usable', () async {
    const atom = '''
<feed xmlns="http://www.w3.org/2005/Atom">
<title>Fallback</title>
<entry><title>E</title><id>e1</id>
<updated>2026-10-04T12:00:00</updated></entry>
</feed>
''';
    final articles =
        await AtomParser().parseArticles(atom, 'feed-1', feedUrl: _feedUrl);
    expect(articles.first.publishedAt, isNotNull);
  });

  test('B06: RSS resolves relative enclosure and image URLs', () async {
    const rss = '''
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"
     xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel><title>Podcast</title><link>https://example.com/</link>
<image><url>/channel-art.png</url></image>
<itunes:image href="/cover.jpg"/>
<item><title>Episode 1</title><guid>g1</guid>
<link>/episodes/1</link>
<enclosure url="audio/ep1.mp3" type="audio/mpeg" length="1234"/>
<media:content medium="image" url="media/pic.jpg"/>
<description>&lt;img src="images/in-desc.jpg"&gt;</description>
</item></channel></rss>
''';

    final feed = await RssParser().parseFeed(rss, _feedUrl);
    expect(feed.imageUrl, 'https://example.com/channel-art.png');

    final articles =
        await RssParser().parseArticles(rss, 'feed-1', feedUrl: _feedUrl);
    final article = articles.single;
    expect(article.url, 'https://example.com/episodes/1');
    expect(article.imageUrl, 'https://example.com/blog/media/pic.jpg',
        reason: 'relative media image must resolve against the feed URL');
    expect(article.enclosures, isNotNull);
    expect(article.enclosures!.first.url,
        'https://example.com/blog/audio/ep1.mp3',
        reason: 'relative enclosure URLs must resolve for playback');
  });

  test('B06: RSS media:thumbnail and content images resolve', () async {
    const rss = '''
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
<channel><title>T</title><link>https://example.com/</link>
<item><title>Thumb</title><guid>g1</guid>
<media:thumbnail url="thumbs/1.jpg"/>
</item>
<item><title>Content image</title><guid>g2</guid>
<description>&lt;img src="imgs/2.jpg"&gt;</description>
</item></channel></rss>
''';

    final articles =
        await RssParser().parseArticles(rss, 'feed-1', feedUrl: _feedUrl);
    expect(articles[0].imageUrl, 'https://example.com/blog/thumbs/1.jpg');
    expect(articles[1].imageUrl, 'https://example.com/blog/imgs/2.jpg');
  });

  test('B06: Atom resolves relative enclosure, logo, and image URLs',
      () async {
    const atom = '''
<feed xmlns="http://www.w3.org/2005/Atom">
<title>Media</title>
<logo>/logo.png</logo>
<entry><title>E</title><id>e1</id>
<link rel="enclosure" href="files/ep1.mp3" type="audio/mpeg" length="99"/>
<content type="html">&lt;img src="pics/1.jpg"&gt;</content>
</entry></feed>
''';

    final feed = await AtomParser().parseFeed(atom, _feedUrl);
    expect(feed.imageUrl, 'https://example.com/logo.png');

    final articles =
        await AtomParser().parseArticles(atom, 'feed-1', feedUrl: _feedUrl);
    final article = articles.single;
    expect(article.enclosures!.single.url,
        'https://example.com/blog/files/ep1.mp3');
    expect(article.imageUrl, 'https://example.com/blog/pics/1.jpg');
  });

  test('B06: absolute URLs survive resolution unchanged', () async {
    const rss = '''
<rss version="2.0"><channel><title>T</title><link>https://example.com/</link>
<item><title>A</title><guid>g1</guid>
<enclosure url="https://cdn.example.com/ep1.mp3" type="audio/mpeg"/>
</item></channel></rss>
''';

    final articles =
        await RssParser().parseArticles(rss, 'feed-1', feedUrl: _feedUrl);
    expect(articles.single.enclosures!.single.url,
        'https://cdn.example.com/ep1.mp3');
  });
}
