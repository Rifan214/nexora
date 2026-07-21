import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/api_paths.dart';
import '../models/completed_file_download.dart';
import '../models/download_job.dart';
import '../models/job_update.dart';
import '../models/media_metadata.dart';
import '../services/api_service.dart';
import '../services/device_file_service.dart';
import '../services/web_socket_service.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(
    ref.watch(apiServiceProvider),
    ref.watch(webSocketServiceProvider),
    ref.watch(deviceFileServiceProvider),
  );
});

class MediaRepository {
  const MediaRepository(
    this._apiService,
    this._webSocketService,
    this._deviceFileService,
  );

  final ApiService _apiService;
  final WebSocketService _webSocketService;
  final DeviceFileService _deviceFileService;

  Future<MediaMetadata> getMediaInfo(String url) async {
    final response = await _apiService.postJson(
      ApiPaths.mediaInfo,
      data: {'url': url.trim()},
    );
    final mediaResponse = MediaInfoResponse.fromJson(response);

    if (!mediaResponse.success) {
      throw ApiException(
        mediaResponse.error?.details.isNotEmpty == true
            ? mediaResponse.error!.details
            : mediaResponse.message,
      );
    }

    final metadata = mediaResponse.data;
    if (metadata == null) {
      throw const ApiException('Invalid response from server.');
    }

    return metadata;
  }

  Future<DownloadJobData> createDownloadJob({
    required String mediaUrl,
    required MediaFormat format,
  }) async {
    final request = DownloadJobRequest(
      url: mediaUrl.trim(),
      formatId: format.formatId,
      type: _downloadTypeFor(format),
    );
    final response = await _apiService.postJson(
      ApiPaths.mediaDownload,
      data: request.toJson(),
    );
    final downloadResponse = DownloadJobResponse.fromJson(response);

    if (!downloadResponse.success) {
      throw ApiException(
        downloadResponse.error?.details.isNotEmpty == true
            ? downloadResponse.error!.details
            : downloadResponse.message,
      );
    }

    final job = downloadResponse.data;
    if (job == null) {
      throw const ApiException('Invalid response from server.');
    }

    return job;
  }

  Stream<JobUpdate> listenToJob(String jobId) {
    final trimmedJobId = jobId.trim();
    if (trimmedJobId.isEmpty) {
      return Stream<JobUpdate>.error(const ApiException('Invalid job id.'));
    }

    return _webSocketService
        .connectJson(ApiPaths.jobWebSocket(trimmedJobId))
        .map(JobUpdate.fromJson);
  }

  Future<CompletedFileDownload> downloadCompletedFile({
    required String downloadUrl,
    required String suggestedFilename,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final trimmedDownloadUrl = downloadUrl.trim();
    if (trimmedDownloadUrl.isEmpty) {
      throw const ApiException('Download URL is missing.');
    }

    final downloadDirectory = await _prepareDownloadDirectory();
    final fallbackFilename = _deviceFileService.sanitizeFilename(
      suggestedFilename,
    );
    String? savedPath;
    String? resolvedFilename;

    try {
      await _apiService.downloadFile(
        trimmedDownloadUrl,
        savePath: (Headers headers) {
          resolvedFilename = _deviceFileService.filenameFromContentDisposition(
                headers.value('content-disposition'),
              ) ??
              fallbackFilename;
          savedPath = _deviceFileService.uniqueFilePath(
            directory: downloadDirectory,
            filename: resolvedFilename!,
          );
          return savedPath!;
        },
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
      );
    } on ApiException {
      rethrow;
    } on FileSystemException {
      throw const ApiException('Unable to write the downloaded file.');
    } catch (_) {
      throw const ApiException('Unable to save the downloaded file.');
    }

    final finalSavedPath = savedPath;
    if (finalSavedPath == null || finalSavedPath.isEmpty) {
      throw const ApiException('Unable to save the downloaded file.');
    }

    return CompletedFileDownload(
      filename:
          resolvedFilename ?? _deviceFileService.filenameFromPath(finalSavedPath),
      savedPath: finalSavedPath,
      savedDirectory: downloadDirectory.path,
    );
  }

  Future<void> openDownloadedFile(String filePath) {
    final trimmedPath = filePath.trim();
    if (trimmedPath.isEmpty) {
      throw const ApiException('Downloaded file path is missing.');
    }

    return _deviceFileService.openFile(trimmedPath);
  }

  String _downloadTypeFor(MediaFormat format) {
    final videoCodec = format.videoCodec?.trim().toLowerCase();
    final audioCodec = format.audioCodec?.trim().toLowerCase();
    final hasVideo =
        videoCodec != null && videoCodec.isNotEmpty && videoCodec != 'none';
    final hasAudio =
        audioCodec != null && audioCodec.isNotEmpty && audioCodec != 'none';

    if (!hasVideo && hasAudio) {
      return 'audio';
    }

    return 'video';
  }

  Future<Directory> _prepareDownloadDirectory() async {
    try {
      return await _deviceFileService.prepareDownloadDirectory();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Unable to prepare the download location.');
    }
  }
}
