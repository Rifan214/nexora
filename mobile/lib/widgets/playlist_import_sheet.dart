import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../models/playlist_metadata.dart';
import '../providers/playlist_import_provider.dart';

class PlaylistImportSheet extends ConsumerStatefulWidget {
  const PlaylistImportSheet({super.key});

  static Future<List<String>?> show(BuildContext context) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PlaylistImportSheet(),
    );
  }

  @override
  ConsumerState<PlaylistImportSheet> createState() =>
      _PlaylistImportSheetState();
}

class _PlaylistImportSheetState extends ConsumerState<PlaylistImportSheet> {
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = ref.read(playlistImportProvider).url;
    _urlController.addListener(_persistUrl);
  }

  @override
  void dispose() {
    _urlController
      ..removeListener(_persistUrl)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final playlistState = ref.watch(playlistImportProvider);
    final playlistController = ref.read(playlistImportProvider.notifier);

    return AnimatedPadding(
      duration: AppDurations.short,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Material(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.xl),
          ),
          child: Column(
            children: [
              _PlaylistSheetHeader(
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: !playlistState.hasPreview
                    ? _PlaylistUrlInput(
                        controller: _urlController,
                        isLoading: playlistState.isLoading,
                        errorMessage: playlistState.errorMessage,
                        onPreview: playlistController.previewPlaylist,
                      )
                    : _PlaylistPreview(
                        playlist: playlistState.playlist!,
                        selectedUrls: playlistState.selectedUrls,
                        onToggle: playlistController.toggleItem,
                        onSelectAll: playlistController.selectAll,
                        onClearSelection: playlistController.clearSelection,
                        onInvertSelection: playlistController.invertSelection,
                      ),
              ),
              if (playlistState.hasPreview)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          playlistState.selectedUrls.isEmpty
                              ? null
                              : _importSelected,
                      icon: const Icon(Icons.playlist_add_rounded),
                      label: Text(
                        'Import Selected (${playlistState.selectedUrls.length})',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _persistUrl() {
    ref.read(playlistImportProvider.notifier).updateUrl(_urlController.text);
  }

  void _importSelected() {
    final selectedUrls = ref
        .read(playlistImportProvider.notifier)
        .selectedUrlsInPlaylistOrder();
    Navigator.of(context).pop(selectedUrls);
  }
}

class _PlaylistSheetHeader extends StatelessWidget {
  const _PlaylistSheetHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Import Playlist',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Close playlist import',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _PlaylistUrlInput extends StatelessWidget {
  const _PlaylistUrlInput({
    required this.controller,
    required this.isLoading,
    required this.errorMessage,
    required this.onPreview,
  });

  final TextEditingController controller;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onPreview;

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
            'Paste a supported playlist URL to choose videos for this batch.',
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: controller,
            enabled: !isLoading,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onPreview(),
            decoration: const InputDecoration(
              hintText: 'https://www.youtube.com/playlist?list=...',
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              errorMessage!,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: isLoading ? null : onPreview,
            icon: isLoading
                ? const SizedBox(
                    width: AppSpacing.lg,
                    height: AppSpacing.lg,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview_rounded),
            label: const Text('Preview Playlist'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistPreview extends StatelessWidget {
  const _PlaylistPreview({
    required this.playlist,
    required this.selectedUrls,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onInvertSelection,
  });

  final PlaylistMetadata playlist;
  final Set<String> selectedUrls;
  final void Function(String url, bool isSelected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onInvertSelection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (playlist.items.isEmpty) {
      return Center(
        child: Padding(
          padding: AppSpacing.pageHorizontal,
          child: Text(
            'No videos found in this playlist.',
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: AppSpacing.pageHorizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(playlist.title, style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${playlist.totalCount} videos',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton(onPressed: onSelectAll, child: const Text('Select All')),
                  TextButton(
                    onPressed: onClearSelection,
                    child: const Text('Clear Selection'),
                  ),
                  TextButton(
                    onPressed: onInvertSelection,
                    child: const Text('Invert Selection'),
                  ),
                ],
              ),
              Text(
                '${selectedUrls.length} selected of ${playlist.totalCount} videos',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: AppSpacing.pageHorizontal,
            itemCount: playlist.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final item = playlist.items[index];
              return _PlaylistItemTile(
                item: item,
                isSelected: selectedUrls.contains(item.webpageUrl),
                onChanged: (value) => onToggle(item.webpageUrl, value),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaylistItemTile extends StatelessWidget {
  const _PlaylistItemTile({
    required this.item,
    required this.isSelected,
    required this.onChanged,
  });

  final PlaylistItem item;
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        borderRadius: AppRadii.card,
        onTap: () => onChanged(!isSelected),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              _PlaylistThumbnail(url: item.thumbnailUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                    if (item.durationSeconds != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _formatDuration(item.durationSeconds!),
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Checkbox(
                value: isSelected,
                onChanged: (value) => onChanged(value ?? false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistThumbnail extends StatelessWidget {
  const _PlaylistThumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final thumbnail = url?.trim();

    return ClipRRect(
      borderRadius: AppRadii.duration,
      child: SizedBox(
        width: 96,
        height: 54,
        child: thumbnail == null || thumbnail.isEmpty
            ? ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : Image.network(
                thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.play_circle_outline_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final remainingSeconds = duration.inSeconds.remainder(60);
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = remainingSeconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minuteText:$secondText' : '$minutes:$secondText';
}
