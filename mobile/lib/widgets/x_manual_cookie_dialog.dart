import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/theme/app_tokens.dart';
import '../providers/x_auth_provider.dart';

/// Dialog allowing power users to securely import an existing X session
/// by entering `auth_token` and `ct0` session cookies directly.
///
/// Ensures credentials are kept strictly in-memory during transfer, never
/// persisted, never displayed after creation, and never leaked in logs or errors.
class XManualCookieDialog extends ConsumerStatefulWidget {
  const XManualCookieDialog({super.key});

  /// Presents the manual cookie import dialog.
  ///
  /// Returns `true` if authentication succeeded, `false` or `null` otherwise.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const XManualCookieDialog(),
    );
  }

  /// Maps internal or backend errors into safe, static user-facing error messages.
  ///
  /// Guarantees raw credential values, request bodies, and headers are never echoed.
  static String mapError(String? rawMessage) {
    if (rawMessage == null || rawMessage.trim().isEmpty) {
      return 'Unable to connect this X session. Please verify the imported cookies and try again.';
    }
    final msg = rawMessage.toLowerCase();
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('timeout')) {
      return 'Could not connect to the server. Please check your connection and try again.';
    }
    if (msg.contains('storage') || msg.contains('saved locally')) {
      return 'X session was created, but could not be saved locally.';
    }
    return 'Unable to connect this X session. Please verify the imported cookies and try again.';
  }

  @override
  ConsumerState<XManualCookieDialog> createState() =>
      _XManualCookieDialogState();
}

class _XManualCookieDialogState extends ConsumerState<XManualCookieDialog> {
  final _authTokenController = TextEditingController();
  final _ct0Controller = TextEditingController();

  bool _obscureAuthToken = true;
  bool _obscureCt0 = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _authTokenController.dispose();
    _ct0Controller.dispose();
    super.dispose();
  }

  Future<void> _pasteInto(TextEditingController controller) async {
    if (_isSubmitting) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        // Enforce maximum length consistent with backend validation
        final truncated = text.length > 512 ? text.substring(0, 512) : text;
        controller.text = truncated;
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
      }
    } catch (_) {
      // Safe fallback if clipboard access is denied
    }
  }

  Future<void> _handleConnect() async {
    if (_isSubmitting) return;

    final rawAuthToken = _authTokenController.text.trim();
    final rawCt0 = _ct0Controller.text.trim();

    if (rawAuthToken.isEmpty || rawCt0.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both X session cookies.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(xAuthProvider.notifier).authenticateWithCookies(
            authToken: rawAuthToken,
            ct0: rawCt0,
          );

      // Credential references are released as early as practical and are not persisted
      _authTokenController.clear();
      _ct0Controller.clear();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = XManualCookieDialog.mapError(e.message);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage =
              'Could not connect to the server. Please check your connection and try again.';
        });
      }
    }
  }

  void _handleCancel() {
    if (_isSubmitting) return;
    _authTokenController.clear();
    _ct0Controller.clear();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.card),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.sm,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xs,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: AppRadii.duration,
              ),
              child: Icon(
                Icons.key_rounded,
                size: 22,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import X Session',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Paste active cookies from browser',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: AppSizes.actionPanelMaxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Obtain auth_token and ct0 from your personal browser (Developer Tools > Application > Cookies > x.com). Nexora never asks for your password.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Error message banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: AppRadii.badge,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: colorScheme.onErrorContainer,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            key: const Key('manual_cookie_error_text'),
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // auth_token field
                TextFormField(
                  key: const Key('manual_auth_token_field'),
                  controller: _authTokenController,
                  obscureText: _obscureAuthToken,
                  enabled: !_isSubmitting,
                  maxLength: 512,
                  decoration: InputDecoration(
                    labelText: 'auth_token',
                    hintText: 'Enter auth_token cookie',
                    counterText: '',
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.input,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const Key('toggle_auth_token_visibility'),
                          icon: Icon(
                            _obscureAuthToken
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          tooltip: _obscureAuthToken ? 'Show' : 'Hide',
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _obscureAuthToken = !_obscureAuthToken;
                                  });
                                },
                        ),
                        IconButton(
                          key: const Key('paste_auth_token_button'),
                          icon: const Icon(Icons.paste_rounded, size: 20),
                          tooltip: 'Paste',
                          onPressed: _isSubmitting
                              ? null
                              : () => _pasteInto(_authTokenController),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ct0 field
                TextFormField(
                  key: const Key('manual_ct0_field'),
                  controller: _ct0Controller,
                  obscureText: _obscureCt0,
                  enabled: !_isSubmitting,
                  maxLength: 512,
                  decoration: InputDecoration(
                    labelText: 'ct0 (CSRF Token)',
                    hintText: 'Enter ct0 cookie',
                    counterText: '',
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.input,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const Key('toggle_ct0_visibility'),
                          icon: Icon(
                            _obscureCt0
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          tooltip: _obscureCt0 ? 'Show' : 'Hide',
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _obscureCt0 = !_obscureCt0;
                                  });
                                },
                        ),
                        IconButton(
                          key: const Key('paste_ct0_button'),
                          icon: const Icon(Icons.paste_rounded, size: 20),
                          tooltip: 'Paste',
                          onPressed: _isSubmitting
                              ? null
                              : () => _pasteInto(_ct0Controller),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('manual_import_cancel_button'),
            onPressed: _isSubmitting ? null : _handleCancel,
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('manual_import_connect_button'),
            onPressed: _isSubmitting ? null : _handleConnect,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
