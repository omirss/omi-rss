import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
