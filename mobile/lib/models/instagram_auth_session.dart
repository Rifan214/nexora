import 'package:flutter/foundation.dart';

@immutable
class InstagramAuthSession {
  const InstagramAuthSession({
    required this.sessionId,
    this.source = 'user_session',
    this.status = 'available',
    this.authenticated = true,
    this.createdAt,
    this.expiresAt,
    this.expiresInSeconds,
  });

  /// Opaque server-generated session identifier.
  final String sessionId;

  /// Authentication source ('user_session', 'service_account', 'guest').
  final String source;

  /// Session status ('available', 'unavailable', 'invalid', 'expired').
  final String status;

  /// Whether the session is considered authenticated.
  final bool authenticated;

  /// UTC creation timestamp.
  final DateTime? createdAt;

  /// UTC expiration timestamp.
  final DateTime? expiresAt;

  /// Calculated remaining lifetime in seconds at time of response.
  final int? expiresInSeconds;

  /// Whether the session has passed its expiration time.
  bool isExpired([DateTime? now]) {
    if (expiresAt == null) {
      return false;
    }
    final current = now?.toUtc() ?? DateTime.now().toUtc();
    return !current.isBefore(expiresAt!);
  }

  /// Whether this session is active, authenticated, and unexpired.
  bool get isAvailable {
    return authenticated && status == 'available' && !isExpired();
  }

  /// Remaining duration until expiration, or Duration.zero if already expired.
  Duration get remainingDuration {
    if (expiresAt == null) {
      return Duration.zero;
    }
    final now = DateTime.now().toUtc();
    final difference = expiresAt!.difference(now);
    return difference.isNegative ? Duration.zero : difference;
  }

  factory InstagramAuthSession.fromJson(Map<String, dynamic> json) {
    DateTime? parseUtc(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value.toUtc();
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value)?.toUtc();
      }
      return null;
    }

    return InstagramAuthSession(
      sessionId: json['session_id'] as String? ?? '',
      source: json['source'] as String? ?? 'user_session',
      status: json['status'] as String? ?? 'available',
      authenticated: json['authenticated'] as bool? ?? true,
      createdAt: parseUtc(json['created_at']),
      expiresAt: parseUtc(json['expires_at']),
      expiresInSeconds: json['expires_in_seconds'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'source': source,
      'status': status,
      'authenticated': authenticated,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      if (expiresInSeconds != null) 'expires_in_seconds': expiresInSeconds,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstagramAuthSession &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          source == other.source &&
          status == other.status &&
          authenticated == other.authenticated &&
          createdAt == other.createdAt &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode => Object.hash(
        sessionId,
        source,
        status,
        authenticated,
        createdAt,
        expiresAt,
      );

  @override
  String toString() {
    return 'InstagramAuthSession(sessionId: $sessionId, status: $status, authenticated: $authenticated)';
  }
}

@immutable
class InstagramCookieCredentials {
  const InstagramCookieCredentials({
    required this.sessionid,
    this.dsUserId,
    this.csrftoken,
  });

  /// The `sessionid` cookie value.
  final String sessionid;

  /// The optional `ds_user_id` cookie value.
  final String? dsUserId;

  /// The optional `csrftoken` cookie value.
  final String? csrftoken;

  /// Whether the required sessionid credential is non-empty after trimming.
  bool get isValid => sessionid.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstagramCookieCredentials &&
          runtimeType == other.runtimeType &&
          sessionid == other.sessionid &&
          dsUserId == other.dsUserId &&
          csrftoken == other.csrftoken;

  @override
  int get hashCode => Object.hash(sessionid, dsUserId, csrftoken);

  @override
  String toString() => 'InstagramCookieCredentials([PROTECTED])';
}
