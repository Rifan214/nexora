import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/job_update.dart';
import '../models/media_metadata.dart';
import '../models/media_state.dart';
import '../repositories/media_repository.dart';

final mediaProvider = NotifierProvider<MediaController, MediaState>(
  MediaController.new,
);

class MediaController extends Notifier<MediaState> {
  StreamSubscription<JobUpdate>? _jobSubscription;
  CancelToken? _fileDownloadCancelToken;

  @override
  MediaState build() {
    ref.onDispose(() {
      unawaited(_jobSubscription?.cancel());
      _jobSubscription = null;
      _fileDownloadCancelToken?.cancel('File download cancelled.');
      _fileDownloadCancelToken = null;
    });

    return const MediaState.idle();
  }

  Future<void> getMediaInfo(String url) async {
    await _closeJobSubscription();
    _cancelFileDownload();

    final trimmedUrl = url.trim();
    final validationMessage = _validateUrl(trimmedUrl);
    if (validationMessage != null) {
      state = MediaState.error(validationMessage);
      return;
    }

    state = const MediaState.loading();

    try {
      final metadata =
          await ref.read(mediaRepositoryProvider).getMediaInfo(trimmedUrl);
      state = MediaState.success(metadata: metadata);
    } on ApiException catch (error) {
      state = MediaState.error(error.message);
    } catch (_) {
      state = const MediaState.error('Unable to retrieve media metadata.');
    }
  }

  void selectFormat(MediaFormat format) {
    unawaited(_closeJobSubscription());
    _cancelFileDownload();

    final current = _successState;
    if (current == null) {
      return;
    }

    state = MediaState.success(
      metadata: current.metadata,
      selectedFormat: format,
    );
  }

  Future<void> createDownloadJob() async {
    _cancelFileDownload();

    final current = _successState;
    if (current == null ||
        current.downloadLoading ||
        _isActiveStatus(current.currentStatus)) {
      return;
    }

    final selectedFormat = current.selectedFormat;
    if (selectedFormat == null) {
      state = current.copyWith(
        downloadError: 'Select a format before downloading.',
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
      fileDownloadLoading: false,
      fileDownloadProgress: 0,
      fileDownloadError: null,
      downloadedFilename: null,
      savedFilePath: null,
      savedDirectory: null,
    );

    try {
      final job = await ref.read(mediaRepositoryProvider).createDownloadJob(
            mediaUrl: current.metadata.webpageUrl,
            format: selectedFormat,
          );
      final latest = _successState;
      if (latest == null) {
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
      _listenToJob(job.jobId);
    } on ApiException catch (error) {
      final latest = _successState;
      if (latest == null) {
        return;
      }

      state = latest.copyWith(
        downloadLoading: false,
        downloadError: error.message,
      );
    } catch (_) {
      final latest = _successState;
      if (latest == null) {
        return;
      }

      state = latest.copyWith(
        downloadLoading: false,
        downloadError: 'Unable to create download job.',
      );
    }
  }

  Future<void> downloadCompletedFile() async {
    final current = _successState;
    if (current == null || current.fileDownloadLoading) {
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
    );

    try {
      final savedFile = await ref.read(mediaRepositoryProvider).downloadCompletedFile(
            downloadUrl: downloadUrl,
            suggestedFilename: _suggestedFilename(current),
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
      );
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
    if (current == null || filePath == null || filePath.isEmpty) {
      _setFileDownloadError('Downloaded file path is missing.');
      return;
    }

    try {
      await ref.read(mediaRepositoryProvider).openDownloadedFile(filePath);
      final latest = _successState;
      if (latest != null) {
        state = latest.copyWith(fileDownloadError: null);
      }
    } on ApiException catch (error) {
      final latest = _successState;
      if (latest != null) {
        state = latest.copyWith(fileDownloadError: error.message);
      }
    } catch (_) {
      final latest = _successState;
      if (latest != null) {
        state = latest.copyWith(fileDownloadError: 'Unable to open the file.');
      }
    }
  }

  void _listenToJob(String jobId) {
    _jobSubscription = ref.read(mediaRepositoryProvider).listenToJob(jobId).listen(
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

    state = current.copyWith(
      downloadError: update.isFailed ? update.error ?? 'Download failed.' : null,
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
    );
  }

  void _setFileDownloadError(String message) {
    final current = _successState;
    if (current != null) {
      state = current.copyWith(fileDownloadError: message);
    }
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

  String _progressErrorMessage(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    final message = error.toString().trim();
    if (message.isNotEmpty) {
      return message;
    }

    return 'Unable to receive download progress.';
  }

  String _suggestedFilename(MediaSuccess current) {
    final title = current.metadata.title.trim().isEmpty
        ? 'download'
        : current.metadata.title.trim();
    final extension = current.selectedFormat?.extension.trim();

    if (extension == null || extension.isEmpty) {
      return title;
    }

    final normalizedExtension =
        extension.startsWith('.') ? extension.substring(1) : extension;
    return '$title.$normalizedExtension';
  }

  bool _isActiveStatus(String? status) {
    final normalizedStatus = status?.toLowerCase();
    return normalizedStatus == 'pending' || normalizedStatus == 'processing';
  }

  bool _isTerminalStatus(String? status) {
    final normalizedStatus = status?.toLowerCase();
    return normalizedStatus == 'completed' || normalizedStatus == 'failed';
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
