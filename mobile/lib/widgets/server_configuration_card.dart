import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../models/server_config.dart';
import '../providers/server_config_provider.dart';
import '../services/server_config_service.dart';
import '../utils/server_url_validator.dart';

/// Card widget allowing users to inspect and override the backend development server.
class ServerConfigurationCard extends ConsumerStatefulWidget {
  const ServerConfigurationCard({super.key});

  @override
  ConsumerState<ServerConfigurationCard> createState() =>
      _ServerConfigurationCardState();
}

class _ServerConfigurationCardState
    extends ConsumerState<ServerConfigurationCard> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;

  String? _validationError;
  bool _isTestingConnection = false;
  ServerConnectionTestResult? _testResult;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    final initialConfig = ref.read(effectiveServerConfigProvider);
    _hostController = TextEditingController(text: initialConfig.host);
    _portController = TextEditingController(text: initialConfig.port.toString());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _syncControllersIfUntouched(ServerConfig config) {
    if (!_hostController.text.isNotEmpty && !_portController.text.isNotEmpty) {
      _hostController.text = config.host;
      _portController.text = config.port.toString();
    }
  }

  Future<void> _handleTestConnection() async {
    setState(() {
      _validationError = null;
      _successMessage = null;
      _testResult = null;
    });

    final validation = ServerUrlValidator.validate(
      rawHost: _hostController.text,
      rawPort: _portController.text,
    );

    if (!validation.isValid) {
      setState(() {
        _validationError = validation.errorMessage;
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
    });

    try {
      final controller = ref.read(serverConfigProvider.notifier);
      final result = await controller.testConnection(
        host: validation.cleanHost!,
        port: validation.cleanPort!,
      );

      if (mounted) {
        setState(() {
          _testResult = result;
          _isTestingConnection = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResult = ServerConnectionTestResult(
            isSuccess: false,
            message: 'Test failed: $e',
          );
          _isTestingConnection = false;
        });
      }
    }
  }

  Future<void> _handleApply() async {
    setState(() {
      _validationError = null;
      _successMessage = null;
      _testResult = null;
    });

    final validation = ServerUrlValidator.validate(
      rawHost: _hostController.text,
      rawPort: _portController.text,
    );

    if (!validation.isValid) {
      setState(() {
        _validationError = validation.errorMessage;
      });
      return;
    }

    final controller = ref.read(serverConfigProvider.notifier);
    await controller.setOverride(
      host: validation.cleanHost!,
      port: validation.cleanPort!,
    );

    if (mounted) {
      // Normalize controllers with cleaned values
      _hostController.text = validation.cleanHost!;
      _portController.text = validation.cleanPort!.toString();

      setState(() {
        _successMessage =
            'Server applied: http://${validation.cleanHost}:${validation.cleanPort}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server updated to http://${validation.cleanHost}:${validation.cleanPort}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleReset() async {
    setState(() {
      _validationError = null;
      _successMessage = null;
      _testResult = null;
    });

    final controller = ref.read(serverConfigProvider.notifier);
    await controller.resetToDefault();

    final defaultCfg = ServerConfig.fromDefault();
    _hostController.text = defaultCfg.host;
    _portController.text = defaultCfg.port.toString();

    if (mounted) {
      setState(() {
        _successMessage = 'Server reset to default: ${defaultCfg.apiBaseUrl}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server reset to default (${defaultCfg.apiBaseUrl})'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final activeConfig = ref.watch(effectiveServerConfigProvider);

    _syncControllersIfUntouched(activeConfig);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: AppSizes.touchTarget + AppSpacing.xs,
                  height: AppSizes.touchTarget + AppSpacing.xs,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.dns_rounded,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Development Server',
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Configure backend IP for local testing without rebuilding.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),

            // Active Server Banner
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: AppRadii.input,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: AppSpacing.lg,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Active Server',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          activeConfig.apiBaseUrl,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: activeConfig.isCustomOverride
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadii.badge,
                    ),
                    child: Text(
                      activeConfig.isCustomOverride ? 'Custom' : 'Default',
                      style: textTheme.labelSmall?.copyWith(
                        color: activeConfig.isCustomOverride
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Form inputs
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Server Address', style: textTheme.labelMedium),
                      const SizedBox(height: AppSpacing.xxs),
                      TextField(
                        controller: _hostController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          hintText: '192.168.1.15',
                          prefixIcon: Icon(Icons.computer_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Port', style: textTheme.labelMedium),
                      const SizedBox(height: AppSpacing.xxs),
                      TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        decoration: const InputDecoration(
                          hintText: '8000',
                          prefixIcon: Icon(Icons.numbers_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_validationError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: colorScheme.error,
                    size: AppSpacing.md,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _validationError!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (_successMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: colorScheme.tertiary,
                    size: AppSpacing.md,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _successMessage!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.tertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Connection Test Result Banner
            if (_isTestingConnection) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadii.input,
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Testing connection to ${_hostController.text.trim()}:${_portController.text.trim()}...',
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_testResult != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: _testResult!.isSuccess
                      ? colorScheme.tertiaryContainer.withValues(alpha: 0.5)
                      : colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: AppRadii.input,
                ),
                child: Row(
                  children: [
                    Icon(
                      _testResult!.isSuccess
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      size: AppSpacing.md,
                      color: _testResult!.isSuccess
                          ? colorScheme.onTertiaryContainer
                          : colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _testResult!.message,
                        style: textTheme.bodySmall?.copyWith(
                          color: _testResult!.isSuccess
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // Action Buttons
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (activeConfig.isCustomOverride)
                  TextButton.icon(
                    onPressed: _handleReset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset to Default'),
                  ),
                OutlinedButton.icon(
                  onPressed: _isTestingConnection ? null : _handleTestConnection,
                  icon: const Icon(Icons.network_check_rounded, size: 18),
                  label: const Text('Test Connection'),
                ),
                FilledButton.icon(
                  onPressed: _handleApply,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
