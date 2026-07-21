import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_tokens.dart';
import '../models/health_check_result.dart';
import '../models/media_metadata.dart';
import '../models/media_state.dart';
import '../providers/health_provider.dart';
import '../providers/media_provider.dart';
import '../widgets/downloads_content.dart';
import '../widgets/history_content.dart';
import '../widgets/nexora_brand.dart';
import '../widgets/nexora_navigation_bar.dart';

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
    final healthState = ref.watch(healthProvider);
    final mediaState = ref.watch(mediaProvider);
    final isCheckingHealth = healthState.isLoading;
    final hasMediaUrl = _urlController.text.trim().isNotEmpty;
    final isMediaBusy = _isMediaBusy(mediaState);
    final canRequestMetadata = hasMediaUrl && !isMediaBusy;

    if (_selectedDestinationIndex == NexoraNavigationBar.downloadsIndex) {
      return _buildScaffold(DownloadsContent(mediaState: mediaState));
    }

    if (_selectedDestinationIndex == NexoraNavigationBar.historyIndex) {
      return _buildScaffold(HistoryContent(mediaState: mediaState));
    }

    if (mediaState is MediaIdle) {
      return _buildScaffold(
        _HomeReadyContent(
          urlController: _urlController,
          canAnalyze: canRequestMetadata,
          onPaste: _pasteUrl,
          onAnalyze: () => _getMetadata(canRequestMetadata),
        ),
      );
    }

    if (mediaState is MediaSuccess) {
      return _buildScaffold(
        _MetadataLoadedContent(
          urlController: _urlController,
          isInputEnabled: !isMediaBusy,
          canAnalyze: canRequestMetadata,
          showClearAction: hasMediaUrl,
          onClearUrl: _clearUrl,
          onAnalyze: () => _getMetadata(canRequestMetadata),
          metadataContent: _MediaStatus(mediaState: mediaState),
        ),
      );
    }

    final metadataButtonLabel = mediaState is MediaLoading
        ? 'Loading...'
        : isMediaBusy
            ? 'Please wait...'
            : 'Get Metadata';

    return _buildScaffold(
      _LegacyWorkflowContent(
        urlController: _urlController,
        healthState: healthState,
        isCheckingHealth: isCheckingHealth,
        isMediaBusy: isMediaBusy,
        canRequestMetadata: canRequestMetadata,
        metadataButtonLabel: metadataButtonLabel,
        mediaState: mediaState,
        onCheckBackend: () {
          ref.read(healthProvider.notifier).checkBackend();
        },
        onGetMetadata: () => _getMetadata(canRequestMetadata),
      ),
    );
  }

  Widget _buildScaffold(Widget body) {
    return Scaffold(
      body: SafeArea(child: body),
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
        index == NexoraNavigationBar.historyIndex) {
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

    final normalizedStatus = state.currentStatus?.toLowerCase();
    return state.downloadLoading ||
        state.fileDownloadLoading ||
        state.fileOpenLoading ||
        normalizedStatus == 'pending' ||
        normalizedStatus == 'processing';
  }
}

class _HomeReadyContent extends StatelessWidget {
  const _HomeReadyContent({
    required this.urlController,
    required this.canAnalyze,
    required this.onPaste,
    required this.onAnalyze,
  });

  final TextEditingController urlController;
  final bool canAnalyze;
  final Future<void> Function() onPaste;
  final VoidCallback onAnalyze;

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
                            size: 64,
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
                                    onPressed: () {
                                      onPaste();
                                    },
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
    required this.onAnalyze,
    required this.metadataContent,
  });

  final TextEditingController urlController;
  final bool isInputEnabled;
  final bool canAnalyze;
  final bool showClearAction;
  final VoidCallback onClearUrl;
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
                  suffixIcon: IconButton(
                    tooltip: 'Clear URL',
                    onPressed: showClearAction && isInputEnabled
                        ? onClearUrl
                        : null,
                    icon: const Icon(Icons.close_rounded),
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

class _LegacyWorkflowContent extends StatelessWidget {
  const _LegacyWorkflowContent({
    required this.urlController,
    required this.healthState,
    required this.isCheckingHealth,
    required this.isMediaBusy,
    required this.canRequestMetadata,
    required this.metadataButtonLabel,
    required this.mediaState,
    required this.onCheckBackend,
    required this.onGetMetadata,
  });

  final TextEditingController urlController;
  final AsyncValue<HealthCheckResult?> healthState;
  final bool isCheckingHealth;
  final bool isMediaBusy;
  final bool canRequestMetadata;
  final String metadataButtonLabel;
  final MediaState mediaState;
  final VoidCallback onCheckBackend;
  final VoidCallback onGetMetadata;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.actionPanelMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nexora',
                style: textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: isCheckingHealth ? null : onCheckBackend,
                child: Text(isCheckingHealth ? 'Checking...' : 'Check Backend'),
              ),
              const SizedBox(height: AppSpacing.md),
              _HealthStatus(healthState: healthState),
              const SizedBox(height: AppSpacing.xxl),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(labelText: 'Media URL'),
                enabled: !isMediaBusy,
                onSubmitted: (_) => onGetMetadata(),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: canRequestMetadata ? onGetMetadata : null,
                child: Text(metadataButtonLabel),
              ),
              const SizedBox(height: AppSpacing.md),
              _MediaStatus(mediaState: mediaState),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthStatus extends StatelessWidget {
  const _HealthStatus({required this.healthState});

  final AsyncValue<HealthCheckResult?> healthState;

  @override
  Widget build(BuildContext context) {
    return healthState.when(
      data: (result) {
        if (result == null) {
          return const SizedBox.shrink();
        }

        return _StatusMessage(
          title: result.isHealthy ? '\u2705 Backend Online' : '\u274C Backend Offline',
          message: result.serverMessage,
        );
      },
      error: (error, _) {
        return _StatusMessage(
          title: '\u274C Backend Offline',
          message: _readErrorMessage(error),
        );
      },
      loading: () {
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  String _readErrorMessage(Object error) {
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }

    return 'Unable to contact the backend.';
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
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      success: (state) {
        final mediaController = ref.read(mediaProvider.notifier);
        return _MetadataSummary(
          metadata: state.metadata,
          selectedVideoQuality: state.selectedVideoQuality,
          isAudioSelected: state.currentMediaType?.name == 'audio',
          downloadLoading: state.downloadLoading,
          downloadSuccess: state.downloadSuccess,
          downloadError: state.downloadError,
          currentJobId: state.currentJobId,
          currentStatus: state.currentStatus,
          currentProgress: state.currentProgress,
          fileDownloadLoading: state.fileDownloadLoading,
          fileDownloadProgress: state.fileDownloadProgress,
          fileDownloadError: state.fileDownloadError,
          downloadedFilename: state.downloadedFilename,
          savedFilePath: state.savedFilePath,
          savedDirectory: state.savedDirectory,
          fileOpenLoading: state.fileOpenLoading,
          onVideoQualitySelected: mediaController.selectVideoQuality,
          onVideoDownloadPressed: mediaController.createVideoDownloadJob,
          onAudioDownloadPressed: mediaController.createAudioDownloadJob,
          onFileDownloadPressed: mediaController.downloadCompletedFile,
          onOpenFilePressed: mediaController.openDownloadedFile,
        );
      },
      error: (state) {
        return _StatusMessage(
          title: '\u274C Metadata Error',
          message: state.message,
        );
      },
    );
  }
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
    required this.onVideoDownloadPressed,
    required this.onAudioDownloadPressed,
    required this.onFileDownloadPressed,
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
  final VoidCallback onVideoDownloadPressed;
  final VoidCallback onAudioDownloadPressed;
  final VoidCallback onFileDownloadPressed;
  final VoidCallback onOpenFilePressed;

  @override
  Widget build(BuildContext context) {
    final hasCreatedJob = downloadSuccess && currentJobId != null;
    final isDownloadActionDisabled = downloadLoading ||
        fileDownloadLoading ||
        fileOpenLoading ||
        _isActiveStatus(currentStatus) ||
        _isCompletedStatus(currentStatus);
    final isVideoDownloadDisabled =
        selectedVideoQuality == null || isDownloadActionDisabled;
    final isVideoQualitySelectionEnabled = !downloadLoading &&
        !fileDownloadLoading &&
        !fileOpenLoading &&
        !_isActiveStatus(currentStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetadataPreviewCard(metadata: metadata),
        const SizedBox(height: AppSpacing.xxl),
        _VideoQualitySelectionList(
          qualities: metadata.videoQualities,
          selectedVideoQuality: selectedVideoQuality,
          enabled: isVideoQualitySelectionEnabled,
          onVideoQualitySelected: onVideoQualitySelected,
        ),
        if (metadata.audioOptions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          const Divider(),
          const SizedBox(height: AppSpacing.xxl),
          _AudioOptionSelector(
            options: metadata.audioOptions,
            isSelected: isAudioSelected,
            enabled: !isDownloadActionDisabled,
            onSelected: onAudioDownloadPressed,
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed:
                isVideoDownloadDisabled ? null : onVideoDownloadPressed,
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
            onFileDownloadPressed: onFileDownloadPressed,
            onOpenFilePressed: onOpenFilePressed,
          ),
        ] else if (downloadError != null && downloadError!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _StatusMessage(
            title: '\u274C Download Error',
            message: downloadError!,
          ),
        ],
      ],
    );
  }

  bool _isActiveStatus(String? status) {
    final normalizedStatus = status?.toLowerCase();
    return normalizedStatus == 'pending' || normalizedStatus == 'processing';
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
                    borderRadius: AppRadii.input,
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
          size: 40,
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
    required this.onFileDownloadPressed,
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
  final VoidCallback onFileDownloadPressed;
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
        onFileDownloadPressed: onFileDownloadPressed,
        onOpenFilePressed: onOpenFilePressed,
      );
    }

    if (normalizedStatus == 'failed') {
      return _StatusMessage(
        title: '\u274C Download Failed',
        message: _fallback(error, 'Download failed.'),
      );
    }

    if (error != null && error!.isNotEmpty) {
      return _StatusMessage(
        title: '\u274C Progress Error',
        message: error!,
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status: ${_formatStatus(normalizedStatus)}',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '$clampedProgress%',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: clampedProgress / 100),
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

  String _formatStatus(String value) {
    final words = value.replaceAll('_', ' ').split(' ');
    return words.map((word) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
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
    required this.onFileDownloadPressed,
    required this.onOpenFilePressed,
  });

  final bool fileDownloadLoading;
  final int fileDownloadProgress;
  final String? fileDownloadError;
  final String? downloadedFilename;
  final String? savedFilePath;
  final String? savedDirectory;
  final bool fileOpenLoading;
  final VoidCallback onFileDownloadPressed;
  final VoidCallback onOpenFilePressed;

  @override
  Widget build(BuildContext context) {
    final hasSavedFile = downloadedFilename != null &&
        downloadedFilename!.isNotEmpty &&
        savedFilePath != null &&
        savedFilePath!.isNotEmpty;
    final filename = downloadedFilename ?? '';
    final savedLocation = _fallback(savedDirectory, savedFilePath ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StatusMessage(
          title: '\u2705 Download Complete',
          message: 'Ready to download.',
        ),
        const SizedBox(height: 12),
        if (fileDownloadLoading)
          _FileTransferProgress(progress: fileDownloadProgress)
        else if (!hasSavedFile)
          FilledButton(
            onPressed: onFileDownloadPressed,
            child: const Text('Download File'),
          ),
        if (hasSavedFile) ...[
          const SizedBox(height: 12),
          _StatusMessage(
            title: '\u2705 File downloaded successfully',
            message: 'Filename:\n$filename\n\nSaved location:\n$savedLocation',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: fileOpenLoading ? null : onOpenFilePressed,
            child: Text(fileOpenLoading ? 'Opening...' : 'Open File'),
          ),
        ],
        if (fileDownloadError != null && fileDownloadError!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _StatusMessage(
            title: '\u274C File Download Error',
            message: fileDownloadError!,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saving file',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          hasKnownProgress ? '$clampedProgress%' : 'Starting...',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: hasKnownProgress ? clampedProgress / 100 : null,
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
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    if (qualities.isEmpty) {
      return Text(
        'No video qualities are available.',
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Video Quality',
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final quality in qualities)
              _VideoQualityChip(
                quality: quality,
                selectedHeight: selectedVideoQuality?.height,
                enabled: enabled,
                onSelected: () => onVideoQualitySelected(quality),
              ),
          ],
        ),
      ],
    );
  }
}

class _VideoQualityChip extends StatelessWidget {
  const _VideoQualityChip({
    required this.quality,
    required this.selectedHeight,
    required this.enabled,
    required this.onSelected,
  });

  final VideoQuality quality;
  final int? selectedHeight;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = selectedHeight == quality.height;

    return ChoiceChip(
      label: Text(quality.label),
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
      labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      labelStyle: textTheme.bodyLarge?.copyWith(
        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
        fontWeight: FontWeight.w600,
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        for (final option in options)
          Material(
            type: MaterialType.transparency,
            borderRadius: AppRadii.input,
            child: InkWell(
              onTap: enabled ? onSelected : null,
              borderRadius: AppRadii.input,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Icon(
                      Icons.music_note_rounded,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      size: AppSpacing.xl,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${option.label} (Best Quality)',
                            style: textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Save as high-quality ${option.extension.toUpperCase()}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isSelected,
                      onChanged: enabled ? (_) => onSelected() : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
