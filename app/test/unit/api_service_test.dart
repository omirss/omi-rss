import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/config/api_config.dart';
import 'package:rss_glassmorphism_reader/core/models/article.dart';
import 'package:rss_glassmorphism_reader/providers/auth_provider.dart';
import 'package:rss_glassmorphism_reader/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<HttpServer> _jsonServer(Object? Function() body,
    {Duration delay = Duration.zero}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body()));
    await response.close();
  });
  return server;
}

String _base(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

void main() {
  test('B11: malformed refresh payloads throw ApiException, never TypeError',
      () async {
    final server = await _jsonServer(() => <String, dynamic>{});
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues(
        {'access_token': 'old', 'refresh_token': 'r'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);

    await expectLater(
      api.refreshTokensSingleFlight('r', _base(server)),
      throwsA(isA<ApiException>()),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), 'old',
        reason: 'a malformed payload must never be written to prefs');
  });

  test('B11: wrong-typed token field is rejected', () async {
    final server = await _jsonServer(() => {'token': 123});
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues(
        {'access_token': 'old', 'refresh_token': 'r'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);

    await expectLater(
      api.refreshTokensSingleFlight('r', _base(server)),
      throwsA(isA<ApiException>()),
    );
  });

  test('B11: non-map 200 response is rejected as a typed error', () async {
    final server = await _jsonServer(() => [1, 2, 3]);
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues(
        {'access_token': 'old', 'refresh_token': 'r'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);

    await expectLater(
      api.refreshTokensSingleFlight('r', _base(server)),
      throwsA(isA<ApiException>()),
    );
  });

  test('B12: single-flight is keyed by refresh token and base URL',
      () async {
    var hitsA = 0;
    var hitsB = 0;
    final serverA = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(serverA.close);
    serverA.listen((request) async {
      hitsA++;
      final response = request.response;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(
          {'token': 'token-a', 'refreshToken': 'r'}));
      await response.close();
    });
    final serverB = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(serverB.close);
    serverB.listen((request) async {
      hitsB++;
      final response = request.response;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(
          {'token': 'token-b', 'refreshToken': 'r'}));
      await response.close();
    });

    SharedPreferences.setMockInitialValues(
        {'access_token': 'old', 'refresh_token': 'r'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);

    final f1 = api.refreshTokensSingleFlight('r', _base(serverA));
    // Same key: joins the in-flight refresh instead of starting a new one.
    final f2 = api.refreshTokensSingleFlight('r', _base(serverA));
    expect(identical(f1, f2), isTrue);

    // Different refresh token and different origin each start their own.
    final f3 = api.refreshTokensSingleFlight('r2', _base(serverA));
    final f4 = api.refreshTokensSingleFlight('r', _base(serverB));
    expect(identical(f1, f3), isFalse);
    expect(identical(f1, f4), isFalse);

    await Future.wait([f1, f2, f3, f4]);

    expect(hitsA, 2, reason: 'same-key callers share one request');
    expect(hitsB, 1);
    expect((await f1)!['token'], 'token-a');
    expect((await f4)!['token'], 'token-b',
        reason: 'a caller must never receive another origin\'s tokens');
  });

  test('B12: rotation invalidates an in-flight refresh for new callers',
      () async {
    final server = await _jsonServer(
        () => {'token': 'token-x', 'refreshToken': 'r'},
        delay: const Duration(milliseconds: 150));
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues(
        {'access_token': 'old', 'refresh_token': 'r'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);

    final f1 = api.refreshTokensSingleFlight('r', _base(server));
    api.rotateAuthSession();
    final f2 = api.refreshTokensSingleFlight('r', _base(server));
    expect(identical(f1, f2), isFalse,
        reason: 'a new generation must not join the stale flight');

    await Future.wait([f1, f2]);
    // The stale flight's result is discarded (null) after rotation.
    expect(await f1, isNull);
  });

  test('C17: nested server folders are flattened with parents first',
      () async {
    final server = await _jsonServer(() => {
          'folders': [
            {
              'id': 'root',
              'name': 'Root',
              'parentId': null,
              'children': [
                {
                  'id': 'child',
                  'name': 'Child',
                  'parentId': 'root',
                  'children': [
                    {
                      'id': 'grandchild',
                      'name': 'Grandchild',
                      'parentId': 'child',
                      'children': const <dynamic>[],
                    },
                  ],
                },
              ],
            },
          ],
        });
    addTearDown(server.close);

    SharedPreferences.setMockInitialValues(const {});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);
    api.updateBaseUrl(_base(server));

    final folders = await api.getFolders();
    expect(folders.map((f) => f.id).toList(),
        ['root', 'child', 'grandchild']);
    expect(folders[1].parentId, 'root');
    expect(folders[2].parentId, 'child');
  });

  test('C19: createFeed sends the configured interval and keeps the server value',
      () async {
    Map<String, dynamic>? captured;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      captured = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      final response = request.response;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({
        'feed': {
          'id': 'f1',
          'url': 'https://example.com/x',
          'title': 'T',
          'updateInterval': 120,
        },
      }));
      await response.close();
    });

    SharedPreferences.setMockInitialValues(const {});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);
    api.updateBaseUrl(_base(server));

    final feed = await api.createFeed('https://example.com/x',
        updateInterval: 120);
    expect(captured?['updateInterval'], 120,
        reason: 'the server must store the configured interval');
    expect(feed.updateFrequency, 120,
        reason: 'the persisted value comes from the server response');
  });

  test('C05: getArticlePage exposes pagination so sync can walk all pages',
      () async {
    final requests = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      requests.add(request.uri);
      final page = int.parse(request.uri.queryParameters['page'] ?? '1');
      final limit = int.parse(request.uri.queryParameters['limit'] ?? '20');
      final start = (page - 1) * limit;
      final slice = [for (var i = start; i < start + limit && i < 250; i++) i];
      final response = request.response;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({
        'articles': [
          for (final i in slice)
            {
              'id': 'a$i',
              'feedId': 'f1',
              'title': 'T$i',
              'url': 'https://example.com/$i',
            }
        ],
        'pagination': {
          'page': page,
          'limit': limit,
          'total': 250,
          'totalPages': (250 / limit).ceil(),
        },
      }));
      await response.close();
    });

    SharedPreferences.setMockInitialValues(const {});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);
    api.updateBaseUrl(_base(server));

    // Same walk syncFromServer performs.
    final articles = <Article>[];
    var page = 1;
    ArticlePage result;
    do {
      result = await api.getArticlePage(page: page, limit: 200);
      articles.addAll(result.articles);
      page++;
    } while (page <= result.totalPages);

    expect(articles, hasLength(250),
        reason: 'accounts beyond one page must fully converge');
    expect(result.totalPages, 2);
    expect(requests, hasLength(2));
    expect(requests.first.queryParameters['limit'], '200');
    expect(requests.last.queryParameters['page'], '2');
  });

  test('R4-03: Article.fromJson prefers the real guid over the URL fallback',
      () {
    final article = Article.fromJson({
      'id': 'a1',
      'feedId': 'f1',
      'guid': 'urn:uuid:real-publisher-guid',
      'title': 'T',
      'url': 'https://example.com/1',
    });
    expect(article.guid, 'urn:uuid:real-publisher-guid');
    expect(article.guid, isNot(article.url));

    final legacy = Article.fromJson({
      'id': 'a2',
      'feedId': 'f1',
      'title': 'T',
      'url': 'https://example.com/2',
    });
    expect(legacy.guid, 'https://example.com/2',
        reason: 'older servers without the guid field fall back to the URL');
  });

  test('R4-04: a stale 401 from the old origin triggers no refresh after a '
      'server switch', () async {
    var refreshHits = 0;
    final serverA = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(serverA.close);
    serverA.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/api/auth/refresh') {
        refreshHits++;
      }
      // The 401 lands only after the client has already switched origin.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final response = request.response;
      response.headers.contentType = ContentType.json;
      response.statusCode = 401;
      response.write(jsonEncode({'error': 'Token expired'}));
      await response.close();
    });

    await ApiConfig.setServerUrl(_base(serverA));
    addTearDown(() => ApiConfig.setServerUrl(''));
    SharedPreferences.setMockInitialValues(
        {'access_token': 'a-old', 'refresh_token': 'r-old'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);

    final stale = api.getArticles();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Switch origin while the request is in flight: the session (and
    // the dio base URL) rotate before the old origin answers.
    api.updateBaseUrl('http://127.0.0.1:9');
    await expectLater(stale, throwsA(isA<ApiException>()));

    expect(refreshHits, 0,
        reason: 'the captured origin/session snapshot is stale; the '
            'interceptor must surface the 401 instead of refreshing');
  });

  test('R4-04/R4-05: a refresh rejection racing a newer login never clears '
      'the newer session', () async {
    var loginHits = 0;
    var refreshHits = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    late StreamSubscription<HttpRequest> sub;
    sub = server.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (request.method == 'POST' && request.uri.path == '/api/auth/login') {
        loginHits++;
        response.write(jsonEncode({
          'token': 'token-new',
          'refreshToken': 'r-new',
          'user': {'id': 'u2', 'email': 'b@b.c', 'username': 'b'},
        }));
      } else if (request.method == 'POST' &&
          request.uri.path == '/api/auth/refresh') {
        refreshHits++;
        // Rejection arrives after the newer login completed.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        response.statusCode = 401;
        response.write(jsonEncode({'error': 'Invalid refresh token'}));
      } else {
        response.statusCode = 401;
        response.write(jsonEncode({'error': 'Token expired'}));
      }
      await response.close();
    });
    addTearDown(() async => sub.cancel());

    await ApiConfig.setServerUrl(_base(server));
    addTearDown(() => ApiConfig.setServerUrl(''));
    SharedPreferences.setMockInitialValues(
        {'access_token': 'a-old', 'refresh_token': 'r-old'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final api = container.read(apiServiceProvider);
    final auth = container.read(authProvider.notifier);

    // The stale request 401s immediately; its refresh is still pending
    // when the newer login lands and rotates the session.
    final stale = api.getArticles();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await auth.login(emailOrUsername: 'b', password: 'pw');
    await expectLater(stale, throwsA(isA<ApiException>()));

    expect(refreshHits, 1);
    expect(loginHits, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), 'token-new',
        reason: 'an old rejected refresh must not clear the newer login');
    expect(prefs.getString('refresh_token'), 'r-new');
    expect(container.read(authProvider).isAuthenticated, isTrue);
  });
}
