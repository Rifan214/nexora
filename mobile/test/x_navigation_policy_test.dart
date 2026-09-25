import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/utils/x_navigation_policy.dart';

void main() {
  group('XNavigationPolicy Tests', () {
    group('Allowlist Security', () {
      test('allows legitimate HTTPS X and Twitter domains', () {
        final allowed = [
          Uri.parse('https://x.com/'),
          Uri.parse('https://x.com/i/flow/login'),
          Uri.parse('https://www.x.com/home'),
          Uri.parse('https://mobile.x.com/settings'),
          Uri.parse('https://api.x.com/1.1/account'),
          Uri.parse('https://twitter.com/'),
          Uri.parse('https://twitter.com/i/flow/login'),
          Uri.parse('https://www.twitter.com/home'),
          Uri.parse('https://mobile.twitter.com/login'),
        ];

        for (final uri in allowed) {
          expect(
            XNavigationPolicy.isAllowedXUrl(uri),
            isTrue,
            reason: 'Should allow $uri',
          );
        }
      });

      test('rejects non-HTTPS schemes', () {
        final nonHttps = [
          Uri.parse('http://x.com/'),
          Uri.parse('http://twitter.com/login'),
          Uri.parse('javascript:alert(document.cookie)'),
          Uri.parse('data:text/html,<html>Evil</html>'),
          Uri.parse('file:///etc/passwd'),
          Uri.parse('intent://x.com'),
        ];

        for (final uri in nonHttps) {
          expect(
            XNavigationPolicy.isAllowedXUrl(uri),
            isFalse,
            reason: 'Should reject non-HTTPS scheme: $uri',
          );
        }
      });

      test('rejects deceptive, spoofed, and third-party domains', () {
        final disallowed = [
          Uri.parse('https://evil-x.com/login'),
          Uri.parse('https://notx.com'),
          Uri.parse('https://x.com.evil.com/'),
          Uri.parse('https://twitter.com.attacker.com/login'),
          Uri.parse('https://example.com/'),
          Uri.parse('https://google.com/'),
          Uri.parse('https://login.x.com.attacker.org/'),
          Uri.parse('https://fake-twitter.com/'),
        ];

        for (final uri in disallowed) {
          expect(
            XNavigationPolicy.isAllowedXUrl(uri),
            isFalse,
            reason: 'Should reject untrusted domain: $uri',
          );
        }
      });

      test('rejects null or empty URIs', () {
        expect(XNavigationPolicy.isAllowedXUrl(null), isFalse);
        expect(XNavigationPolicy.isAllowedXUrl(Uri.parse('')), isFalse);
      });
    });

    group('Login Flow Detection', () {
      test('identifies URLs inside the authentication flow', () {
        final loginUrls = [
          Uri.parse('https://x.com/i/flow/login'),
          Uri.parse('https://x.com/i/flow/login?input_flow_data=...'),
          Uri.parse('https://twitter.com/i/flow/login'),
          Uri.parse('https://x.com/login'),
          Uri.parse('https://x.com/login/flow'),
          Uri.parse('https://x.com/account/access'),
        ];

        for (final uri in loginUrls) {
          expect(
            XNavigationPolicy.isLoginFlow(uri),
            isTrue,
            reason: 'Should recognize $uri as login flow',
          );
        }
      });

      test('identifies URLs outside the login flow', () {
        final nonLoginUrls = [
          Uri.parse('https://x.com/home'),
          Uri.parse('https://x.com/'),
          Uri.parse('https://x.com/explore'),
          Uri.parse('https://twitter.com/notifications'),
          Uri.parse('https://x.com/user_profile'),
        ];

        for (final uri in nonLoginUrls) {
          expect(
            XNavigationPolicy.isLoginFlow(uri),
            isFalse,
            reason: 'Should recognize $uri as outside login flow',
          );
        }
      });
    });

    group('Authenticated Destination Detection', () {
      test(
          'login flow URLs are never marked as potential authenticated destinations',
          () {
        final loginUrls = [
          Uri.parse('https://x.com/i/flow/login'),
          Uri.parse('https://twitter.com/i/flow/login'),
          Uri.parse('https://x.com/login'),
          Uri.parse('https://x.com/account/access'),
        ];

        for (final uri in loginUrls) {
          expect(
            XNavigationPolicy.isPotentialAuthenticatedDestination(uri),
            isFalse,
            reason: 'Login URL $uri must not trigger authenticated destination',
          );
        }
      });

      test('identifies post-login destinations suitable for cookie inspection',
          () {
        final destinations = [
          Uri.parse('https://x.com/home'),
          Uri.parse('https://x.com/'),
          Uri.parse('https://x.com/explore'),
          Uri.parse('https://twitter.com/home'),
          Uri.parse('https://twitter.com/'),
          Uri.parse('https://x.com/elonmusk'),
        ];

        for (final uri in destinations) {
          expect(
            XNavigationPolicy.isPotentialAuthenticatedDestination(uri),
            isTrue,
            reason: 'Post-login URL $uri should trigger cookie inspection',
          );
        }
      });

      test('disallowed domains are never considered authenticated destinations',
          () {
        expect(
          XNavigationPolicy.isPotentialAuthenticatedDestination(
            Uri.parse('https://evil.com/home'),
          ),
          isFalse,
        );
      });
    });
  });
}
