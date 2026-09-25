import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/x_auth_session.dart';
import '../services/x_auth_service.dart';
import '../services/x_auth_storage.dart';

enum XAuthStatusType {
  unauthenticated,
  restoring,
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
  bool get isExpired => status == XAuthStatusType.expired;

  const XAuthState.unauthenticated()
      : status = XAuthStatusType.unauthenticated,
        session = null,
        errorMessage = null;

  const XAuthState.restoring()
      : status = XAuthStatusType.restoring,
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

  /// Checks local storage for a previously saved session ID and validates it
  /// against the backend API.
  Future<void> restoreSession() async {
    state = const XAuthState.restoring();

    final storage = ref.read(xAuthStorageProvider);
    final service = ref.read(xAuthServiceProvider);

    final storedId = await storage.readSessionId();
    if (storedId == null || storedId.isEmpty) {
      state = const XAuthState.unauthenticated();
      return;
    }

    try {
      final session = await service.getSession(storedId);

      if (session.isAvailable) {
        state = XAuthState.authenticated(session);
      } else if (session.isExpired()) {
        await storage.clearSessionId();
        state = const XAuthState.expired('Session expired.');
      } else {
        await storage.clearSessionId();
        state = const XAuthState.unauthenticated();
      }
    } on ApiException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('not found') ||
          msg.contains('invalid') ||
          msg.contains('404')) {
        await storage.clearSessionId();
        state = const XAuthState.unauthenticated();
      } else if (msg.contains('expired') || msg.contains('401')) {
        await storage.clearSessionId();
        state = XAuthState.expired(e.message);
      } else {
        state = XAuthState.error(e.message);
      }
    } catch (_) {
      state = const XAuthState.error('Unable to verify X session.');
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

  /// Revokes the active session on the backend and purges local secure storage.
  Future<void> logout() async {
    final currentSession = state.session;
    final storage = ref.read(xAuthStorageProvider);
    final service = ref.read(xAuthServiceProvider);

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
    state = const XAuthState.unauthenticated();
  }
}
