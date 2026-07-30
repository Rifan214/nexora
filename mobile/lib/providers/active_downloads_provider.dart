import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/completed_file_download.dart';
import '../models/download_history_item.dart';
import '../models/job_update.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';
import '../models/tracked_download.dart';
import '../repositories/media_repository.dart';
import 'history_provider.dart';

final activeDownloadsProvider =
    NotifierProvider<ActiveDownloadsController, List<TrackedDownload>>(
  ActiveDownloadsController.new,
);

class ActiveDownloadsController extends Notifier<List<TrackedDownload>> {
  final _jobSubscriptions = <String, StreamSubscription<JobUpdate>>{};
  final _fileDownloadCancelTokens = <String, CancelToken>{};
  final _startedFileDownloads = <String>{};
  final _recordedHistoryJobs = <String>{};

  @override
  List<TrackedDownload> build() {
    ref.onDispose(() {
      for (final subscription in _jobSubscriptions.values) {
        unawaited(subscription.cancel());
      }
      _jobSubscriptions.clear();

      for (final cancelToken in _fileDownloadCancelTokens.values) {
        cancelToken.cancel('File download cancelled.');
      }
      _fileDownloadCancelTokens.clear();
    });

    return const <TrackedDownload>[];
  }

  void trackDownload({
    required String jobId,
    required MediaMetadata metadata,
    required MediaDownloadType mediaType,
    VideoQuality? selectedVideoQuality,
  }) {
    final normalizedJobId = jobId.trim();
    if (normalizedJobId.isEmpty || _find(normalizedJobId) != null) {
      return;
    }

    state = [
      ...state,
      TrackedDownload(
        jobId: normalizedJobId,
        metadata: metadata,
        mediaType: mediaType,
        selectedVideoQuality: selectedVideoQuality,
        status: 'pending',
        progress: 0,
      ),
    ];
    _listenToJob(normalizedJobId);
  }

  Future<void> cancelDownload(String jobId) async {
    final download = _find(jobId);
    if (download == null ||
        download.fileDownloadLoading ||
        download.fileOpenLoading ||
        download.status == 'cancelling' ||
        !_isCancellable(download.status)) {
      return;
    }

    _replace(download.copyWith(status: 'cancelling', error: null));

    try {
      final update = await ref
          .read(mediaRepositoryProvider)
          .cancelDownloadJob(download.jobId);
      _handleJobUpdate(update);
    } on ApiException catch (error) {
      final latest = _find(download.jobId);
      if (latest != null && !_isTerminal(latest.status)) {
        _replace(
          latest.copyWith(status: download.status, error: error.message),
        );
      }
    } catch (_) {
      final latest = _find(download.jobId);
      if (latest != null && !_isTerminal(latest.status)) {
        _replace(
          latest.copyWith(
            status: download.status,
            error: 'Unable to cancel the download.',
          ),
        );
      }
    }
  }

  Future<String?> openDownloadedFile(String jobId) async {
    final download = _find(jobId);
    final filePath = download?.savedFilePath?.trim();
    if (download == null ||
        filePath == null ||
        filePath.isEmpty) {
      return 'File Missing';
    }

    try {
      if (!await ref.read(mediaRepositoryProvider).downloadedFileExists(filePath)) {
        return 'File Missing';
      }
      await ref.read(mediaRepositoryProvider).openDownloadedFile(filePath);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Unable to open the file.';
    }
  }

  Future<String?> retryFailedDownload(String jobId) async {
    final failedDownload = _find(jobId);
    if (failedDownload == null ||
        failedDownload.isRetrying ||
        !_isRetryable(failedDownload)) {
      return 'This download can no longer be retried.';
    }

    final mediaUrl = failedDownload.metadata.webpageUrl.trim();
    if (!_isValidMediaUrl(mediaUrl) ||
        (failedDownload.mediaType == MediaDownloadType.video &&
            failedDownload.selectedVideoQuality == null)) {
      return 'This download can no longer be retried.';
    }

    _replace(failedDownload.copyWith(isRetrying: true));

    try {
      final job = await ref.read(mediaRepositoryProvider).createDownloadJob(
            mediaUrl: mediaUrl,
            mediaType: failedDownload.mediaType,
            videoQuality: failedDownload.selectedVideoQuality,
          );

      state = [
        for (final download in state)
          if (download.jobId.toLowerCase() != failedDownload.jobId.toLowerCase())
            download,
        TrackedDownload(
          jobId: job.jobId,
          metadata: failedDownload.metadata,
          mediaType: failedDownload.mediaType,
          selectedVideoQuality: failedDownload.selectedVideoQuality,
          status: 'pending',
          progress: 0,
        ),
      ];
      _listenToJob(job.jobId);
      return null;
    } on ApiException catch (error) {
      _restoreFailedDownload(failedDownload.jobId);
      final message = error.message.trim();
      return message.isEmpty ? 'Unable to retry the download.' : message;
    } catch (_) {
      _restoreFailedDownload(failedDownload.jobId);
      return 'Unable to retry the download.';
    }
  }

  void clearCompletedDownloads() {
    state = state.where((download) {
      return !(download.status == 'completed' &&
          download.savedFilePath?.trim().isNotEmpty == true &&
          download.fileDownloadError?.trim().isNotEmpty != true);
    }).toList();
  }

  void clearFailedDownloads() {
    state = state.where((download) {
      return !(download.status == 'failed' ||
          download.status == 'connection_lost' ||
          download.fileDownloadError?.trim().isNotEmpty == true);
    }).toList();
  }

  void _listenToJob(String jobId) {
    _jobSubscriptions[jobId] = ref
        .read(mediaRepositoryProvider)
        .listenToJob(jobId)
        .listen(
          _handleJobUpdate,
          onError: (Object error, StackTrace _) {
            _markProgressConnectionLost(jobId, error);
          },
          onDone: () {
            final download = _find(jobId);
            if (download == null ||
                _isTerminal(download.status) ||
                download.error?.trim().isNotEmpty == true) {
              return;
            }
            _markProgressConnectionLost(
              jobId,
              const ApiException('Download progress connection closed.'),
            );
          },
        );
  }

  void _handleJobUpdate(JobUpdate update) {
    final download = _find(update.jobId);
    if (download == null) {
      return;
    }

    if (download.isFinalized || _isTerminal(download.status)) {
      return;
    }

    _replace(
      download.copyWith(
        status: update.status,
        progress: update.isCompleted ? 100 : update.progress,
        downloadUrl: update.downloadUrl,
        error: update.isFailed ? update.error ?? 'Download failed.' : null,
      ),
    );

    if (update.isCompleted) {
      unawaited(_downloadCompletedFile(update.jobId));
    }
    if (update.isTerminal) {
      unawaited(_closeJobSubscription(update.jobId));
    }
  }

  Future<void> _downloadCompletedFile(String jobId) async {
    final download = _find(jobId);
    final downloadUrl = download?.downloadUrl?.trim();
    if (download == null ||
        download.status != 'completed' ||
        download.fileDownloadLoading ||
        download.savedFilePath?.trim().isNotEmpty == true ||
        downloadUrl == null ||
        downloadUrl.isEmpty ||
        !_startedFileDownloads.add(jobId)) {
      return;
    }

    final cancelToken = CancelToken();
    _fileDownloadCancelTokens[jobId] = cancelToken;
    _replace(
      download.copyWith(
        fileDownloadLoading: true,
        fileDownloadProgress: 0,
        fileDownloadError: null,
        downloadedFilename: null,
        savedFilePath: null,
        savedDirectory: null,
        fileOpenLoading: false,
      ),
    );

    try {
      final savedFile = await ref.read(mediaRepositoryProvider).downloadCompletedFile(
            downloadUrl: downloadUrl,
            suggestedFilename: _suggestedFilename(download),
            mediaType: download.mediaType,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              _handleFileDownloadProgress(jobId, cancelToken, received, total);
            },
          );
      if (!identical(_fileDownloadCancelTokens[jobId], cancelToken)) {
        return;
      }

      final latest = _find(jobId);
      if (latest == null) {
        return;
      }

      _replace(
        latest.copyWith(
          fileDownloadLoading: false,
          fileDownloadProgress: 100,
          fileDownloadError: null,
          downloadedFilename: savedFile.filename,
          savedFilePath: savedFile.savedPath,
          savedDirectory: savedFile.savedDirectory,
          fileOpenLoading: false,
        ),
      );
      await _recordCompletedDownload(download, savedFile);
    } on ApiException catch (error) {
      _markFileDownloadFailed(jobId, cancelToken, error.message);
    } catch (_) {
      _markFileDownloadFailed(
        jobId,
        cancelToken,
        'Unable to save the downloaded file.',
      );
    } finally {
      if (identical(_fileDownloadCancelTokens[jobId], cancelToken)) {
        _fileDownloadCancelTokens.remove(jobId);
      }
    }
  }

  void _handleFileDownloadProgress(
    String jobId,
    CancelToken cancelToken,
    int received,
    int total,
  ) {
    if (!identical(_fileDownloadCancelTokens[jobId], cancelToken) || total <= 0) {
      return;
    }

    final download = _find(jobId);
    if (download == null || !download.fileDownloadLoading) {
      return;
    }

    final rawProgress = ((received / total) * 100).round();
    final progress = rawProgress < 0
        ? 0
        : rawProgress > 100
            ? 100
            : rawProgress;
    _replace(download.copyWith(fileDownloadProgress: progress));
  }

  void _markFileDownloadFailed(
    String jobId,
    CancelToken cancelToken,
    String message,
  ) {
    if (!identical(_fileDownloadCancelTokens[jobId], cancelToken)) {
      return;
    }

    final download = _find(jobId);
    if (download != null && !download.isFinalized) {
      _replace(
        download.copyWith(
          fileDownloadLoading: false,
          fileDownloadError: message,
          fileOpenLoading: false,
        ),
      );
    }
  }

  void _markProgressConnectionLost(String jobId, Object error) {
    final download = _find(jobId);
    if (download == null ||
        download.isFinalized ||
        _isTerminal(download.status)) {
      return;
    }

    final message = error is ApiException
        ? error.message
        : 'Unable to receive download progress.';
    _replace(download.copyWith(status: 'connection_lost', error: message));
    unawaited(_closeJobSubscription(jobId));
  }

  Future<void> _recordCompletedDownload(
    TrackedDownload download,
    CompletedFileDownload savedFile,
  ) async {
    if (!_recordedHistoryJobs.add(download.jobId)) {
      return;
    }

    final createdAt = DateTime.now();
    final title = download.metadata.title.trim();
    final thumbnailUrl = download.metadata.thumbnailUrl?.trim();
    final item = DownloadHistoryItem(
      id: '${createdAt.microsecondsSinceEpoch}-${savedFile.savedPath.hashCode}',
      title: title.isEmpty ? savedFile.filename : title,
      thumbnailUrl:
          thumbnailUrl == null || thumbnailUrl.isEmpty ? null : thumbnailUrl,
      mediaType: download.mediaType,
      selectedQuality: _historyQuality(download),
      localFilePath: savedFile.savedPath,
      createdAt: createdAt,
      durationSeconds: download.metadata.durationSeconds,
    );

    try {
      await ref.read(downloadHistoryProvider.future);
      await ref.read(downloadHistoryProvider.notifier).addCompletedDownload(item);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Unable to save download history: $error');
      }
    }
  }

  String? _historyQuality(TrackedDownload download) {
    if (download.mediaType == MediaDownloadType.audio) {
      return 'MP3';
    }
    return download.selectedVideoQuality?.label;
  }

  String _suggestedFilename(TrackedDownload download) {
    final title = download.metadata.title.trim().isEmpty
        ? 'download'
        : download.metadata.title.trim();
    final extension = download.mediaType == MediaDownloadType.audio
        ? 'mp3'
        : download.selectedVideoQuality?.extension.trim();
    if (extension == null || extension.isEmpty) {
      return title;
    }
    return '$title.${extension.startsWith('.') ? extension.substring(1) : extension}';
  }

  Future<void> _closeJobSubscription(String jobId) async {
    final subscription = _jobSubscriptions.remove(jobId);
    await subscription?.cancel();
  }

  TrackedDownload? _find(String jobId) {
    final normalizedJobId = jobId.trim().toLowerCase();
    for (final download in state) {
      if (download.jobId.toLowerCase() == normalizedJobId) {
        return download;
      }
    }
    return null;
  }

  void _replace(TrackedDownload replacement) {
    state = [
      for (final download in state)
        if (download.jobId.toLowerCase() == replacement.jobId.toLowerCase())
          replacement
        else
          download,
    ];
  }

  void _restoreFailedDownload(String jobId) {
    final latest = _find(jobId);
    if (latest != null) {
      _replace(latest.copyWith(isRetrying: false));
    }
  }

  bool _isRetryable(TrackedDownload download) {
    return download.status == 'failed' ||
        download.status == 'connection_lost' ||
        download.fileDownloadError?.trim().isNotEmpty == true;
  }

  bool _isValidMediaUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  bool _isCancellable(String status) {
    return status == 'pending' || status == 'queued' || status == 'processing';
  }

  bool _isTerminal(String status) {
    return status == 'completed' || status == 'failed' || status == 'cancelled';
  }
}
