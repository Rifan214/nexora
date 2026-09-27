import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/x_auth_diagnostics.dart';

/// In-memory ephemeral representation of extracted X credentials.
///
/// Never serialized, stored to disk, or kept in persistent state.
@immutable
class XExtractedCookies {
  const XExtractedCookies({
    required this.authToken,
    required this.ct0,
    this.twid,
  });

  final String authToken;
  final String ct0;
  final String? twid;

  bool get isValid => authToken.trim().isNotEmpty && ct0.trim().isNotEmpty;

  @override
  String toString() => 'XExtractedCookies([PROTECTED])';
}

abstract class XCookieManagerWrapper {
  Future<List<Cookie>> getCookies({required WebUri url});
  Future<void> deleteCookie({
    required WebUri url,
    required String name,
    String? domain,
  });
  Future<void> deleteCookies({
    required WebUri url,
    String? domain,
  });
}

class InAppWebViewCookieManagerWrapper implements XCookieManagerWrapper {
  InAppWebViewCookieManagerWrapper([CookieManager? manager])
      : _providedManager = manager;

  final CookieManager? _providedManager;

  CookieManager? get _manager {
    if (_providedManager != null) return _providedManager;
    try {
      return CookieManager.instance();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Cookie>> getCookies({required WebUri url}) async {
    final mgr = _manager;
    if (mgr == null) return const [];
    try {
      return await mgr.getCookies(url: url);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> deleteCookie({
    required WebUri url,
    required String name,
    String? domain,
  }) async {
    final mgr = _manager;
    if (mgr == null) return;
    try {
      await mgr.deleteCookie(url: url, name: name, domain: domain);
    } catch (_) {
      // Non-fatal on unsupported or headless platforms
    }
  }

  @override
  Future<void> deleteCookies({
    required WebUri url,
    String? domain,
  }) async {
    final mgr = _manager;
    if (mgr == null) return;
    try {
      await mgr.deleteCookies(url: url, domain: domain);
    } catch (_) {
      // Non-fatal on unsupported or headless platforms
    }
  }
}

final xCookieManagerProvider = Provider<XCookieManagerService>((ref) {
  return XCookieManagerService(InAppWebViewCookieManagerWrapper());
});

/// Service responsible for native cookie extraction and isolation for X authentication.
class XCookieManagerService {
  const XCookieManagerService(this._wrapper);

  final XCookieManagerWrapper _wrapper;

  /// Inspects the native cookie jar for official X/Twitter session cookies.
  ///
  /// Extracts ONLY `auth_token` and `ct0`.
  /// Never serializes or stores the entire cookie jar.
  Future<XExtractedCookies?> extractSessionCookies(
      [Uri? destinationUri]) async {
    final searchUris = <Uri>[
      if (destinationUri != null) destinationUri,
      Uri.parse('https://x.com'),
      Uri.parse('https://twitter.com'),
    ];

    for (final target in searchUris) {
      try {
        final cookies = await _wrapper.getCookies(url: WebUri.uri(target));
        XAuthDiagnostics.logCookieMetadata(cookies, targetDomain: target.host);
        String? authToken;
        String? ct0;
        String? twid;

        for (final cookie in cookies) {
          final name = cookie.name.trim();
          final val = cookie.value?.toString().trim();
          if (val == null || val.isEmpty) continue;

          if (name == 'auth_token') {
            authToken = val;
          } else if (name == 'ct0') {
            ct0 = val;
          } else if (name == 'twid') {
            twid = val;
          }
        }

        final hasAuth = authToken != null && authToken.isNotEmpty;
        final hasCt0 = ct0 != null && ct0.isNotEmpty;
        final classification = XAuthDiagnostics.classifyAuth(
          hasAuthToken: hasAuth,
          hasCt0: hasCt0,
        );

        if (classification == XAuthClassification.authenticated) {
          XAuthDiagnostics.logAuthMilestone('cookies_extracted_successfully', {
            'targetDomain': target.host,
            'auth_token_present': true,
            'ct0_present': true,
            'twid_present': twid != null,
            'classification': classification.name,
          });
          return XExtractedCookies(
            authToken: authToken!,
            ct0: ct0!,
            twid: twid,
          );
        }
      } catch (_) {
        // Platform or extraction failure
      }
    }

    XAuthDiagnostics.logAuthMilestone('cookies_extraction_incomplete_or_missing', {
      'auth_token_present': false,
      'ct0_present': false,
      'twid_present': false,
      'classification': XAuthClassification.guest.name,
    });

    return null;
  }

  /// Purges X/Twitter authentication cookies from the WebView.
  ///
  /// Scoped exclusively to X/Twitter domains to avoid affecting unrelated WebViews.
  Future<void> clearXCookies() async {
    final targets = [
      (url: WebUri('https://x.com'), domain: '.x.com'),
      (url: WebUri('https://twitter.com'), domain: '.twitter.com'),
      (url: WebUri('https://x.com'), domain: null),
      (url: WebUri('https://twitter.com'), domain: null),
    ];

    for (final target in targets) {
      try {
        await _wrapper.deleteCookie(
          url: target.url,
          name: 'auth_token',
          domain: target.domain,
        );
        await _wrapper.deleteCookie(
          url: target.url,
          name: 'ct0',
          domain: target.domain,
        );
        await _wrapper.deleteCookies(
          url: target.url,
          domain: target.domain,
        );
      } catch (_) {
        // Platform or extraction failure
      }
    }
  }
}
