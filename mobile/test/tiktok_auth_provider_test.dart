import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/tiktok_auth_session.dart';
import 'package:nexora/providers/tiktok_auth_provider.dart';
import 'package:nexora/services/tiktok_auth_service.dart';
import 'package:nexora/services/tiktok_auth_storage.dart';

import 'tiktok_auth_storage_test.dart';

class FakeTikTokAuthService implements TikTokAuthService {
  final Map<String, TikTokAuthSession> _sessions = {};
  final Set<String> _deletedSessions = {};
  int createSessionCallCount = 0;
  bool failCreateSession = false;

  void addSession(TikTokAuthSession session) {
    _sessions[session.sessionId] = session;
  }

  @override
  Future<TikTokAuthSession> createSession(
      {required String sessionid, String? sidTt}) async {
    createSessionCallCount++;
    if (failCreateSession) {
      throw const ApiException('Failed to create TikTok session on upstream');
    }
    final session = TikTokAuthSession(
      sessionId: 'created_tiktok_session_123',
      source: 'user_session',
      status: 'available',
      authenticated: true,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    _sessions[session.sessionId] = session;
    return session;
  }

  @override
  Future<TikTokAuthSession> getSession(String sessionId) async {
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

class FailingTikTokAuthService implements TikTokAuthService {
  @override
  Future<TikTokAuthSession> createSession(
      {required String sessionid, String? sidTt}) async {
    throw const ApiException('Backend failed to create TikTok session');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TikTokAuthProvider Tests', () {
    late FakeSecureStorage fakeSecureStorage;
    late TikTokAuthStorage authStorage;
    late FakeTikTokAuthService fakeAuthService;
    late ProviderContainer container;

    setUp(() {
      fakeSecureStorage = FakeSecureStorage();
      authStorage = TikTokAuthStorage(fakeSecureStorage);
      fakeAuthService = FakeTikTokAuthService();

      container = ProviderContainer(
        overrides: [
          tikTokAuthStorageProvider.overrideWithValue(authStorage),
          tikTokAuthServiceProvider.overrideWithValue(fakeAuthService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test(
        'initial state is unauthenticated and activeTikTokSessionIdProvider is null',
        () {
      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(container.read(activeTikTokSessionIdProvider), isNull);
    });

    test('restoreSession with no stored ID and no credentials stays unauthenticated',
        () async {
      final controller = container.read(tikTokAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(container.read(activeTikTokSessionIdProvider), isNull);
      expect(fakeAuthService.createSessionCallCount, 0);
    });

    test('Scenario A: Existing session valid -> keeps authenticated without using credentials',
        () async {
      const activeSession = TikTokAuthSession(
        sessionId: 'active_tt_token_123',
        status: 'available',
        authenticated: true,
      );
      fakeAuthService.addSession(activeSession);
      await authStorage.saveSessionId('active_tt_token_123');
      await authStorage.saveCredentials(
        sessionid: 'persisted_sessionid',
        sidTt: 'persisted_sid_tt',
      );

      final controller = container.read(tikTokAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.authenticated);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'active_tt_token_123');
      expect(container.read(activeTikTokSessionIdProvider), 'active_tt_token_123');
      expect(fakeAuthService.createSessionCallCount, 0);
    });

    test('Scenario B: Session expired + credentials available -> auto-restores fresh session',
        () async {
      final expiredSession = TikTokAuthSession(
        sessionId: 'expired_tt_token_123',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      fakeAuthService.addSession(expiredSession);
      await authStorage.saveSessionId('expired_tt_token_123');
      await authStorage.saveCredentials(
        sessionid: 'persisted_sessionid',
        sidTt: 'persisted_sid_tt',
      );

      final controller = container.read(tikTokAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.authenticated);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'created_tiktok_session_123');
      expect(await authStorage.readSessionId(), 'created_tiktok_session_123');
      expect(container.read(activeTikTokSessionIdProvider), 'created_tiktok_session_123');
      expect(fakeAuthService.createSessionCallCount, 1);
    });

    test('Scenario C: Backend restart (404 Not Found) + credentials available -> auto-restores',
        () async {
      await authStorage.saveSessionId('orphaned_tt_session_404');
      await authStorage.saveCredentials(
        sessionid: 'persisted_sessionid',
        sidTt: 'persisted_sid_tt',
      );

      final controller = container.read(tikTokAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.authenticated);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'created_tiktok_session_123');
      expect(await authStorage.readSessionId(), 'created_tiktok_session_123');
      expect(container.read(activeTikTokSessionIdProvider), 'created_tiktok_session_123');
      expect(fakeAuthService.createSessionCallCount, 1);
    });

    test('Scenario D: Session expired + credentials NOT available -> unauthenticated',
        () async {
      final expiredSession = TikTokAuthSession(
        sessionId: 'expired_tt_no_creds',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      fakeAuthService.addSession(expiredSession);
      await authStorage.saveSessionId('expired_tt_no_creds');

      final controller = container.read(tikTokAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(await authStorage.readSessionId(), isNull);
      expect(container.read(activeTikTokSessionIdProvider), isNull);
      expect(fakeAuthService.createSessionCallCount, 0);
    });

    test('Scenario E: Re-registration fails -> unauthenticated, credentials kept, stale ID cleared',
        () async {
      await authStorage.saveSessionId('stale_tt_session_id');
      await authStorage.saveCredentials(
        sessionid: 'valid_sessionid',
        sidTt: 'valid_sid_tt',
      );
      fakeAuthService.failCreateSession = true;

      final controller = container.read(tikTokAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(await authStorage.readSessionId(), isNull);
      expect(container.read(activeTikTokSessionIdProvider), isNull);

      final storedCreds = await authStorage.readCredentials();
      expect(storedCreds, isNotNull);
      expect(storedCreds?.sessionid, 'valid_sessionid');
      expect(storedCreds?.sidTt, 'valid_sid_tt');
    });

    test('Scenario F: Logout deletes backend session, clears session ID, and clears credentials',
        () async {
      const session = TikTokAuthSession(
        sessionId: 'session_to_logout',
        status: 'available',
        authenticated: true,
      );
      fakeAuthService.addSession(session);
      await authStorage.saveSessionId('session_to_logout');
      await authStorage.saveCredentials(
        sessionid: 'sessionid_to_clear',
        sidTt: 'sid_tt_to_clear',
      );

      final controller = container.read(tikTokAuthProvider.notifier);
      await controller.attachSession(session);
      expect(container.read(tikTokAuthProvider).isAuthenticated, isTrue);

      await controller.logout();

      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(fakeAuthService._deletedSessions, contains('session_to_logout'));
      expect(await authStorage.readSessionId(), isNull);
      expect(await authStorage.readCredentials(), isNull);
      expect(container.read(activeTikTokSessionIdProvider), isNull);
    });

    test('Scenario G: Security - tokens never leaked in toString or error messages',
        () async {
      final controller = container.read(tikTokAuthProvider.notifier);

      await controller.authenticateWithCookies(
        sessionid: 'SECRET_SESSIONID_VALUE',
        sidTt: 'SECRET_SID_TT_VALUE',
      );

      final state = container.read(tikTokAuthProvider);
      expect(state.isAuthenticated, isTrue);

      final stateStr = state.toString();
      expect(stateStr, isNot(contains('SECRET_SESSIONID_VALUE')));
      expect(stateStr, isNot(contains('SECRET_SID_TT_VALUE')));

      final creds = await authStorage.readCredentials();
      expect(creds.toString(), isNot(contains('SECRET_SESSIONID_VALUE')));
      expect(creds.toString(), isNot(contains('SECRET_SID_TT_VALUE')));
    });

    test('attachSession saves token and transitions to authenticated',
        () async {
      const session = TikTokAuthSession(
        sessionId: 'newly_logged_in_tt_id',
        status: 'available',
        authenticated: true,
      );

      final controller = container.read(tikTokAuthProvider.notifier);
      await controller.attachSession(session);

      final state = container.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.authenticated);
      expect(state.session?.sessionId, 'newly_logged_in_tt_id');
      expect(await authStorage.readSessionId(), 'newly_logged_in_tt_id');
      expect(container.read(activeTikTokSessionIdProvider), 'newly_logged_in_tt_id');
    });

    test('authenticateWithCookies saves credentials and attaches session',
        () async {
      final controller = container.read(tikTokAuthProvider.notifier);

      await controller.authenticateWithCookies(
        sessionid: 'TIKTOK_TEST_COOKIE',
        sidTt: 'SID_TT_TEST_COOKIE',
      );

      final state = container.read(tikTokAuthProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'created_tiktok_session_123');
      expect(await authStorage.readSessionId(), 'created_tiktok_session_123');

      final savedCreds = await authStorage.readCredentials();
      expect(savedCreds, isNotNull);
      expect(savedCreds?.sessionid, 'TIKTOK_TEST_COOKIE');
      expect(savedCreds?.sidTt, 'SID_TT_TEST_COOKIE');
    });

    test('authenticateWithCookies handles service failure gracefully',
        () async {
      final failingContainer = ProviderContainer(
        overrides: [
          tikTokAuthStorageProvider.overrideWithValue(authStorage),
          tikTokAuthServiceProvider.overrideWithValue(FailingTikTokAuthService()),
        ],
      );

      final controller = failingContainer.read(tikTokAuthProvider.notifier);

      await expectLater(
        () => controller.authenticateWithCookies(
          sessionid: 'TEST_SESSIONID',
          sidTt: 'TEST_SID_TT',
        ),
        throwsA(isA<ApiException>()),
      );

      final state = failingContainer.read(tikTokAuthProvider);
      expect(state.status, TikTokAuthStatusType.error);
      expect(state.errorMessage, 'Backend failed to create TikTok session');
      expect(await authStorage.readSessionId(), isNull);
    });
  });
}
