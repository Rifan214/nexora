import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/api_paths.dart';
import '../models/download_job.dart';
import '../models/media_metadata.dart';
import '../services/api_service.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref.watch(apiServiceProvider));
});

class MediaRepository {
  const MediaRepository(this._apiService);

  final ApiService _apiService;

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
}
