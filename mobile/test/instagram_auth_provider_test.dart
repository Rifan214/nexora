import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/instagram_auth_session.dart';
import 'package:nexora/providers/instagram_auth_provider.dart';
import 'package:nexora/services/instagram_auth_service.dart';
import 'package:nexora/services/instagram_auth_storage.dart';

import 'instagram_auth_storage_test.dart';

class FakeInstagramAuthService implements InstagramAuthService {
  final Map<String, InstagramAuthSession> _sessions = {};
  final Set<String> _deletedSessions = {};
  int createSessionCallCount = 0;
  bool failCreateSession = false;

  void addSession(InstagramAuthSession session) {
    _sessions[session.sessionId] = session;
  }

  @override
  Future<InstagramAuthSession> createSession({
    required String sessionid,
    String? dsUserId,
    String? csrftoken,
  }) async {
    createSessionCallCount++;
    if (failCreateSession) {
      throw const ApiException('Failed to create Instagram session on upstream');
    }
    final session = InstagramAuthSession(
      sessionId: 'created_ig_session_123',
      source: 'user_session',
      status: 'available',
      authenticated: true,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      expiresInSeconds: 3600,
    );
    _sessions[session.sessionId] = session;
    return session;
  }

  @override
  Future<InstagramAuthSession?> getSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || _deletedSessions.contains(sessionId)) {
      return null;
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
  group('InstagramAuthProvider Tests', () {
    late FakeSecureStorage fakeSecureStorage;
    late InstagramAuthStorage authStorage;
    late FakeInstagramAuthService fakeAuthService;
    late ProviderContainer container;

    setUp(() {
      fakeSecureStorage = FakeSecureStorage();
      authStorage = InstagramAuthStorage(fakeSecureStorage);
      fakeAuthService = FakeInstagramAuthService();

      container = ProviderContainer(
        overrides: [
          instagramAuthStorageProvider.overrideWithValue(authStorage),
          instagramAuthServiceProvider.overrideWithValue(fakeAuthService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is unauthenticated and activeInstagramSessionIdProvider is null', () {
      final state = container.read(instagramAuthProvider);
      expect(state.status, InstagramAuthStatusType.unauthenticated);
      expect(state.isAuthenticated, isFalse);
      expect(container.read(activeInstagramSessionIdProvider), isNull);
    });

    test('authenticateWithCookies creates session and persists both ID and credentials', () async {
      await container.read(instagramAuthProvider.notifier).authenticateWithCookies(
            sessionid: 'test_sessionid%3Aabc',
            dsUserId: '12345678',
            csrftoken: 'test_csrf',
          );

      final state = container.read(instagramAuthProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'created_ig_session_123');
      expect(container.read(activeInstagramSessionIdProvider), 'created_ig_session_123');

      // Check secure storage
      expect(await authStorage.readSessionId(), 'created_ig_session_123');
      final creds = await authStorage.readCredentials();
      expect(creds?.sessionid, 'test_sessionid%3Aabc');
      expect(creds?.dsUserId, '12345678');
      expect(creds?.csrftoken, 'test_csrf');
    });

    test('restoreSession restores active valid session from storage', () async {
      final existingSession = InstagramAuthSession(
        sessionId: 'existing_ig_id',
        source: 'user_session',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
        expiresInSeconds: 1800,
      );
      fakeAuthService.addSession(existingSession);
      await authStorage.saveSessionId('existing_ig_id');

      await container.read(instagramAuthProvider.notifier).restoreSession();

      final state = container.read(instagramAuthProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'existing_ig_id');
      expect(container.read(activeInstagramSessionIdProvider), 'existing_ig_id');
    });

    test('restoreSession auto-restores fresh session when stored ID is expired/missing but credentials exist', () async {
      // Stored ID is non-existent
      await authStorage.saveSessionId('expired_or_invalid_id');
      await authStorage.saveCredentials(
        sessionid: 'persisted_sessionid%3A999',
        dsUserId: 'persisted_user',
      );

      await container.read(instagramAuthProvider.notifier).restoreSession();

      final state = container.read(instagramAuthProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.session?.sessionId, 'created_ig_session_123');
      expect(fakeAuthService.createSessionCallCount, 1);
      expect(await authStorage.readSessionId(), 'created_ig_session_123');
    });

    test('restoreSession remains unauthenticated when storage is empty', () async {
      await container.read(instagramAuthProvider.notifier).restoreSession();

      final state = container.read(instagramAuthProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.status, InstagramAuthStatusType.unauthenticated);
      expect(container.read(activeInstagramSessionIdProvider), isNull);
    });

    test('handleSessionInvalidated with isExpired=true updates state and clears session ID', () async {
      final session = InstagramAuthSession(
        sessionId: 'to_expire_id',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      await container.read(instagramAuthProvider.notifier).attachSession(session);
      expect(container.read(instagramAuthProvider).isAuthenticated, isTrue);

      await container.read(instagramAuthProvider.notifier).handleSessionInvalidated(
            isExpired: true,
            reason: 'Token expired',
          );

      final state = container.read(instagramAuthProvider);
      expect(state.isExpired, isTrue);
      expect(state.errorMessage, 'Token expired');
      expect(await authStorage.readSessionId(), isNull);
    });

    test('logout deletes session upstream, clears storage and resets state', () async {
      final session = InstagramAuthSession(
        sessionId: 'active_ig_logout',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      fakeAuthService.addSession(session);
      await container.read(instagramAuthProvider.notifier).attachSession(session);
      await authStorage.saveCredentials(sessionid: 'token_to_forget');

      await container.read(instagramAuthProvider.notifier).logout();

      final state = container.read(instagramAuthProvider);
      expect(state.isUnauthenticated, isTrue);
      expect(await authStorage.readSessionId(), isNull);
      expect(await authStorage.readCredentials(), isNull);
      expect(fakeAuthService._deletedSessions, contains('active_ig_logout'));
    });
  });
}
