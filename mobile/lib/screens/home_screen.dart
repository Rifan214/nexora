import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_tokens.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';
import '../models/media_state.dart';
import '../models/tracked_download.dart';
import '../providers/active_downloads_provider.dart';
import '../providers/media_provider.dart';
import '../widgets/download_progress_status.dart';
import '../widgets/downloads_content.dart';
import '../widgets/history_content.dart';
import '../widgets/nexora_brand.dart';
import '../widgets/nexora_floating_notification.dart';
import '../widgets/nexora_navigation_bar.dart';
import '../widgets/nexora_state_panel.dart';
import '../widgets/settings_content.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static const routeName = 'home';
  static const routePath = '/';

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _urlController = TextEditingController();
  var _selectedDestinationIndex = NexoraNavigationBar.downloadIndex;
  final _shownCompletionNotificationKeys = <String>{};

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
    ref.listen<List<TrackedDownload>>(activeDownloadsProvider, (_, next) {
      _scheduleCompletionNotifications(next);
    });

    final mediaState = ref.watch(mediaProvider);
    final activeDownloads = ref.watch(activeDownloadsProvider);
    final hasMediaUrl = _urlController.text.trim().isNotEmpty;
    final isMediaBusy = _isMediaBusy(mediaState);
    final canRequestMetadata = hasMediaUrl && !isMediaBusy;

    if (_selectedDestinationIndex == NexoraNavigationBar.downloadsIndex) {
      final downloadsController = ref.read(activeDownloadsProvider.notifier);
      return _buildScaffold(
        DownloadsContent(
          downloads: activeDownloads,
          onCancelDownload: (jobId) {
            unawaited(
              downloadsController.cancelDownload(jobId),
            );
          },
          onClearCompleted: downloadsController.clearCompletedDownloads,
          onClearFailed: downloadsController.clearFailedDownloads,
          onRetryFailedDownload: _retryFailedDownload,
        ),
      );
    }

    if (_selectedDestinationIndex == NexoraNavigationBar.historyIndex) {
      return _buildScaffold(const HistoryContent());
    }

    if (_selectedDestinationIndex == NexoraNavigationBar.settingsIndex) {
      return _buildScaffold(const SettingsContent());
    }

    if (mediaState is! MediaSuccess) {
      return _buildScaffold(
        _HomeReadyContent(
          urlController: _urlController,
          isInputEnabled: !isMediaBusy,
          canAnalyze: canRequestMetadata,
          onPaste: _pasteUrl,
          onAnalyze: () => _getMetadata(canRequestMetadata),
          statusContent: mediaState is MediaIdle
              ? null
              : _MediaStatus(mediaState: mediaState),
        ),
      );
    }

    return _buildScaffold(
      _MetadataLoadedContent(
        urlController: _urlController,
        isInputEnabled: !isMediaBusy,
        canAnalyze: canRequestMetadata,
        showClearAction: hasMediaUrl,
        onClearUrl: _clearUrl,
        onPaste: _pasteUrl,
        onAnalyze: () => _getMetadata(canRequestMetadata),
        metadataContent: _MediaStatus(mediaState: mediaState),
      ),
    );
  }

  Widget _buildScaffold(Widget body) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppDurations.medium,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey(_selectedDestinationIndex),
            child: body,
          ),
        ),
      ),
      bottomNavigationBar: NexoraNavigationBar(
        selectedIndex: _selectedDestinationIndex,
        onDestinationSelected: _onDestinationSelected,
      ),
    );
  }

  void _getMetadata(bool canRequest) {
    if (!canRequest) {
      return;
    }

    ref.read(mediaProvider.notifier).getMediaInfo(_urlController.text);
  }

  Future<void> _retryFailedDownload(String jobId) async {
    final message = await ref
        .read(activeDownloadsProvider.notifier)
        .retryFailedDownload(jobId);
    if (message == null || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scheduleCompletionNotifications(List<TrackedDownload> downloads) {
    for (final download in downloads) {
      final savedFilePath = download.savedFilePath?.trim();
      if (savedFilePath == null || savedFilePath.isEmpty) {
        continue;
      }

      final notificationKey = '${download.jobId}:$savedFilePath';
      if (!_shownCompletionNotificationKeys.add(notificationKey)) {
        continue;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        final isStillSaved = ref.read(activeDownloadsProvider).any(
              (item) =>
                  item.jobId == download.jobId &&
                  item.savedFilePath?.trim() == savedFilePath,
            );
        if (isStillSaved) {
          _showCompletionSnackBar(_snackBarFilename(download));
        }
      });
    }
  }

  void _showCompletionSnackBar(String filename) {
    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        buildNexoraFloatingNotification(
          context,
          title: 'Downloaded',
          message: filename,
          semanticLabel: 'Downloaded $filename',
        ),
      );
  }

  String _snackBarFilename(TrackedDownload download) {
    final downloadedFilename = download.downloadedFilename?.trim();
    if (downloadedFilename != null && downloadedFilename.isNotEmpty) {
      return downloadedFilename;
    }

    final savedFilePath = download.savedFilePath?.trim();
    if (savedFilePath == null || savedFilePath.isEmpty) {
      return 'Download';
    }

    final normalizedPath = savedFilePath.replaceAll('\\', '/');
    final pathSegments = normalizedPath.split('/');
    final fallbackFilename =
        pathSegments.isEmpty ? savedFilePath : pathSegments.last;
    return fallbackFilename.trim().isEmpty ? 'Download' : fallbackFilename;
  }

  void _onUrlChanged() {
    setState(() {});
  }

  void _clearUrl() {
    _urlController.clear();
  }

  Future<void> _pasteUrl() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final url = clipboardData?.text?.trim();
      if (!mounted) {
        return;
      }

      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty.')),
        );
        return;
      }

      _urlController.value = TextEditingValue(
        text: url,
        selection: TextSelection.collapsed(offset: url.length),
      );
    } on PlatformException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to read the clipboard.')),
      );
    }
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedDestinationIndex) {
      return;
    }

    if (index == NexoraNavigationBar.downloadIndex ||
        index == NexoraNavigationBar.downloadsIndex ||
        index == NexoraNavigationBar.historyIndex ||
        index == NexoraNavigationBar.settingsIndex) {
      setState(() {
        _selectedDestinationIndex = index;
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon.')),
    );
  }

  bool _isMediaBusy(MediaState state) {
    if (state is MediaLoading) {
      return true;
    }

    if (state is! MediaSuccess) {
      return false;
    }

    return state.downloadLoading;
  }
}

class _HomeReadyContent extends StatelessWidget {
  const _HomeReadyContent({
    required this.urlController,
    required this.isInputEnabled,
    required this.canAnalyze,
    required this.onPaste,
    required this.onAnalyze,
    this.statusContent,
  });

  final TextEditingController urlController;
  final bool isInputEnabled;
  final bool canAnalyze;
  final Future<void> Function() onPaste;
  final VoidCallback onAnalyze;
  final Widget? statusContent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxHeight < 760;
        final heroTopSpacing = isCompact
            ? AppSpacing.heroTopCompact
            : AppSpacing.heroTop;
        final panelTopSpacing = isCompact
            ? AppSpacing.panelTopCompact
            : AppSpacing.panelTop;

        return SingleChildScrollView(
          padding: AppSpacing.pageHorizontal,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: NexoraBrand(),
                  ),
                  SizedBox(height: heroTopSpacing),
                  Column(
                    children: [
                      Card(
                        child: SizedBox.square(
                          dimension: AppSizes.heroIconContainer,
                          child: Icon(
                            Icons.bolt_rounded,
                            color: colorScheme.primary,
                            size: AppSizes.heroIcon,
                            semanticLabel: 'Ready to fetch media',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Ready to fetch.',
                        style: textTheme.headlineLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text(
                          'Paste a supported URL to begin downloading high-quality media.',
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: panelTopSpacing),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSizes.actionPanelMaxWidth,
                      ),
                      child: Card(
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadii.actionPanel,
                        ),
                        child: Padding(
                          padding: AppSpacing.actionPanel,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: urlController,
                                enabled: isInputEnabled,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.search,
                                autocorrect: false,
                                enableSuggestions: false,
                                onSubmitted: (_) {
                                  if (canAnalyze) {
                                    onAnalyze();
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Paste media URL here...',
                                  prefixIcon: const Icon(Icons.link_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: 'Paste from clipboard',
                                    onPressed: isInputEnabled
                                        ? () {
                                            onPaste();
                                          }
                                        : null,
                                    icon: const Icon(Icons.content_paste_rounded),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              FilledButton.icon(
                                onPressed: canAnalyze ? onAnalyze : null,
                                icon: const Icon(Icons.download_rounded),
                                label: const Text('Analyze'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (statusContent != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    statusContent!,
                  ],
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetadataLoadedContent extends StatelessWidget {
  const _MetadataLoadedContent({
    required this.urlController,
    required this.isInputEnabled,
    required this.canAnalyze,
    required this.showClearAction,
    required this.onClearUrl,
    required this.onPaste,
    required this.onAnalyze,
    required this.metadataContent,
  });

  final TextEditingController urlController;
  final bool isInputEnabled;
  final bool canAnalyze;
  final bool showClearAction;
  final VoidCallback onClearUrl;
  final Future<void> Function() onPaste;
  final VoidCallback onAnalyze;
  final Widget metadataContent;

  @override
  Widget build(BuildContext context) {
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
              TextField(
                controller: urlController,
                enabled: isInputEnabled,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) {
                  if (canAnalyze) {
                    onAnalyze();
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Paste URL here...',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Paste from clipboard',
                        onPressed: isInputEnabled ? onPaste : null,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                      IconButton(
                        tooltip: 'Clear URL',
                        onPressed: showClearAction && isInputEnabled
                            ? onClearUrl
                            : null,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              metadataContent,
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
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
        return const NexoraStatePanel(
          title: 'Fetching metadata',
          message: 'Inspecting the media link.',
          isLoading: true,
        );
      },
      success: (state) {
        final mediaController = ref.read(mediaProvider.notifier);
        final downloadController = ref.read(activeDownloadsProvider.notifier);
        final activeDownload = _downloadForJob(
          ref.watch(activeDownloadsProvider),
          state.currentJobId,
        );
        final hasDetachedSession =
            state.currentJobId?.trim().isNotEmpty == true &&
            activeDownload == null;
        return _MetadataSummary(
          metadata: state.metadata,
          selectedVideoQuality: state.selectedVideoQuality,
          isAudioSelected: state.currentMediaType == MediaDownloadType.audio,
          downloadLoading: state.downloadLoading,
          downloadSuccess: hasDetachedSession ? false : state.downloadSuccess,
          downloadError: hasDetachedSession
              ? null
              : activeDownload?.error ?? state.downloadError,
          currentJobId: hasDetachedSession ? null : state.currentJobId,
          currentStatus: hasDetachedSession
              ? null
              : activeDownload?.status ?? state.currentStatus,
          currentProgress: hasDetachedSession
              ? 0
              : activeDownload?.progress ?? state.currentProgress,
          fileDownloadLoading:
              hasDetachedSession
                  ? false
                  : activeDownload?.fileDownloadLoading ??
                      state.fileDownloadLoading,
          fileDownloadProgress: activeDownload?.fileDownloadProgress ??
              (hasDetachedSession ? 0 : state.fileDownloadProgress),
          fileDownloadError:
              hasDetachedSession
                  ? null
                  : activeDownload?.fileDownloadError ?? state.fileDownloadError,
          downloadedFilename:
              hasDetachedSession
                  ? null
                  : activeDownload?.downloadedFilename ?? state.downloadedFilename,
          savedFilePath: hasDetachedSession
              ? null
              : activeDownload?.savedFilePath ?? state.savedFilePath,
          savedDirectory: hasDetachedSession
              ? null
              : activeDownload?.savedDirectory ?? state.savedDirectory,
          fileOpenLoading:
              hasDetachedSession
                  ? false
                  : activeDownload?.fileOpenLoading ?? state.fileOpenLoading,
          onVideoQualitySelected: mediaController.selectVideoQuality,
          onAudioOptionSelected: mediaController.selectAudioOption,
          onVideoDownloadPressed: mediaController.createVideoDownloadJob,
          onAudioDownloadPressed: mediaController.createAudioDownloadJob,
          onOpenFilePressed: activeDownload == null
              ? () {}
              : () => unawaited(
                    _openCompletedFile(
                      context,
                      downloadController,
                      activeDownload.jobId,
                    ),
                  ),
        );
      },
      error: (state) {
        return _StatusMessage(
          title: 'Metadata Error',
          message: state.message,
          tone: NexoraStateTone.error,
        );
      },
    );
  }
}

Future<void> _openCompletedFile(
  BuildContext context,
  ActiveDownloadsController downloadController,
  String jobId,
) async {
  final message = await downloadController.openDownloadedFile(jobId);
  if (message == null || !context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

TrackedDownload? _downloadForJob(
  List<TrackedDownload> downloads,
  String? jobId,
) {
  final normalizedJobId = jobId?.trim().toLowerCase();
  if (normalizedJobId == null || normalizedJobId.isEmpty) {
    return null;
  }

  for (final download in downloads) {
    if (download.jobId.toLowerCase() == normalizedJobId) {
      return download;
    }
  }
  return null;
}

class _MetadataSummary extends StatelessWidget {
  const _MetadataSummary({
    required this.metadata,
    required this.selectedVideoQuality,
    required this.isAudioSelected,
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
    required this.onAudioOptionSelected,
    required this.onVideoDownloadPressed,
    required this.onAudioDownloadPressed,
    required this.onOpenFilePressed,
  });

  final MediaMetadata metadata;
  final VideoQuality? selectedVideoQuality;
  final bool isAudioSelected;
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
  final VoidCallback onAudioOptionSelected;
  final VoidCallback onVideoDownloadPressed;
  final VoidCallback onAudioDownloadPressed;
  final VoidCallback onOpenFilePressed;

  @override
  Widget build(BuildContext context) {
    final hasCreatedJob = downloadSuccess && currentJobId != null;
    final isDownloadActionDisabled = downloadLoading ||
        fileDownloadLoading ||
        fileOpenLoading ||
        _isActiveStatus(currentStatus) ||
        _isCompletedStatus(currentStatus);
    final hasMediaSelection = selectedVideoQuality != null || isAudioSelected;
    final isStartDownloadDisabled =
        !hasMediaSelection || isDownloadActionDisabled;
    final isMediaSelectionEnabled = !isDownloadActionDisabled;
    final onStartDownloadPressed = isAudioSelected
        ? onAudioDownloadPressed
        : onVideoDownloadPressed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetadataPreviewCard(metadata: metadata),
        const SizedBox(height: AppSpacing.xxl),
        _UnifiedMediaSelection(
          videoQualities: metadata.videoQualities,
          audioOptions: metadata.audioOptions,
          selectedVideoQuality: selectedVideoQuality,
          isAudioSelected: isAudioSelected,
          enabled: isMediaSelectionEnabled,
          onVideoQualitySelected: onVideoQualitySelected,
          onAudioOptionSelected: onAudioOptionSelected,
        ),
        const SizedBox(height: AppSpacing.xxl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: isStartDownloadDisabled ? null : onStartDownloadPressed,
            child: downloadLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: AppSpacing.lg,
                        height: AppSpacing.lg,
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.onPrimary,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Text('Starting Download'),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_rounded),
                      SizedBox(width: AppSpacing.xs),
                      Text('Start Download'),
                    ],
                  ),
          ),
        ),
        if (hasCreatedJob) ...[
          const SizedBox(height: AppSpacing.xl),
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
            onOpenFilePressed: onOpenFilePressed,
          ),
        ] else if (downloadError != null && downloadError!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _StatusMessage(
            title: 'Download Error',
            message: downloadError!,
            tone: NexoraStateTone.error,
          ),
        ],
      ],
    );
  }

  bool _isActiveStatus(String? status) {
    final normalizedStatus = status?.toLowerCase();
    return normalizedStatus == 'pending' ||
        normalizedStatus == 'queued' ||
        normalizedStatus == 'processing' ||
        normalizedStatus == 'cancelling';
  }

  bool _isCompletedStatus(String? status) {
    return status?.toLowerCase() == 'completed';
  }
}

class _MetadataPreviewCard extends StatelessWidget {
  const _MetadataPreviewCard({required this.metadata});

  final MediaMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final thumbnailUrl = metadata.thumbnailUrl?.trim();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: thumbnailUrl == null || thumbnailUrl.isEmpty
                    ? const _ThumbnailPlaceholder()
                    : Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        semanticLabel: metadata.title,
                        errorBuilder: (_, __, ___) {
                          return const _ThumbnailPlaceholder();
                        },
                      ),
              ),
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.inverseSurface.withAlpha(224),
                    borderRadius: AppRadii.duration,
                  ),
                  child: Text(
                    _formatMediaDuration(metadata.durationSeconds),
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onInverseSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _metadataFallback(metadata.title),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      color: colorScheme.onSurfaceVariant,
                      size: AppSpacing.xl,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '${_metadataFallback(metadata.uploader)}  \u2022  ${metadata.platform}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: colorScheme.onSurfaceVariant,
          size: AppSizes.mediaPlaceholderIcon,
        ),
      ),
    );
  }
}

String _metadataFallback(String? value) {
  final trimmedValue = value?.trim();
  if (trimmedValue == null || trimmedValue.isEmpty) {
    return 'Unknown';
  }
  return trimmedValue;
}

String _formatMediaDuration(int? seconds) {
  if (seconds == null) {
    return 'Unknown';
  }

  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final remainingSeconds =
      duration.inSeconds.remainder(60).toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$minutes:$remainingSeconds';
  }

  return '${duration.inMinutes}:$remainingSeconds';
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
        onOpenFilePressed: onOpenFilePressed,
      );
    }

    if (normalizedStatus == 'failed') {
      return _StatusMessage(
        title: 'Download Failed',
        message: _fallback(error, 'Download failed.'),
        tone: NexoraStateTone.error,
      );
    }

    if (normalizedStatus == 'cancelled') {
      return const NexoraStatePanel(
        title: 'Download Cancelled',
        message: 'The download was cancelled.',
        icon: Icons.cancel_outlined,
      );
    }

    if (error != null && error!.isNotEmpty) {
      return _StatusMessage(
        title: 'Progress Error',
        message: error!,
        tone: NexoraStateTone.error,
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final statusLabel = friendlyDownloadStatus(
      backendStatus: status,
      backendProgress: clampedProgress,
      isSavingToDevice: false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                statusLabel,
                style: textTheme.bodyMedium,
              ),
            ),
            Text(
              '$clampedProgress%',
              style: textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppRadii.pill,
          child: LinearProgressIndicator(value: clampedProgress / 100),
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
    required this.onOpenFilePressed,
  });

  final bool fileDownloadLoading;
  final int fileDownloadProgress;
  final String? fileDownloadError;
  final String? downloadedFilename;
  final String? savedFilePath;
  final String? savedDirectory;
  final bool fileOpenLoading;
  final VoidCallback onOpenFilePressed;

  @override
  Widget build(BuildContext context) {
    final hasSavedFile = downloadedFilename != null &&
        downloadedFilename!.isNotEmpty &&
        savedFilePath != null &&
        savedFilePath!.isNotEmpty;
    final hasFileDownloadError =
        fileDownloadError != null && fileDownloadError!.isNotEmpty;
    final filename = downloadedFilename ?? '';
    final savedLocation = _fallback(savedDirectory, savedFilePath ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fileDownloadLoading)
          _FileTransferProgress(progress: fileDownloadProgress)
        else if (!hasSavedFile && !hasFileDownloadError)
          const NexoraStatePanel(
            title: 'Saving to device...',
            message: 'Preparing your download for device storage.',
            isLoading: true,
          ),
        if (hasSavedFile) ...[
          _StatusMessage(
            title: 'Completed',
            message:
                'File saved to your device.\n\nFilename:\n$filename\n\nSaved location:\n$savedLocation',
            tone: NexoraStateTone.success,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: fileOpenLoading ? null : onOpenFilePressed,
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(fileOpenLoading ? 'Opening...' : 'Open File'),
          ),
        ],
        if (hasFileDownloadError) ...[
          _StatusMessage(
            title: 'File Download Error',
            message: fileDownloadError!,
            tone: NexoraStateTone.error,
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
    final statusLabel = friendlyDownloadStatus(
      backendStatus: 'completed',
      backendProgress: 100,
      isSavingToDevice: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                statusLabel,
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (hasKnownProgress)
              Text(
                '$clampedProgress%',
                style: textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppRadii.pill,
          child: LinearProgressIndicator(
            value: hasKnownProgress ? clampedProgress / 100 : null,
          ),
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

class _UnifiedMediaSelection extends StatelessWidget {
  const _UnifiedMediaSelection({
    required this.videoQualities,
    required this.audioOptions,
    required this.selectedVideoQuality,
    required this.isAudioSelected,
    required this.enabled,
    required this.onVideoQualitySelected,
    required this.onAudioOptionSelected,
  });

  final List<VideoQuality> videoQualities;
  final List<AudioOption> audioOptions;
  final VideoQuality? selectedVideoQuality;
  final bool isAudioSelected;
  final bool enabled;
  final ValueChanged<VideoQuality> onVideoQualitySelected;
  final VoidCallback onAudioOptionSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Format',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Video',
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _VideoQualitySelectionList(
          qualities: videoQualities,
          selectedVideoQuality: selectedVideoQuality,
          enabled: enabled,
          onVideoQualitySelected: onVideoQualitySelected,
        ),
        if (audioOptions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          const Divider(),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Audio',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _AudioOptionSelector(
            options: audioOptions,
            isSelected: isAudioSelected,
            enabled: enabled,
            onSelected: onAudioOptionSelected,
          ),
        ],
      ],
    );
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
    final colorScheme = Theme.of(context).colorScheme;

    if (qualities.isEmpty) {
      return Text(
        'No video qualities are available.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final quality in qualities)
              _MediaFormatChip(
                primaryLabel: quality.label,
                secondaryLabel: _estimatedFilesizeLabel(
                  quality.estimatedFilesize,
                ),
                isSelected: selectedVideoQuality?.height == quality.height,
                enabled: enabled,
                onSelected: () => onVideoQualitySelected(quality),
              ),
          ],
        ),
      ],
    );
  }
}

class _MediaFormatChip extends StatelessWidget {
  const _MediaFormatChip({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.isSelected,
    required this.enabled,
    required this.onSelected,
  });

  final String primaryLabel;
  final String? secondaryLabel;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secondaryLabel = this.secondaryLabel;

    return ChoiceChip(
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primaryLabel,
            style: textTheme.bodyLarge?.copyWith(
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (secondaryLabel != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              secondaryLabel,
              style: textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? colorScheme.onPrimary.withAlpha(184)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      selected: isSelected,
      onSelected: enabled ? (_) => onSelected() : null,
      showCheckmark: false,
      selectedColor: colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainer,
      disabledColor: colorScheme.surfaceContainerHigh,
      side: BorderSide(
        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
      ),
      shape: const StadiumBorder(),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
    );
  }
}

class _AudioOptionSelector extends StatelessWidget {
  const _AudioOptionSelector({
    required this.options,
    required this.isSelected,
    required this.enabled,
    required this.onSelected,
  });

  final List<AudioOption> options;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final option in options)
          _MediaFormatChip(
            primaryLabel: '${option.label} (Best Quality)',
            secondaryLabel: 'Best Audio',
            isSelected: isSelected,
            enabled: enabled,
            onSelected: onSelected,
          ),
      ],
    );
  }
}

String? _estimatedFilesizeLabel(int? filesize) {
  if (filesize == null || filesize <= 0) {
    return null;
  }

  const bytesPerMegabyte = 1024 * 1024;
  final megabytes = filesize / bytesPerMegabyte;
  return megabytes >= 100
      ? '~${megabytes.round()} MB'
      : '~${megabytes.toStringAsFixed(1)} MB';
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.title,
    required this.message,
    required this.tone,
  });

  final String title;
  final String message;
  final NexoraStateTone tone;

  @override
  Widget build(BuildContext context) {
    return NexoraStatePanel(
      title: title,
      message: message,
      tone: tone,
    );
  }
}
