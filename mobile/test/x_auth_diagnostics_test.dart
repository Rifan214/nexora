import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/utils/x_auth_diagnostics.dart';

void main() {
  group('XAuthDiagnostics Security & Redaction Tests', () {
    final capturedLogs = <String>[];

    setUp(() {
      capturedLogs.clear();
      XAuthDiagnostics.logger = (line) => capturedLogs.add(line);
    });

    tearDown(() {
      capturedLogs.clear();
    });

    test('sanitizeUri strips query parameters, userinfo, and fragments', () {
      final sensitiveUri = Uri.parse(
        'https://user:pass@x.com/i/flow/login?token=SECRET123&state=xyz#auth',
      );
      final sanitized = XAuthDiagnostics.sanitizeUri(sensitiveUri);

      expect(sanitized, 'https://x.com/i/flow/login');
      expect(sanitized, isNot(contains('SECRET123')));
      expect(sanitized, isNot(contains('user:pass')));
      expect(sanitized, isNot(contains('xyz')));
      expect(sanitized, isNot(contains('#auth')));
    });

    test('sanitizeConsoleMessage redacts sensitive tokens and keywords', () {
      final sensitiveCases = [
        'User entered password: Secret123',
        'Received auth_token in response',
        'ct0 cookie set by server',
        'Authorization: Bearer AAAAA12345',
        'Cookie: guest_id=123',
        'User email: test@example.com',
        'username: my_user',
        'secret token generated',
        'client credentials verified',
      ];

      for (final msg in sensitiveCases) {
        final sanitized = XAuthDiagnostics.sanitizeConsoleMessage(msg);
        expect(
          sanitized,
          contains('<SUPPRESSED: Contains sensitive keyword'),
          reason: 'Expected suppression for: $msg',
        );
        expect(sanitized, isNot(contains('Secret123')));
        expect(sanitized, isNot(contains('AAAAA12345')));
        expect(sanitized, isNot(contains('test@example.com')));
      }
    });

    test('sanitizeConsoleMessage preserves harmless logs', () {
      const safeMessage = 'Navigation completed successfully to /i/flow/login';
      final sanitized = XAuthDiagnostics.sanitizeConsoleMessage(safeMessage);

      expect(sanitized, safeMessage);
    });

    test('logCookieMetadata masks all cookie values unconditionally', () {
      final cookies = [
        Cookie(
          name: 'auth_token',
          value: 'VERY_SECRET_AUTH_TOKEN_VALUE',
          domain: '.x.com',
          path: '/',
          isSecure: true,
          isHttpOnly: true,
        ),
        Cookie(
          name: 'ct0',
          value: 'VERY_SECRET_CT0_VALUE',
          domain: '.x.com',
          path: '/',
          isSecure: true,
          isHttpOnly: false,
        ),
        Cookie(
          name: 'guest_id',
          value: 'v1%3A1234567890',
          domain: '.x.com',
          path: '/',
        ),
      ];

      XAuthDiagnostics.logCookieMetadata(cookies, targetDomain: 'x.com');

      final output = capturedLogs.join('\n');

      // Crucial security assertions: secret values MUST NOT appear
      expect(output, isNot(contains('VERY_SECRET_AUTH_TOKEN_VALUE')));
      expect(output, isNot(contains('VERY_SECRET_CT0_VALUE')));
      expect(output, isNot(contains('v1%3A1234567890')));

      // Metadata must be logged clearly
      expect(output, contains('name=auth_token'));
      expect(output, contains('name=ct0'));
      expect(output, contains('name=guest_id'));
      expect(output, contains('domain=.x.com'));
      expect(output, contains('value=<REDACTED>'));
      expect(output, contains('auth_token_present=true ct0_present=true'));
    });

    test('logNavigation logs scheme, host, path, and frame without query parameters', () {
      final uriWithQuery = Uri.parse(
        'https://client-api.arkoselabs.com/fc/gt2/public_key/?pk=SENSITIVE_KEY&bda=DATA',
      );

      XAuthDiagnostics.logNavigation(
        uri: uriWithQuery,
        isForMainFrame: false,
        decision: 'CANCEL',
        method: 'GET',
      );

      final log = capturedLogs.first;

      expect(log, contains('[X-DIAG][NAV]'));
      expect(log, contains('host=client-api.arkoselabs.com'));
      expect(log, contains('path=/fc/gt2/public_key/'));
      expect(log, contains('scheme=https'));
      expect(log, contains('mainFrame=false'));
      expect(log, contains('decision=CANCEL'));
      expect(log, contains('method=GET'));

      // Sensitive query params must be completely excluded
      expect(log, isNot(contains('SENSITIVE_KEY')));
      expect(log, isNot(contains('bda=DATA')));
    });

    test('logEnvironment outputs prefix and metadata safely', () {
      final packageInfo = WebViewPackageInfo(
        packageName: 'com.google.android.webview',
        versionName: '120.0.6099.144',
      );
      final settings = InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: false,
      );

      XAuthDiagnostics.logEnvironment(
        packageInfo: packageInfo,
        userAgent:
            'Mozilla/5.0 (Linux; Android 10; Test) AppleWebKit/537.36 Chrome/120.0.6099.144 Mobile Safari/537.36',
        settings: settings,
      );

      final output = capturedLogs.join('\n');

      expect(output, contains('[X-DIAG][ENV]'));
      expect(output, contains('[X-ENV]'));
      expect(output, contains('containsChromeMarker=true'));
      expect(output, contains('Android WebView Package: com.google.android.webview'));
      expect(output, contains('Android WebView Version: 120.0.6099.144'));
      expect(output, contains('Runtime User-Agent: Mozilla/5.0'));
      expect(output, contains('javaScriptEnabled=true'));
      expect(output, contains('cacheEnabled=false'));
    });

    test('logAuthMilestone prefixes milestone tags properly', () {
      XAuthDiagnostics.logAuthMilestone('login_sheet_opened', {'step': 1});

      final log = capturedLogs.first;
      expect(log, contains('[X-DIAG][AUTH] login_sheet_opened details={step: 1}'));
    });

    test('classifyUserAgent identifies WebView vs Chrome markers accurately', () {
      const webViewUa =
          'Mozilla/5.0 (Linux; Android 10; vivo 1935; Build/QP1A.190711.020; wv) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/151.0.7922.199 Mobile Safari/537.36';
      final webViewResult = XAuthDiagnostics.classifyUserAgent(webViewUa);

      expect(webViewResult.containsWebViewMarker, isTrue);
      expect(webViewResult.containsVersion40Marker, isTrue);
      expect(webViewResult.containsChromeMarker, isTrue);
      expect(webViewResult.browserFamily, 'Chrome');
      expect(webViewResult.platform, 'Android');

      const chromeUa =
          'Mozilla/5.0 (Linux; Android 10; vivo 1935; Build/QP1A.190711.020) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.199 Mobile Safari/537.36';
      final chromeResult = XAuthDiagnostics.classifyUserAgent(chromeUa);

      expect(chromeResult.containsWebViewMarker, isFalse);
      expect(chromeResult.containsVersion40Marker, isFalse);
      expect(chromeResult.containsChromeMarker, isTrue);
      expect(chromeResult.browserFamily, 'Chrome');
      expect(chromeResult.platform, 'Android');
    });

    test('alignUserAgentToChrome strips WebView markers while preserving identity', () {
      const rawUa =
          'Mozilla/5.0 (Linux; Android 10; vivo 1935; Build/QP1A.190711.020; wv) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/151.0.7922.199 Mobile Safari/537.36';
      final aligned = XAuthDiagnostics.alignUserAgentToChrome(rawUa);

      expect(aligned, isNot(contains('; wv')));
      expect(aligned, isNot(contains('Version/4.0')));
      expect(aligned, contains('Android 10'));
      expect(aligned, contains('vivo 1935'));
      expect(aligned, contains('Chrome/151.0.7922.199'));

      final alignedClassification = XAuthDiagnostics.classifyUserAgent(aligned);
      expect(alignedClassification.containsWebViewMarker, isFalse);
      expect(alignedClassification.containsVersion40Marker, isFalse);
      expect(alignedClassification.browserFamily, 'Chrome');
      expect(alignedClassification.platform, 'Android');
    });

    test('alignUserAgentToChrome works dynamically across arbitrary devices without hardcoding', () {
      // Test different Android version and OEM device (Pixel 7 on Android 13)
      const pixelUa =
          'Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230901.001; wv) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/120.0.6099.144 Mobile Safari/537.36';
      final pixelAligned = XAuthDiagnostics.alignUserAgentToChrome(pixelUa);

      expect(pixelAligned, isNot(contains('; wv')));
      expect(pixelAligned, isNot(contains('Version/4.0')));
      expect(pixelAligned, contains('Android 13'));
      expect(pixelAligned, contains('Pixel 7'));
      expect(pixelAligned, contains('Chrome/120.0.6099.144'));

      // Test clean Chrome UA remains unchanged
      const cleanChrome =
          'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.64 Mobile Safari/537.36';
      final cleanResult = XAuthDiagnostics.alignUserAgentToChrome(cleanChrome);
      expect(cleanResult, cleanChrome);
    });

    test('classifyAuth accurately categorizes authentication states', () {
      expect(
        XAuthDiagnostics.classifyAuth(hasAuthToken: true, hasCt0: true),
        XAuthClassification.authenticated,
      );
      expect(
        XAuthDiagnostics.classifyAuth(hasAuthToken: true, hasCt0: false),
        XAuthClassification.incomplete,
      );
      expect(
        XAuthDiagnostics.classifyAuth(hasAuthToken: false, hasCt0: true),
        XAuthClassification.incomplete,
      );
      expect(
        XAuthDiagnostics.classifyAuth(hasAuthToken: false, hasCt0: false),
        XAuthClassification.guest,
      );
    });

    test('logCookieMetadata reports twid and auth classification', () {
      final cookies = [
        Cookie(name: 'auth_token', value: 'SECRET_AUTH'),
        Cookie(name: 'ct0', value: 'SECRET_CT0'),
        Cookie(name: 'twid', value: 'u%3D12345'),
      ];

      XAuthDiagnostics.logCookieMetadata(cookies, targetDomain: 'x.com');

      final output = capturedLogs.join('\n');
      expect(output, contains('auth_token_present=true'));
      expect(output, contains('ct0_present=true'));
      expect(output, contains('twid_present=true'));
      expect(output, contains('classification=authenticated'));
      expect(output, contains('total_cookies=3'));
      expect(output, isNot(contains('SECRET_AUTH')));
      expect(output, isNot(contains('SECRET_CT0')));
      expect(output, isNot(contains('u%3D12345')));
    });

    test('InAppWebViewSettings validates normal cache and suppressed X-Requested-With', () {
      final settings = InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        cacheEnabled: true,
        clearCache: false,
        userAgent: 'Mozilla/5.0 Aligned',
        requestedWithHeaderOriginAllowList: <String>{},
      );

      expect(settings.cacheEnabled, isTrue);
      // ignore: deprecated_member_use
      expect(settings.clearCache, isFalse);
      expect(settings.thirdPartyCookiesEnabled, isTrue);
      expect(settings.domStorageEnabled, isTrue);
      expect(settings.requestedWithHeaderOriginAllowList, isEmpty);
      expect(settings.userAgent, 'Mozilla/5.0 Aligned');
    });

    test('logResourceLoad strips sensitive query parameters and fragments', () {
      final sensitiveResourceUri = Uri.parse(
        'https://x.com/i/api/1.1/onboarding/task.json?flow_token=SECRET_FLOW_TOKEN&input_flow_data=SECRET_DATA#subtask',
      );

      XAuthDiagnostics.logResourceLoad(
        uri: sensitiveResourceUri,
        initiatorType: 'fetch',
        duration: 42.54,
      );

      final log = capturedLogs.first;
      expect(log, contains('[X-DIAG][RESOURCE]'));
      expect(log, contains('type=fetch'));
      expect(log, contains('url=https://x.com/i/api/1.1/onboarding/task.json'));
      expect(log, contains('duration=42.5ms'));

      // Ensure secret query parameters and fragments are completely excluded
      expect(log, isNot(contains('SECRET_FLOW_TOKEN')));
      expect(log, isNot(contains('SECRET_DATA')));
      expect(log, isNot(contains('subtask')));
    });

    test('classifyDomState accurately maps DOM probe tokens', () {
      expect(
        XAuthDiagnostics.classifyDomState('login_error_detected'),
        'login_error_detected',
      );
      expect(
        XAuthDiagnostics.classifyDomState('challenge_detected'),
        'challenge_detected',
      );
      expect(
        XAuthDiagnostics.classifyDomState('login_form_active:password'),
        'login_form_active',
      );
      expect(
        XAuthDiagnostics.classifyDomState('login_form_active:identifier'),
        'login_form_active',
      );
      expect(
        XAuthDiagnostics.classifyDomState('login_form_active'),
        'login_form_active',
      );
      expect(
        XAuthDiagnostics.classifyDomState('home_path_active'),
        'unknown',
      );
      expect(
        XAuthDiagnostics.classifyDomState('arbitrary_junk_string'),
        'unknown',
      );
      expect(
        XAuthDiagnostics.classifyDomState(null),
        'unknown',
      );
      expect(
        XAuthDiagnostics.classifyDomState(''),
        'unknown',
      );
    });

    test('logAuthMilestone logs login flow milestones without leaking secrets', () {
      XAuthDiagnostics.logAuthMilestone('login_page_loaded', {
        'url': 'https://x.com/i/jf/onboarding/web',
      });
      XAuthDiagnostics.logAuthMilestone('login_page_still_active', {
        'url': 'https://x.com/i/jf/onboarding/web',
        'state': 'login_form_active',
      });
      XAuthDiagnostics.logAuthMilestone('login_flow_network_activity', {
        'initiator': 'fetch',
        'path': '/i/api/1.1/onboarding/task.json',
      });
      XAuthDiagnostics.logAuthMilestone('auth_cookie_state_changed', {
        'auth_token_present': false,
        'ct0_present': false,
        'twid_present': false,
      });

      final output = capturedLogs.join('\n');
      expect(output, contains('[X-DIAG][AUTH] login_page_loaded'));
      expect(output, contains('[X-DIAG][AUTH] login_page_still_active'));
      expect(output, contains('[X-DIAG][AUTH] login_flow_network_activity'));
      expect(output, contains('[X-DIAG][AUTH] auth_cookie_state_changed'));
      expect(output, contains('auth_token_present: false'));
    });

    test('classifyLoginError maps synthetic fixtures accurately without guessing', () {
      // 1. credential_rejected fixtures
      expect(
        XAuthDiagnostics.classifyLoginError('Wrong password!'),
        'credential_rejected',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(
          'The username and password you entered did not match our records.',
        ),
        'credential_rejected',
      );
      expect(
        XAuthDiagnostics.classifyLoginError('Invalid credentials provided.'),
        'credential_rejected',
      );

      // 2. verification_required fixtures
      expect(
        XAuthDiagnostics.classifyLoginError(
          'There was unusual login activity. Enter your verification code.',
        ),
        'verification_required',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Check your email for the confirmation code we sent.',
        ),
        'verification_required',
      );

      // 3. challenge_required fixtures
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Authenticate your account. Please complete the challenge.',
        ),
        'challenge_required',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(
          "Let's make sure you're human before proceeding.",
        ),
        'challenge_required',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Please solve this puzzle so we know you are a real person.',
        ),
        'challenge_required',
      );

      // 4. account_locked_or_suspended fixtures
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Your account has been locked for security.',
        ),
        'account_locked_or_suspended',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Your account has been suspended due to a violation of our rules.',
        ),
        'account_locked_or_suspended',
      );

      // 5. rate_limited fixtures
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Too many attempts. Please try again later.',
        ),
        'rate_limited',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Rate limit exceeded. Please wait a few minutes.',
        ),
        'rate_limited',
      );

      // 6. generic_login_error fixtures
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Something went wrong, but don’t fret — let’s give it another shot.',
        ),
        'generic_login_error',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(
          'Sorry, you are not allowed to log in at this time.',
        ),
        'generic_login_error',
      );
      expect(
        XAuthDiagnostics.classifyLoginError('Unable to complete this request.'),
        'generic_login_error',
      );

      // 7. ambiguous/unknown fixtures (must never guess)
      expect(
        XAuthDiagnostics.classifyLoginError('Service announcement: scheduled maintenance'),
        'unknown',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(''),
        'unknown',
      );
      expect(
        XAuthDiagnostics.classifyLoginError('   '),
        'unknown',
      );
      expect(
        XAuthDiagnostics.classifyLoginError(null),
        'unknown',
      );
    });

    test('extractLoginErrorCategory parses categorized error tokens safely', () {
      expect(
        XAuthDiagnostics.extractLoginErrorCategory('login_error_detected:credential_rejected'),
        'credential_rejected',
      );
      expect(
        XAuthDiagnostics.extractLoginErrorCategory('login_error_detected:rate_limited'),
        'rate_limited',
      );
      expect(
        XAuthDiagnostics.extractLoginErrorCategory('login_error_detected:fake_category'),
        'unknown',
      );
      expect(
        XAuthDiagnostics.extractLoginErrorCategory('login_form_active'),
        'unknown',
      );
      expect(
        XAuthDiagnostics.extractLoginErrorCategory(null),
        'unknown',
      );
    });

    test('classifyDomState maps categorized login error to login_error_detected', () {
      expect(
        XAuthDiagnostics.classifyDomState('login_error_detected:credential_rejected'),
        'login_error_detected',
      );
      expect(
        XAuthDiagnostics.classifyDomState('login_error_detected:unknown'),
        'login_error_detected',
      );
    });

    test('logAuthMilestone logs error category milestones correctly', () {
      XAuthDiagnostics.logAuthMilestone('login_error_category_detected', {
        'category': 'credential_rejected',
      });
      XAuthDiagnostics.logAuthMilestone('login_error_category_unknown');

      final output = capturedLogs.join('\n');
      expect(
        output,
        contains('[X-DIAG][AUTH] login_error_category_detected details={category: credential_rejected}'),
      );
      expect(
        output,
        contains('[X-DIAG][AUTH] login_error_category_unknown'),
      );
    });
  });
}
