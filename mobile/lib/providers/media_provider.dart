import 'dart:async';

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

  @override
  MediaState build() {
    ref.onDispose(() {
      unawaited(_jobSubscription?.cancel());
      _jobSubscription = null;
    });

    return const MediaState.idle();
  }

  Future<void> getMediaInfo(String url) async {
    await _closeJobSubscription();

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

    state.maybeWhen(
      success: (
        metadata,
        _,
        __,
        ___,
        ____,
        _____,
        ______,
        _______,
        ________,
      ) {
        state = MediaState.success(
          metadata: metadata,
          selectedFormat: format,
        );
      },
      orElse: () {},
    );
  }

  Future<void> createDownloadJob() async {
    MediaMetadata? currentMetadata;
    MediaFormat? currentFormat;
    String? currentStatus;
    var isDownloadLoading = false;

    state.maybeWhen(
      success: (
        metadata,
        selectedFormat,
        downloadLoading,
        _,
        __,
        ___,
        status,
        ____,
        _____,
      ) {
        currentMetadata = metadata;
        currentFormat = selectedFormat;
        currentStatus = status;
        isDownloadLoading = downloadLoading;
      },
      orElse: () {},
    );

    final metadata = currentMetadata;
    if (metadata == null ||
        isDownloadLoading ||
        _isActiveStatus(currentStatus)) {
      return;
    }

    final selectedFormat = currentFormat;
    if (selectedFormat == null) {
      state = MediaState.success(
        metadata: metadata,
        downloadError: 'Select a format before downloading.',
      );
      return;
    }

    final validationMessage = _validateUrl(metadata.webpageUrl);
    if (validationMessage != null) {
      state = MediaState.success(
        metadata: metadata,
        selectedFormat: selectedFormat,
        downloadError: validationMessage,
      );
      return;
    }

    await _closeJobSubscription();

    state = MediaState.success(
      metadata: metadata,
      selectedFormat: selectedFormat,
      downloadLoading: true,
    );

    try {
      final job = await ref.read(mediaRepositoryProvider).createDownloadJob(
            mediaUrl: metadata.webpageUrl,
            format: selectedFormat,
          );
      state = MediaState.success(
        metadata: metadata,
        selectedFormat: selectedFormat,
        downloadSuccess: true,
        currentJobId: job.jobId,
        currentStatus: 'pending',
        currentProgress: 0,
      );
      _listenToJob(job.jobId);
    } on ApiException catch (error) {
      state = MediaState.success(
        metadata: metadata,
        selectedFormat: selectedFormat,
        downloadError: error.message,
      );
    } catch (_) {
      state = MediaState.success(
        metadata: metadata,
        selectedFormat: selectedFormat,
        downloadError: 'Unable to create download job.',
      );
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
    var shouldCloseConnection = false;

    state.maybeWhen(
      success: (
        metadata,
        selectedFormat,
        _,
        downloadSuccess,
        __,
        currentJobId,
        ___,
        ____,
        _____,
      ) {
        if (currentJobId?.toLowerCase() != update.jobId.toLowerCase()) {
          return;
        }

        shouldCloseConnection = update.isTerminal;
        state = MediaState.success(
          metadata: metadata,
          selectedFormat: selectedFormat,
          downloadSuccess: downloadSuccess,
          downloadError: update.isFailed
              ? update.error ?? 'Download failed.'
              : null,
          currentJobId: update.jobId,
          currentStatus: update.status,
          currentProgress: update.isCompleted ? 100 : update.progress,
          downloadUrl: update.downloadUrl,
        );
      },
      orElse: () {},
    );

    if (shouldCloseConnection) {
      unawaited(_closeJobSubscription());
    }
  }

  void _handleJobStreamError(Object error) {
    final message = _progressErrorMessage(error);
    _markProgressConnectionLost(message);
    unawaited(_closeJobSubscription());
  }

  void _handleJobStreamDone() {
    var shouldMarkConnectionLost = false;

    state.maybeWhen(
      success: (
        _,
        __,
        ___,
        ____,
        downloadError,
        currentJobId,
        currentStatus,
        ______,
        _______,
      ) {
        shouldMarkConnectionLost = currentJobId != null &&
            downloadError == null &&
            !_isTerminalStatus(currentStatus) &&
            !_isConnectionLostStatus(currentStatus);
      },
      orElse: () {},
    );

    if (shouldMarkConnectionLost) {
      _markProgressConnectionLost('Download progress connection closed.');
    }
  }

  void _markProgressConnectionLost(String message) {
    state.maybeWhen(
      success: (
        metadata,
        selectedFormat,
        _,
        downloadSuccess,
        __,
        currentJobId,
        ___,
        currentProgress,
        downloadUrl,
      ) {
        if (currentJobId == null) {
          return;
        }

        state = MediaState.success(
          metadata: metadata,
          selectedFormat: selectedFormat,
          downloadSuccess: downloadSuccess,
          downloadError: message,
          currentJobId: currentJobId,
          currentStatus: 'connection_lost',
          currentProgress: currentProgress,
          downloadUrl: downloadUrl,
        );
      },
      orElse: () {},
    );
  }

  Future<void> _closeJobSubscription() async {
    final subscription = _jobSubscription;
    _jobSubscription = null;
    await subscription?.cancel();
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
