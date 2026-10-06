import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/models/user.dart';
import 'package:rss_glassmorphism_reader/providers/auth_provider.dart';
import 'package:rss_glassmorphism_reader/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiService extends ApiService {
  _FakeApiService(super.ref,
      {this.currentUserError,
      this.refreshError,
      this.loginResponse,
      this.currentUserGate});

  final Object? currentUserError;
  final Object? refreshError;
  final Map<String, dynamic>? loginResponse;
  final Future<User>? currentUserGate;

  @override
  Future<User> getCurrentUser() async {
    if (currentUserGate != null) return currentUserGate!;
    if (currentUserError != null) throw currentUserError!;
    return User(id: 'u1', email: 'a@b.c', username: 'a');
  }

  @override
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    if (refreshError != null) throw refreshError!;
    // Token-only payload, like the server's refresh response.
    return {'token': 'new-access'};
  }

  @override
  Future<Map<String, dynamic>> login(
      String emailOrUsername, String password) async {
    if (loginResponse != null) return loginResponse!;
    throw const ApiException('Login failed', statusCode: 503);
  }
}

/// First login stays pending until released; later logins answer from
/// [nextLogin].
class _GateLoginApiService extends ApiService {
  _GateLoginApiService(super.ref, this.firstLogin);

  final Future<Map<String, dynamic>> firstLogin;
  Future<Map<String, dynamic>>? nextLogin;

  @override
  Future<Map<String, dynamic>> login(
      String emailOrUsername, String password) {
    return nextLogin ?? firstLogin;
  }
}

/// Server-side logout hangs forever; the local session must still be
/// cleared promptly.
class _HangingLogoutApiService extends ApiService {
  _HangingLogoutApiService(super.ref);

  final Future<void> _never = Completer<void>().future;

  @override
  Future<User> getCurrentUser() async =>
      User(id: 'u1', email: 'a@b.c', username: 'a');

  @override
  Future<void> logoutWithToken(String token, String baseUrl) => _never;
}

Future<ProviderContainer> _container({
  Map<String, Object> prefs = const {},
  Object? currentUserError,
  Object? refreshError,
  Map<String, dynamic>? loginResponse,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWith((ref) => _FakeApiService(
          ref,
          currentUserError: currentUserError,
          refreshError: refreshError,
          loginResponse: loginResponse,
        )),
  ]);
  await SharedPreferences.getInstance();
  return container;
}

void main() {
  test('A11: copyWith(error: null) clears the error', () {
    final state = AuthState(isAuthenticated: true, error: 'bad');
    final cleared = state.copyWith(isLoading: true, error: null);
    expect(cleared.error, isNull);
    expect(cleared.isAuthenticated, isTrue);

    final kept = state.copyWith(isLoading: true);
    expect(kept.error, 'bad');
  });

  test('R4-05: a delayed restore completing after logout stays logged out',
      () async {
    final release = Completer<User>();
    SharedPreferences.setMockInitialValues(
        {'access_token': 't', 'refresh_token': 'r'});
    final container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWith((ref) => _FakeApiService(
            ref,
            currentUserGate: release.future,
          )),
    ]);
    await SharedPreferences.getInstance();
    addTearDown(container.dispose);
    container.read(authProvider.notifier);

    await pumpEventQueue();
    // Logout while the restore's getCurrentUser is still in flight.
    await container.read(authProvider.notifier).logout();
    release.complete(User(id: 'u1', email: 'a@b.c', username: 'a'));
    await pumpEventQueue();

    final state = container.read(authProvider);
    expect(state.isAuthenticated, isFalse,
        reason: 'an old network result must not resurrect a cleared session');
    expect(state.user, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);
  });

  test('R4-05: login A resolving after login B cannot overwrite B',
      () async {
    final releaseA = Completer<Map<String, dynamic>>();
    SharedPreferences.setMockInitialValues(const {});
    late final _GateLoginApiService gate;
    final container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWith(
          (ref) => gate = _GateLoginApiService(ref, releaseA.future)),
    ]);
    await SharedPreferences.getInstance();
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    final pendingA = notifier.login(emailOrUsername: 'a', password: 'pw');
    await pumpEventQueue();

    // Login B completes first and installs its session.
    gate.nextLogin = Future.value({
      'token': 'token-b',
      'refreshToken': 'r-b',
      'user': {'id': 'u2', 'email': 'b@b.c', 'username': 'b'},
    });
    await notifier.login(emailOrUsername: 'b', password: 'pw');
    expect(container.read(authProvider).token, 'token-b');

    // Login A's delayed response arrives last: it must be discarded.
    releaseA.complete({
      'token': 'token-a',
      'refreshToken': 'r-a',
      'user': {'id': 'u1', 'email': 'a@b.c', 'username': 'a'},
    });
    await expectLater(pendingA, completes);
    await pumpEventQueue();

    final state = container.read(authProvider);
    expect(state.token, 'token-b',
        reason: 'the newer login owns the session');
    expect(state.user!.id, 'u2');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), 'token-b');
    expect(prefs.getString('refresh_token'), 'r-b');
  });

  test('R4-05: logout clears locally without waiting for the server',
      () async {
    SharedPreferences.setMockInitialValues({
      'access_token': 't',
      'refresh_token': 'r',
      'auth_user': jsonEncode(
          {'id': 'u1', 'email': 'a@b.c', 'username': 'a'}),
    });
    final container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWith(_HangingLogoutApiService.new),
    ]);
    await SharedPreferences.getInstance();
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    await pumpEventQueue();
    expect(container.read(authProvider).isAuthenticated, isTrue);

    await notifier
        .logout()
        .timeout(const Duration(seconds: 2), onTimeout: () {
      fail('logout must not block on the server-side logout call');
    });

    expect(container.read(authProvider).isAuthenticated, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull);
  });

  test('R4-05: applyRotatedTokens publishes to state and auth headers',
      () async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'old',
      'auth_user': jsonEncode(
          {'id': 'u1', 'email': 'a@b.c', 'username': 'a'}),
    });
    final container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWith(_FakeApiService.new),
    ]);
    await SharedPreferences.getInstance();
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    await pumpEventQueue();
    expect(container.read(authProvider).isAuthenticated, isTrue);
    expect(
        notifier.getAuthHeaders(),
        containsPair('Authorization', 'Bearer old'));

    notifier.applyRotatedTokens(token: 'rotated', refreshToken: 'r2');
    expect(container.read(authProvider).token, 'rotated');
    expect(
        notifier.getAuthHeaders(),
        containsPair('Authorization', 'Bearer rotated'),
        reason: 'getAuthHeaders must observe interceptor rotations '
            'without a restart');
  });

  test('A05: calling login before initialization completes does not throw',
      () async {
    final container = await _container();
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    // No await on any init: this must not throw LateInitializationError.
    await expectLater(
      notifier.login(emailOrUsername: 'user', password: 'pw'),
      throwsA(isA<ApiException>()),
    );

    expect(container.read(authProvider).error, 'Login failed');
  });

  test('A10: transient refresh failure (503) keeps stored credentials',
      () async {
    final container = await _container(
      prefs: {'access_token': 'a', 'refresh_token': 'r'},
      currentUserError: const ApiException('server down', statusCode: 503),
      refreshError: const ApiException('still down', statusCode: 503),
    );
    addTearDown(container.dispose);

    container.read(authProvider.notifier);
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), 'a',
        reason: 'transient failures must not erase the session');
    expect(prefs.getString('refresh_token'), 'r');
    expect(container.read(authProvider).isAuthenticated, isFalse);
  });

  test('A10: rejected refresh (401) clears stored credentials', () async {
    final container = await _container(
      prefs: {'access_token': 'a', 'refresh_token': 'r'},
      currentUserError: const ApiException('expired', statusCode: 401),
      refreshError: const ApiException('rejected', statusCode: 401),
    );
    addTearDown(container.dispose);

    container.read(authProvider.notifier);
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);
  });

  test('A10: valid session is restored when the server answers', () async {
    final container = await _container(
      prefs: {'access_token': 'a', 'refresh_token': 'r'},
    );
    addTearDown(container.dispose);

    container.read(authProvider.notifier);
    await pumpEventQueue();

    expect(container.read(authProvider).isAuthenticated, isTrue);
    expect(container.read(authProvider).user?.id, 'u1');
  });

  test('C18: startup refresh keeps the cached user hydrated', () async {
    final user = User(id: 'cached', email: 'a@b.c', username: 'a');
    final container = await _container(
      prefs: {
        'access_token': 'expired',
        'refresh_token': 'r',
        'auth_user': jsonEncode(user.toJson()),
      },
      currentUserError: const ApiException('expired', statusCode: 401),
    );
    addTearDown(container.dispose);

    container.read(authProvider.notifier);
    await pumpEventQueue();

    final state = container.read(authProvider);
    expect(state.isAuthenticated, isTrue,
        reason: 'the refresh succeeded; the session must be live');
    expect(state.user?.id, 'cached',
        reason: 'a token-only refresh response must not clear the user');
    expect(state.token, 'new-access');
  });

  test('C21: malformed login response without a token throws', () async {
    final container = await _container(loginResponse: <String, dynamic>{});
    addTearDown(container.dispose);

    final notifier = container.read(authProvider.notifier);
    await expectLater(
      notifier.login(emailOrUsername: 'user', password: 'pw'),
      throwsA(isA<ApiException>()),
    );

    final state = container.read(authProvider);
    expect(state.isAuthenticated, isFalse);
    expect(state.error, contains('no token'));
  });
}
