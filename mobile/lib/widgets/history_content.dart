import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../models/download_history_item.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';
import '../providers/history_provider.dart';
import '../repositories/media_repository.dart';
import 'media_card_parts.dart';
import 'nexora_brand.dart';
import 'nexora_floating_notification.dart';
import 'nexora_state_panel.dart';

class HistoryContent extends ConsumerStatefulWidget {
  const HistoryContent({super.key});

  @override
  ConsumerState<HistoryContent> createState() => _HistoryContentState();
}

class _HistoryContentState extends ConsumerState<HistoryContent> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<DownloadHistoryItem> _sourceDownloads = const [];
  List<DownloadHistoryItem> _visibleDownloads = const [];
  var _searchQuery = '';
  var _mediaFilter = _HistoryMediaFilter.all;
  var _sortOrder = _HistorySortOrder.newestFirst;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyState = ref.watch(downloadHistoryProvider);
    final historyController = ref.read(downloadHistoryProvider.notifier);
    final textTheme = Theme.of(context).textTheme;
    final header = _HistoryHeader(
      textTheme: textTheme,
      searchController: _searchController,
      searchQuery: _searchQuery,
      selectedFilter: _mediaFilter,
      selectedSortOrder: _sortOrder,
      onSearchChanged: _onSearchChanged,
      onClearSearch: _clearSearch,
      onFilterSelected: _setMediaFilter,
      onSortSelected: _setSortOrder,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
        child: historyState.when(
          data: (downloads) {
            _replaceSourceDownloads(downloads);
            return _HistoryList(
              header: header,
              sourceIsEmpty: downloads.isEmpty,
              visibleDownloads: _visibleDownloads,
              onOpen: (download) {
                unawaited(_openHistoryFile(ref, download.localFilePath));
              },
              onDelete: (download) {
                unawaited(
                  _confirmAndDeleteHistoryItem(
                    context,
                    ref,
                    historyController,
                    download,
                  ),
                );
              },
            );
          },
          loading: () => _HistoryStateList(
            header: header,
            panel: const NexoraStatePanel(
              title: 'Loading history',
              message: 'Loading completed downloads from this device.',
              isLoading: true,
            ),
          ),
          error: (_, __) => _HistoryStateList(
            header: header,
            panel: const NexoraStatePanel(
              title: 'History unavailable',
              message: 'Unable to load saved download history.',
              tone: NexoraStateTone.error,
            ),
          ),
        ),
      ),
    );
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    if (_searchQuery.isNotEmpty) {
      setState(() {
        _searchQuery = '';
        _rebuildVisibleDownloads();
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _searchQuery == value) {
        return;
      }
      setState(() {
        _searchQuery = value;
        _rebuildVisibleDownloads();
      });
    });
  }

  void _setMediaFilter(_HistoryMediaFilter filter) {
    if (filter == _mediaFilter) {
      return;
    }
    setState(() {
      _mediaFilter = filter;
      _rebuildVisibleDownloads();
    });
  }

  void _setSortOrder(_HistorySortOrder sortOrder) {
    if (sortOrder == _sortOrder) {
      return;
    }
    setState(() {
      _sortOrder = sortOrder;
      _rebuildVisibleDownloads();
    });
  }

  void _replaceSourceDownloads(List<DownloadHistoryItem> downloads) {
    if (identical(_sourceDownloads, downloads)) {
      return;
    }
    _sourceDownloads = downloads;
    _rebuildVisibleDownloads();
  }

  void _rebuildVisibleDownloads() {
    _visibleDownloads = _HistoryViewPipeline(
      query: _searchQuery,
      mediaFilter: _mediaFilter,
      sortOrder: _sortOrder,
    ).apply(_sourceDownloads);
  }

  Future<void> _confirmAndDeleteHistoryItem(
    BuildContext context,
    WidgetRef ref,
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

    final updatedHistory = ref.read(downloadHistoryProvider).valueOrNull;
    if (updatedHistory == null ||
        updatedHistory.any((item) => item.id == download.id)) {
      return;
    }

    if (deleteOption == _HistoryDeleteOption.historyAndFile) {
      await _deleteLocalFileIfPresent(download.localFilePath);
    }

    if (!context.mounted) {
      return;
    }

    final message = deleteOption == _HistoryDeleteOption.historyAndFile
        ? 'Download removed'
        : 'History removed';
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(buildNexoraFloatingNotification(context, title: message));
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

  Future<void> _openHistoryFile(WidgetRef ref, String path) async {
    try {
      await ref.read(mediaRepositoryProvider).openDownloadedFile(path);
    } catch (_) {
      // The card only enables tapping after confirming that the file exists.
    }
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.textTheme,
    required this.searchController,
    required this.searchQuery,
    required this.selectedFilter,
    required this.selectedSortOrder,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onFilterSelected,
    required this.onSortSelected,
  });

  final TextTheme textTheme;
  final TextEditingController searchController;
  final String searchQuery;
  final _HistoryMediaFilter selectedFilter;
  final _HistorySortOrder selectedSortOrder;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_HistoryMediaFilter> onFilterSelected;
  final ValueChanged<_HistorySortOrder> onSortSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                'Recent Downloads',
                style: textTheme.headlineMedium,
              ),
            ),
            PopupMenuButton<_HistorySortOrder>(
              tooltip: 'Sort history',
              icon: const Icon(Icons.sort_rounded),
              initialValue: selectedSortOrder,
              onSelected: onSortSelected,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _HistorySortOrder.newestFirst,
                  child: Text('Newest first'),
                ),
                PopupMenuItem(
                  value: _HistorySortOrder.oldestFirst,
                  child: Text('Oldest first'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SearchBar(
          controller: searchController,
          hintText: 'Search downloads...',
          leading: const Icon(Icons.search_rounded),
          trailing: searchQuery.isEmpty
              ? null
              : [
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        _HistoryFilterBar(
          selectedFilter: selectedFilter,
          onSelected: onFilterSelected,
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _HistoryStateList extends StatelessWidget {
  const _HistoryStateList({required this.header, required this.panel});

  final Widget header;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: AppSpacing.pageHorizontal,
      itemCount: 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return header;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: panel,
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.header,
    required this.sourceIsEmpty,
    required this.visibleDownloads,
    required this.onOpen,
    required this.onDelete,
  });

  final Widget header;
  final bool sourceIsEmpty;
  final List<DownloadHistoryItem> visibleDownloads;
  final ValueChanged<DownloadHistoryItem> onOpen;
  final ValueChanged<DownloadHistoryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final showsStatePanel = sourceIsEmpty || visibleDownloads.isEmpty;
    final itemCount = showsStatePanel ? 2 : visibleDownloads.length + 1;

    return ListView.builder(
      padding: AppSpacing.pageHorizontal,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return header;
        }
        if (sourceIsEmpty) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xxl),
            child: NexoraStatePanel(
              title: 'No completed downloads',
              message:
                  'Completed downloads saved on this device will appear here.',
              icon: Icons.history_rounded,
            ),
          );
        }
        if (visibleDownloads.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xxl),
            child: NexoraStatePanel(
              title: 'No matching downloads found.',
              message: 'Try a different search or filter.',
              icon: Icons.search_off_rounded,
            ),
          );
        }

        final download = visibleDownloads[index - 1];
        final isLastDownload = index == visibleDownloads.length;
        return Padding(
          padding: EdgeInsets.only(
            bottom: isLastDownload
                ? AppSpacing.xl + AppSpacing.xxl
                : AppSpacing.xl,
          ),
          child: _HistoryDownloadCard(
            download: download,
            onOpen: () => onOpen(download),
            onDelete: () => onDelete(download),
          ),
        );
      },
    );
  }
}

enum _HistoryMediaFilter { all, videos, audio }

enum _HistorySortOrder { newestFirst, oldestFirst }

class _HistoryViewPipeline {
  const _HistoryViewPipeline({
    required this.query,
    required this.mediaFilter,
    required this.sortOrder,
  });

  final String query;
  final _HistoryMediaFilter mediaFilter;
  final _HistorySortOrder sortOrder;

  List<DownloadHistoryItem> apply(List<DownloadHistoryItem> downloads) {
    final normalizedQuery = query.trim().toLowerCase();
    final searched = normalizedQuery.isEmpty
        ? downloads
        : [
            for (final download in downloads)
              if (_matchesSearch(download, normalizedQuery)) download,
          ];
    final filtered = [
      for (final download in searched)
        if (_matchesMediaFilter(download)) download,
    ];
    final sorted = List<DownloadHistoryItem>.of(filtered);
    sorted.sort(_compareByCreatedAt);
    return sorted;
  }

  bool _matchesMediaFilter(DownloadHistoryItem download) {
    return switch (mediaFilter) {
      _HistoryMediaFilter.all => true,
      _HistoryMediaFilter.videos => download.mediaType == MediaDownloadType.video,
      _HistoryMediaFilter.audio => download.mediaType == MediaDownloadType.audio,
    };
  }

  bool _matchesSearch(DownloadHistoryItem download, String query) {
    // The current local history schema persists the title only. Keep matching
    // centralized so future persisted uploader or source URL fields can join
    // this local-only filter without changing the History UI.
    return download.title.toLowerCase().contains(query);
  }

  int _compareByCreatedAt(DownloadHistoryItem left, DownloadHistoryItem right) {
    final comparison = left.createdAt.compareTo(right.createdAt);
    return sortOrder == _HistorySortOrder.newestFirst
        ? -comparison
        : comparison;
  }
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.selectedFilter,
    required this.onSelected,
  });

  final _HistoryMediaFilter selectedFilter;
  final ValueChanged<_HistoryMediaFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in _HistoryMediaFilter.values) ...[
            ChoiceChip(
              label: Text(_historyFilterLabel(filter)),
              selected: selectedFilter == filter,
              onSelected: (_) => onSelected(filter),
              showCheckmark: false,
            ),
            if (filter != _HistoryMediaFilter.values.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

String _historyFilterLabel(_HistoryMediaFilter filter) {
  return switch (filter) {
    _HistoryMediaFilter.all => 'All',
    _HistoryMediaFilter.videos => 'Videos',
    _HistoryMediaFilter.audio => 'Audio',
  };
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
    final textTheme = Theme.of(context).textTheme;
    final actionStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, AppSizes.touchTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      textStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );

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
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: actionStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(
              colorScheme.surfaceContainerHigh,
            ),
            foregroundColor: WidgetStatePropertyAll(colorScheme.onSurface),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedOption),
          style: actionStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(colorScheme.error),
            foregroundColor: WidgetStatePropertyAll(colorScheme.onError),
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

class _HistoryDownloadCard extends StatefulWidget {
  const _HistoryDownloadCard({
    required this.download,
    required this.onOpen,
    required this.onDelete,
  });

  final DownloadHistoryItem download;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_HistoryDownloadCard> createState() => _HistoryDownloadCardState();
}

class _HistoryDownloadCardState extends State<_HistoryDownloadCard> {
  late Future<bool> _fileExists;

  @override
  void initState() {
    super.initState();
    _fileExists = _checkFileExists();
  }

  @override
  void didUpdateWidget(covariant _HistoryDownloadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.download.localFilePath != widget.download.localFilePath) {
      _fileExists = _checkFileExists();
    }
  }

  Future<bool> _checkFileExists() async {
    try {
      return await FileSystemEntity.type(
            widget.download.localFilePath,
            followLinks: false,
          ) ==
          FileSystemEntityType.file;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _fileExists,
      builder: (context, snapshot) {
        final isFileMissing =
            snapshot.connectionState == ConnectionState.done &&
            snapshot.data != true;
        final isFileAvailable =
            snapshot.connectionState == ConnectionState.done &&
            snapshot.data == true;
        return _buildCard(
          context,
          isFileMissing: isFileMissing,
          isFileAvailable: isFileAvailable,
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool isFileMissing,
    required bool isFileAvailable,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final mediaTypeLabel = _mediaTypeLabel(widget.download);
    final qualityLabel = widget.download.selectedQuality;

    return Card(
      child: InkWell(
        onTap: isFileAvailable ? widget.onOpen : null,
        borderRadius: AppRadii.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NexoraMediaThumbnail(
              metadata: _thumbnailMetadata(widget.download),
              mediaType: widget.download.mediaType,
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
                          widget.download.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove from history',
                        color: Theme.of(context).colorScheme.error,
                        onPressed: widget.onDelete,
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
                      if (isFileMissing)
                        const MediaBadge(
                          label: 'File Missing',
                          tone: MediaBadgeTone.error,
                          icon: Icons.error_outline_rounded,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
