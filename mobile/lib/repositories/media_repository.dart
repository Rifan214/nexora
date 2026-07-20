import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/api_paths.dart';
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
}
