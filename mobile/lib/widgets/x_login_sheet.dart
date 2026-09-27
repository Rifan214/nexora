import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../providers/x_auth_provider.dart';
import '../services/x_cookie_manager.dart';
import '../utils/x_auth_diagnostics.dart';
import '../utils/x_navigation_policy.dart';

/// Modal bottom sheet presenting the official X (Twitter) login WebView.
///
/// Ensures credentials are submitted solely to X, extracts the resulting
/// session cookies in-memory, transfers them to XAuthService, and purges
/// the WebView cookies.
class XLoginSheet extends ConsumerStatefulWidget {
  const XLoginSheet({super.key});

  /// Presents the X login sheet as a modal bottom sheet.
  ///
  /// Returns `true` if the session was successfully connected, `false` or `null` otherwise.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.navigation,
      ),
      builder: (_) => const XLoginSheet(),
    );
  }

  @override
  ConsumerState<XLoginSheet> createState() => _XLoginSheetState();
}

class _XLoginSheetState extends ConsumerState<XLoginSheet> {
  InAppWebViewController? _webViewController;
  bool _isLoadingPage = true;
  double _loadProgress = 0.0;
  bool _isConnectingBackend = false;
  String? _errorMessage;
  bool _hasExtracted = false;
  String? _overrideUserAgent;
  Timer? _heartbeatTimer;
  bool _lastHasAuthToken = false;
  bool _lastHasCt0 = false;
  bool _lastHasTwid = false;

  @override
  void initState() {
    super.initState();
    XAuthDiagnostics.logAuthMilestone('login_sheet_opened');
    _initUserAgent();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _isConnectingBackend || _webViewController == null) return;
      try {
        final currentUrl = await _webViewController?.getUrl();
        final uri = currentUrl?.uriValue;
        if (uri != null) {
          final domState =
              await XAuthDiagnostics.probePageState(_webViewController);
          XAuthDiagnostics.logAuthMilestone('login_page_still_active', {
            'url': XAuthDiagnostics.sanitizeUri(uri),
            'state': domState,
          });
          await _checkCookiePresenceOnly(uri);
        }
      } catch (_) {}
    });
  }

  Future<void> _checkCookiePresenceOnly(Uri? uri) async {
    if (uri == null) return;
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri.uri(uri),
      );
      var hasAuthToken = false;
      var hasCt0 = false;
      var hasTwid = false;

      for (final c in cookies) {
        if (c.name == 'auth_token') hasAuthToken = true;
        if (c.name == 'ct0') hasCt0 = true;
        if (c.name == 'twid') hasTwid = true;
      }

      if (hasAuthToken != _lastHasAuthToken ||
          hasCt0 != _lastHasCt0 ||
          hasTwid != _lastHasTwid) {
        _lastHasAuthToken = hasAuthToken;
        _lastHasCt0 = hasCt0;
        _lastHasTwid = hasTwid;
        XAuthDiagnostics.logAuthMilestone('auth_cookie_state_changed', {
          'auth_token_present': hasAuthToken,
          'ct0_present': hasCt0,
          'twid_present': hasTwid,
        });
      }
    } catch (_) {}
  }

  Future<void> _initUserAgent() async {
    XAuthDiagnostics.logAuthMilestone('user_agent_init_started');
    try {
      final rawUa = await InAppWebViewController.getDefaultUserAgent();
      final aligned = XAuthDiagnostics.alignUserAgentToChrome(rawUa);
      XAuthDiagnostics.logAuthMilestone('user_agent_aligned', {
        'raw_characteristics':
            XAuthDiagnostics.classifyUserAgent(rawUa).toString(),
        'aligned_characteristics':
            XAuthDiagnostics.classifyUserAgent(aligned).toString(),
      });
      if (mounted) {
        setState(() {
          _overrideUserAgent = aligned;
        });
      }
    } catch (e) {
      XAuthDiagnostics.logAuthMilestone('user_agent_init_failed', {
        'error': e.toString(),
      });
      XAuthDiagnostics.logAuthMilestone('ua_override_unavailable', {
        'fallback': 'default_system_webview_ua',
      });
      if (mounted) {
        setState(() {
          _overrideUserAgent = '';
        });
      }
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _webViewController = null;
    super.dispose();
  }

  Future<void> _handleCancel() async {
    XAuthDiagnostics.logAuthMilestone('login_sheet_cancelled_by_user');
    // Purge any partial/temporary authentication cookies on cancellation
    try {
      await ref.read(xCookieManagerProvider).clearXCookies();
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _checkDestinationForCookies(Uri? uri) async {
    if (uri == null) return;
    final isCandidate =
        XNavigationPolicy.isPotentialAuthenticatedDestination(uri);
    final isHome = uri.path == '/home' || uri.path.endsWith('/home');

    XAuthDiagnostics.logAuthMilestone('destination_checked', {
      'path': uri.path,
      'isPotentialCandidate': isCandidate,
      'isHome': isHome,
      'hasExtracted': _hasExtracted,
      'isConnectingBackend': _isConnectingBackend,
    });

    if (_hasExtracted || _isConnectingBackend) {
      return;
    }

    // Only inspect when navigating away from the login/challenge flow
    if (!isCandidate) {
      return;
    }

    XAuthDiagnostics.logAuthMilestone(
      'cookie_inspection_triggered',
      {'path': uri.path, 'isHome': isHome},
    );

    final cookieManager = ref.read(xCookieManagerProvider);
    final extracted = await cookieManager.extractSessionCookies(uri);

    if (extracted != null && extracted.isValid && mounted) {
      _hasExtracted = true;
      setState(() {
        _isConnectingBackend = true;
        _errorMessage = null;
      });

      try {
        XAuthDiagnostics.logAuthMilestone('backend_session_creation_attempted', {
          'reason': 'valid_auth_token_and_ct0_present',
          'has_twid': extracted.twid != null,
        });
        // Ephemeral in-memory bridge to existing XAuthService via XAuthController
        await ref.read(xAuthProvider.notifier).authenticateWithCookies(
              authToken: extracted.authToken,
              ct0: extracted.ct0,
            );
        XAuthDiagnostics.logAuthMilestone(
            'backend_session_creation_succeeded');

        // Immediately purge WebView cookies to avoid lingering browser session
        await cookieManager.clearXCookies();

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (_) {
        XAuthDiagnostics.logAuthMilestone('backend_session_creation_failed');
        // On backend error, clear WebView session as well
        await cookieManager.clearXCookies();
        if (mounted) {
          setState(() {
            _isConnectingBackend = false;
            _hasExtracted = false;
            _errorMessage =
                'Failed to create backend session. Please check connection and try again.';
          });
        }
      }
    } else {
      // Incomplete or guest session reached a candidate destination (e.g. /home)
      XAuthDiagnostics.logAuthMilestone('backend_session_creation_skipped', {
        'reason': 'incomplete_or_guest_session',
        'path': uri.path,
        'isHome': isHome,
        'action': 'awaiting_valid_credentials_or_user_action',
      });
    }
  }

  void _retryLogin() {
    XAuthDiagnostics.logAuthMilestone('login_retry_requested');
    setState(() {
      _errorMessage = null;
      _isLoadingPage = true;
      _hasExtracted = false;
      _isConnectingBackend = false;
    });
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri.uri(XNavigationPolicy.loginUri)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;

    return PopScope(
      canPop: !_isConnectingBackend,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          try {
            await ref.read(xCookieManagerProvider).clearXCookies();
          } catch (_) {}
        }
      },
      child: SizedBox(
        height: screenHeight * 0.88,
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: AppRadii.pill,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadii.duration,
                    ),
                    child: Icon(
                      Icons.alternate_email_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connect X Account',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Sign in directly on X. Nexora never sees your password.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                    onPressed: _isConnectingBackend ? null : _handleCancel,
                  ),
                ],
              ),
            ),

            // Loading bar
            if (_isLoadingPage || _isConnectingBackend)
              LinearProgressIndicator(
                value: _isConnectingBackend
                    ? null
                    : (_loadProgress > 0 ? _loadProgress : null),
                minHeight: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              )
            else
              const SizedBox(height: 3),

            // Error banner if any
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.all(AppSpacing.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: AppRadii.badge,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: colorScheme.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _retryLogin,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),

            // WebView or Connecting overlay
            Expanded(
              child: _overrideUserAgent == null
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri.uri(XNavigationPolicy.loginUri),
                          ),
                          initialSettings: InAppWebViewSettings(
                            useShouldOverrideUrlLoading: true,
                            useOnLoadResource: true,
                            javaScriptEnabled: true,
                            domStorageEnabled: true,
                            thirdPartyCookiesEnabled: true,
                            cacheEnabled: true,
                            clearCache: false,
                            userAgent: (_overrideUserAgent != null &&
                                    _overrideUserAgent!.isNotEmpty)
                                ? _overrideUserAgent
                                : null,
                            requestedWithHeaderOriginAllowList: <String>{},
                          ),
                    onWebViewCreated: (controller) async {
                      _webViewController = controller;
                      try {
                        final packageInfo =
                            await InAppWebViewController.getCurrentWebViewPackage();
                        final settings = await controller.getSettings();
                        XAuthDiagnostics.logEnvironment(
                          packageInfo: packageInfo,
                          userAgent: settings?.userAgent,
                          settings: settings,
                        );
                      } catch (_) {
                        XAuthDiagnostics.logEnvironment();
                      }
                    },
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                      final uri = navigationAction.request.url?.uriValue;
                      final isAllowed = XNavigationPolicy.isAllowedXUrl(uri);
                      XAuthDiagnostics.logNavigation(
                        uri: uri,
                        isForMainFrame: navigationAction.isForMainFrame,
                        decision:
                            (uri != null && !isAllowed) ? 'CANCEL' : 'ALLOW',
                        method: navigationAction.request.method,
                      );
                      if (uri != null && !isAllowed) {
                        // Strictly reject non-X and insecure destinations
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                    onLoadResource: (controller, resource) async {
                      final uri = resource.url?.uriValue;
                      XAuthDiagnostics.logResourceLoad(
                        uri: uri,
                        initiatorType: resource.initiatorType,
                        duration: resource.duration,
                      );
                      if (uri != null && XNavigationPolicy.isAllowedXUrl(uri)) {
                        final path = uri.path.toLowerCase();
                        if (path.contains('task.json') ||
                            path.contains('/onboarding/') ||
                            path.contains('/actions/') ||
                            path.contains('/flow/') ||
                            path.contains('/challenge/') ||
                            path.contains('/verify/') ||
                            path.contains('/verification/') ||
                            path.contains('/arkose/') ||
                            path.contains('/captcha/') ||
                            path.contains('/auth/')) {
                          XAuthDiagnostics.logAuthMilestone(
                            'login_flow_network_activity',
                            {
                              'initiator': resource.initiatorType ?? 'unknown',
                              'path': uri.path,
                            },
                          );
                          await XAuthDiagnostics.probePageState(controller);
                          await _checkCookiePresenceOnly(uri);
                        }
                      }
                    },
                    onLoadStart: (controller, url) {
                      XAuthDiagnostics.logLoadStart(url?.uriValue);
                    },
                    onProgressChanged: (controller, progress) {
                      if (mounted) {
                        setState(() {
                          _loadProgress = progress / 100.0;
                          _isLoadingPage = progress < 100;
                        });
                      }
                    },
                    onLoadStop: (controller, url) async {
                      final uri = url?.uriValue;
                      XAuthDiagnostics.logLoadStop(uri);
                      XAuthDiagnostics.logAuthMilestone('login_page_loaded', {
                        'url': XAuthDiagnostics.sanitizeUri(uri),
                      });
                      await XAuthDiagnostics.probePageState(controller);
                      await _checkCookiePresenceOnly(uri);
                      if (mounted) {
                        setState(() {
                          _isLoadingPage = false;
                        });
                      }
                      await _checkDestinationForCookies(uri);
                    },
                    onUpdateVisitedHistory: (controller, url, isReload) async {
                      final uri = url?.uriValue;
                      XAuthDiagnostics.logVisitedHistory(uri, isReload);
                      await XAuthDiagnostics.probePageState(controller);
                      await _checkCookiePresenceOnly(uri);
                      await _checkDestinationForCookies(uri);
                    },
                    onReceivedError: (controller, request, error) {
                      XAuthDiagnostics.logError(
                        uri: request.url.uriValue,
                        errorCode: error.type.toNativeValue(),
                        description: error.description,
                        isForMainFrame: request.isForMainFrame,
                      );
                      if (request.isForMainFrame ?? true) {
                        if (mounted) {
                          setState(() {
                            _isLoadingPage = false;
                            _errorMessage =
                                'Unable to load X login page (${error.description}).';
                          });
                        }
                      }
                    },
                    onReceivedHttpError: (controller, request, errorResponse) {
                      XAuthDiagnostics.logHttpError(
                        uri: request.url.uriValue,
                        statusCode: errorResponse.statusCode,
                        reasonPhrase: errorResponse.reasonPhrase,
                      );
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      XAuthDiagnostics.logConsoleMessage(
                        level: consoleMessage.messageLevel,
                        message: consoleMessage.message,
                      );
                    },
                  ),
                  if (_isConnectingBackend)
                    Container(
                      color: colorScheme.surface.withValues(alpha: 0.9),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Establishing secure X session...',
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Creating ephemeral backend session',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
