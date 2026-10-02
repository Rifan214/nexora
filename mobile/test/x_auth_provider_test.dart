import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/services/x_auth_service.dart';
import 'package:nexora/services/x_auth_storage.dart';

import 'x_auth_storage_test.dart';

class FakeXAuthService implements XAuthService {
  final Map<String, XAuthSession> _sessions = {};
  final Set<String> _deletedSessions = {};
  int createSessionCallCount = 0;
  bool failCreateSession = false;

  void addSession(XAuthSession session) {
    _sessions[session.sessionId] = session;
  }

  @override
  Future<XAuthSession> createSession(
      {required String authToken, required String ct0}) async {
    createSessionCallCount++;
    if (failCreateSession) {
      throw const ApiException('Failed to create session on upstream');
    }
    final session = XAuthSession(
      sessionId: 'created_session_123',
      source: 'user_session',
      status: 'available',
      authenticated: true,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    _sessions[session.sessionId] = session;
    return session;
  }

  @override
  Future<XAuthSession> getSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || _deletedSessions.contains(sessionId)) {
      throw const ApiException('Session not found (404)');
    }
    return session;
  }

  @override
  Future<bool> deleteSession(String sessionId) async {
    _deletedSessions.add(sessionId);
    _sessions.remove(sessionId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('XAuthProvider Tests', () {
    late FakeSecureStorage fakeSecureStorage;
    late XAuthStorage authStorage;
    late FakeXAuthService fakeAuthService;
    late ProviderContainer container;

    setUp(() {
      fakeSecureStorage = FakeSecureStorage();
      authStorage = XAuthStorage(fakeSecureStorage);
      fakeAuthService = FakeXAuthService();

      container = ProviderContainer(
        overrides: [
          xAuthStorageProvider.overrideWithValue(authStorage),
          xAuthServiceProvider.overrideWithValue(fakeAuthService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test(
        'initial state is unauthenticated and activeXSessionIdProvider is null',
        () {
      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(container.read(activeXSessionIdProvider), isNull);
    });

    test('restoreSession with no stored ID and no credentials stays unauthenticated',
        () async {
      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(container.read(activeXSessionIdProvider), isNull);
      expect(fakeAuthService.createSessionCallCount, 0);
    });

    test('Scenario A: Existing session valid -> keeps authenticated without using credentials',
        () async {
      const activeSession = XAuthSession(
        sessionId: 'active_token_123',
        status: 'available',
        authenticated: true,
      );
      fakeAuthService.addSession(activeSession);
      await authStorage.saveSessionId('active_token_123');
      await authStorage.saveCredentials(
        authToken: 'persisted_auth_token',
        ct0: 'persisted_ct0',
      );

      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.authenticated);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'active_token_123');
      expect(container.read(activeXSessionIdProvider), 'active_token_123');
      // Verify credentials were not needed or called because session was active
      expect(fakeAuthService.createSessionCallCount, 0);
    });

    test('Scenario B: Session expired + credentials available -> auto-restores fresh session',
        () async {
      final expiredSession = XAuthSession(
        sessionId: 'expired_token_123',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      fakeAuthService.addSession(expiredSession);
      await authStorage.saveSessionId('expired_token_123');
      await authStorage.saveCredentials(
        authToken: 'persisted_auth_token',
        ct0: 'persisted_ct0',
      );

      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.authenticated);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'created_session_123');
      expect(await authStorage.readSessionId(), 'created_session_123');
      expect(container.read(activeXSessionIdProvider), 'created_session_123');
      expect(fakeAuthService.createSessionCallCount, 1);
    });

    test('Scenario C: Backend restart (404 Not Found) + credentials available -> auto-restores',
        () async {
      // Session ID exists in mobile storage, but backend restarted and returns 404
      await authStorage.saveSessionId('orphaned_session_404');
      await authStorage.saveCredentials(
        authToken: 'persisted_auth_token',
        ct0: 'persisted_ct0',
      );

      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.authenticated);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'created_session_123');
      expect(await authStorage.readSessionId(), 'created_session_123');
      expect(container.read(activeXSessionIdProvider), 'created_session_123');
      expect(fakeAuthService.createSessionCallCount, 1);
    });

    test('Scenario D: Session expired + credentials NOT available -> unauthenticated without calling register',
        () async {
      final expiredSession = XAuthSession(
        sessionId: 'expired_token_no_creds',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      fakeAuthService.addSession(expiredSession);
      await authStorage.saveSessionId('expired_token_no_creds');
      // No credentials saved in storage

      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(await authStorage.readSessionId(), isNull);
      expect(container.read(activeXSessionIdProvider), isNull);
      expect(fakeAuthService.createSessionCallCount, 0);
    });

    test('Scenario E: Re-registration fails -> unauthenticated, credentials kept, stale ID cleared',
        () async {
      await authStorage.saveSessionId('stale_session_id');
      await authStorage.saveCredentials(
        authToken: 'valid_auth_token',
        ct0: 'valid_ct0',
      );
      fakeAuthService.failCreateSession = true;

      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      // Stale session ID must be cleared
      expect(await authStorage.readSessionId(), isNull);
      expect(container.read(activeXSessionIdProvider), isNull);
      // Credentials must remain intact for future retries
      final storedCreds = await authStorage.readCredentials();
      expect(storedCreds, isNotNull);
      expect(storedCreds?.authToken, 'valid_auth_token');
      expect(storedCreds?.ct0, 'valid_ct0');
    });

    test('Scenario F: Logout deletes backend session, clears session ID, and clears credentials',
        () async {
      const session = XAuthSession(
        sessionId: 'session_to_logout',
        status: 'available',
        authenticated: true,
      );
      fakeAuthService.addSession(session);
      await authStorage.saveSessionId('session_to_logout');
      await authStorage.saveCredentials(
        authToken: 'auth_to_clear',
        ct0: 'ct0_to_clear',
      );

      final controller = container.read(xAuthProvider.notifier);
      await controller.attachSession(session);
      expect(container.read(xAuthProvider).isAuthenticated, isTrue);

      await controller.logout();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      // Backend session removed
      expect(fakeAuthService._deletedSessions, contains('session_to_logout'));
      // Storage session ID cleared
      expect(await authStorage.readSessionId(), isNull);
      // Storage credentials cleared
      expect(await authStorage.readCredentials(), isNull);
      expect(container.read(activeXSessionIdProvider), isNull);
    });

    test('Scenario G: Security - tokens never leaked in toString or error messages',
        () async {
      final controller = container.read(xAuthProvider.notifier);

      await controller.authenticateWithCookies(
        authToken: 'SECRET_AUTH_TOKEN_VALUE',
        ct0: 'SECRET_CT0_VALUE',
      );

      final state = container.read(xAuthProvider);
      expect(state.isAuthenticated, isTrue);

      final stateStr = state.toString();
      expect(stateStr, isNot(contains('SECRET_AUTH_TOKEN_VALUE')));
      expect(stateStr, isNot(contains('SECRET_CT0_VALUE')));

      final creds = await authStorage.readCredentials();
      expect(creds.toString(), isNot(contains('SECRET_AUTH_TOKEN_VALUE')));
      expect(creds.toString(), isNot(contains('SECRET_CT0_VALUE')));
    });

    test('attachSession saves token and transitions to authenticated',
        () async {
      const session = XAuthSession(
        sessionId: 'newly_logged_in_id',
        status: 'available',
        authenticated: true,
      );

      final controller = container.read(xAuthProvider.notifier);
      await controller.attachSession(session);

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.authenticated);
      expect(state.session?.sessionId, 'newly_logged_in_id');
      expect(await authStorage.readSessionId(), 'newly_logged_in_id');
      expect(container.read(activeXSessionIdProvider), 'newly_logged_in_id');
    });

    test('authenticateWithCookies saves credentials and attaches session',
        () async {
      final controller = container.read(xAuthProvider.notifier);

      await controller.authenticateWithCookies(
        authToken: 'AUTH_TEST_COOKIE',
        ct0: 'CT0_TEST_COOKIE',
      );

      final state = container.read(xAuthProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'created_session_123');
      expect(await authStorage.readSessionId(), 'created_session_123');

      final savedCreds = await authStorage.readCredentials();
      expect(savedCreds, isNotNull);
      expect(savedCreds?.authToken, 'AUTH_TEST_COOKIE');
      expect(savedCreds?.ct0, 'CT0_TEST_COOKIE');
    });

    test('authenticateWithCookies handles service failure gracefully',
        () async {
      final failingContainer = ProviderContainer(
        overrides: [
          xAuthStorageProvider.overrideWithValue(authStorage),
          xAuthServiceProvider.overrideWithValue(FailingXAuthService()),
        ],
      );

      final controller = failingContainer.read(xAuthProvider.notifier);

      await expectLater(
        () => controller.authenticateWithCookies(
          authToken: 'TEST_AUTH_TOKEN',
          ct0: 'TEST_CT0',
        ),
        throwsA(isA<ApiException>()),
      );

      final state = failingContainer.read(xAuthProvider);
      expect(state.status, XAuthStatusType.error);
      expect(state.errorMessage, 'Backend failed to create session');
      expect(await authStorage.readSessionId(), isNull);
    });
  });
}

class FailingXAuthService implements XAuthService {
  @override
  Future<XAuthSession> createSession(
      {required String authToken, required String ct0}) async {
    throw const ApiException('Backend failed to create session');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
