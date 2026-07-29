import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../models/batch_import.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';
import '../providers/batch_import_provider.dart';
import 'media_card_parts.dart';
import 'media_format_chip.dart';

class BatchImportSheet extends ConsumerStatefulWidget {
  const BatchImportSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BatchImportSheet(),
    );
  }

  @override
  ConsumerState<BatchImportSheet> createState() => _BatchImportSheetState();
}

class _BatchImportSheetState extends ConsumerState<BatchImportSheet> {
  final _urlController = TextEditingController();
  var _detectedUrlCount = 0;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_updateDetectedUrlCount);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final batchState = ref.read(batchImportProvider);
      if (!batchState.isAnalyzing && !batchState.isSubmitting) {
        ref.read(batchImportProvider.notifier).reset();
      }
    });
  }

  @override
  void dispose() {
    _urlController
      ..removeListener(_updateDetectedUrlCount)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final batchState = ref.watch(batchImportProvider);
    final batchController = ref.read(batchImportProvider.notifier);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return AnimatedPadding(
      duration: AppDurations.short,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.xl),
          ),
          child: Column(
            children: [
              _BatchSheetHeader(onClose: () => Navigator.of(context).pop()),
              Expanded(
                child: batchState.items.isEmpty
                    ? _BatchInput(
                        controller: _urlController,
                        detectedUrlCount: _detectedUrlCount,
                        onAnalyze: _detectedUrlCount == 0
                            ? null
                            : () => unawaited(
                                  batchController.analyzeUrls(
                                    _urlController.text.split(RegExp(r'\r?\n')),
                                  ),
                                ),
                      )
                    : _BatchResults(
                        state: batchState,
                        onVideoSelected: batchController.selectVideoQuality,
                        onAudioSelected: batchController.selectAudioOption,
                        onRemove: batchController.removeItem,
                        onStartAll: () => unawaited(
                          batchController.submitSelectedDownloads(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateDetectedUrlCount() {
    final detectedUrlCount =
        normalizeBatchUrls(_urlController.text.split(RegExp(r'\r?\n'))).length;
    if (_detectedUrlCount != detectedUrlCount) {
      setState(() => _detectedUrlCount = detectedUrlCount);
    }
  }
}

class _BatchSheetHeader extends StatelessWidget {
  const _BatchSheetHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text('Batch Import', style: textTheme.titleLarge)),
          IconButton(
            tooltip: 'Close batch import',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _BatchInput extends StatelessWidget {
  const _BatchInput({
    required this.controller,
    required this.detectedUrlCount,
    required this.onAnalyze,
  });

  final TextEditingController controller;
  final int detectedUrlCount;
  final VoidCallback? onAnalyze;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: AppSpacing.pageHorizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          Text(
            'Paste one URL per line.',
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: controller,
            minLines: 7,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'https://example.com/media\nhttps://example.com/media',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '$detectedUrlCount URLs detected',
            style: textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: onAnalyze,
            icon: const Icon(Icons.manage_search_rounded),
            label: const Text('Analyze URLs'),
          ),
        ],
      ),
    );
  }
}

class _BatchResults extends StatelessWidget {
  const _BatchResults({
    required this.state,
    required this.onVideoSelected,
    required this.onAudioSelected,
    required this.onRemove,
    required this.onStartAll,
  });

  final BatchImportState state;
  final void Function(String url, VideoQuality quality) onVideoSelected;
  final void Function(String url, AudioOption option) onAudioSelected;
  final ValueChanged<String> onRemove;
  final VoidCallback onStartAll;

  @override
  Widget build(BuildContext context) {
    final canStart =
        !state.isAnalyzing && !state.isSubmitting && state.selectedReadyCount > 0;

    return Column(
      children: [
        if (state.isAnalyzing) _BatchAnalysisProgress(state: state),
        Expanded(
          child: ListView.separated(
            padding: AppSpacing.pageHorizontal,
            itemCount: state.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) => _BatchResultCard(
              item: state.items[index],
              selectionEnabled: !state.isAnalyzing && !state.isSubmitting,
              canRemove: !state.isAnalyzing &&
                  !state.isSubmitting &&
                  state.items[index].status != BatchImportItemStatus.submitted,
              onVideoSelected: onVideoSelected,
              onAudioSelected: onAudioSelected,
              onRemove: onRemove,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canStart ? onStartAll : null,
              icon: state.isSubmitting
                  ? const SizedBox(
                      width: AppSpacing.lg,
                      height: AppSpacing.lg,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: const Text('Start All Downloads'),
            ),
          ),
        ),
      ],
    );
  }
}

class _BatchAnalysisProgress extends StatelessWidget {
  const _BatchAnalysisProgress({required this.state});

  final BatchImportState state;

  @override
  Widget build(BuildContext context) {
    final total = state.totalCount;
    final progress = total == 0 ? 0.0 : state.analysisCompletedCount / total;
    final currentItem = state.currentTitle ?? state.currentUrl;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analyzing... ${state.analysisCompletedCount} / $total'),
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(value: progress),
          if (currentItem != null && currentItem.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              currentItem,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _BatchResultCard extends StatelessWidget {
  const _BatchResultCard({
    required this.item,
    required this.selectionEnabled,
    required this.canRemove,
    required this.onVideoSelected,
    required this.onAudioSelected,
    required this.onRemove,
  });

  final BatchImportItem item;
  final bool selectionEnabled;
  final bool canRemove;
  final void Function(String url, VideoQuality quality) onVideoSelected;
  final void Function(String url, AudioOption option) onAudioSelected;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final metadata = item.metadata;
    if (metadata == null) {
      return _BatchFailureCard(item: item, canRemove: canRemove, onRemove: onRemove);
    }

    final totalFormats =
        metadata.videoQualities.length + metadata.audioOptions.length;
    final selectedMediaType = item.mediaType ?? MediaDownloadType.video;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NexoraMediaThumbnail(
              metadata: metadata,
              mediaType: selectedMediaType,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    metadata.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium,
                  ),
                ),
                if (canRemove)
                  IconButton(
                    tooltip: 'Remove from batch',
                    onPressed: () => onRemove(item.url),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                MediaBadge(label: metadata.platform),
                MediaBadge(
                  label: '$totalFormats formats',
                  tone: MediaBadgeTone.neutral,
                ),
                if (item.status == BatchImportItemStatus.submitted)
                  const MediaBadge(
                    label: 'Added to downloads',
                    tone: MediaBadgeTone.success,
                    icon: Icons.check_circle_rounded,
                  ),
                if (item.status == BatchImportItemStatus.submissionFailed)
                  const MediaBadge(
                    label: 'Unavailable',
                    tone: MediaBadgeTone.error,
                    icon: Icons.error_outline_rounded,
                  ),
              ],
            ),
            if (item.status == BatchImportItemStatus.submissionFailed &&
                item.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                item.error!,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (item.status == BatchImportItemStatus.ready) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Video', style: textTheme.labelMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final quality in metadata.videoQualities)
                    MediaFormatChip(
                      primaryLabel: quality.label,
                      secondaryLabel: formatEstimatedFilesize(
                        quality.estimatedFilesize,
                      ),
                      isSelected: item.mediaType == MediaDownloadType.video &&
                          item.selectedVideoQuality?.height == quality.height,
                      enabled: selectionEnabled,
                      onSelected: () => onVideoSelected(item.url, quality),
                    ),
                ],
              ),
              if (metadata.audioOptions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.lg),
                Text('Audio', style: textTheme.labelMedium),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final option in metadata.audioOptions)
                      MediaFormatChip(
                        primaryLabel: option.label,
                        secondaryLabel: 'Best Audio',
                        isSelected:
                            item.mediaType == MediaDownloadType.audio &&
                                item.selectedAudioOptionLabel == option.label,
                        enabled: selectionEnabled,
                        onSelected: () => onAudioSelected(item.url, option),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _BatchFailureCard extends StatelessWidget {
  const _BatchFailureCard({
    required this.item,
    required this.canRemove,
    required this.onRemove,
  });

  final BatchImportItem item;
  final bool canRemove;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isAnalyzing = item.status == BatchImportItemStatus.analyzing ||
        item.status == BatchImportItemStatus.pending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isAnalyzing
                  ? Icons.manage_search_rounded
                  : Icons.error_outline_rounded,
              color: isAnalyzing ? colorScheme.primary : colorScheme.error,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAnalyzing ? 'Analyzing...' : 'Failed to analyze',
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    item.error?.trim().isNotEmpty == true
                        ? item.error!
                        : item.url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canRemove)
              IconButton(
                tooltip: 'Remove from batch',
                onPressed: () => onRemove(item.url),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
