import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/instagram_auth_session.dart';
import '../services/instagram_auth_service.dart';
import '../services/instagram_auth_storage.dart';

enum InstagramAuthStatusType {
  unauthenticated,
  restoring,
  authenticating,
  authenticated,
  expired,
  error,
}

@immutable
class InstagramAuthState {
  const InstagramAuthState({
    required this.status,
    this.session,
    this.errorMessage,
  });

  final InstagramAuthStatusType status;
  final InstagramAuthSession? session;
  final String? errorMessage;

  bool get isAuthenticated =>
      status == InstagramAuthStatusType.authenticated && session?.isAvailable == true;

  bool get isRestoring => status == InstagramAuthStatusType.restoring;
  bool get isAuthenticating => status == InstagramAuthStatusType.authenticating;
  bool get isExpired => status == InstagramAuthStatusType.expired;
  bool get isUnauthenticated => status == InstagramAuthStatusType.unauthenticated;

  const InstagramAuthState.unauthenticated()
      : status = InstagramAuthStatusType.unauthenticated,
        session = null,
        errorMessage = null;

  const InstagramAuthState.restoring()
      : status = InstagramAuthStatusType.restoring,
        session = null,
        errorMessage = null;

  const InstagramAuthState.authenticating()
      : status = InstagramAuthStatusType.authenticating,
        session = null,
        errorMessage = null;

  const InstagramAuthState.authenticated(InstagramAuthSession activeSession)
      : status = InstagramAuthStatusType.authenticated,
        session = activeSession,
        errorMessage = null;

  const InstagramAuthState.expired([String? message])
      : status = InstagramAuthStatusType.expired,
        session = null,
        errorMessage = message;

  const InstagramAuthState.error(String message)
      : status = InstagramAuthStatusType.error,
        session = null,
        errorMessage = message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstagramAuthState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          session == other.session &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(status, session, errorMessage);

  @override
  String toString() =>
      'InstagramAuthState(status: $status, session: $session, errorMessage: $errorMessage)';
}

final instagramAuthProvider =
    NotifierProvider<InstagramAuthController, InstagramAuthState>(
  InstagramAuthController.new,
);

/// Exposes the active, validated opaque session identifier if authenticated.
final activeInstagramSessionIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(instagramAuthProvider);
  return authState.isAuthenticated ? authState.session?.sessionId : null;
});

class InstagramAuthController extends Notifier<InstagramAuthState> {
  @override
  InstagramAuthState build() {
    return const InstagramAuthState.unauthenticated();
  }

  /// Checks local storage for an active session ID and validates it against the backend.
  /// If the session is missing, expired, or rejected (e.g. after a backend restart),
  /// attempts to auto-restore a fresh session using securely persisted credentials.
  Future<void> restoreSession() async {
    state = const InstagramAuthState.restoring();

    final storage = ref.read(instagramAuthStorageProvider);
    final service = ref.read(instagramAuthServiceProvider);

    final storedId = await storage.readSessionId();
    if (storedId != null && storedId.isNotEmpty) {
      try {
        final session = await service.getSession(storedId);

        if (session != null && session.isAvailable) {
          state = InstagramAuthState.authenticated(session);
          return;
        } else {
          await storage.clearSessionId();
        }
      } on ApiException {
        await storage.clearSessionId();
      } catch (_) {
        await storage.clearSessionId();
      }
    }

    // Stored session ID was absent, expired, or invalid.
    // Attempt auto-restoration using securely persisted credentials.
    final credentials = await storage.readCredentials();
    if (credentials != null && credentials.isValid) {
      try {
        final newSession = await service.createSession(
          sessionid: credentials.sessionid,
          dsUserId: credentials.dsUserId,
          csrftoken: credentials.csrftoken,
        );
        await attachSession(newSession);
        return;
      } on ApiException {
        state = const InstagramAuthState.unauthenticated();
        return;
      } catch (_) {
        state = const InstagramAuthState.unauthenticated();
        return;
      }
    }

    state = const InstagramAuthState.unauthenticated();
  }

  /// Handles session invalidation reported during media operations or verification.
  /// Safely purges local session identifier while keeping credentials for potential re-auth.
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    await ref.read(instagramAuthStorageProvider).clearSessionId();
    if (isExpired) {
      state = InstagramAuthState.expired(reason ?? 'Session expired.');
    } else {
      state = const InstagramAuthState.unauthenticated();
    }
  }

  /// Sets an active session in memory and persists the opaque identifier to secure storage.
  Future<void> attachSession(InstagramAuthSession session) async {
    if (!session.isAvailable) {
      await ref.read(instagramAuthStorageProvider).clearSessionId();
      state = const InstagramAuthState.unauthenticated();
      return;
    }

    await ref.read(instagramAuthStorageProvider).saveSessionId(session.sessionId);
    state = InstagramAuthState.authenticated(session);
  }

  /// Bridges extracted or imported credentials to the backend and securely persists them.
  Future<void> authenticateWithCookies({
    required String sessionid,
    String? dsUserId,
    String? csrftoken,
  }) async {
    state = const InstagramAuthState.authenticating();
    try {
      final service = ref.read(instagramAuthServiceProvider);
      final session = await service.createSession(
        sessionid: sessionid,
        dsUserId: dsUserId,
        csrftoken: csrftoken,
      );
      await ref.read(instagramAuthStorageProvider).saveCredentials(
            sessionid: sessionid,
            dsUserId: dsUserId,
            csrftoken: csrftoken,
          );
      await attachSession(session);
    } on ApiException catch (e) {
      state = InstagramAuthState.error(e.message);
      rethrow;
    } catch (_) {
      state = const InstagramAuthState.error('Failed to authenticate Instagram session.');
      rethrow;
    }
  }

  /// Revokes active session on backend, purges local storage and persisted credentials.
  Future<void> logout() async {
    final currentSession = state.session;
    final storage = ref.read(instagramAuthStorageProvider);
    final service = ref.read(instagramAuthServiceProvider);

    final sessionId =
        currentSession?.sessionId ?? await storage.readSessionId();
    if (sessionId != null && sessionId.isNotEmpty) {
      try {
        await service.deleteSession(sessionId);
      } catch (_) {
        // Safe fallback
      }
    }

    await storage.clearSessionId();
    await storage.clearCredentials();

    state = const InstagramAuthState.unauthenticated();
  }
}
