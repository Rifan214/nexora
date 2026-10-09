import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/theme/app_tokens.dart';
import '../providers/instagram_auth_provider.dart';
import '../services/cookie_file_picker_service.dart';
import '../utils/instagram_cookie_parser.dart';

/// Dialog allowing users to manually import or configure their Instagram session credentials.
///
/// Ensures raw cookie files/text are processed locally on mobile via [InstagramCookieParser],
/// never stored to disk, never sent to the backend, and never leaked in logs or error UI.
class InstagramManualCookieDialog extends ConsumerStatefulWidget {
  const InstagramManualCookieDialog({super.key});

  /// Presents the manual cookie import dialog.
  ///
  /// Returns `true` if authentication succeeded, `false` or `null` otherwise.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const InstagramManualCookieDialog(),
    );
  }

  /// Maps internal or backend errors into safe, static user-facing error messages.
  ///
  /// Guarantees raw credential values, request bodies, and headers are never echoed.
  static String mapError(String? rawMessage) {
    if (rawMessage == null || rawMessage.trim().isEmpty) {
      return 'Unable to connect this Instagram session. Please verify the imported cookies and try again.';
    }
    final msg = rawMessage.toLowerCase();
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('timeout')) {
      return 'Could not connect to the server. Please check your connection and try again.';
    }
    if (msg.contains('storage') || msg.contains('saved locally')) {
      return 'Instagram session was created, but could not be saved locally.';
    }
    return 'Unable to connect this Instagram session. Please verify the imported cookies and try again.';
  }

  /// Maps parser errors into safe, user-friendly messages without leaking tokens.
  static String mapParserError(String? rawMessage) {
    if (rawMessage == null || rawMessage.trim().isEmpty) {
      return 'Could not recognize valid Instagram cookies in the provided input.';
    }
    final msg = rawMessage.toLowerCase();
    if (msg.contains('missing') && msg.contains('sessionid')) {
      return 'sessionid cookie was not found in the imported cookie data.';
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
    return 'Could not recognize valid Instagram cookies in the provided input.';
  }

  @override
  ConsumerState<InstagramManualCookieDialog> createState() =>
      _InstagramManualCookieDialogState();
}

class _InstagramManualCookieDialogState
    extends ConsumerState<InstagramManualCookieDialog> {
  final _cookieTextController = TextEditingController();
  final _sessionidController = TextEditingController();
  final _dsUserIdController = TextEditingController();

  bool _obscureSessionid = true;
  bool _obscureDsUserId = true;
  bool _isSubmitting = false;
  bool _isFileImporting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _cookieTextController.dispose();
    _sessionidController.dispose();
    _dsUserIdController.dispose();
    super.dispose();
  }

  void _handleCancel() {
    if (_isSubmitting) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _pasteInto(
    TextEditingController controller, {
    bool truncate = true,
  }) async {
    if (_isSubmitting) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        setState(() {
          controller.text = truncate && text.length > 2048
              ? text.substring(0, 2048)
              : text;
          _errorMessage = null;
        });
      }
    } catch (_) {
      // Safe fallback on clipboard failure
    }
  }

  Future<void> _handleFileImport() async {
    if (_isSubmitting || _isFileImporting) return;
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

      final parsed = InstagramCookieParser.parse(content);

      await ref.read(instagramAuthProvider.notifier).authenticateWithCookies(
            sessionid: parsed.sessionid,
            dsUserId: parsed.dsUserId,
            csrftoken: parsed.csrftoken,
          );

      _cookieTextController.clear();
      _sessionidController.clear();
      _dsUserIdController.clear();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isFileImporting = false;
          _errorMessage = InstagramManualCookieDialog.mapParserError(e.message);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isFileImporting = false;
          _errorMessage = InstagramManualCookieDialog.mapError(e.message);
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
    final rawSessionid = _sessionidController.text.trim();
    final rawDsUserId = _dsUserIdController.text.trim();

    String sessionid;
    String? dsUserId;
    String? csrftoken;

    if (rawCookieText.isNotEmpty) {
      try {
        final parsed = InstagramCookieParser.parse(rawCookieText);
        sessionid = parsed.sessionid;
        dsUserId = parsed.dsUserId;
        csrftoken = parsed.csrftoken;
      } on FormatException catch (e) {
        setState(() {
          _errorMessage = InstagramManualCookieDialog.mapParserError(e.message);
        });
        return;
      } catch (_) {
        setState(() {
          _errorMessage = 'Could not parse cookie text. Please verify the format.';
        });
        return;
      }
    } else if (rawSessionid.isNotEmpty) {
      sessionid = rawSessionid;
      dsUserId = rawDsUserId.isNotEmpty ? rawDsUserId : null;
    } else {
      setState(() {
        _errorMessage = 'Please import a cookies.txt file, paste cookie text, or enter sessionid.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(instagramAuthProvider.notifier).authenticateWithCookies(
            sessionid: sessionid,
            dsUserId: dsUserId,
            csrftoken: csrftoken,
          );

      _cookieTextController.clear();
      _sessionidController.clear();
      _dsUserIdController.clear();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = InstagramManualCookieDialog.mapError(e.message);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to connect Instagram session.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                color: colorScheme.onSecondaryContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Instagram Cookie Authentication',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Connect via Netscape file, JSON, or session token',
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
                // File Import Button
                OutlinedButton.icon(
                  key: const Key('instagram_import_file_button'),
                  onPressed: _isSubmitting ? null : _handleFileImport,
                  icon: _isFileImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload_outlined),
                  label: const Text('Import cookies.txt or JSON'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadii.input,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Divider with "OR"
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: Text(
                        'OR PASTE TEXT',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // Cookie Text Field (with Paste button)
                TextField(
                  key: const Key('instagram_cookie_text_field'),
                  controller: _cookieTextController,
                  enabled: !_isSubmitting,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Paste cookies.txt content or raw Cookie header',
                    hintStyle: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.input,
                    ),
                    suffixIcon: IconButton(
                      key: const Key('instagram_paste_cookie_text_button'),
                      icon: const Icon(Icons.paste_rounded, size: 20),
                      tooltip: 'Paste from clipboard',
                      onPressed: () => _pasteInto(_cookieTextController, truncate: false),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Divider with "OR MANUAL ENTRY"
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: Text(
                        'OR ENTER TOKENS',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // sessionid Field
                TextField(
                  key: const Key('instagram_sessionid_field'),
                  controller: _sessionidController,
                  enabled: !_isSubmitting,
                  obscureText: _obscureSessionid,
                  decoration: InputDecoration(
                    labelText: 'sessionid (Required)',
                    labelStyle: textTheme.bodySmall,
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.input,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const Key('instagram_toggle_sessionid_visibility'),
                          icon: Icon(
                            _obscureSessionid
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureSessionid = !_obscureSessionid;
                            });
                          },
                        ),
                        IconButton(
                          key: const Key('instagram_paste_sessionid_button'),
                          icon: const Icon(Icons.paste_rounded, size: 20),
                          tooltip: 'Paste',
                          onPressed: () => _pasteInto(_sessionidController),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ds_user_id Field (Optional)
                TextField(
                  key: const Key('instagram_ds_user_id_field'),
                  controller: _dsUserIdController,
                  enabled: !_isSubmitting,
                  obscureText: _obscureDsUserId,
                  decoration: InputDecoration(
                    labelText: 'ds_user_id (Optional)',
                    labelStyle: textTheme.bodySmall,
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.input,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const Key('instagram_toggle_ds_user_id_visibility'),
                          icon: Icon(
                            _obscureDsUserId
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureDsUserId = !_obscureDsUserId;
                            });
                          },
                        ),
                        IconButton(
                          key: const Key('instagram_paste_ds_user_id_button'),
                          icon: const Icon(Icons.paste_rounded, size: 20),
                          tooltip: 'Paste',
                          onPressed: () => _pasteInto(_dsUserIdController),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
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
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('instagram_cancel_button'),
            onPressed: _isSubmitting ? null : _handleCancel,
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('instagram_connect_button'),
            onPressed: _isSubmitting ? null : _handleConnect,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
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
