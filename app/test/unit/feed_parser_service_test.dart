import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/services/feed_parser_service.dart';

typedef _Handler = ResponseBody Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final _Handler handler;
  final List<Uri> requested = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future? cancelFuture) async {
    requested.add(options.uri);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

(_FakeAdapter, Dio) _dioFor(_Handler handler) {
  final adapter = _FakeAdapter(handler);
  return (
    adapter,
    Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ))..httpClientAdapter = adapter
  );
}

const _rssFeed = '''
<rss version="2.0"><channel>
<title>Example</title>
<link>/</link>
<item><title>One</title><link>/posts/1</link><guid>g1</guid>
<pubDate>Sun, 04 Oct 2026 16:00:00 -0700</pubDate></item>
</channel></rss>
''';

void main() {
  test('A06: HTML-heavy content with short visible text does not throw',
      () async {
    final content = '<span title="${'a' * 600}"><b>hi</b></span>';
    expect(content.length, greaterThan(500));

    final rss = '''
<rss version="2.0"><channel><title>T</title><link>https://example.com/</link>
<item><title>Heavy markup</title><guid>g1</guid>
<content:encoded><![CDATA[$content]]></content:encoded>
<pubDate>Sun, 04 Oct 2026 16:00:00 -0700</pubDate></item>
</channel></rss>
''';

    final (_, dio) = _dioFor((o) => ResponseBody.fromString(rss, 200,
        headers: {
          Headers.contentTypeHeader: ['application/xml'],
        }));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.xml');
    expect(feed.items, hasLength(1));
    expect(feed.items.first.description, 'hi');
  });

  test('A08: connection errors never fall back to third-party proxies',
      () async {
    final (adapter, dio) = _dioFor((o) => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
          message: 'connection refused',
        ));
    final service = FeedParserService(dio: dio);

    await expectLater(
      service.parseFeed('https://private.example/feed.xml'),
      throwsA(isA<FeedParseException>()),
    );

    expect(adapter.requested, hasLength(1),
        reason: 'only the original feed URL may be requested');
    expect(adapter.requested.first.toString(),
        'https://private.example/feed.xml');
  });

  test('A13: one malformed JSON Feed item does not abort the feed', () async {
    const json = '''
{
  "version": "https://jsonfeed.org/version/1.1",
  "title": "J",
  "items": [
    {"id": "1", "url": "https://example.com/1", "title": "one"},
    {"id": "2", "url": "https://example.com/2", "title": "two", "tags": "oops"},
    {"id": "3", "url": "https://example.com/3", "title": "three",
     "date_published": "definitely not a date"}
  ]
}
''';
    final (_, dio) = _dioFor((o) => ResponseBody.fromString(json, 200,
        headers: {
          Headers.contentTypeHeader: ['application/feed+json'],
        }));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.json');
    expect(feed.items, hasLength(2),
        reason: 'malformed-typed item must be skipped, siblings kept');
    expect(feed.items.map((i) => i.guid), unorderedEquals(['1', '3']));
    // The item with an unparsable date is kept as undated (null); the
    // database preserves its first-seen date instead of re-dating it
    // on every refresh.
    expect(feed.items.last.publishedAt, isNull);
  });

  test('A15: relative RSS links resolve against the feed URL', () async {
    final (_, dio) = _dioFor((o) => ResponseBody.fromString(_rssFeed, 200,
        headers: {
          Headers.contentTypeHeader: ['application/xml'],
        }));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/blog/feed.xml');
    expect(feed.siteUrl, 'https://example.com/');
    expect(feed.items.first.link, 'https://example.com/posts/1');
  });

  test('A15: relative Atom links resolve against the feed URL', () async {
    const atom = '''
<feed xmlns="http://www.w3.org/2005/Atom">
<title>A</title>
<link rel="alternate" href="../home"/>
<entry><title>E</title><id>e1</id>
<link rel="alternate" href="../posts/1"/></entry>
</feed>
''';
    final (_, dio) = _dioFor((o) => ResponseBody.fromString(atom, 200,
        headers: {
          Headers.contentTypeHeader: ['application/atom+xml'],
        }));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/blog/feed.xml');
    expect(feed.siteUrl, 'https://example.com/home');
    // '../posts/1' resolves against '/blog/feed.xml' -> '/posts/1'
    expect(feed.items.first.link, 'https://example.com/posts/1');
  });

  test('A20: oversized feed responses are rejected at the cap', () async {
    final items = List.filled(200000, '<item><title>x</title></item>').join();
    final huge = '<rss version="2.0"><channel><title>T</title>$items</channel></rss>';
    expect(huge.length, greaterThan(FeedParserService.maxFeedBytes));

    final (_, dio) = _dioFor((o) => ResponseBody(
          Stream.value(Uint8List.fromList(utf8.encode(huge))),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/xml'],
          },
        ));
    final service = FeedParserService(dio: dio);

    await expectLater(
      service.parseFeed('https://example.com/huge.xml'),
      throwsA(isA<FeedParseException>().having(
        (e) => e.message,
        'message',
        contains('exceeds'),
      )),
    );
  });

  test('A25: favicon lookup never contacts third-party services', () async {
    final (adapter, dio) =
        _dioFor((o) => ResponseBody.fromString('nope', 404));
    final service = FeedParserService(dio: dio);

    final favicon = await service.getFeedFavicon('https://example.com');
    expect(favicon, isNull,
        reason: 'no Google favicon fallback may be returned');
    expect(
      adapter.requested.every((u) => u.host == 'example.com'),
      isTrue,
      reason: 'only same-origin favicon paths may be probed',
    );
  });

  test('C12: ISO-8859-1 feeds decode via the declared header charset',
      () async {
    final rss = latin1.encode(
      '<rss version="2.0"><channel><title>Café</title>'
      '<link>https://example.com/</link>'
      '<item><title>Café au lait</title><guid>g1</guid>'
      '<link>https://example.com/1</link></item>'
      '</channel></rss>',
    );
    final (_, dio) = _dioFor((o) => ResponseBody.fromBytes(rss, 200,
        headers: {
          Headers.contentTypeHeader: [
            'application/rss+xml; charset=ISO-8859-1',
          ],
        }));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.xml');
    expect(feed.title, 'Café',
        reason: 'force-decoding latin1 bytes as UTF-8 corrupts the text');
    expect(feed.items.first.title, 'Café au lait');
  });

  test('C12: charset falls back to the XML declaration without a header '
      'charset', () async {
    final rss = latin1.encode(
      '<?xml version="1.0" encoding="ISO-8859-1"?>'
      '<rss version="2.0"><channel><title>Café</title>'
      '<link>https://example.com/</link>'
      '</channel></rss>',
    );
    final (_, dio) = _dioFor((o) => ResponseBody.fromBytes(rss, 200,
        headers: {
          Headers.contentTypeHeader: ['application/xml'],
        }));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.xml');
    expect(feed.title, 'Café');
  });

  test('C13: relative RSS item images resolve against the feed URL',
      () async {
    const rss = '''
<rss version="2.0"><channel><title>T</title>
<link>https://example.com/blog/</link>
<item><title>One</title><guid>g1</guid><link>/posts/1</link>
<content:encoded><![CDATA[<p><img src="../images/x.jpg"></p>]]></content:encoded>
</item>
</channel></rss>
''';
    final (_, dio) = _dioFor((o) => ResponseBody.fromString(rss, 200,
        headers: {
          Headers.contentTypeHeader: ['application/xml'],
        }));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/blog/feed.xml');
    expect(feed.items.first.thumbnail, 'https://example.com/images/x.jpg');
  });

  test('C13: relative Atom entry images resolve against the feed URL',
      () async {
    const atom = '''
<feed xmlns="http://www.w3.org/2005/Atom">
<title>A</title>
<link rel="alternate" href="https://example.com/"/>
<entry><title>E</title><id>e1</id>
<link rel="alternate" href="https://example.com/posts/1"/>
<content type="html">&lt;p&gt;&lt;img src="images/y.png"&gt;&lt;/p&gt;</content>
</entry>
</feed>
''';
    final (_, dio) = _dioFor((o) => ResponseBody.fromString(atom, 200,
        headers: {
          Headers.contentTypeHeader: ['application/atom+xml'],
        }));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/blog/feed.xml');
    expect(feed.items.first.thumbnail, 'https://example.com/blog/images/y.png');
  });

  ResponseBody byteResponse(
    List<int> bytes, {
    String contentType = 'application/xml',
  }) {
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  test('R4-08: a decoder failure rejects the parse future instead of '
      'hanging', () async {
    // Declared charset the decoder does not support: _decodeFeedBytes
    // throws inside the stream's onDone callback. The completer must
    // surface that error; awaiting parseFeed used to never resolve.
    final bytes = ascii.encode(
        '<rss version="1.0"?><rss version="2.0"><channel><title>T</title>'
        '<item><title>One</title><guid>g1</guid></item></channel></rss>');
    final (_, dio) = _dioFor((o) => byteResponse(bytes,
        contentType: 'application/xml; charset=iso-8859-5'));
    final service = FeedParserService(dio: dio);

    await expectLater(
      service.parseFeed('https://example.com/feed.xml').timeout(
        const Duration(seconds: 5),
      ),
      throwsA(isA<FeedParseException>()),
    );
  });

  test('R4-09: Windows-1252 high bytes decode to punctuation, not C1 '
      'controls', () async {
    final bytes = <int>[
      ...ascii.encode(
          '<rss version="2.0"><channel><title>T</title><item><title>It'),
      0x92, // cp1252 RIGHT SINGLE QUOTATION MARK
      ...ascii.encode(
          's</title><guid>g1</guid></item></channel></rss>'),
    ];
    final (_, dio) = _dioFor((o) => byteResponse(bytes,
        contentType: 'application/xml; charset=windows-1252'));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.xml');
    expect(feed.items.first.title, 'It’s');
  });

  test('R4-09: quoted charset parameters are honored', () async {
    const rss = '<rss version="2.0"><channel><title>T</title>'
        '<item><title>One</title><guid>g1</guid></item></channel></rss>';
    final (_, dio) = _dioFor((o) => byteResponse(ascii.encode(rss),
        contentType: 'application/xml; charset="utf-8"'));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.xml');
    expect(feed.items, hasLength(1));
  });

  test('R4-09: a UTF-8 BOM outranks a lying Content-Type charset',
      () async {
    const body = '<rss version="2.0"><channel><title>café</title>'
        '<item><title>One</title><guid>g1</guid></item></channel></rss>';
    final bytes = <int>[
      0xEF, 0xBB, 0xBF, // UTF-8 BOM
      ...utf8.encode(body),
    ];
    // The header claims latin-1; force-decoding the UTF-8 bytes as
    // latin-1 would corrupt "café" into "cafÃ©".
    final (_, dio) = _dioFor((o) => byteResponse(bytes,
        contentType: 'application/xml; charset=iso-8859-1'));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.xml');
    expect(feed.title, 'café');
  });

  test('R4-09: true ISO-8859-1 content still decodes as latin-1',
      () async {
    final bytes = <int>[
      ...ascii.encode(
          '<rss version="2.0"><channel><title>caf'),
      0xE9, // é in ISO-8859-1
      ...ascii.encode(
          '</title><item><title>One</title><guid>g1</guid></item>'
          '</channel></rss>'),
    ];
    final (_, dio) = _dioFor((o) => byteResponse(bytes,
        contentType: 'application/xml; charset=iso-8859-1'));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.xml');
    expect(feed.title, 'café');
  });

  test('R4-09: a UTF-16 BOM decodes the document instead of throwing',
      () async {
    const body = '<rss version="2.0"><channel><title>café</title>'
        '<item><title>One</title><guid>g1</guid></item></channel></rss>';
    // UTF-16LE with BOM: each code unit becomes two little-endian bytes.
    final units = body.codeUnits;
    final bytes = <int>[
      0xFF, 0xFE,
      for (final unit in units) ...[unit & 0xFF, (unit >> 8) & 0xFF],
    ];
    final (_, dio) = _dioFor((o) => byteResponse(bytes));
    final service = FeedParserService(dio: dio);

    final feed = await service.parseFeed('https://example.com/feed.xml');
    expect(feed.title, 'café');
    expect(feed.items, hasLength(1));
  });
}
