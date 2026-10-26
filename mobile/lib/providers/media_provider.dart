import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/platform_auth_headers.dart';
import '../models/completed_file_download.dart';
import '../models/download_preferences.dart';
import '../models/download_history_item.dart';
import '../models/job_update.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';
import '../models/media_state.dart';
import '../repositories/media_repository.dart';
import 'active_downloads_provider.dart';
import 'download_preferences_provider.dart';
import 'history_provider.dart';

final mediaProvider = NotifierProvider<MediaController, MediaState>(
  MediaController.new,
);

class MediaController extends Notifier<MediaState> {
  StreamSubscription<JobUpdate>? _jobSubscription;
  CancelToken? _fileDownloadCancelToken;
  CancelToken? _metadataCancelToken;
  CancelToken? _createJobCancelToken;
  int _downloadGeneration = 0;

  @override
  MediaState build() {
    ref.onDispose(() {
      unawaited(_jobSubscription?.cancel());
      _jobSubscription = null;
      _fileDownloadCancelToken?.cancel('File download cancelled.');
      _fileDownloadCancelToken = null;
      _metadataCancelToken?.cancel('MediaController disposed.');
      _metadataCancelToken = null;
      _createJobCancelToken?.cancel('MediaController disposed.');
      _createJobCancelToken = null;
    });

    return const MediaState.idle();
  }

  Future<void> getMediaInfo(String url) async {
    if (_isWorkflowBusy) {
      return;
    }

    await _closeJobSubscription();
    _cancelFileDownload();
    _metadataCancelToken?.cancel('Cancelled by new request.');
    final metadataCancelToken = CancelToken();
    _metadataCancelToken = metadataCancelToken;

    final trimmedUrl = url.trim();
    final validationMessage = _validateUrl(trimmedUrl);
    if (validationMessage != null) {
      state = MediaState.error(validationMessage);
      return;
    }

    state = const MediaState.loading();

    try {
      final authHeaders = buildAuthHeadersForUrl(ref, trimmedUrl);
      final metadata = await ref
          .read(mediaRepositoryProvider)
          .getMediaInfo(
            trimmedUrl,
            headers: authHeaders,
            cancelToken: metadataCancelToken,
          );
      if (!identical(_metadataCancelToken, metadataCancelToken)) {
        return;
      }
      if (kDebugMode) {
        debugPrint(
          'MediaProvider received video quality count=${metadata.videoQualities.length} '
          'audio option count=${metadata.audioOptions.length}',
        );
      }
      final preferences = await _loadDownloadPreferences();
      final preferredSelection =
          resolvePreferredMediaSelection(metadata, preferences);
      state = MediaState.success(
        metadata: metadata,
        selectedVideoQuality: preferredSelection?.videoQuality,
        currentMediaType: preferredSelection?.mediaType,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) ||
          !identical(_metadataCancelToken, metadataCancelToken)) {
        return;
      }
      state = const MediaState.error('Unable to retrieve media metadata.');
    } on ApiException catch (error) {
      if (!identical(_metadataCancelToken, metadataCancelToken)) {
        return;
      }
      await handleSessionInvalidationForUrl(
        ref,
        trimmedUrl,
        message: error.message,
      );
      state = MediaState.error(error.message);
    } catch (_) {
      if (!identical(_metadataCancelToken, metadataCancelToken)) {
        return;
      }
      state = const MediaState.error('Unable to retrieve media metadata.');
    } finally {
      if (identical(_metadataCancelToken, metadataCancelToken)) {
        _metadataCancelToken = null;
      }
    }
  }

  Future<DownloadPreferences> _loadDownloadPreferences() async {
    try {
      return await ref.read(downloadPreferencesProvider.future);
    } catch (_) {
      return const DownloadPreferences();
    }
  }

  void selectVideoQuality(VideoQuality quality) {
    final current = _successState;
    if (current == null ||
        current.downloadLoading ||
        current.fileDownloadLoading ||
        current.fileOpenLoading) {
      return;
    }

    unawaited(_closeJobSubscription());
    _cancelFileDownload();

    state = MediaState.success(
      metadata: current.metadata,
      selectedVideoQuality: quality,
      currentMediaType: MediaDownloadType.video,
    );
  }

  void selectAudioOption() {
    final current = _successState;
    if (current == null ||
        current.downloadLoading ||
        current.fileDownloadLoading ||
        current.fileOpenLoading ||
        current.metadata.audioOptions.isEmpty) {
      return;
    }

    unawaited(_closeJobSubscription());
    _cancelFileDownload();

    state = MediaState.success(
      metadata: current.metadata,
      currentMediaType: MediaDownloadType.audio,
    );
  }

  Future<void> createVideoDownloadJob() {
    return _createDownloadJob(MediaDownloadType.video);
  }

  Future<void> createAudioDownloadJob() {
    return _createDownloadJob(MediaDownloadType.audio);
  }

  Future<void> cancelCurrentDownload() async {
    if (state is MediaLoading) {
      _metadataCancelToken?.cancel('Metadata retrieval cancelled.');
      _metadataCancelToken = null;
      state = const MediaState.idle();
      return;
    }

    final current = _successState;
    if (current == null) {
      return;
    }

    final jobId = current.currentJobId?.trim();
    final status = current.currentStatus?.trim().toLowerCase();

    // 1. If job creation is still loading (in-flight network request before job ID exists)
    if (current.downloadLoading) {
      _createJobCancelToken?.cancel('Download cancelled during job creation.');
      _createJobCancelToken = null;
      _downloadGeneration++;
      state = current.copyWith(
        downloadLoading: false,
        downloadSuccess: false,
        currentStatus: 'cancelled',
        downloadError: null,
      );
      return;
    }

    if (jobId == null || jobId.isEmpty) {
      return;
    }

    if (status == 'cancelled' || !_isActiveStatus(status)) {
      return;
    }

    // 2. Immediately close subscriptions and cancel local downloads
    unawaited(_closeJobSubscription());
    _cancelFileDownload();

    // 3. Immediately settle state to 'cancelled' (safe offline)
    state = current.copyWith(
      currentStatus: 'cancelled',
      downloadLoading: false,
      fileDownloadLoading: false,
      downloadError: null,
    );

    // 4. Ensure activeDownloadsProvider is cancelled synchronously
    unawaited(
      ref.read(activeDownloadsProvider.notifier).cancelDownload(jobId),
    );

    // 5. Best-effort background notification to backend
    try {
      await ref.read(mediaRepositoryProvider).cancelDownloadJob(jobId);
    } catch (_) {
      // Network unreachable or offline: local state remains cancelled!
    }
  }

  Future<void> _createDownloadJob(MediaDownloadType mediaType) async {
    final current = _successState;
    if (current == null ||
        current.downloadLoading ||
        current.fileDownloadLoading ||
        current.fileOpenLoading) {
      return;
    }

    _cancelFileDownload();
    _createJobCancelToken?.cancel('Cancelled by new download.');
    final createJobCancelToken = CancelToken();
    _createJobCancelToken = createJobCancelToken;
    final generation = ++_downloadGeneration;

    final selectedVideoQuality = current.selectedVideoQuality;
    if (mediaType == MediaDownloadType.video && selectedVideoQuality == null) {
      state = current.copyWith(
        downloadError: 'Select a video quality before downloading.',
      );
      return;
    }
    if (mediaType == MediaDownloadType.audio &&
        current.metadata.audioOptions.isEmpty) {
      state = current.copyWith(
        downloadError: 'Audio download is not available for this media.',
      );
      return;
    }

    final validationMessage = _validateUrl(current.metadata.webpageUrl);
    if (validationMessage != null) {
      state = current.copyWith(downloadError: validationMessage);
      return;
    }

    await _closeJobSubscription();

    state = current.copyWith(
      downloadLoading: true,
      downloadSuccess: false,
      downloadError: null,
      currentJobId: null,
      currentStatus: null,
      currentProgress: 0,
      downloadUrl: null,
      currentMediaType: mediaType,
      fileDownloadLoading: false,
      fileDownloadProgress: 0,
      fileDownloadError: null,
      downloadedFilename: null,
      savedFilePath: null,
      savedDirectory: null,
      fileOpenLoading: false,
    );

    try {
      final authHeaders = buildAuthHeadersForUrl(ref, current.metadata.webpageUrl);
      final job = await ref.read(mediaRepositoryProvider).createDownloadJob(
            mediaUrl: current.metadata.webpageUrl,
            mediaType: mediaType,
            videoQuality: selectedVideoQuality,
            headers: authHeaders,
            cancelToken: createJobCancelToken,
          );

      if (generation != _downloadGeneration ||
          !identical(_createJobCancelToken, createJobCancelToken)) {
        // Cancelled or superseded while request was in-flight
        unawaited(
          ref.read(mediaRepositoryProvider).cancelDownloadJob(job.jobId).catchError(
            (_) => JobUpdate(jobId: job.jobId, status: 'cancelled', progress: 0),
          ),
        );
        return;
      }

      final latest = _successState;
      if (latest == null) {
        unawaited(
          ref.read(mediaRepositoryProvider).cancelDownloadJob(job.jobId).catchError(
            (_) => JobUpdate(jobId: job.jobId, status: 'cancelled', progress: 0),
          ),
        );
        return;
      }

      state = latest.copyWith(
        downloadLoading: false,
        downloadSuccess: true,
        downloadError: null,
        currentJobId: job.jobId,
        currentStatus: 'pending',
        currentProgress: 0,
      );
      ref.read(activeDownloadsProvider.notifier).trackDownload(
            jobId: job.jobId,
            metadata: current.metadata,
            mediaType: mediaType,
            selectedVideoQuality: selectedVideoQuality,
          );
      _listenToJob(job.jobId);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || generation != _downloadGeneration) {
        return;
      }
      final latest = _successState;
      if (latest == null) {
        return;
      }
      state = latest.copyWith(
        downloadLoading: false,
        downloadError: 'Network unavailable. Check your connection.',
      );
    } on ApiException catch (error) {
      if (generation != _downloadGeneration) {
        return;
      }
      await handleSessionInvalidationForUrl(
        ref,
        current.metadata.webpageUrl,
        message: error.message,
      );
      final latest = _successState;
      if (latest == null) {
        return;
      }

      state = latest.copyWith(
        downloadLoading: false,
        downloadError: error.message,
      );
    } catch (_) {
      if (generation != _downloadGeneration) {
        return;
      }
      final latest = _successState;
      if (latest == null) {
        return;
      }

      state = latest.copyWith(
        downloadLoading: false,
        downloadError: 'Unable to create download job.',
      );
    } finally {
      if (identical(_createJobCancelToken, createJobCancelToken)) {
        _createJobCancelToken = null;
      }
    }
  }

  Future<void> downloadCompletedFile() async {
    final current = _successState;
    if (current == null ||
        current.fileDownloadLoading ||
        current.fileOpenLoading) {
      return;
    }

    if (current.savedFilePath?.trim().isNotEmpty == true) {
      return;
    }

    if (current.currentStatus?.toLowerCase() != 'completed') {
      state = current.copyWith(
        fileDownloadError: 'Wait until the download is complete.',
      );
      return;
    }

    final downloadUrl = current.downloadUrl?.trim();
    if (downloadUrl == null || downloadUrl.isEmpty) {
      state = current.copyWith(
        fileDownloadError: 'Completed file URL is missing.',
      );
      return;
    }

    final cancelToken = CancelToken();
    _fileDownloadCancelToken = cancelToken;

    state = current.copyWith(
      fileDownloadLoading: true,
      fileDownloadProgress: 0,
      fileDownloadError: null,
      downloadedFilename: null,
      savedFilePath: null,
      savedDirectory: null,
      fileOpenLoading: false,
    );

    try {
      final savedFile =
          await ref.read(mediaRepositoryProvider).downloadCompletedFile(
                downloadUrl: downloadUrl,
                suggestedFilename: _suggestedFilename(current),
                mediaType: current.currentMediaType ?? MediaDownloadType.video,
                cancelToken: cancelToken,
                onReceiveProgress: (received, total) {
                  _handleFileDownloadProgress(cancelToken, received, total);
                },
              );

      if (!identical(_fileDownloadCancelToken, cancelToken)) {
        return;
      }

      final latest = _successState;
      if (latest == null) {
        return;
      }

      state = latest.copyWith(
        fileDownloadLoading: false,
        fileDownloadProgress: 100,
        fileDownloadError: null,
        downloadedFilename: savedFile.filename,
        savedFilePath: savedFile.savedPath,
        savedDirectory: savedFile.savedDirectory,
        fileOpenLoading: false,
      );
      await _recordCompletedDownload(current, savedFile);
    } on ApiException catch (error) {
      _markFileDownloadFailed(cancelToken, error.message);
    } catch (_) {
      _markFileDownloadFailed(
        cancelToken,
        'Unable to save the downloaded file.',
      );
    } finally {
      if (identical(_fileDownloadCancelToken, cancelToken)) {
        _fileDownloadCancelToken = null;
      }
    }
  }

  Future<void> openDownloadedFile() async {
    final current = _successState;
    final filePath = current?.savedFilePath?.trim();
    if (current == null || current.fileOpenLoading) {
      return;
    }

    if (filePath == null || filePath.isEmpty) {
      _setFileDownloadError('Downloaded file path is missing.');
      return;
    }

    state = current.copyWith(
      fileOpenLoading: true,
      fileDownloadError: null,
    );

    try {
      await ref.read(mediaRepositoryProvider).openDownloadedFile(filePath);
      final latest = _successState;
      if (latest != null) {
        state = latest.copyWith(
          fileOpenLoading: false,
          fileDownloadError: null,
        );
      }
    } on ApiException catch (error) {
      final latest = _successState;
      if (latest != null) {
        state = latest.copyWith(
          fileOpenLoading: false,
          fileDownloadError: error.message,
        );
      }
    } catch (_) {
      final latest = _successState;
      if (latest != null) {
        state = latest.copyWith(
          fileOpenLoading: false,
          fileDownloadError: 'Unable to open the file.',
        );
      }
    }
  }

  void _listenToJob(String jobId) {
    _jobSubscription =
        ref.read(mediaRepositoryProvider).listenToJob(jobId).listen(
              _handleJobUpdate,
              onError: _handleJobStreamError,
              onDone: _handleJobStreamDone,
            );
  }

  void _handleJobUpdate(JobUpdate update) {
    final current = _successState;
    if (current == null ||
        current.currentJobId?.toLowerCase() != update.jobId.toLowerCase()) {
      return;
    }

    if (current.currentStatus == 'cancelled') {
      return;
    }

    if (_isTerminalStatus(current.currentStatus) &&
        !_isTerminalStatus(update.status)) {
      return;
    }

    state = current.copyWith(
      downloadError:
          update.isFailed ? update.error ?? 'Download failed.' : null,
      currentJobId: update.jobId,
      currentStatus: update.status,
      currentProgress: update.isCompleted ? 100 : update.progress,
      downloadUrl: update.downloadUrl,
    );

    if (update.isTerminal) {
      unawaited(_closeJobSubscription());
    }
  }

  void _handleJobStreamError(Object error) {
    final message = _progressErrorMessage(error);
    _markProgressConnectionLost(message);
    unawaited(_closeJobSubscription());
  }

  void _handleJobStreamDone() {
    final current = _successState;
    if (current == null ||
        current.currentJobId == null ||
        current.downloadError != null ||
        _isTerminalStatus(current.currentStatus) ||
        _isConnectionLostStatus(current.currentStatus)) {
      return;
    }

    _markProgressConnectionLost('Download progress connection closed.');
  }

  void _markProgressConnectionLost(String message) {
    final current = _successState;
    if (current == null || current.currentJobId == null) {
      return;
    }

    if (current.currentStatus == 'cancelled') {
      return;
    }

    state = current.copyWith(
      downloadError: message,
      currentStatus: 'connection_lost',
    );
  }

  void _handleFileDownloadProgress(
    CancelToken cancelToken,
    int received,
    int total,
  ) {
    if (!identical(_fileDownloadCancelToken, cancelToken) || total <= 0) {
      return;
    }

    final current = _successState;
    if (current == null || !current.fileDownloadLoading) {
      return;
    }

    final rawProgress = ((received / total) * 100).round();
    final progress = rawProgress < 0
        ? 0
        : rawProgress > 100
            ? 100
            : rawProgress;
    state = current.copyWith(fileDownloadProgress: progress);
  }

  void _markFileDownloadFailed(CancelToken cancelToken, String message) {
    if (!identical(_fileDownloadCancelToken, cancelToken)) {
      return;
    }

    final current = _successState;
    if (current == null) {
      return;
    }

    state = current.copyWith(
      fileDownloadLoading: false,
      fileDownloadError: message,
      fileOpenLoading: false,
    );
  }

  void _setFileDownloadError(String message) {
    final current = _successState;
    if (current != null) {
      state = current.copyWith(fileDownloadError: message);
    }
  }

  Future<void> _recordCompletedDownload(
    MediaSuccess download,
    CompletedFileDownload savedFile,
  ) async {
    final createdAt = DateTime.now();
    final title = download.metadata.title.trim();
    final thumbnailUrl = download.metadata.thumbnailUrl?.trim();
    final item = DownloadHistoryItem(
      id: '${createdAt.microsecondsSinceEpoch}-${savedFile.savedPath.hashCode}',
      title: title.isEmpty ? savedFile.filename : title,
      thumbnailUrl:
          thumbnailUrl == null || thumbnailUrl.isEmpty ? null : thumbnailUrl,
      mediaType: download.currentMediaType ?? MediaDownloadType.video,
      selectedQuality: _historyQuality(download),
      localFilePath: savedFile.savedPath,
      createdAt: createdAt,
      durationSeconds: download.metadata.durationSeconds,
    );

    try {
      await ref.read(downloadHistoryProvider.future);
      await ref
          .read(downloadHistoryProvider.notifier)
          .addCompletedDownload(item);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Unable to save download history: $error');
      }
    }
  }

  String? _historyQuality(MediaSuccess download) {
    if (download.currentMediaType == MediaDownloadType.audio) {
      return 'MP3';
    }

    return download.selectedVideoQuality?.label;
  }

  Future<void> _closeJobSubscription() async {
    final subscription = _jobSubscription;
    _jobSubscription = null;
    await subscription?.cancel();
  }

  void _cancelFileDownload() {
    _fileDownloadCancelToken?.cancel('File download cancelled.');
    _fileDownloadCancelToken = null;
  }

  MediaSuccess? get _successState {
    final current = state;
    return current is MediaSuccess ? current : null;
  }

  bool get _isWorkflowBusy {
    final current = state;
    if (current is! MediaSuccess) {
      return false;
    }

    return current.downloadLoading;
  }

  String _progressErrorMessage(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return 'Unable to receive download progress.';
  }

  String _suggestedFilename(MediaSuccess current) {
    final title = current.metadata.title.trim().isEmpty
        ? 'download'
        : current.metadata.title.trim();
    final extension = current.currentMediaType == MediaDownloadType.audio
        ? 'mp3'
        : current.selectedVideoQuality?.extension.trim();

    if (extension == null || extension.isEmpty) {
      return title;
    }

    final normalizedExtension =
        extension.startsWith('.') ? extension.substring(1) : extension;
    return '$title.$normalizedExtension';
  }

  bool _isActiveStatus(String? status) {
    final normalizedStatus = status?.toLowerCase();
    return normalizedStatus == 'pending' ||
        normalizedStatus == 'queued' ||
        normalizedStatus == 'processing' ||
        normalizedStatus == 'cancelling' ||
        normalizedStatus == 'connection_lost';
  }

  bool _isTerminalStatus(String? status) {
    final normalizedStatus = status?.toLowerCase();
    return normalizedStatus == 'completed' ||
        normalizedStatus == 'failed' ||
        normalizedStatus == 'cancelled';
  }


  bool _isConnectionLostStatus(String? status) {
    return status?.toLowerCase() == 'connection_lost';
  }

  String? _validateUrl(String value) {
    if (value.isEmpty) {
      return 'Enter a media URL.';
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid URL.';
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Enter an HTTP or HTTPS URL.';
    }

    return null;
  }


}
