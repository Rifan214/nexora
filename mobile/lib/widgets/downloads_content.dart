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
    final downloading = downloads.where(_isDownloading).toList();
    final waiting = downloads.where((download) => download.status == 'queued').toList();
    final completed = downloads.where(_isCompleted).toList();
    final failed = downloads.where(_isFailed).toList();
    final hasBackendActiveDownload = downloads.any(_isBackendActive);
    final activeCount = downloading.length + waiting.length;
    final hasDownloads =
        activeCount > 0 || completed.isNotEmpty || failed.isNotEmpty;
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
                      'Downloads',
                      style: textTheme.headlineMedium,
                    ),
                  ),
                  _DownloadCountBadge(count: activeCount),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _downloadsSummary(activeCount),
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AnimatedSwitcher(
                duration: AppDurations.short,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: hasDownloads
                    ? _DownloadSections(
                        downloading: downloading,
                        waiting: waiting,
                        queueOffset: hasBackendActiveDownload ? 1 : 0,
                        completed: completed,
                        failed: failed,
                        onCancelDownload: onCancelDownload,
                      )
                    : const NexoraStatePanel(
                        title: 'No active downloads',
                        message:
                            'New download jobs will appear here while media is downloading or saving.',
                        icon: Icons.downloading_outlined,
                      ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  bool _isDownloading(TrackedDownload download) {
    return download.status == 'pending' ||
        download.status == 'processing' ||
        download.status == 'cancelling' ||
        download.isSavingToDevice;
  }

  bool _isCompleted(TrackedDownload download) {
    return download.status == 'completed' &&
        download.savedFilePath?.trim().isNotEmpty == true;
  }

  bool _isBackendActive(TrackedDownload download) {
    return download.status == 'pending' ||
        download.status == 'processing' ||
        download.status == 'cancelling';
  }

  bool _isFailed(TrackedDownload download) {
    return download.status == 'failed' ||
        download.status == 'connection_lost' ||
        download.fileDownloadError?.trim().isNotEmpty == true;
  }

  String _downloadsSummary(int count) {
    if (count == 1) {
      return 'Managing 1 active file.';
    }

    return 'Managing $count active files.';
  }
}

class _DownloadSections extends StatelessWidget {
  const _DownloadSections({
    required this.downloading,
    required this.waiting,
    required this.queueOffset,
    required this.completed,
    required this.failed,
    required this.onCancelDownload,
  });

  final List<TrackedDownload> downloading;
  final List<TrackedDownload> waiting;
  final int queueOffset;
  final List<TrackedDownload> completed;
  final List<TrackedDownload> failed;
  final ValueChanged<String> onCancelDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey(
        '${downloading.length}:${waiting.length}:${completed.length}:${failed.length}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (downloading.isNotEmpty)
          _DownloadSection(
            title: 'Downloading',
            count: downloading.length,
            children: [
              for (final download in downloading)
                _DownloadCard(
                  download: download,
                  section: _DownloadSectionType.downloading,
                  onCancelDownload: onCancelDownload,
                ),
            ],
          ),
        if (waiting.isNotEmpty)
          _DownloadSection(
            title: 'Waiting',
            count: waiting.length,
            children: [
              for (var index = 0; index < waiting.length; index += 1)
                _DownloadCard(
                  download: waiting[index],
                  section: _DownloadSectionType.waiting,
                  waitingPosition: queueOffset + index + 1,
                  onCancelDownload: onCancelDownload,
                ),
            ],
          ),
        if (completed.isNotEmpty)
          _DownloadSection(
            title: 'Completed',
            count: completed.length,
            children: [
              for (final download in completed)
                _DownloadCard(
                  download: download,
                  section: _DownloadSectionType.completed,
                  onCancelDownload: onCancelDownload,
                ),
            ],
          ),
        if (failed.isNotEmpty)
          _DownloadSection(
            title: 'Failed',
            count: failed.length,
            children: [
              for (final download in failed)
                _DownloadCard(
                  download: download,
                  section: _DownloadSectionType.failed,
                  onCancelDownload: onCancelDownload,
                ),
            ],
          ),
      ],
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$title ($count)',
            style: textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final child in children) ...[
            child,
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

enum _DownloadSectionType { downloading, waiting, completed, failed }

class _DownloadCountBadge extends StatelessWidget {
  const _DownloadCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = count == 1 ? '1 Active' : '$count Active';

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

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.download,
    required this.section,
    required this.onCancelDownload,
    this.waitingPosition,
  });

  final TrackedDownload download;
  final _DownloadSectionType section;
  final int? waitingPosition;
  final ValueChanged<String> onCancelDownload;

  @override
  Widget build(BuildContext context) {
    final isWaiting = section == _DownloadSectionType.waiting;
    final colorScheme = Theme.of(context).colorScheme;
    final action = _action();

    return Opacity(
      opacity: isWaiting ? 0.72 : 1,
      child: Card(
        color: isWaiting ? colorScheme.surfaceContainerLow : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useVerticalLayout = constraints.maxWidth < 520;
              final thumbnail = NexoraMediaThumbnail(
                metadata: download.metadata,
                mediaType: download.mediaType,
              );
              final details = _DownloadDetails(
                download: download,
                section: section,
                waitingPosition: waitingPosition,
              );

              if (useVerticalLayout) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    thumbnail,
                    const SizedBox(height: AppSpacing.md),
                    details,
                    if (action != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
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
                  if (action != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    action,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget? _action() {
    if (section == _DownloadSectionType.failed) {
      return const _RetryDownloadAction();
    }
    if (download.isSavingToDevice) {
      return const _SavingToDeviceAction();
    }
    if (section == _DownloadSectionType.downloading ||
        section == _DownloadSectionType.waiting) {
      return _CancelDownloadAction(
        status: download.status,
        onCancel: () => onCancelDownload(download.jobId),
      );
    }
    return null;
  }
}

class _DownloadDetails extends StatelessWidget {
  const _DownloadDetails({
    required this.download,
    required this.section,
    this.waitingPosition,
  });

  final TrackedDownload download;
  final _DownloadSectionType section;
  final int? waitingPosition;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isWaiting = section == _DownloadSectionType.waiting;
    final isDownloading = section == _DownloadSectionType.downloading;
    final isSavingToDevice = download.isSavingToDevice;
    final progress = _clampProgress(
      isSavingToDevice ? download.fileDownloadProgress : download.progress,
    );
    final hasKnownProgress = !isSavingToDevice || progress > 0;
    final status = _statusLabel();
    final failureMessage = _failureMessage();

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
              section: section,
              isSavingToDevice: isSavingToDevice,
            ),
            const Spacer(),
            if (isDownloading && hasKnownProgress)
              Text(
                '$progress%',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
          ],
        ),
        if (isDownloading) ...[
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
        if (failureMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            failureMessage,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String _statusLabel() {
    switch (section) {
      case _DownloadSectionType.waiting:
        return 'Waiting (#${waitingPosition ?? 1})';
      case _DownloadSectionType.completed:
        return 'Completed';
      case _DownloadSectionType.failed:
        return 'Failed';
      case _DownloadSectionType.downloading:
        return friendlyDownloadStatus(
          backendStatus: download.status,
          backendProgress: download.progress,
          isSavingToDevice: download.isSavingToDevice,
        );
    }
  }

  String? _failureMessage() {
    if (section != _DownloadSectionType.failed) {
      return null;
    }

    final message = download.fileDownloadError ?? download.error;
    final trimmedMessage = message?.trim();
    if (trimmedMessage == null || trimmedMessage.isEmpty) {
      return 'The download could not be completed.';
    }
    return trimmedMessage;
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
    required this.section,
    required this.isSavingToDevice,
  });

  final String status;
  final _DownloadSectionType section;
  final bool isSavingToDevice;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isWaiting = section == _DownloadSectionType.waiting;
    final isCompleted = section == _DownloadSectionType.completed;
    final isFailed = section == _DownloadSectionType.failed;
    final foregroundColor = isFailed
        ? colorScheme.error
        : isCompleted
            ? colorScheme.tertiary
            : isWaiting
                ? colorScheme.onSurfaceVariant
                : colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isFailed
            ? colorScheme.errorContainer
            : isCompleted
                ? colorScheme.tertiaryContainer
                : colorScheme.surfaceContainerLow,
        borderRadius: AppRadii.badge,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSavingToDevice
                ? Icons.save_rounded
                : isWaiting
                    ? Icons.schedule_rounded
                    : isCompleted
                        ? Icons.check_circle_outline_rounded
                        : isFailed
                            ? Icons.error_outline_rounded
                            : Icons.downloading_rounded,
            color: foregroundColor,
            size: AppSpacing.md,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            status,
            style: textTheme.labelMedium?.copyWith(
              color: foregroundColor,
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

class _RetryDownloadAction extends StatelessWidget {
  const _RetryDownloadAction();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: false,
      label: 'Retry download coming soon',
      child: TextButton.icon(
        onPressed: null,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry (Coming Soon)'),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      ),
    );
  }
}
