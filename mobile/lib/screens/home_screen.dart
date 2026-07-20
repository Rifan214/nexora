import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/health_check_result.dart';
import '../models/media_metadata.dart';
import '../models/media_state.dart';
import '../providers/health_provider.dart';
import '../providers/media_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static const routeName = 'home';
  static const routePath = '/';

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final healthState = ref.watch(healthProvider);
    final mediaState = ref.watch(mediaProvider);
    final isCheckingHealth = healthState.isLoading;
    final isLoadingMedia = mediaState.maybeWhen(
      loading: () => true,
      orElse: () => false,
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nexora',
                    style: textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: isCheckingHealth
                        ? null
                        : () {
                            ref.read(healthProvider.notifier).checkBackend();
                          },
                    child: Text(isCheckingHealth ? 'Checking...' : 'Check Backend'),
                  ),
                  const SizedBox(height: 16),
                  _HealthStatus(healthState: healthState),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Media URL',
                    ),
                    onSubmitted: (_) => _getMetadata(isLoadingMedia),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: isLoadingMedia ? null : () => _getMetadata(isLoadingMedia),
                    child: Text(isLoadingMedia ? 'Loading...' : 'Get Metadata'),
                  ),
                  const SizedBox(height: 16),
                  _MediaStatus(mediaState: mediaState),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _getMetadata(bool isLoading) {
    if (isLoading) {
      return;
    }

    ref.read(mediaProvider.notifier).getMediaInfo(_urlController.text);
  }
}

class _HealthStatus extends StatelessWidget {
  const _HealthStatus({required this.healthState});

  final AsyncValue<HealthCheckResult?> healthState;

  @override
  Widget build(BuildContext context) {
    return healthState.when(
      data: (result) {
        if (result == null) {
          return const SizedBox.shrink();
        }

        return _StatusMessage(
          title: result.isHealthy ? '\u2705 Backend Online' : '\u274C Backend Offline',
          message: result.serverMessage,
        );
      },
      error: (error, _) {
        return _StatusMessage(
          title: '\u274C Backend Offline',
          message: error.toString(),
        );
      },
      loading: () {
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}

class _MediaStatus extends StatelessWidget {
  const _MediaStatus({required this.mediaState});

  final MediaState mediaState;

  @override
  Widget build(BuildContext context) {
    return mediaState.when(
      idle: () => const SizedBox.shrink(),
      loading: () {
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      success: (metadata) => _MetadataSummary(metadata: metadata),
      error: (message) {
        return _StatusMessage(
          title: '\u274C Metadata Error',
          message: message,
        );
      },
    );
  }
}

class _MetadataSummary extends StatelessWidget {
  const _MetadataSummary({required this.metadata});

  final MediaMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = metadata.thumbnailUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              thumbnailUrl,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return const SizedBox(
                  height: 180,
                  child: Center(
                    child: Text('Thumbnail unavailable'),
                  ),
                );
              },
            ),
          )
        else
          const SizedBox(
            height: 80,
            child: Center(
              child: Text('Thumbnail unavailable'),
            ),
          ),
        const SizedBox(height: 16),
        _MetadataRow(label: 'Title', value: metadata.title),
        _MetadataRow(label: 'Uploader', value: _fallback(metadata.uploader)),
        _MetadataRow(label: 'Duration', value: _formatDuration(metadata.durationSeconds)),
        _MetadataRow(label: 'Platform', value: metadata.platform),
        _MetadataRow(
          label: 'Available formats',
          value: metadata.formats.length.toString(),
        ),
      ],
    );
  }

  static String _fallback(String? value) {
    final trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) {
      return 'Unknown';
    }
    return trimmedValue;
  }

  static String _formatDuration(int? seconds) {
    if (seconds == null) {
      return 'Unknown';
    }

    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remainingSeconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$remainingSeconds';
    }

    return '${duration.inMinutes}:$remainingSeconds';
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium,
          ),
          Text(
            value,
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
