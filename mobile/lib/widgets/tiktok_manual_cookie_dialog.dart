import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/theme/app_tokens.dart';
import '../providers/tiktok_auth_provider.dart';
import '../services/cookie_file_picker_service.dart';
import '../utils/tiktok_cookie_parser.dart';

/// Dialog allowing users to manually import or configure their TikTok session credentials.
///
/// Ensures raw cookie files/text are processed locally on mobile via [TikTokCookieParser],
/// never stored to disk, never sent to the backend, and never leaked in logs or error UI.
class TikTokManualCookieDialog extends ConsumerStatefulWidget {
  const TikTokManualCookieDialog({super.key});

  /// Presents the manual cookie import dialog.
  ///
  /// Returns `true` if authentication succeeded, `false` or `null` otherwise.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const TikTokManualCookieDialog(),
    );
  }

  /// Maps internal or backend errors into safe, static user-facing error messages.
  ///
  /// Guarantees raw credential values, request bodies, and headers are never echoed.
  static String mapError(String? rawMessage) {
    if (rawMessage == null || rawMessage.trim().isEmpty) {
      return 'Unable to connect this TikTok session. Please verify the imported cookies and try again.';
    }
    final msg = rawMessage.toLowerCase();
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('timeout')) {
      return 'Could not connect to the server. Please check your connection and try again.';
    }
    if (msg.contains('storage') || msg.contains('saved locally')) {
      return 'TikTok session was created, but could not be saved locally.';
    }
    return 'Unable to connect this TikTok session. Please verify the imported cookies and try again.';
  }

  /// Maps parser errors into safe, user-friendly messages without leaking tokens.
  static String mapParserError(String? rawMessage) {
    if (rawMessage == null || rawMessage.trim().isEmpty) {
      return 'Could not recognize valid TikTok cookies in the provided input.';
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
    return 'Could not recognize valid TikTok cookies in the provided input.';
  }

  @override
  ConsumerState<TikTokManualCookieDialog> createState() =>
      _TikTokManualCookieDialogState();
}

class _TikTokManualCookieDialogState
    extends ConsumerState<TikTokManualCookieDialog> {
  final _cookieTextController = TextEditingController();
  final _sessionidController = TextEditingController();
  final _sidTtController = TextEditingController();

  bool _obscureSessionid = true;
  bool _obscureSidTt = true;
  bool _isSubmitting = false;
  bool _isFileImporting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _cookieTextController.dispose();
    _sessionidController.dispose();
    _sidTtController.dispose();
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

      final parsed = TikTokCookieParser.parse(content);

      await ref.read(tikTokAuthProvider.notifier).authenticateWithCookies(
            sessionid: parsed.sessionid,
            sidTt: parsed.sidTt,
          );

      _cookieTextController.clear();
      _sessionidController.clear();
      _sidTtController.clear();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isFileImporting = false;
          _errorMessage = TikTokManualCookieDialog.mapParserError(e.message);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isFileImporting = false;
          _errorMessage = TikTokManualCookieDialog.mapError(e.message);
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
    final rawSidTt = _sidTtController.text.trim();

    String sessionid;
    String? sidTt;

    if (rawCookieText.isNotEmpty) {
      try {
        final parsed = TikTokCookieParser.parse(rawCookieText);
        sessionid = parsed.sessionid;
        sidTt = parsed.sidTt;
      } on FormatException catch (e) {
        setState(() {
          _errorMessage = TikTokManualCookieDialog.mapParserError(e.message);
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
      sidTt = rawSidTt.isNotEmpty ? rawSidTt : null;
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
      await ref.read(tikTokAuthProvider.notifier).authenticateWithCookies(
            sessionid: sessionid,
            sidTt: sidTt,
          );

      _cookieTextController.clear();
      _sessionidController.clear();
      _sidTtController.clear();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = TikTokManualCookieDialog.mapError(e.message);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = TikTokManualCookieDialog.mapError(null);
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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.music_note_rounded,
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
                    'Import TikTok Session',
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

                // sessionid field
                TextFormField(
                  key: const Key('manual_sessionid_field'),
                  controller: _sessionidController,
                  obscureText: _obscureSessionid,
                  enabled: !_isSubmitting,
                  maxLength: 512,
                  decoration: InputDecoration(
                    labelText: 'sessionid (Required)',
                    hintText: 'Enter sessionid cookie',
                    counterText: '',
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.input,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const Key('toggle_sessionid_visibility'),
                          icon: Icon(
                            _obscureSessionid
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          tooltip: _obscureSessionid ? 'Show' : 'Hide',
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _obscureSessionid = !_obscureSessionid;
                                  });
                                },
                        ),
                        IconButton(
                          key: const Key('paste_sessionid_button'),
                          icon: const Icon(Icons.paste_rounded, size: 20),
                          tooltip: 'Paste',
                          onPressed: _isSubmitting
                              ? null
                              : () => _pasteInto(_sessionidController),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // sid_tt field
                TextFormField(
                  key: const Key('manual_sid_tt_field'),
                  controller: _sidTtController,
                  obscureText: _obscureSidTt,
                  enabled: !_isSubmitting,
                  maxLength: 512,
                  decoration: InputDecoration(
                    labelText: 'sid_tt (Optional)',
                    hintText: 'Enter sid_tt cookie',
                    counterText: '',
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.input,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const Key('toggle_sid_tt_visibility'),
                          icon: Icon(
                            _obscureSidTt
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          tooltip: _obscureSidTt ? 'Show' : 'Hide',
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _obscureSidTt = !_obscureSidTt;
                                  });
                                },
                        ),
                        IconButton(
                          key: const Key('paste_sid_tt_button'),
                          icon: const Icon(Icons.paste_rounded, size: 20),
                          tooltip: 'Paste',
                          onPressed: _isSubmitting
                              ? null
                              : () => _pasteInto(_sidTtController),
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
