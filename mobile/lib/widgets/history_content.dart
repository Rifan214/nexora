import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../models/media_download_type.dart';
import '../models/media_state.dart';
import 'media_card_parts.dart';
import 'nexora_brand.dart';
import 'nexora_state_panel.dart';

class HistoryContent extends StatelessWidget {
  const HistoryContent({
    super.key,
    required this.mediaState,
  });

  final MediaState mediaState;

  @override
  Widget build(BuildContext context) {
    final completedDownloads = _completedDownloads(mediaState);
    final textTheme = Theme.of(context).textTheme;

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
              Text(
                'Recent Downloads',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              AnimatedSwitcher(
                duration: AppDurations.short,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(completedDownloads.isEmpty),
                  child: completedDownloads.isEmpty
                      ? const NexoraStatePanel(
                          title: 'No completed downloads',
                          message: 'Completed downloads will appear here.',
                          icon: Icons.history_rounded,
                        )
                      : Column(
                          children: [
                            for (final download in completedDownloads) ...[
                              _HistoryDownloadCard(download: download),
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

  List<MediaSuccess> _completedDownloads(MediaState state) {
    if (state is! MediaSuccess) {
      return const <MediaSuccess>[];
    }

    final hasSavedFile = state.savedFilePath?.trim().isNotEmpty == true;
    if (state.currentStatus?.toLowerCase() != 'completed' || !hasSavedFile) {
      return const <MediaSuccess>[];
    }

    return <MediaSuccess>[state];
  }
}

class _HistoryDownloadCard extends StatelessWidget {
  const _HistoryDownloadCard({required this.download});

  final MediaSuccess download;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mediaTypeLabel = _mediaTypeLabel(download);
    final qualityLabel = _qualityLabel(download);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexoraMediaThumbnail(
            metadata: download.metadata,
            mediaType: download.currentMediaType,
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  download.metadata.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (mediaTypeLabel != null)
                      MediaBadge(
                        label: mediaTypeLabel,
                        tone: MediaBadgeTone.neutral,
                      ),
                    if (qualityLabel != null && qualityLabel != mediaTypeLabel)
                      MediaBadge(label: qualityLabel),
                    const MediaBadge(
                      label: 'Completed',
                      tone: MediaBadgeTone.success,
                      icon: Icons.check_circle_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _mediaTypeLabel(MediaSuccess state) {
    switch (state.currentMediaType) {
      case MediaDownloadType.video:
        return 'Video';
      case MediaDownloadType.audio:
        return 'MP3';
      case null:
        return null;
    }
  }

  String? _qualityLabel(MediaSuccess state) {
    if (state.currentMediaType == MediaDownloadType.audio) {
      return 'MP3';
    }

    return state.selectedVideoQuality?.label;
  }
}
