import 'package:flutter/foundation.dart';
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
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final healthState = ref.watch(healthProvider);
    final mediaState = ref.watch(mediaProvider);
    final isCheckingHealth = healthState.isLoading;
    final hasMediaUrl = _urlController.text.trim().isNotEmpty;
    final isMediaBusy = _isMediaBusy(mediaState);
    final canRequestMetadata = hasMediaUrl && !isMediaBusy;
    final metadataButtonLabel = mediaState is MediaLoading
        ? 'Loading...'
        : isMediaBusy
            ? 'Please wait...'
            : 'Get Metadata';

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
                    enabled: !isMediaBusy,
                    onSubmitted: (_) => _getMetadata(canRequestMetadata),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        canRequestMetadata ? () => _getMetadata(canRequestMetadata) : null,
                    child: Text(metadataButtonLabel),
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

  void _getMetadata(bool canRequest) {
    if (!canRequest) {
      return;
    }

    ref.read(mediaProvider.notifier).getMediaInfo(_urlController.text);
  }

  void _onUrlChanged() {
    setState(() {});
  }

  bool _isMediaBusy(MediaState state) {
    if (state is MediaLoading) {
      return true;
    }

    if (state is! MediaSuccess) {
      return false;
    }

    final normalizedStatus = state.currentStatus?.toLowerCase();
    return state.downloadLoading ||
        state.fileDownloadLoading ||
        state.fileOpenLoading ||
        normalizedStatus == 'pending' ||
        normalizedStatus == 'processing';
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
          message: _readErrorMessage(error),
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

  String _readErrorMessage(Object error) {
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }

    return 'Unable to contact the backend.';
  }
}

class _MediaStatus extends ConsumerWidget {
  const _MediaStatus({required this.mediaState});

  final MediaState mediaState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return mediaState.map(
      idle: (_) => const SizedBox.shrink(),
      loading: (_) {
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      success: (state) {
        final mediaController = ref.read(mediaProvider.notifier);
        return _MetadataSummary(
          metadata: state.metadata,
          selectedVideoQuality: state.selectedVideoQuality,
          downloadLoading: state.downloadLoading,
          downloadSuccess: state.downloadSuccess,
          downloadError: state.downloadError,
          currentJobId: state.currentJobId,
          currentStatus: state.currentStatus,
          currentProgress: state.currentProgress,
          fileDownloadLoading: state.fileDownloadLoading,
          fileDownloadProgress: state.fileDownloadProgress,
          fileDownloadError: state.fileDownloadError,
          downloadedFilename: state.downloadedFilename,
          savedFilePath: state.savedFilePath,
          savedDirectory: state.savedDirectory,
          fileOpenLoading: state.fileOpenLoading,
          onVideoQualitySelected: mediaController.selectVideoQuality,
          onVideoDownloadPressed: mediaController.createVideoDownloadJob,
          onAudioDownloadPressed: mediaController.createAudioDownloadJob,
          onFileDownloadPressed: mediaController.downloadCompletedFile,
          onOpenFilePressed: mediaController.openDownloadedFile,
        );
      },
      error: (state) {
        return _StatusMessage(
          title: '\u274C Metadata Error',
          message: state.message,
        );
      },
    );
  }
}

class _MetadataSummary extends StatelessWidget {
  const _MetadataSummary({
    required this.metadata,
    required this.selectedVideoQuality,
    required this.downloadLoading,
    required this.downloadSuccess,
    required this.downloadError,
    required this.currentJobId,
    required this.currentStatus,
    required this.currentProgress,
    required this.fileDownloadLoading,
    required this.fileDownloadProgress,
    required this.fileDownloadError,
    required this.downloadedFilename,
    required this.savedFilePath,
    required this.savedDirectory,
    required this.fileOpenLoading,
    required this.onVideoQualitySelected,
    required this.onVideoDownloadPressed,
    required this.onAudioDownloadPressed,
    required this.onFileDownloadPressed,
    required this.onOpenFilePressed,
  });

  final MediaMetadata metadata;
  final VideoQuality? selectedVideoQuality;
  final bool downloadLoading;
  final bool downloadSuccess;
  final String? downloadError;
  final String? currentJobId;
  final String? currentStatus;
  final int currentProgress;
  final bool fileDownloadLoading;
  final int fileDownloadProgress;
  final String? fileDownloadError;
  final String? downloadedFilename;
  final String? savedFilePath;
  final String? savedDirectory;
  final bool fileOpenLoading;
  final ValueChanged<VideoQuality> onVideoQualitySelected;
  final VoidCallback onVideoDownloadPressed;
  final VoidCallback onAudioDownloadPressed;
  final VoidCallback onFileDownloadPressed;
  final VoidCallback onOpenFilePressed;

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = metadata.thumbnailUrl;
    final hasCreatedJob = downloadSuccess && currentJobId != null;
    final isDownloadActionDisabled = downloadLoading ||
        fileDownloadLoading ||
        fileOpenLoading ||
        _isActiveStatus(currentStatus) ||
        _isCompletedStatus(currentStatus);
    final isVideoDownloadDisabled =
        selectedVideoQuality == null || isDownloadActionDisabled;
    final isVideoQualitySelectionEnabled = !downloadLoading &&
        !fileDownloadLoading &&
        !fileOpenLoading &&
        !_isActiveStatus(currentStatus);

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
          label: 'Available qualities',
          value: metadata.videoQualities.length.toString(),
        ),
        const SizedBox(height: 16),
        _VideoQualitySelectionList(
          qualities: metadata.videoQualities,
          selectedVideoQuality: selectedVideoQuality,
          enabled: isVideoQualitySelectionEnabled,
          onVideoQualitySelected: onVideoQualitySelected,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: isVideoDownloadDisabled ? null : onVideoDownloadPressed,
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
        if (metadata.audioOptions.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Audio',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final option in metadata.audioOptions)
            _AudioOptionCard(
              option: option,
              enabled: !isDownloadActionDisabled,
              onSelected: onAudioDownloadPressed,
            ),
        ],
        if (hasCreatedJob) ...[
          const SizedBox(height: 16),
          _DownloadProgressStatus(
            status: currentStatus,
            progress: currentProgress,
            error: downloadError,
            fileDownloadLoading: fileDownloadLoading,
            fileDownloadProgress: fileDownloadProgress,
            fileDownloadError: fileDownloadError,
            downloadedFilename: downloadedFilename,
            savedFilePath: savedFilePath,
            savedDirectory: savedDirectory,
            fileOpenLoading: fileOpenLoading,
            onFileDownloadPressed: onFileDownloadPressed,
            onOpenFilePressed: onOpenFilePressed,
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
    required this.fileDownloadLoading,
    required this.fileDownloadProgress,
    required this.fileDownloadError,
    required this.downloadedFilename,
    required this.savedFilePath,
    required this.savedDirectory,
    required this.fileOpenLoading,
    required this.onFileDownloadPressed,
    required this.onOpenFilePressed,
  });

  final String? status;
  final int progress;
  final String? error;
  final bool fileDownloadLoading;
  final int fileDownloadProgress;
  final String? fileDownloadError;
  final String? downloadedFilename;
  final String? savedFilePath;
  final String? savedDirectory;
  final bool fileOpenLoading;
  final VoidCallback onFileDownloadPressed;
  final VoidCallback onOpenFilePressed;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status?.toLowerCase() ?? 'pending';
    final clampedProgress = _clampProgress(progress);

    if (normalizedStatus == 'completed') {
      return _CompletedDownloadSection(
        fileDownloadLoading: fileDownloadLoading,
        fileDownloadProgress: fileDownloadProgress,
        fileDownloadError: fileDownloadError,
        downloadedFilename: downloadedFilename,
        savedFilePath: savedFilePath,
        savedDirectory: savedDirectory,
        fileOpenLoading: fileOpenLoading,
        onFileDownloadPressed: onFileDownloadPressed,
        onOpenFilePressed: onOpenFilePressed,
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

class _CompletedDownloadSection extends StatelessWidget {
  const _CompletedDownloadSection({
    required this.fileDownloadLoading,
    required this.fileDownloadProgress,
    required this.fileDownloadError,
    required this.downloadedFilename,
    required this.savedFilePath,
    required this.savedDirectory,
    required this.fileOpenLoading,
    required this.onFileDownloadPressed,
    required this.onOpenFilePressed,
  });

  final bool fileDownloadLoading;
  final int fileDownloadProgress;
  final String? fileDownloadError;
  final String? downloadedFilename;
  final String? savedFilePath;
  final String? savedDirectory;
  final bool fileOpenLoading;
  final VoidCallback onFileDownloadPressed;
  final VoidCallback onOpenFilePressed;

  @override
  Widget build(BuildContext context) {
    final hasSavedFile = downloadedFilename != null &&
        downloadedFilename!.isNotEmpty &&
        savedFilePath != null &&
        savedFilePath!.isNotEmpty;
    final filename = downloadedFilename ?? '';
    final savedLocation = _fallback(savedDirectory, savedFilePath ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StatusMessage(
          title: '\u2705 Download Complete',
          message: 'Ready to download.',
        ),
        const SizedBox(height: 12),
        if (fileDownloadLoading)
          _FileTransferProgress(progress: fileDownloadProgress)
        else if (!hasSavedFile)
          FilledButton(
            onPressed: onFileDownloadPressed,
            child: const Text('Download File'),
          ),
        if (hasSavedFile) ...[
          const SizedBox(height: 12),
          _StatusMessage(
            title: '\u2705 File downloaded successfully',
            message: 'Filename:\n$filename\n\nSaved location:\n$savedLocation',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: fileOpenLoading ? null : onOpenFilePressed,
            child: Text(fileOpenLoading ? 'Opening...' : 'Open File'),
          ),
        ],
        if (fileDownloadError != null && fileDownloadError!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _StatusMessage(
            title: '\u274C File Download Error',
            message: fileDownloadError!,
          ),
        ],
      ],
    );
  }

  static String _fallback(String? value, String fallback) {
    final trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) {
      return fallback;
    }
    return trimmedValue;
  }
}

class _FileTransferProgress extends StatelessWidget {
  const _FileTransferProgress({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    final clampedProgress = _clampProgress(progress);
    final hasKnownProgress = clampedProgress > 0;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saving file',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          hasKnownProgress ? '$clampedProgress%' : 'Starting...',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: hasKnownProgress ? clampedProgress / 100 : null,
        ),
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
}

class _VideoQualitySelectionList extends StatelessWidget {
  const _VideoQualitySelectionList({
    required this.qualities,
    required this.selectedVideoQuality,
    required this.enabled,
    required this.onVideoQualitySelected,
  });

  final List<VideoQuality> qualities;
  final VideoQuality? selectedVideoQuality;
  final bool enabled;
  final ValueChanged<VideoQuality> onVideoQualitySelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (kDebugMode) {
      debugPrint('Video quality UI render count=${qualities.length}');
    }

    if (qualities.isEmpty) {
      return const Text('No video qualities were returned.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Qualities',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final quality in qualities)
          _VideoQualityCard(
            quality: quality,
            selectedHeight: selectedVideoQuality?.height,
            enabled: enabled,
            onSelected: () => onVideoQualitySelected(quality),
          ),
      ],
    );
  }
}

class _VideoQualityCard extends StatelessWidget {
  const _VideoQualityCard({
    required this.quality,
    required this.selectedHeight,
    required this.enabled,
    required this.onSelected,
  });

  final VideoQuality quality;
  final int? selectedHeight;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = selectedHeight == quality.height;

    return Card(
      color: isSelected ? colorScheme.secondaryContainer : null,
      child: ListTile(
        enabled: enabled,
        selected: isSelected,
        onTap: enabled ? onSelected : null,
        leading: Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: isSelected ? colorScheme.primary : null,
        ),
        title: Text(_qualityTitle(quality)),
        subtitle: Text(_qualitySubtitle(quality)),
      ),
    );
  }

  String _qualityTitle(VideoQuality quality) {
    return '${quality.label} - ${quality.extension.toUpperCase()}';
  }

  String _qualitySubtitle(VideoQuality quality) {
    return 'Estimated filesize: ${_formatFileSize(quality.estimatedFilesize)}';
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
}

class _AudioOptionCard extends StatelessWidget {
  const _AudioOptionCard({
    required this.option,
    required this.enabled,
    required this.onSelected,
  });

  final AudioOption option;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onSelected : null,
        leading: const Icon(Icons.music_note),
        title: Text('${option.label} (Best Quality)'),
        subtitle: Text(option.extension.toUpperCase()),
      ),
    );
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
