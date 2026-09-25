import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../providers/x_auth_provider.dart';
import '../services/x_cookie_manager.dart';
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

  @override
  void dispose() {
    _webViewController = null;
    super.dispose();
  }

  Future<void> _handleCancel() async {
    // Purge any partial/temporary authentication cookies on cancellation
    try {
      await ref.read(xCookieManagerProvider).clearXCookies();
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _checkDestinationForCookies(Uri? uri) async {
    if (_hasExtracted || _isConnectingBackend || uri == null) {
      return;
    }

    // Only inspect when navigating away from the login/challenge flow
    if (!XNavigationPolicy.isPotentialAuthenticatedDestination(uri)) {
      return;
    }

    final cookieManager = ref.read(xCookieManagerProvider);
    final extracted = await cookieManager.extractSessionCookies(uri);

    if (extracted != null && extracted.isValid && mounted) {
      _hasExtracted = true;
      setState(() {
        _isConnectingBackend = true;
        _errorMessage = null;
      });

      try {
        // Ephemeral in-memory bridge to existing XAuthService via XAuthController
        await ref.read(xAuthProvider.notifier).authenticateWithCookies(
              authToken: extracted.authToken,
              ct0: extracted.ct0,
            );

        // Immediately purge WebView cookies to avoid lingering browser session
        await cookieManager.clearXCookies();

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (_) {
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
    }
  }

  void _retryLogin() {
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
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri.uri(XNavigationPolicy.loginUri),
                    ),
                    initialSettings: InAppWebViewSettings(
                      useShouldOverrideUrlLoading: true,
                      javaScriptEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      clearCache: true,
                      cacheEnabled: false,
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                      final uri = navigationAction.request.url?.uriValue;
                      if (uri != null &&
                          !XNavigationPolicy.isAllowedXUrl(uri)) {
                        // Strictly reject non-X and insecure destinations
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.ALLOW;
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
                      if (mounted) {
                        setState(() {
                          _isLoadingPage = false;
                        });
                      }
                      await _checkDestinationForCookies(url?.uriValue);
                    },
                    onUpdateVisitedHistory: (controller, url, isReload) async {
                      await _checkDestinationForCookies(url?.uriValue);
                    },
                    onReceivedError: (controller, request, error) {
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
