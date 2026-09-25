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

  void addSession(XAuthSession session) {
    _sessions[session.sessionId] = session;
  }

  @override
  Future<XAuthSession> createSession(
      {required String authToken, required String ct0}) async {
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

    test('restoreSession with no stored ID stays unauthenticated', () async {
      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(container.read(activeXSessionIdProvider), isNull);
    });

    test('restoreSession with active stored ID transitions to authenticated',
        () async {
      const activeSession = XAuthSession(
        sessionId: 'active_token_123',
        status: 'available',
        authenticated: true,
      );
      fakeAuthService.addSession(activeSession);
      await authStorage.saveSessionId('active_token_123');

      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.authenticated);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'active_token_123');
      expect(container.read(activeXSessionIdProvider), 'active_token_123');
    });

    test(
        'restoreSession with expired session clears storage and transitions to expired',
        () async {
      final expiredSession = XAuthSession(
        sessionId: 'expired_token_123',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      fakeAuthService.addSession(expiredSession);
      await authStorage.saveSessionId('expired_token_123');

      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.expired);
      expect(state.isExpired, isTrue);
      expect(await authStorage.readSessionId(), isNull);
      expect(container.read(activeXSessionIdProvider), isNull);
    });

    test(
        'restoreSession with unknown/404 ID clears storage and reverts to unauthenticated',
        () async {
      await authStorage.saveSessionId('unknown_id_404');

      final controller = container.read(xAuthProvider.notifier);
      await controller.restoreSession();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.unauthenticated);
      expect(await authStorage.readSessionId(), isNull);
      expect(container.read(activeXSessionIdProvider), isNull);
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

    test(
        'logout deletes session from backend, clears storage, and unauthenticates',
        () async {
      const session = XAuthSession(
        sessionId: 'session_to_logout',
        status: 'available',
        authenticated: true,
      );
      fakeAuthService.addSession(session);
      await authStorage.saveSessionId('session_to_logout');

      final controller = container.read(xAuthProvider.notifier);
      await controller.attachSession(session);
      expect(container.read(xAuthProvider).isAuthenticated, isTrue);

      await controller.logout();

      final state = container.read(xAuthProvider);
      expect(state.status, XAuthStatusType.unauthenticated);
      expect(await authStorage.readSessionId(), isNull);
      expect(container.read(activeXSessionIdProvider), isNull);
    });
  });
}
