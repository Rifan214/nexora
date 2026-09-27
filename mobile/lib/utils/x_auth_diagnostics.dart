import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Diagnostic logger and sanitizer for the X authentication WebView.
///
/// Ensures diagnostic telemetry provides deep visibility into WebView
/// environment, navigation decisions, and errors, while strictly guaranteeing
/// that sensitive credential data (passwords, auth tokens, cookie values,
/// and query parameters) are NEVER logged.
class XAuthDiagnostics {
  XAuthDiagnostics._();

  /// Destination logger. Can be overridden in unit tests.
  @visibleForTesting
  static void Function(String line) logger = (line) => debugPrint(line);

  static const String prefix = '[X-DIAG]';

  /// Sensitive keywords that trigger message redaction in console logs.
  static final List<RegExp> _sensitivePatterns = [
    RegExp(r'auth_token', caseSensitive: false),
    RegExp(r'ct0', caseSensitive: false),
    RegExp(r'password', caseSensitive: false),
    RegExp(r'passwd', caseSensitive: false),
    RegExp(r'authorization', caseSensitive: false),
    RegExp(r'cookie', caseSensitive: false),
    RegExp(r'bearer', caseSensitive: false),
    RegExp(r'username', caseSensitive: false),
    RegExp(r'email', caseSensitive: false),
    RegExp(r'token', caseSensitive: false),
    RegExp(r'secret', caseSensitive: false),
    RegExp(r'credentials', caseSensitive: false),
  ];

  /// Strips query parameters, userinfo, and fragments from a URI to prevent
  /// leaking sensitive tokens or query arguments.
  static String sanitizeUri(Uri? uri) {
    if (uri == null) return '<null>';
    final scheme = uri.scheme.isNotEmpty ? '${uri.scheme}://' : '';
    final host = uri.host;
    final path = uri.path;
    return '$scheme$host$path';
  }

  /// Sanitizes console messages, replacing any text matching sensitive patterns.
  static String sanitizeConsoleMessage(String rawMessage) {
    for (final pattern in _sensitivePatterns) {
      if (pattern.hasMatch(rawMessage)) {
        return '<SUPPRESSED: Contains sensitive keyword (${pattern.pattern})>';
      }
    }
    return rawMessage;
  }

  /// Characteristics extracted from a User-Agent string for diagnostic audit.
  static UserAgentCharacteristics classifyUserAgent(String? userAgent) {
    if (userAgent == null || userAgent.isEmpty) {
      return const UserAgentCharacteristics(
        containsWebViewMarker: false,
        containsVersion40Marker: false,
        browserFamily: 'Unknown',
        platform: 'Unknown',
      );
    }

    final hasWv = userAgent.contains(RegExp(r';\s*wv\b'));
    final hasVersion40 = userAgent.contains('Version/4.0');
    final hasChrome = userAgent.contains('Chrome/');

    String browserFamily = 'Unknown';
    if (userAgent.contains('Chrome/') || userAgent.contains('CriOS/')) {
      browserFamily = 'Chrome';
    } else if (userAgent.contains('Safari/') && !userAgent.contains('Chrome/')) {
      browserFamily = 'Safari';
    } else if (userAgent.contains('Firefox/') || userAgent.contains('FxiOS/')) {
      browserFamily = 'Firefox';
    }

    String platform = 'Unknown';
    if (userAgent.contains('Android')) {
      platform = 'Android';
    } else if (userAgent.contains('iPhone') || userAgent.contains('iPad')) {
      platform = 'iOS';
    } else if (userAgent.contains('Linux')) {
      platform = 'Linux';
    } else if (userAgent.contains('Windows')) {
      platform = 'Windows';
    } else if (userAgent.contains('Macintosh')) {
      platform = 'Mac';
    }

    return UserAgentCharacteristics(
      containsWebViewMarker: hasWv,
      containsVersion40Marker: hasVersion40,
      containsChromeMarker: hasChrome,
      browserFamily: browserFamily,
      platform: platform,
    );
  }

  /// Aligns an Android WebView User-Agent to match standalone Chrome on the same device.
  ///
  /// Removes the WebView-identifying tokens:
  /// - `; wv` (WebView platform token)
  /// - `Version/4.0 ` (WebView engine version prefix)
  /// Leaves Chrome version, device model, Android OS version, and Build ID identical.
  static String alignUserAgentToChrome(String rawUserAgent) {
    if (rawUserAgent.isEmpty) return rawUserAgent;
    var aligned = rawUserAgent.replaceAll(RegExp(r';\s*wv\b'), '');
    aligned = aligned.replaceAll(RegExp(r'Version\/4\.0\s*'), '');
    return aligned;
  }

  /// Classifies current X authentication status based on cookie presence.
  static XAuthClassification classifyAuth({
    required bool hasAuthToken,
    required bool hasCt0,
  }) {
    if (hasAuthToken && hasCt0) return XAuthClassification.authenticated;
    if (hasAuthToken || hasCt0) return XAuthClassification.incomplete;
    return XAuthClassification.guest;
  }

  /// Logs WebView environment, Android WebView package information, and settings.
  static void logEnvironment({
    WebViewPackageInfo? packageInfo,
    String? userAgent,
    InAppWebViewSettings? settings,
  }) {
    final osVersion = kIsWeb ? 'web' : Platform.operatingSystemVersion;
    logger('$prefix[ENV] Platform: ${defaultTargetPlatform.name} ($osVersion)');
    logger(
      '$prefix[ENV] Android WebView Package: ${packageInfo?.packageName ?? "unavailable"}',
    );
    logger(
      '$prefix[ENV] Android WebView Version: ${packageInfo?.versionName ?? "unavailable"}',
    );
    logger('$prefix[ENV] Runtime User-Agent: ${userAgent ?? "unknown"}');
    final uaCharacteristics = classifyUserAgent(userAgent);
    logger('$prefix[ENV] UA Characteristics: $uaCharacteristics');

    if (settings != null) {
      logger('$prefix[ENV] Settings: '
          'javaScriptEnabled=${settings.javaScriptEnabled}, '
          'domStorageEnabled=${settings.domStorageEnabled}, '
          'thirdPartyCookiesEnabled=${settings.thirdPartyCookiesEnabled}, '
          'cacheEnabled=${settings.cacheEnabled}, '
          // ignore: deprecated_member_use
          'clearCache=${settings.clearCache}, '
          'supportZoom=${settings.supportZoom}, '
          'requestedWithHeaderOriginAllowList=${settings.requestedWithHeaderOriginAllowList}, '
          'useShouldOverrideUrlLoading=${settings.useShouldOverrideUrlLoading}');

      logger('[X-ENV] UA characteristics: '
          'containsWebViewMarker=${uaCharacteristics.containsWebViewMarker}, '
          'containsVersion40Marker=${uaCharacteristics.containsVersion40Marker}, '
          'containsChromeMarker=${uaCharacteristics.containsChromeMarker}');
      logger('[X-ENV] Settings: '
          'cacheEnabled=${settings.cacheEnabled}, '
          // ignore: deprecated_member_use
          'clearCache=${settings.clearCache}, '
          'requestedWithHeaderOriginAllowList=${settings.requestedWithHeaderOriginAllowList}, '
          'javaScriptEnabled=${settings.javaScriptEnabled}, '
          'domStorageEnabled=${settings.domStorageEnabled}, '
          'thirdPartyCookiesEnabled=${settings.thirdPartyCookiesEnabled}, '
          'supportZoom=${settings.supportZoom}, '
          'package=${packageInfo?.packageName ?? "unavailable"}, '
          'version=${packageInfo?.versionName ?? "unavailable"}');
    }
  }

  /// Logs navigation interception events from `shouldOverrideUrlLoading`.
  static void logNavigation({
    required Uri? uri,
    required bool isForMainFrame,
    required String decision,
    String? method,
  }) {
    final host = uri?.host.isNotEmpty == true ? uri!.host : '<empty-host>';
    final path = uri?.path.isNotEmpty == true ? uri!.path : '/';
    final scheme = uri?.scheme.isNotEmpty == true ? uri!.scheme : '<empty-scheme>';
    final methodStr = method != null ? ' method=$method' : '';

    logger(
      '$prefix[NAV] host=$host path=$path scheme=$scheme '
      'mainFrame=$isForMainFrame$methodStr decision=$decision',
    );
  }

  /// Logs page load start events.
  static void logLoadStart(Uri? uri) {
    logger('$prefix[PAGE] onLoadStart: ${sanitizeUri(uri)}');
  }

  /// Logs page load stop events.
  static void logLoadStop(Uri? uri) {
    logger('$prefix[PAGE] onLoadStop: ${sanitizeUri(uri)}');
  }

  /// Logs navigation history changes.
  static void logVisitedHistory(Uri? uri, bool? isReload) {
    logger(
      '$prefix[PAGE] onUpdateVisitedHistory: ${sanitizeUri(uri)} isReload=$isReload',
    );
  }

  /// Logs webview resource and connection errors.
  static void logError({
    Uri? uri,
    int? errorCode,
    String? description,
    bool? isForMainFrame,
  }) {
    logger(
      '$prefix[ERROR] url=${sanitizeUri(uri)} errorCode=$errorCode '
      'mainFrame=$isForMainFrame description="$description"',
    );
  }

  /// Logs HTTP-level status code errors.
  static void logHttpError({
    Uri? uri,
    int? statusCode,
    String? reasonPhrase,
  }) {
    logger(
      '$prefix[HTTP] url=${sanitizeUri(uri)} statusCode=$statusCode '
      'reason="${reasonPhrase ?? ""}"',
    );
  }

  /// Logs sanitized JavaScript console output.
  static void logConsoleMessage({
    required ConsoleMessageLevel? level,
    required String message,
  }) {
    final sanitized = sanitizeConsoleMessage(message);
    logger('$prefix[JS] level=${level?.toString() ?? "LOG"} message=$sanitized');
  }

  /// Logs non-sensitive cookie metadata only. Values are strictly masked.
  static void logCookieMetadata(List<Cookie> cookies, {String? targetDomain}) {
    final domainTag = targetDomain != null ? ' for $targetDomain' : '';
    logger('$prefix[COOKIE] Inspecting ${cookies.length} cookie(s)$domainTag:');

    var hasAuthToken = false;
    var hasCt0 = false;
    var hasTwid = false;

    for (final c in cookies) {
      if (c.name == 'auth_token') hasAuthToken = true;
      if (c.name == 'ct0') hasCt0 = true;
      if (c.name == 'twid') hasTwid = true;

      final expires = c.expiresDate != null
          ? DateTime.fromMillisecondsSinceEpoch(c.expiresDate!).toUtc().toIso8601String()
          : 'session';

      logger(
        '$prefix[COOKIE] name=${c.name} domain=${c.domain ?? "<none>"} '
        'path=${c.path ?? "/"} secure=${c.isSecure ?? false} '
        'httpOnly=${c.isHttpOnly ?? false} expires=$expires value=<REDACTED>',
      );
    }

    final classification = classifyAuth(
      hasAuthToken: hasAuthToken,
      hasCt0: hasCt0,
    );

    logger(
      '$prefix[COOKIE] Summary: auth_token_present=$hasAuthToken '
      'ct0_present=$hasCt0 twid_present=$hasTwid '
      'classification=${classification.name} total_cookies=${cookies.length}',
    );
  }

  /// Logs safe resource fetch/load telemetry without any query parameters, headers, or bodies.
  static void logResourceLoad({
    required Uri? uri,
    String? initiatorType,
    double? duration,
  }) {
    final sanitized = sanitizeUri(uri);
    final durationStr =
        duration != null ? ' duration=${duration.toStringAsFixed(1)}ms' : '';
    final typeStr = initiatorType != null ? ' type=$initiatorType' : '';
    logger('$prefix[RESOURCE]$typeStr url=$sanitized$durationStr');
  }

  /// Conservative, deterministic categories for X login flow errors.
  static const Set<String> validErrorCategories = {
    'credential_rejected',
    'verification_required',
    'challenge_required',
    'account_locked_or_suspended',
    'rate_limited',
    'generic_login_error',
    'unknown',
  };

  /// Tracks the last logged error category to avoid redundant repeated milestone logs.
  @visibleForTesting
  static String? lastLoggedErrorCategory;

  /// Resets state tracking for unit tests.
  @visibleForTesting
  static void resetDiagnosticState() {
    lastLoggedErrorCategory = null;
  }

  /// Classifies an error message into a standardized, safe error category.
  ///
  /// Never logs or exposes raw error text or user input.
  static String classifyLoginError(String? text) {
    if (text == null || text.trim().isEmpty) {
      return 'unknown';
    }
    final normalized = text.toLowerCase().trim();

    // 1. credential_rejected
    if (normalized.contains('wrong password') ||
        normalized.contains('incorrect password') ||
        normalized.contains('password you entered is incorrect') ||
        normalized.contains('password did not match') ||
        normalized.contains('did not match our records') ||
        normalized.contains('invalid credentials') ||
        normalized.contains('check your password') ||
        normalized.contains('could not find your account') ||
        normalized.contains("couldn't find your account") ||
        normalized.contains('cannot find your account') ||
        normalized.contains('no account found')) {
      return 'credential_rejected';
    }

    // 2. verification_required
    if (normalized.contains('verify your identity') ||
        normalized.contains('confirm your identity') ||
        normalized.contains('verification code') ||
        normalized.contains('confirmation code') ||
        normalized.contains('enter your phone number or username') ||
        normalized.contains('enter your email') ||
        normalized.contains('check your email') ||
        normalized.contains('check your phone') ||
        normalized.contains('we sent a code') ||
        normalized.contains('unusual login activity') ||
        normalized.contains('unusual activity')) {
      return 'verification_required';
    }

    // 3. challenge_required
    if (normalized.contains('authenticate your account') ||
        normalized.contains("make sure you're human") ||
        normalized.contains('make sure you are human') ||
        normalized.contains('complete the challenge') ||
        normalized.contains('security check') ||
        normalized.contains('arkose') ||
        normalized.contains('funcaptcha') ||
        normalized.contains('recaptcha') ||
        normalized.contains('solve this puzzle') ||
        normalized.contains('automated requests')) {
      return 'challenge_required';
    }

    // 4. account_locked_or_suspended
    if (normalized.contains('account has been locked') ||
        normalized.contains('account has been suspended') ||
        normalized.contains('account is locked') ||
        normalized.contains('account is suspended') ||
        normalized.contains('temporarily locked') ||
        normalized.contains('permanently suspended') ||
        normalized.contains('violation of our rules') ||
        normalized.contains('violation of the x rules') ||
        normalized.contains('violated the rules')) {
      return 'account_locked_or_suspended';
    }

    // 5. rate_limited
    if (normalized.contains('too many attempts') ||
        normalized.contains('rate limit') ||
        normalized.contains('rate-limit') ||
        normalized.contains('slow down') ||
        normalized.contains('try again later') ||
        normalized.contains('wait a few minutes') ||
        normalized.contains('try again in a few minutes') ||
        normalized.contains('exceeded the maximum number of attempts')) {
      return 'rate_limited';
    }

    // 6. generic_login_error
    if (normalized.contains('something went wrong') ||
        normalized.contains('not allowed to log in') ||
        normalized.contains('unable to complete this request') ||
        normalized.contains('an error occurred') ||
        normalized.contains('error occurred') ||
        normalized.contains('oops') ||
        normalized.contains('please try again')) {
      return 'generic_login_error';
    }

    return 'unknown';
  }

  /// Extracts the categorized error name from probe output (e.g. `login_error_detected:credential_rejected`).
  static String extractLoginErrorCategory(String? raw) {
    if (raw == null) return 'unknown';
    final trimmed = raw.trim();
    if (trimmed.startsWith('login_error_detected:')) {
      final cat = trimmed.substring('login_error_detected:'.length).trim();
      if (validErrorCategories.contains(cat)) {
        return cat;
      }
    }
    return 'unknown';
  }

  /// Classifies DOM probe output into a strict non-sensitive state token.
  ///
  /// Possible return values:
  /// - `login_error_detected`
  /// - `challenge_detected`
  /// - `login_form_active`
  /// - `unknown`
  static String classifyDomState(String? raw) {
    if (raw == null) return 'unknown';
    final trimmed = raw.trim();
    if (trimmed.startsWith('login_error_detected')) {
      return 'login_error_detected';
    }
    if (trimmed == 'challenge_detected') {
      return 'challenge_detected';
    }
    if (trimmed.startsWith('login_form_active')) {
      return 'login_form_active';
    }
    return 'unknown';
  }

  /// Non-intrusive JavaScript probe for X SPA authentication DOM state.
  ///
  /// Strictly checks for element existence and normalizes error categories locally.
  /// NEVER reads input values, user credentials, cookies, tokens, or dumps HTML.
  static const String probeJsScript = '''
(function() {
  try {
    // 1. Check for error banners / toasts / alerts / OCF error elements
    var errorBanner = document.querySelector('[data-testid="toast"], [role="alert"], [data-testid="error-message"], [data-testid*="error"], [data-testid*="Error"], [id*="error"], [id*="Error"]');
    if (errorBanner && errorBanner.textContent && errorBanner.textContent.trim().length > 0) {
      var raw = (errorBanner.textContent || '').toLowerCase().trim();
      var category = 'unknown';
      if (raw.indexOf('wrong password') !== -1 ||
          raw.indexOf('incorrect password') !== -1 ||
          raw.indexOf('password you entered is incorrect') !== -1 ||
          raw.indexOf('password did not match') !== -1 ||
          raw.indexOf('did not match our records') !== -1 ||
          raw.indexOf('invalid credentials') !== -1 ||
          raw.indexOf('check your password') !== -1 ||
          raw.indexOf('could not find your account') !== -1 ||
          raw.indexOf("couldn't find your account") !== -1 ||
          raw.indexOf('cannot find your account') !== -1 ||
          raw.indexOf('no account found') !== -1) {
        category = 'credential_rejected';
      } else if (raw.indexOf('verify your identity') !== -1 ||
                 raw.indexOf('confirm your identity') !== -1 ||
                 raw.indexOf('verification code') !== -1 ||
                 raw.indexOf('confirmation code') !== -1 ||
                 raw.indexOf('enter your phone number or username') !== -1 ||
                 raw.indexOf('enter your email') !== -1 ||
                 raw.indexOf('check your email') !== -1 ||
                 raw.indexOf('check your phone') !== -1 ||
                 raw.indexOf('we sent a code') !== -1 ||
                 raw.indexOf('unusual login activity') !== -1 ||
                 raw.indexOf('unusual activity') !== -1) {
        category = 'verification_required';
      } else if (raw.indexOf('authenticate your account') !== -1 ||
                 raw.indexOf("make sure you're human") !== -1 ||
                 raw.indexOf('make sure you are human') !== -1 ||
                 raw.indexOf('complete the challenge') !== -1 ||
                 raw.indexOf('security check') !== -1 ||
                 raw.indexOf('arkose') !== -1 ||
                 raw.indexOf('funcaptcha') !== -1 ||
                 raw.indexOf('recaptcha') !== -1 ||
                 raw.indexOf('solve this puzzle') !== -1 ||
                 raw.indexOf('automated requests') !== -1) {
        category = 'challenge_required';
      } else if (raw.indexOf('account has been locked') !== -1 ||
                 raw.indexOf('account has been suspended') !== -1 ||
                 raw.indexOf('account is locked') !== -1 ||
                 raw.indexOf('account is suspended') !== -1 ||
                 raw.indexOf('temporarily locked') !== -1 ||
                 raw.indexOf('permanently suspended') !== -1 ||
                 raw.indexOf('violation of our rules') !== -1 ||
                 raw.indexOf('violation of the x rules') !== -1 ||
                 raw.indexOf('violated the rules') !== -1) {
        category = 'account_locked_or_suspended';
      } else if (raw.indexOf('too many attempts') !== -1 ||
                 raw.indexOf('rate limit') !== -1 ||
                 raw.indexOf('rate-limit') !== -1 ||
                 raw.indexOf('slow down') !== -1 ||
                 raw.indexOf('try again later') !== -1 ||
                 raw.indexOf('wait a few minutes') !== -1 ||
                 raw.indexOf('try again in a few minutes') !== -1 ||
                 raw.indexOf('exceeded the maximum number of attempts') !== -1) {
        category = 'rate_limited';
      } else if (raw.indexOf('something went wrong') !== -1 ||
                 raw.indexOf('not allowed to log in') !== -1 ||
                 raw.indexOf('unable to complete this request') !== -1 ||
                 raw.indexOf('an error occurred') !== -1 ||
                 raw.indexOf('error occurred') !== -1 ||
                 raw.indexOf('oops') !== -1 ||
                 raw.indexOf('please try again') !== -1) {
        category = 'generic_login_error';
      }
      return 'login_error_detected:' + category;
    }

    // Check for password input explicitly marked invalid via ARIA
    var invalidPassword = document.querySelector('input[type="password"][aria-invalid="true"]');
    if (invalidPassword) {
      return 'login_error_detected:credential_rejected';
    }

    // 2. Check for challenge / CAPTCHA elements (Arkose Labs, reCAPTCHA, Cloudflare)
    var challengeEl = document.querySelector('iframe[src*="arkoselabs"], iframe[src*="recaptcha"], iframe[src*="challenge"], [data-testid*="challenge"]');
    if (challengeEl) {
      return 'challenge_detected';
    }

    // 3. Check for password input step
    var passwordInput = document.querySelector('input[type="password"]');
    if (passwordInput) {
      return 'login_form_active:password';
    }

    // 4. Check for identifier (username/email/phone) input step
    var usernameInput = document.querySelector('input[autocomplete="username"], input[name="text"]');
    if (usernameInput) {
      return 'login_form_active:identifier';
    }

    // 5. General login form / dialog
    var formEl = document.querySelector('form, [data-testid="sheetDialog"], [role="dialog"]');
    if (formEl) {
      return 'login_form_active';
    }

    // 6. Home or authenticated hub
    if (window.location && window.location.pathname === '/home') {
      return 'home_path_active';
    }

    return 'unknown';
  } catch (e) {
    return 'unknown';
  }
})();
''';

  /// Evaluates the safe DOM state probe on the WebView controller.
  static Future<String> probePageState(InAppWebViewController? controller) async {
    if (controller == null) return 'unknown';
    try {
      final result = await controller.evaluateJavascript(source: probeJsScript);
      final raw = result?.toString() ?? 'unknown';
      final classification = classifyDomState(raw);

      if (classification == 'login_error_detected') {
        final category = extractLoginErrorCategory(raw);
        logger('$prefix[DOM] state=$classification category=$category');
        if (category != lastLoggedErrorCategory) {
          lastLoggedErrorCategory = category;
          if (category == 'unknown') {
            logAuthMilestone('login_error_category_unknown');
          } else {
            logAuthMilestone(
              'login_error_category_detected',
              {'category': category},
            );
          }
        }
      } else {
        lastLoggedErrorCategory = null;
        logger('$prefix[DOM] state=$classification (detail=$raw)');
      }

      return classification;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Logs high-level authentication flow milestones.
  static void logAuthMilestone(String milestone, [Map<String, Object?>? details]) {
    final detailsStr = details != null && details.isNotEmpty
        ? ' details=${details.toString()}'
        : '';
    logger('$prefix[AUTH] $milestone$detailsStr');
  }
}

/// Authentication state classification for X WebView flows.
enum XAuthClassification {
  authenticated,
  incomplete,
  guest,
}

/// User-Agent characteristics model for diagnostic auditing.
@immutable
class UserAgentCharacteristics {
  const UserAgentCharacteristics({
    required this.containsWebViewMarker,
    required this.containsVersion40Marker,
    this.containsChromeMarker = false,
    required this.browserFamily,
    required this.platform,
  });

  final bool containsWebViewMarker;
  final bool containsVersion40Marker;
  final bool containsChromeMarker;
  final String browserFamily;
  final String platform;

  @override
  String toString() {
    return 'containsWebViewMarker=$containsWebViewMarker, '
        'containsVersion40Marker=$containsVersion40Marker, '
        'containsChromeMarker=$containsChromeMarker, '
        'browserFamily=$browserFamily, platform=$platform';
  }
}

