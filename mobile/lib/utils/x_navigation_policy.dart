/// Navigation security policy for X (Twitter) authentication WebView.
///
/// Enforces strict HTTPS-only navigation to official X/Twitter domains
/// and detects navigation away from the authentication flow.
class XNavigationPolicy {
  const XNavigationPolicy._();

  /// Initial entrypoint for official X authentication.
  static final Uri loginUri = Uri.parse('https://x.com/i/flow/login');

  /// Fallback entrypoint if x.com redirects to twitter.com.
  static final Uri twitterLoginUri =
      Uri.parse('https://twitter.com/i/flow/login');

  /// Primary domains allowed for navigation.
  static const Set<String> _allowedExactDomains = {
    'x.com',
    'twitter.com',
  };

  /// Validates whether [uri] is an authorized HTTPS URL on an official X/Twitter domain.
  ///
  /// Rejects:
  /// - Non-HTTPS schemes (http, javascript, data, file, intent)
  /// - Third-party domains (e.g. evil-x.com, x.com.attacker.com)
  /// - Empty or malformed hosts
  static bool isAllowedXUrl(Uri? uri) {
    if (uri == null) return false;

    // Strict HTTPS requirement
    if (uri.scheme.toLowerCase() != 'https') {
      return false;
    }

    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) {
      return false;
    }

    // Must be exactly x.com/twitter.com or an official subdomain (*.x.com / *.twitter.com)
    if (_allowedExactDomains.contains(host)) {
      return true;
    }

    for (final domain in _allowedExactDomains) {
      if (host.endsWith('.$domain')) {
        return true;
      }
    }

    return false;
  }

  /// Determines if [uri] belongs to the unauthenticated login/onboarding flow.
  static bool isLoginFlow(Uri? uri) {
    if (uri == null || !isAllowedXUrl(uri)) {
      return false;
    }

    final path = uri.path.toLowerCase();
    return path.contains('/i/flow/login') ||
        path.startsWith('/i/flow') ||
        path == '/login' ||
        path.startsWith('/login/') ||
        path.contains('/account/access') ||
        path.contains('/account/begin_password_reset');
  }

  /// Evaluates whether the navigation destination indicates the user has
  /// successfully moved beyond the login flow onto an authenticated destination.
  ///
  /// Common post-login paths on X include `/home`, root `/`, user timelines,
  /// settings, or explore pages.
  ///
  /// Note: Navigation to this destination alone is NOT proof of authentication.
  /// Proof requires verification of `auth_token` and `ct0` in the native cookie jar.
  static bool isPotentialAuthenticatedDestination(Uri? uri) {
    if (uri == null || !isAllowedXUrl(uri)) {
      return false;
    }

    // Still inside login / challenge flow
    if (isLoginFlow(uri)) {
      return false;
    }

    final path = uri.path.toLowerCase();

    // Authenticated hubs or root redirection
    if (path == '/home' ||
        path == '/' ||
        path == '' ||
        path.startsWith('/home/') ||
        path.startsWith('/explore') ||
        path.startsWith('/notifications') ||
        path.startsWith('/messages') ||
        path.startsWith('/settings')) {
      return true;
    }

    // Any valid non-login path on x.com or twitter.com (e.g., user profiles like /x)
    // could be reached post-login
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      final firstSegment = segments.first.toLowerCase();
      // Exclude static asset paths or login-adjacent paths
      const excludedPrefixes = {
        'i',
        'login',
        'signup',
        'account',
        'tos',
        'privacy',
        'help',
      };
      if (!excludedPrefixes.contains(firstSegment)) {
        return true;
      }
    }

    return false;
  }
}
