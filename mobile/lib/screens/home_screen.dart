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

class _MediaStatus extends ConsumerWidget {
  const _MediaStatus({required this.mediaState});

  final MediaState mediaState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      success: (
        metadata,
        selectedFormat,
        downloadLoading,
        downloadSuccess,
        downloadError,
        currentJobId,
        currentStatus,
        currentProgress,
        _,
      ) {
        return _MetadataSummary(
          metadata: metadata,
          selectedFormat: selectedFormat,
          downloadLoading: downloadLoading,
          downloadSuccess: downloadSuccess,
          downloadError: downloadError,
          currentJobId: currentJobId,
          currentStatus: currentStatus,
          currentProgress: currentProgress,
          onFormatSelected: ref.read(mediaProvider.notifier).selectFormat,
          onDownloadPressed: ref.read(mediaProvider.notifier).createDownloadJob,
        );
      },
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
  const _MetadataSummary({
    required this.metadata,
    required this.selectedFormat,
    required this.downloadLoading,
    required this.downloadSuccess,
    required this.downloadError,
    required this.currentJobId,
    required this.currentStatus,
    required this.currentProgress,
    required this.onFormatSelected,
    required this.onDownloadPressed,
  });

  final MediaMetadata metadata;
  final MediaFormat? selectedFormat;
  final bool downloadLoading;
  final bool downloadSuccess;
  final String? downloadError;
  final String? currentJobId;
  final String? currentStatus;
  final int currentProgress;
  final ValueChanged<MediaFormat> onFormatSelected;
  final VoidCallback onDownloadPressed;

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = metadata.thumbnailUrl;
    final hasCreatedJob = downloadSuccess && currentJobId != null;
    final isDownloadDisabled = selectedFormat == null ||
        downloadLoading ||
        _isActiveStatus(currentStatus) ||
        _isCompletedStatus(currentStatus);

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
        const SizedBox(height: 16),
        _FormatSelectionList(
          formats: metadata.formats,
          selectedFormat: selectedFormat,
          onFormatSelected: onFormatSelected,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: isDownloadDisabled ? null : onDownloadPressed,
          child: downloadLoading
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Download'),
                  ],
                )
              : const Text('Download'),
        ),
        if (hasCreatedJob) ...[
          const SizedBox(height: 16),
          _DownloadProgressStatus(
            status: currentStatus,
            progress: currentProgress,
            error: downloadError,
          ),
        ] else if (downloadError != null && downloadError!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _StatusMessage(
            title: '\u274C Download Error',
            message: downloadError!,
          ),
        ],
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

  bool _isActiveStatus(String? status) {
    final normalizedStatus = status?.toLowerCase();
    return normalizedStatus == 'pending' || normalizedStatus == 'processing';
  }

  bool _isCompletedStatus(String? status) {
    return status?.toLowerCase() == 'completed';
  }
}

class _DownloadProgressStatus extends StatelessWidget {
  const _DownloadProgressStatus({
    required this.status,
    required this.progress,
    required this.error,
  });

  final String? status;
  final int progress;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status?.toLowerCase() ?? 'pending';
    final clampedProgress = _clampProgress(progress);

    if (normalizedStatus == 'completed') {
      return const _StatusMessage(
        title: '\u2705 Download Complete',
        message: 'Ready to download.',
      );
    }

    if (normalizedStatus == 'failed') {
      return _StatusMessage(
        title: '\u274C Download Failed',
        message: _fallback(error, 'Download failed.'),
      );
    }

    if (error != null && error!.isNotEmpty) {
      return _StatusMessage(
        title: '\u274C Progress Error',
        message: error!,
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status: ${_formatStatus(normalizedStatus)}',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '$clampedProgress%',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: clampedProgress / 100),
      ],
    );
  }

  int _clampProgress(int value) {
    if (value < 0) {
      return 0;
    }

    if (value > 100) {
      return 100;
    }

    return value;
  }

  String _formatStatus(String value) {
    final words = value.replaceAll('_', ' ').split(' ');
    return words.map((word) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
  }

  static String _fallback(String? value, String fallback) {
    final trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) {
      return fallback;
    }
    return trimmedValue;
  }
}

class _FormatSelectionList extends StatelessWidget {
  const _FormatSelectionList({
    required this.formats,
    required this.selectedFormat,
    required this.onFormatSelected,
  });

  final List<MediaFormat> formats;
  final MediaFormat? selectedFormat;
  final ValueChanged<MediaFormat> onFormatSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (formats.isEmpty) {
      return const Text('No formats were returned.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Formats',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final format in formats)
          _FormatCard(
            format: format,
            selectedFormatId: selectedFormat?.formatId,
            onSelected: () => onFormatSelected(format),
          ),
      ],
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.format,
    required this.selectedFormatId,
    required this.onSelected,
  });

  final MediaFormat format;
  final String? selectedFormatId;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = selectedFormatId == format.formatId;

    return Card(
      color: isSelected ? colorScheme.secondaryContainer : null,
      child: RadioListTile<String>(
        value: format.formatId,
        groupValue: selectedFormatId,
        onChanged: (_) => onSelected(),
        selected: isSelected,
        title: Text(_formatTitle(format)),
        subtitle: Text(_formatSubtitle(format)),
      ),
    );
  }

  String _formatTitle(MediaFormat format) {
    final resolution = _fallback(format.resolution);
    final extension = format.extension.toUpperCase();
    return '$resolution - $extension';
  }

  String _formatSubtitle(MediaFormat format) {
    final parts = <String>[
      'Estimated filesize: ${_formatFileSize(format.filesize)}',
      if (format.fps != null) 'FPS: ${format.fps}',
      'Video codec: ${_fallback(format.videoCodec)}',
      'Audio codec: ${_fallback(format.audioCodec)}',
    ];

    return parts.join('\n');
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) {
      return 'Unknown';
    }

    const kib = 1024;
    const mib = kib * 1024;
    const gib = mib * 1024;

    if (bytes >= gib) {
      return '${(bytes / gib).toStringAsFixed(1)} GB';
    }

    if (bytes >= mib) {
      return '${(bytes / mib).toStringAsFixed(1)} MB';
    }

    if (bytes >= kib) {
      return '${(bytes / kib).toStringAsFixed(1)} KB';
    }

    return '$bytes B';
  }

  String _fallback(String? value) {
    final trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) {
      return 'Unknown';
    }
    return trimmedValue;
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
