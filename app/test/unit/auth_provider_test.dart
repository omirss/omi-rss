import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/models/user.dart';
import 'package:rss_glassmorphism_reader/providers/auth_provider.dart';
import 'package:rss_glassmorphism_reader/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiService extends ApiService {
  _FakeApiService(super.ref, {this.currentUserError, this.refreshError});

  final Object? currentUserError;
  final Object? refreshError;

  @override
  Future<User> getCurrentUser() async {
    if (currentUserError != null) throw currentUserError!;
    return User(id: 'u1', email: 'a@b.c', username: 'a');
  }

  @override
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    if (refreshError != null) throw refreshError!;
    return {'token': 'new-access'};
  }

  @override
  Future<Map<String, dynamic>> login(
      String emailOrUsername, String password) async {
    throw const ApiException('Login failed', statusCode: 503);
  }
}

Future<ProviderContainer> _container({
  Map<String, Object> prefs = const {},
  Object? currentUserError,
  Object? refreshError,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWith((ref) => _FakeApiService(
          ref,
          currentUserError: currentUserError,
          refreshError: refreshError,
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
}
