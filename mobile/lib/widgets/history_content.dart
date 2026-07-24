import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../models/download_history_item.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';
import '../providers/history_provider.dart';
import 'media_card_parts.dart';
import 'nexora_brand.dart';
import 'nexora_state_panel.dart';

class HistoryContent extends ConsumerWidget {
  const HistoryContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(downloadHistoryProvider);
    final historyController = ref.read(downloadHistoryProvider.notifier);
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
                  key: ValueKey(_historyStateKey(historyState)),
                  child: historyState.when(
                    data: (downloads) {
                      if (downloads.isEmpty) {
                        return const NexoraStatePanel(
                          title: 'No completed downloads',
                          message:
                              'Completed downloads saved on this device will appear here.',
                          icon: Icons.history_rounded,
                        );
                      }

                      return Column(
                        children: [
                          for (final download in downloads) ...[
                            _HistoryDownloadCard(
                              download: download,
                              onDelete: () {
                                unawaited(
                                  _confirmAndDeleteHistoryItem(
                                    context,
                                    historyController,
                                    download,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: AppSpacing.xl),
                          ],
                        ],
                      );
                    },
                    loading: () => const NexoraStatePanel(
                      title: 'Loading history',
                      message: 'Loading completed downloads from this device.',
                      isLoading: true,
                    ),
                    error: (_, __) => const NexoraStatePanel(
                      title: 'History unavailable',
                      message: 'Unable to load saved download history.',
                      tone: NexoraStateTone.error,
                    ),
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

  String _historyStateKey(AsyncValue<List<DownloadHistoryItem>> state) {
    return state.when(
      data: (downloads) => downloads.isEmpty ? 'empty' : 'history',
      loading: () => 'loading',
      error: (_, __) => 'error',
    );
  }

  Future<void> _confirmAndDeleteHistoryItem(
    BuildContext context,
    DownloadHistoryController historyController,
    DownloadHistoryItem download,
  ) async {
    final deleteOption = await showDialog<_HistoryDeleteOption>(
      context: context,
      builder: (context) => const _HistoryDeleteDialog(),
    );

    if (deleteOption == null) {
      return;
    }

    await historyController.deleteHistoryItem(download.id);

    if (deleteOption == _HistoryDeleteOption.historyAndFile) {
      await _deleteLocalFileIfPresent(download.localFilePath);
    }
  }

  Future<void> _deleteLocalFileIfPresent(String path) async {
    try {
      final fileType = await FileSystemEntity.type(path, followLinks: false);
      if (fileType == FileSystemEntityType.file) {
        await File(path).delete();
      }
    } on FileSystemException {
      // A missing or inaccessible local file must not prevent history cleanup.
    }
  }
}

enum _HistoryDeleteOption { historyOnly, historyAndFile }

class _HistoryDeleteDialog extends StatefulWidget {
  const _HistoryDeleteDialog();

  @override
  State<_HistoryDeleteDialog> createState() => _HistoryDeleteDialogState();
}

class _HistoryDeleteDialogState extends State<_HistoryDeleteDialog> {
  _HistoryDeleteOption _selectedOption = _HistoryDeleteOption.historyOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
      title: const Text('Delete this download?'),
      content: RadioGroup<_HistoryDeleteOption>(
        groupValue: _selectedOption,
        onChanged: (option) {
          if (option != null) {
            setState(() => _selectedOption = option);
          }
        },
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose what to remove.'),
            SizedBox(height: AppSpacing.sm),
            RadioListTile<_HistoryDeleteOption>(
              contentPadding: EdgeInsets.zero,
              value: _HistoryDeleteOption.historyOnly,
              title: Text('History only'),
              subtitle: Text('Keep the downloaded file on this device.'),
            ),
            RadioListTile<_HistoryDeleteOption>(
              contentPadding: EdgeInsets.zero,
              value: _HistoryDeleteOption.historyAndFile,
              title: Text('History and downloaded file'),
              subtitle: Text('Remove the saved file from this device.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedOption),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

class _HistoryDownloadCard extends StatelessWidget {
  const _HistoryDownloadCard({
    required this.download,
    required this.onDelete,
  });

  final DownloadHistoryItem download;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mediaTypeLabel = _mediaTypeLabel(download);
    final qualityLabel = download.selectedQuality;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexoraMediaThumbnail(
            metadata: _thumbnailMetadata(download),
            mediaType: download.mediaType,
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        download.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove from history',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
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

  MediaMetadata _thumbnailMetadata(DownloadHistoryItem item) {
    return MediaMetadata(
      platform: 'local',
      title: item.title,
      thumbnailUrl: item.thumbnailUrl,
      durationSeconds: item.durationSeconds,
      webpageUrl: '',
      extractor: 'local',
      extractorKey: 'Local',
    );
  }

  String _mediaTypeLabel(DownloadHistoryItem item) {
    return item.mediaType == MediaDownloadType.audio ? 'MP3' : 'Video';
  }
}
