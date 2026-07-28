import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../models/media_download_type.dart';
import '../models/tracked_download.dart';
import 'download_progress_status.dart';
import 'media_card_parts.dart';
import 'nexora_brand.dart';
import 'nexora_state_panel.dart';

class DownloadsContent extends StatelessWidget {
  const DownloadsContent({
    super.key,
    required this.downloads,
    required this.onCancelDownload,
  });

  final List<TrackedDownload> downloads;
  final ValueChanged<String> onCancelDownload;

  @override
  Widget build(BuildContext context) {
    final activeDownloads = downloads.where((download) => download.isActive).toList();
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
                              _ActiveDownloadCard(
                                download: download,
                                onCancelDownload: onCancelDownload,
                              ),
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
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(96)),
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
  const _ActiveDownloadCard({
    required this.download,
    required this.onCancelDownload,
  });

  final TrackedDownload download;
  final ValueChanged<String> onCancelDownload;

  @override
  Widget build(BuildContext context) {
    final isQueued = download.status == 'queued';
    final colorScheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: isQueued ? 0.72 : 1,
      child: Card(
        color: isQueued ? colorScheme.surfaceContainerLow : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useVerticalLayout = constraints.maxWidth < 520;
              final thumbnail = NexoraMediaThumbnail(
                metadata: download.metadata,
                mediaType: download.mediaType,
              );
              final details = _DownloadDetails(download: download);
              final action = download.isSavingToDevice
                  ? const _SavingToDeviceAction()
                  : _CancelDownloadAction(
                      status: download.status,
                      onCancel: () => onCancelDownload(download.jobId),
                    );

              if (useVerticalLayout) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    thumbnail,
                    const SizedBox(height: AppSpacing.md),
                    details,
                    const SizedBox(height: AppSpacing.sm),
                    Align(alignment: Alignment.centerRight, child: action),
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
                  action,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DownloadDetails extends StatelessWidget {
  const _DownloadDetails({required this.download});

  final TrackedDownload download;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSavingToDevice = download.isSavingToDevice;
    final isQueued = download.status == 'queued';
    final progress = _clampProgress(
      isSavingToDevice ? download.fileDownloadProgress : download.progress,
    );
    final hasKnownProgress = !isQueued && (!isSavingToDevice || progress > 0);
    final status = friendlyDownloadStatus(
      backendStatus: download.status,
      backendProgress: download.progress,
      isSavingToDevice: isSavingToDevice,
    );

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
              isQueued: isQueued,
            ),
            const Spacer(),
            if (hasKnownProgress)
              Text(
                '$progress%',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
          ],
        ),
        if (!isQueued) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: hasKnownProgress ? '$status $progress percent' : status,
            child: ClipRRect(
              borderRadius: AppRadii.pill,
              child: LinearProgressIndicator(
                value: hasKnownProgress ? progress / 100 : null,
                minHeight: AppSpacing.xs,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _qualityLabel(TrackedDownload download) {
    if (download.mediaType == MediaDownloadType.audio) {
      return 'MP3';
    }
    return download.selectedVideoQuality?.label ?? 'Video';
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

class _DownloadStatusBadge extends StatelessWidget {
  const _DownloadStatusBadge({
    required this.status,
    required this.isSavingToDevice,
    required this.isQueued,
  });

  final String status;
  final bool isSavingToDevice;
  final bool isQueued;

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
            isSavingToDevice
                ? Icons.save_rounded
                : isQueued
                    ? Icons.schedule_rounded
                    : Icons.downloading_rounded,
            color: isQueued ? colorScheme.onSurfaceVariant : colorScheme.primary,
            size: AppSpacing.md,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            status,
            style: textTheme.labelMedium?.copyWith(
              color:
                  isQueued ? colorScheme.onSurfaceVariant : colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelDownloadAction extends StatelessWidget {
  const _CancelDownloadAction({
    required this.status,
    required this.onCancel,
  });

  final String status;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCancelling = status == 'cancelling';
    final isCancellable =
        status == 'pending' || status == 'queued' || status == 'processing';

    return Semantics(
      button: true,
      enabled: isCancellable,
      label: isCancelling ? 'Cancelling download' : 'Cancel download',
      child: TextButton.icon(
        onPressed: isCancellable ? onCancel : null,
        icon: isCancelling
            ? const SizedBox(
                width: AppSpacing.md,
                height: AppSpacing.md,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cancel_outlined),
        label: Text(isCancelling ? 'Cancelling...' : 'Cancel'),
        style: TextButton.styleFrom(
          disabledForegroundColor: colorScheme.error.withAlpha(144),
          minimumSize: const Size(0, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      ),
    );
  }
}

class _SavingToDeviceAction extends StatelessWidget {
  const _SavingToDeviceAction();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      enabled: false,
      label: 'Saving file to device',
      child: ExcludeSemantics(
        child: TextButton.icon(
          onPressed: null,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Saving...'),
          style: TextButton.styleFrom(
            disabledForegroundColor: colorScheme.primary.withAlpha(144),
            minimumSize: const Size(0, AppSizes.touchTarget),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
        ),
      ),
    );
  }
}
