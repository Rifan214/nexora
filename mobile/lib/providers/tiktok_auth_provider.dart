import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/tiktok_auth_session.dart';
import '../services/tiktok_auth_service.dart';
import '../services/tiktok_auth_storage.dart';

enum TikTokAuthStatusType {
  unauthenticated,
  restoring,
  authenticating,
  authenticated,
  expired,
  error,
}

@immutable
class TikTokAuthState {
  const TikTokAuthState({
    required this.status,
    this.session,
    this.errorMessage,
  });

  final TikTokAuthStatusType status;
  final TikTokAuthSession? session;
  final String? errorMessage;

  bool get isAuthenticated =>
      status == TikTokAuthStatusType.authenticated && session?.isAvailable == true;

  bool get isRestoring => status == TikTokAuthStatusType.restoring;
  bool get isAuthenticating => status == TikTokAuthStatusType.authenticating;
  bool get isExpired => status == TikTokAuthStatusType.expired;
  bool get isUnauthenticated => status == TikTokAuthStatusType.unauthenticated;

  const TikTokAuthState.unauthenticated()
      : status = TikTokAuthStatusType.unauthenticated,
        session = null,
        errorMessage = null;

  const TikTokAuthState.restoring()
      : status = TikTokAuthStatusType.restoring,
        session = null,
        errorMessage = null;

  const TikTokAuthState.authenticating()
      : status = TikTokAuthStatusType.authenticating,
        session = null,
        errorMessage = null;

  const TikTokAuthState.authenticated(TikTokAuthSession activeSession)
      : status = TikTokAuthStatusType.authenticated,
        session = activeSession,
        errorMessage = null;

  const TikTokAuthState.expired([String? message])
      : status = TikTokAuthStatusType.expired,
        session = null,
        errorMessage = message;

  const TikTokAuthState.error(String message)
      : status = TikTokAuthStatusType.error,
        session = null,
        errorMessage = message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TikTokAuthState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          session == other.session &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(status, session, errorMessage);

  @override
  String toString() =>
      'TikTokAuthState(status: $status, session: $session, errorMessage: $errorMessage)';
}

final tikTokAuthProvider =
    NotifierProvider<TikTokAuthController, TikTokAuthState>(
  TikTokAuthController.new,
);

/// Exposes the active, validated opaque session identifier if authenticated.
final activeTikTokSessionIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(tikTokAuthProvider);
  return authState.isAuthenticated ? authState.session?.sessionId : null;
});

class TikTokAuthController extends Notifier<TikTokAuthState> {
  @override
  TikTokAuthState build() {
    return const TikTokAuthState.unauthenticated();
  }

  /// Checks local storage for an active session ID and validates it against the backend.
  /// If the session is missing, expired, or rejected (e.g. after a backend restart),
  /// attempts to auto-restore a fresh session using securely persisted credentials.
  Future<void> restoreSession() async {
    state = const TikTokAuthState.restoring();

    final storage = ref.read(tikTokAuthStorageProvider);
    final service = ref.read(tikTokAuthServiceProvider);

    final storedId = await storage.readSessionId();
    if (storedId != null && storedId.isNotEmpty) {
      try {
        final session = await service.getSession(storedId);

        if (session.isAvailable) {
          state = TikTokAuthState.authenticated(session);
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
          sidTt: credentials.sidTt,
        );
        await attachSession(newSession);
        return;
      } on ApiException {
        state = const TikTokAuthState.unauthenticated();
        return;
      } catch (_) {
        state = const TikTokAuthState.unauthenticated();
        return;
      }
    }

    state = const TikTokAuthState.unauthenticated();
  }

  /// Handles session invalidation reported during media operations or verification.
  /// Safely purges local session identifier while keeping credentials for potential re-auth.
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    await ref.read(tikTokAuthStorageProvider).clearSessionId();
    if (isExpired) {
      state = TikTokAuthState.expired(reason ?? 'Session expired.');
    } else {
      state = const TikTokAuthState.unauthenticated();
    }
  }

  /// Sets an active session in memory and persists the opaque identifier to secure storage.
  Future<void> attachSession(TikTokAuthSession session) async {
    if (!session.isAvailable) {
      await ref.read(tikTokAuthStorageProvider).clearSessionId();
      state = const TikTokAuthState.unauthenticated();
      return;
    }

    await ref.read(tikTokAuthStorageProvider).saveSessionId(session.sessionId);
    state = TikTokAuthState.authenticated(session);
  }

  /// Bridges extracted or imported credentials to the backend and securely persists them.
  Future<void> authenticateWithCookies({
    required String sessionid,
    String? sidTt,
  }) async {
    state = const TikTokAuthState.authenticating();
    try {
      final service = ref.read(tikTokAuthServiceProvider);
      final session = await service.createSession(
        sessionid: sessionid,
        sidTt: sidTt,
      );
      await ref.read(tikTokAuthStorageProvider).saveCredentials(
            sessionid: sessionid,
            sidTt: sidTt,
          );
      await attachSession(session);
    } on ApiException catch (e) {
      state = TikTokAuthState.error(e.message);
      rethrow;
    } catch (_) {
      state = const TikTokAuthState.error('Failed to authenticate TikTok session.');
      rethrow;
    }
  }

  /// Revokes active session on backend, purges local storage and persisted credentials.
  Future<void> logout() async {
    final currentSession = state.session;
    final storage = ref.read(tikTokAuthStorageProvider);
    final service = ref.read(tikTokAuthServiceProvider);

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

    state = const TikTokAuthState.unauthenticated();
  }
}
