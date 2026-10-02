import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/x_auth_session.dart';
import '../services/x_auth_service.dart';
import '../services/x_auth_storage.dart';
import '../services/x_cookie_manager.dart';

enum XAuthStatusType {
  unauthenticated,
  restoring,
  authenticating,
  authenticated,
  expired,
  error,
}

@immutable
class XAuthState {
  const XAuthState({
    required this.status,
    this.session,
    this.errorMessage,
  });

  final XAuthStatusType status;
  final XAuthSession? session;
  final String? errorMessage;

  bool get isAuthenticated =>
      status == XAuthStatusType.authenticated && session?.isAvailable == true;

  bool get isRestoring => status == XAuthStatusType.restoring;
  bool get isAuthenticating => status == XAuthStatusType.authenticating;
  bool get isExpired => status == XAuthStatusType.expired;
  bool get isUnauthenticated => status == XAuthStatusType.unauthenticated;

  const XAuthState.unauthenticated()
      : status = XAuthStatusType.unauthenticated,
        session = null,
        errorMessage = null;

  const XAuthState.restoring()
      : status = XAuthStatusType.restoring,
        session = null,
        errorMessage = null;

  const XAuthState.authenticating()
      : status = XAuthStatusType.authenticating,
        session = null,
        errorMessage = null;

  const XAuthState.authenticated(XAuthSession activeSession)
      : status = XAuthStatusType.authenticated,
        session = activeSession,
        errorMessage = null;

  const XAuthState.expired([String? message])
      : status = XAuthStatusType.expired,
        session = null,
        errorMessage = message;

  const XAuthState.error(String message)
      : status = XAuthStatusType.error,
        session = null,
        errorMessage = message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XAuthState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          session == other.session &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(status, session, errorMessage);

  @override
  String toString() =>
      'XAuthState(status: $status, session: $session, errorMessage: $errorMessage)';
}

final xAuthProvider = NotifierProvider<XAuthController, XAuthState>(
  XAuthController.new,
);

/// Exposes the active, validated opaque session identifier if authenticated.
final activeXSessionIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(xAuthProvider);
  return authState.isAuthenticated ? authState.session?.sessionId : null;
});

class XAuthController extends Notifier<XAuthState> {
  @override
  XAuthState build() {
    // Note: session restoration can be triggered via restoreSession()
    return const XAuthState.unauthenticated();
  }

  /// Checks local storage for an active session ID and validates it against the backend.
  /// If the session is missing, expired, or rejected (e.g. after a backend restart),
  /// attempts to auto-restore a fresh session using securely persisted credentials.
  Future<void> restoreSession() async {
    state = const XAuthState.restoring();

    final storage = ref.read(xAuthStorageProvider);
    final service = ref.read(xAuthServiceProvider);

    final storedId = await storage.readSessionId();
    if (storedId != null && storedId.isNotEmpty) {
      try {
        final session = await service.getSession(storedId);

        if (session.isAvailable) {
          state = XAuthState.authenticated(session);
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
          authToken: credentials.authToken,
          ct0: credentials.ct0,
        );
        await attachSession(newSession);
        return;
      } on ApiException {
        // Re-registration failed; credentials remain stored for future retry.
        state = const XAuthState.unauthenticated();
        return;
      } catch (_) {
        state = const XAuthState.unauthenticated();
        return;
      }
    }

    // No credentials available
    state = const XAuthState.unauthenticated();
  }

  /// Handles session invalidation reported during media operations or verification.
  /// Safely purges local session identifier while keeping credentials for potential re-auth.
  Future<void> handleSessionInvalidated({
    bool isExpired = false,
    String? reason,
  }) async {
    await ref.read(xAuthStorageProvider).clearSessionId();
    if (isExpired) {
      state = XAuthState.expired(reason ?? 'Session expired.');
    } else {
      state = const XAuthState.unauthenticated();
    }
  }

  /// Sets an active session in memory and persists the opaque identifier to secure storage.
  Future<void> attachSession(XAuthSession session) async {
    if (!session.isAvailable) {
      await ref.read(xAuthStorageProvider).clearSessionId();
      state = const XAuthState.unauthenticated();
      return;
    }

    await ref.read(xAuthStorageProvider).saveSessionId(session.sessionId);
    state = XAuthState.authenticated(session);
  }

  /// Bridges extracted or imported credentials to the backend and securely persists them.
  Future<void> authenticateWithCookies({
    required String authToken,
    required String ct0,
  }) async {
    state = const XAuthState.authenticating();
    try {
      final service = ref.read(xAuthServiceProvider);
      final session = await service.createSession(
        authToken: authToken,
        ct0: ct0,
      );
      await ref.read(xAuthStorageProvider).saveCredentials(
            authToken: authToken,
            ct0: ct0,
          );
      await attachSession(session);
    } on ApiException catch (e) {
      state = XAuthState.error(e.message);
      rethrow;
    } catch (_) {
      state = const XAuthState.error('Failed to authenticate X session.');
      rethrow;
    }
  }

  /// Revokes the active session on the backend, purges local secure storage,
  /// clears persisted credentials, and cleans native WebView cookies for X/Twitter domains.
  Future<void> logout() async {
    final currentSession = state.session;
    final storage = ref.read(xAuthStorageProvider);
    final service = ref.read(xAuthServiceProvider);
    final cookieManager = ref.read(xCookieManagerProvider);

    final sessionId =
        currentSession?.sessionId ?? await storage.readSessionId();
    if (sessionId != null && sessionId.isNotEmpty) {
      try {
        await service.deleteSession(sessionId);
      } catch (_) {
        // Safe fallback: continue local cleanup even if network fails
      }
    }

    await storage.clearSessionId();
    await storage.clearCredentials();

    try {
      await cookieManager.clearXCookies();
    } catch (_) {
      // Safe fallback: continue logout state reset
    }

    state = const XAuthState.unauthenticated();
  }
}
