import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/theme/app_tokens.dart';
import '../providers/x_auth_provider.dart';
import '../services/cookie_file_picker_service.dart';
import '../utils/x_cookie_parser.dart';

/// Dialog allowing users to securely import an existing X session
/// via file import (cookies.txt / JSON), raw cookie text, or direct manual tokens.
///
/// Ensures raw cookie files/text are processed locally on mobile via [XCookieParser],
/// never stored to disk, never sent to the backend, and never leaked in logs or error UI.
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

  /// Maps parser errors into safe, user-friendly messages without leaking tokens.
  static String mapParserError(String? rawMessage) {
    if (rawMessage == null || rawMessage.trim().isEmpty) {
      return 'Could not recognize valid X cookies in the provided input.';
    }
    final msg = rawMessage.toLowerCase();
    if (msg.contains('missing') && msg.contains('auth_token')) {
      return 'auth_token cookie was not found in the imported cookie data.';
    }
    if (msg.contains('missing') && msg.contains('ct0')) {
      return 'ct0 (CSRF token) cookie was not found in the imported cookie data.';
    }
    if (msg.contains('empty')) {
      return 'Imported cookie data contains empty credential values.';
    }
    if (msg.contains('length') || msg.contains('exceeds')) {
      return 'Imported cookie value exceeds maximum allowed length.';
    }
    if (msg.contains('json')) {
      return 'Invalid JSON cookie export format.';
    }
    return 'Could not recognize valid X cookies in the provided input.';
  }

  @override
  ConsumerState<XManualCookieDialog> createState() =>
      _XManualCookieDialogState();
}

class _XManualCookieDialogState extends ConsumerState<XManualCookieDialog> {
  final _cookieTextController = TextEditingController();
  final _authTokenController = TextEditingController();
  final _ct0Controller = TextEditingController();

  bool _obscureAuthToken = true;
  bool _obscureCt0 = true;
  bool _isSubmitting = false;
  bool _isFileImporting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _cookieTextController.dispose();
    _authTokenController.dispose();
    _ct0Controller.dispose();
    super.dispose();
  }

  Future<void> _pasteInto(TextEditingController controller, {bool truncate = true}) async {
    if (_isSubmitting) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        final processed = (truncate && text.length > 512) ? text.substring(0, 512) : text;
        controller.text = processed;
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

  Future<void> _handleFileImport() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _isFileImporting = true;
      _errorMessage = null;
    });

    try {
      final filePicker = ref.read(cookieFilePickerProvider);
      final content = await filePicker.pickAndReadCookieFile();
      if (content == null) {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _isFileImporting = false;
          });
        }
        return;
      }
      if (content.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _isFileImporting = false;
            _errorMessage = 'Selected file is empty or could not be read.';
          });
        }
        return;
      }

      final parsed = XCookieParser.parse(content);

      await ref.read(xAuthProvider.notifier).authenticateWithCookies(
            authToken: parsed.authToken,
            ct0: parsed.ct0,
          );

      _cookieTextController.clear();
      _authTokenController.clear();
      _ct0Controller.clear();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isFileImporting = false;
          _errorMessage = XManualCookieDialog.mapParserError(e.message);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isFileImporting = false;
          _errorMessage = XManualCookieDialog.mapError(e.message);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isFileImporting = false;
          _errorMessage = 'Could not read or process the selected file.';
        });
      }
    }
  }

  Future<void> _handleConnect() async {
    if (_isSubmitting) return;

    final rawCookieText = _cookieTextController.text.trim();
    final rawAuthToken = _authTokenController.text.trim();
    final rawCt0 = _ct0Controller.text.trim();

    String authToken;
    String ct0;

    if (rawCookieText.isNotEmpty) {
      try {
        final parsed = XCookieParser.parse(rawCookieText);
        authToken = parsed.authToken;
        ct0 = parsed.ct0;
      } on FormatException catch (e) {
        setState(() {
          _errorMessage = XManualCookieDialog.mapParserError(e.message);
        });
        return;
      } catch (_) {
        setState(() {
          _errorMessage = 'Could not parse cookie text. Please verify the format.';
        });
        return;
      }
    } else if (rawAuthToken.isNotEmpty || rawCt0.isNotEmpty) {
      if (rawAuthToken.isEmpty || rawCt0.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter both X session cookies.';
        });
        return;
      }
      authToken = rawAuthToken;
      ct0 = rawCt0;
    } else {
      setState(() {
        _errorMessage = 'Please import a cookies.txt file, paste cookie text, or enter both tokens.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(xAuthProvider.notifier).authenticateWithCookies(
            authToken: authToken,
            ct0: ct0,
          );

      // Credential references are released immediately and inputs cleared
      _cookieTextController.clear();
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
    _cookieTextController.clear();
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
                    'Choose file, paste cookies, or enter tokens',
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
                  'Import cookies.txt from your browser extension or enter session tokens. Nexora parses cookies locally and never asks for your password.',
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

                // Action: Import cookies.txt file
                OutlinedButton.icon(
                  key: const Key('import_cookie_file_button'),
                  onPressed: _isSubmitting ? null : _handleFileImport,
                  icon: _isFileImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload_outlined, size: 20),
                  label: Text(_isFileImporting ? 'Importing file...' : 'Import cookies.txt'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    shape: const RoundedRectangleBorder(borderRadius: AppRadii.input),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Action: Paste cookie text multiline field
                TextFormField(
                  key: const Key('paste_cookie_text_field'),
                  controller: _cookieTextController,
                  enabled: !_isSubmitting,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Paste Cookie Text (Optional)',
                    hintText: 'Paste Netscape cookies.txt, JSON, or header...',
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.input,
                    ),
                    suffixIcon: IconButton(
                      key: const Key('paste_cookie_text_button'),
                      icon: const Icon(Icons.paste_rounded, size: 20),
                      tooltip: 'Paste from clipboard',
                      onPressed: _isSubmitting
                          ? null
                          : () => _pasteInto(_cookieTextController, truncate: false),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Divider: OR ENTER TOKENS MANUALLY
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text(
                        'OR ENTER TOKENS MANUALLY',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

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
