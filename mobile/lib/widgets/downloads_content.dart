import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../models/media_download_type.dart';
import '../models/media_state.dart';
import 'media_card_parts.dart';
import 'nexora_brand.dart';
import 'nexora_state_panel.dart';

class DownloadsContent extends StatelessWidget {
  const DownloadsContent({
    super.key,
    required this.mediaState,
  });

  final MediaState mediaState;

  @override
  Widget build(BuildContext context) {
    final activeDownloads = _activeDownloads(mediaState);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: AppSpacing.pageHorizontal,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.md),
              const Align(
                alignment: Alignment.centerLeft,
                child: NexoraBrand(),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Active Downloads',
                      style: textTheme.headlineMedium,
                    ),
                  ),
                  _DownloadCountBadge(count: activeDownloads.length),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _downloadsSummary(activeDownloads.length),
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AnimatedSwitcher(
                duration: AppDurations.short,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(activeDownloads.isEmpty),
                  child: activeDownloads.isEmpty
                      ? const NexoraStatePanel(
                          title: 'No active downloads',
                          message:
                              'New download jobs will appear here while media is downloading or saving.',
                          icon: Icons.downloading_outlined,
                        )
                      : Column(
                          children: [
                            for (final download in activeDownloads) ...[
                              _ActiveDownloadCard(download: download),
                              const SizedBox(height: AppSpacing.xl),
                            ],
                          ],
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  List<MediaSuccess> _activeDownloads(MediaState state) {
    if (state is! MediaSuccess) {
      return const <MediaSuccess>[];
    }

    final normalizedStatus = state.currentStatus?.trim().toLowerCase();
    final isActive = state.currentJobId != null &&
        (normalizedStatus == 'pending' ||
            normalizedStatus == 'processing' ||
            state.fileDownloadLoading);
    return isActive ? <MediaSuccess>[state] : const <MediaSuccess>[];
  }

  String _downloadsSummary(int count) {
    if (count == 1) {
      return 'Managing 1 file currently.';
    }

    return 'Managing $count files currently.';
  }
}

class _DownloadCountBadge extends StatelessWidget {
  const _DownloadCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = count == 1 ? '1 Item' : '$count Items';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(96),
        ),
        borderRadius: AppRadii.pill,
      ),
      child: Text(
        label,
        style: textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ActiveDownloadCard extends StatelessWidget {
  const _ActiveDownloadCard({required this.download});

  final MediaSuccess download;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useVerticalLayout = constraints.maxWidth < 520;
            final thumbnail = NexoraMediaThumbnail(
              metadata: download.metadata,
              mediaType: download.currentMediaType,
            );
            final details = _DownloadDetails(download: download);
            final cancelAction = const _UnavailableCancelAction();

            if (useVerticalLayout) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  thumbnail,
                  const SizedBox(height: AppSpacing.md),
                  details,
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: cancelAction,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppSizes.compactThumbnailWidth,
                  child: thumbnail,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: details),
                const SizedBox(width: AppSpacing.sm),
                cancelAction,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DownloadDetails extends StatelessWidget {
  const _DownloadDetails({required this.download});

  final MediaSuccess download;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSavingToDevice = download.fileDownloadLoading;
    final progress = _clampProgress(
      isSavingToDevice
          ? download.fileDownloadProgress
          : download.currentProgress,
    );
    final status = isSavingToDevice
        ? 'Saving to device'
        : _formatStatus(download.currentStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                download.metadata.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            MediaBadge(label: _qualityLabel(download)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            _DownloadStatusBadge(
              status: status,
              isSavingToDevice: isSavingToDevice,
            ),
            const Spacer(),
            Text(
              '$progress%',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label:
              '${isSavingToDevice ? 'File transfer' : 'Download'} progress: '
              '$progress percent',
          child: ClipRRect(
            borderRadius: AppRadii.pill,
            child: LinearProgressIndicator(
              value: progress / 100,
              minHeight: AppSpacing.xs,
            ),
          ),
        ),
      ],
    );
  }

  String _qualityLabel(MediaSuccess state) {
    if (state.currentMediaType == MediaDownloadType.audio) {
      return 'MP3';
    }

    return state.selectedVideoQuality?.label ?? 'Video';
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

  String _formatStatus(String? value) {
    final normalizedValue = value?.trim();
    if (normalizedValue == null || normalizedValue.isEmpty) {
      return 'Pending';
    }

    final words = normalizedValue.replaceAll('_', ' ').split(' ');
    return words.map((word) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
  }
}

class _DownloadStatusBadge extends StatelessWidget {
  const _DownloadStatusBadge({
    required this.status,
    required this.isSavingToDevice,
  });

  final String status;
  final bool isSavingToDevice;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: AppRadii.badge,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSavingToDevice ? Icons.save_rounded : Icons.downloading_rounded,
            color: colorScheme.primary,
            size: AppSpacing.md,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            status,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableCancelAction extends StatelessWidget {
  const _UnavailableCancelAction();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      enabled: false,
      label: 'Cancel download unavailable',
      child: TextButton.icon(
        onPressed: null,
        icon: const Icon(Icons.cancel_outlined),
        label: const Text('Cancel'),
        style: TextButton.styleFrom(
          disabledForegroundColor: colorScheme.error.withAlpha(144),
          minimumSize: const Size(0, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      ),
    );
  }
}
