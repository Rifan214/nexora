import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/x_auth_session.dart';

void main() {
  group('XAuthSession Model Tests', () {
    test('parses valid JSON response from backend', () {
      final futureExpiry = DateTime.now().toUtc().add(const Duration(hours: 1));
      final json = {
        'session_id': '8a014f1c47fad867f55bd200bc7aeedf',
        'source': 'user_session',
        'status': 'available',
        'authenticated': true,
        'created_at': '2026-09-25T03:00:00.000Z',
        'expires_at': futureExpiry.toIso8601String(),
        'expires_in_seconds': 3600,
      };

      final session = XAuthSession.fromJson(json);

      expect(session.sessionId, '8a014f1c47fad867f55bd200bc7aeedf');
      expect(session.source, 'user_session');
      expect(session.status, 'available');
      expect(session.authenticated, isTrue);
      expect(session.createdAt, isNotNull);
      expect(session.expiresAt, isNotNull);
      expect(session.expiresInSeconds, 3600);
      expect(session.isAvailable, isTrue);
    });

    test('correctly calculates isExpired based on expiresAt', () {
      final now = DateTime.now().toUtc();

      final unexpiredSession = XAuthSession(
        sessionId: 'test_id_1',
        expiresAt: now.add(const Duration(minutes: 30)),
      );
      expect(unexpiredSession.isExpired(now), isFalse);
      expect(unexpiredSession.isAvailable, isTrue);

      final expiredSession = XAuthSession(
        sessionId: 'test_id_2',
        expiresAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(expiredSession.isExpired(now), isTrue);
      expect(expiredSession.isAvailable, isFalse);

      final noExpirySession = const XAuthSession(sessionId: 'test_id_3');
      expect(noExpirySession.isExpired(now), isFalse);
    });

    test('serializes to JSON with identical keys and values', () {
      final session = XAuthSession(
        sessionId: 'abc1234567890def',
        source: 'user_session',
        status: 'available',
        authenticated: true,
        createdAt: DateTime.utc(2026, 9, 25, 3, 0, 0),
        expiresAt: DateTime.utc(2026, 9, 25, 4, 0, 0),
        expiresInSeconds: 3600,
      );

      final json = session.toJson();

      expect(json['session_id'], 'abc1234567890def');
      expect(json['source'], 'user_session');
      expect(json['status'], 'available');
      expect(json['authenticated'], isTrue);
      expect(json['created_at'], '2026-09-25T03:00:00.000Z');
      expect(json['expires_at'], '2026-09-25T04:00:00.000Z');
      expect(json['expires_in_seconds'], 3600);

      // Verify no credential fields can ever be present
      expect(json.containsKey('auth_token'), isFalse);
      expect(json.containsKey('ct0'), isFalse);
      expect(json.containsKey('cookies'), isFalse);
      expect(json.containsKey('password'), isFalse);
    });

    test('safe toString never exposes secret credentials', () {
      final session = const XAuthSession(
        sessionId: '8a014f1c47fad867f55bd200bc7aeedf',
        source: 'user_session',
        status: 'available',
        authenticated: true,
      );

      final str = session.toString();
      expect(str, contains('8a014f1c47fad867f55bd200bc7aeedf'));
      expect(str, contains('user_session'));
      expect(str, contains('available'));
      expect(str, isNot(contains('auth_token')));
      expect(str, isNot(contains('ct0')));
      expect(str, isNot(contains('cookie')));
      expect(str, isNot(contains('password')));
    });

    test('equality and hashCode work as expected', () {
      final s1 = const XAuthSession(sessionId: 'same_id', status: 'available');
      final s2 = const XAuthSession(sessionId: 'same_id', status: 'available');
      final s3 = const XAuthSession(sessionId: 'diff_id', status: 'available');

      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
      expect(s1, isNot(equals(s3)));
    });
  });
}
