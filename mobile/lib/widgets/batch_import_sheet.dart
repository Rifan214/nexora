import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../models/batch_import.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';
import '../providers/batch_import_provider.dart';
import '../providers/playlist_import_provider.dart';
import 'media_card_parts.dart';
import 'media_format_chip.dart';
import 'playlist_import_sheet.dart';

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
  final _urlFocusNode = FocusNode();
  var _detectedUrlCount = 0;
  var _hasInput = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = ref.read(batchImportProvider).urlInput;
    _urlController.addListener(_updateDetectedUrlCount);
    _updateDetectedUrlCount();
  }

  @override
  void dispose() {
    _urlController
      ..removeListener(_updateDetectedUrlCount)
      ..dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final batchState = ref.watch(batchImportProvider);
    final playlistState = ref.watch(playlistImportProvider);
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
              _BatchSheetHeader(
                onClose: () => Navigator.of(context).pop(),
                onClear: !batchState.hasSession ||
                        batchState.isAnalyzing ||
                        batchState.isSubmitting ||
                        playlistState.isLoading
                    ? null
                    : _clearBatch,
                onImportPlaylist:
                    batchState.items.isEmpty ? _importPlaylist : null,
              ),
              Expanded(
                child: batchState.items.isEmpty
                    ? _BatchInput(
                        controller: _urlController,
                        focusNode: _urlFocusNode,
                        detectedUrlCount: _detectedUrlCount,
                        onAnalyze: !_hasInput
                            ? null
                            : () => unawaited(_validateAndAnalyze(batchController)),
                      )
                    : _BatchResults(
                        state: batchState,
                        onVideoSelected: batchController.selectVideoQuality,
                        onAudioSelected: batchController.selectAudioOption,
                        onRemove: batchController.removeItem,
                        onStartAll: () => unawaited(
                          _submitSelectedDownloads(batchController),
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
    ref.read(batchImportProvider.notifier).updateUrlInput(_urlController.text);
    final validation =
        validateBatchUrlLines(_urlController.text.split(RegExp(r'\r?\n')));
    final detectedUrlCount = normalizeBatchUrls(validation.validUrls).length;
    final hasInput = _urlController.text.trim().isNotEmpty;
    if (_detectedUrlCount != detectedUrlCount || _hasInput != hasInput) {
      setState(() {
        _detectedUrlCount = detectedUrlCount;
        _hasInput = hasInput;
      });
    }
  }

  void _clearBatch() {
    ref.read(batchImportProvider.notifier).clearBatch();
    ref.read(playlistImportProvider.notifier).clear();
    _urlController.clear();
  }

  Future<void> _validateAndAnalyze(BatchImportController controller) async {
    final validation =
        validateBatchUrlLines(_urlController.text.split(RegExp(r'\r?\n')));
    if (validation.hasInvalidUrls) {
      final shouldFocusInput = await _showInvalidUrlsDialog(
        context,
        validation.invalidUrls,
      );
      if (shouldFocusInput && mounted) {
        _urlFocusNode.requestFocus();
      }
      return;
    }

    await controller.analyzeUrls(validation.validUrls);
  }

  Future<void> _importPlaylist() async {
    final urls = await PlaylistImportSheet.show(context);
    if (!mounted || urls == null || urls.isEmpty) {
      return;
    }

    final mergedUrls = normalizeBatchUrls([
      ..._urlController.text.split(RegExp(r'\r?\n')),
      ...urls,
    ]);
    final text = mergedUrls.join('\n');
    _urlController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _submitSelectedDownloads(
    BatchImportController controller,
  ) async {
    await controller.submitSelectedDownloads();
    if (!ref.read(batchImportProvider).hasSession) {
      ref.read(playlistImportProvider.notifier).clear();
      if (mounted) {
        _urlController.clear();
      }
    }
  }
}

Future<bool> _showInvalidUrlsDialog(
  BuildContext context,
  List<BatchInvalidUrl> invalidUrls,
) async {
  return (await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.link_off_rounded),
          title: const Text('Invalid URLs detected'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: invalidUrls.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final invalidUrl = invalidUrls[index];
                return Text(
                  'Line ${invalidUrl.lineNumber}: ${invalidUrl.value.trim()}',
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Fix URLs'),
            ),
          ],
        ),
      )) ??
      false;
}

class _BatchSheetHeader extends StatelessWidget {
  const _BatchSheetHeader({
    required this.onClose,
    required this.onClear,
    required this.onImportPlaylist,
  });

  final VoidCallback onClose;
  final VoidCallback? onClear;
  final VoidCallback? onImportPlaylist;

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
            tooltip: 'Import playlist',
            onPressed: onImportPlaylist,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
          IconButton(
            tooltip: 'Clear batch',
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
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
    required this.focusNode,
    required this.detectedUrlCount,
    required this.onAnalyze,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
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
            focusNode: focusNode,
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
