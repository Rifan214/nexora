import 'media_metadata.dart';

class PlaylistInfoResponse {
  const PlaylistInfoResponse({
    required this.success,
    required this.message,
    this.data,
    this.error,
  });

  final bool success;
  final String message;
  final PlaylistMetadata? data;
  final ApiErrorPayload? error;

  factory PlaylistInfoResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final rawError = json['error'];
    return PlaylistInfoResponse(
      success: json['success'] == true,
      message: json['message'] as String? ?? 'Invalid response from server.',
      data: rawData is Map
          ? PlaylistMetadata.fromJson(Map<String, dynamic>.from(rawData))
          : null,
      error: rawError is Map
          ? ApiErrorPayload.fromJson(Map<String, dynamic>.from(rawError))
          : null,
    );
  }
}

class PlaylistMetadata {
  const PlaylistMetadata({
    required this.title,
    required this.totalCount,
    required this.items,
  });

  final String title;
  final int totalCount;
  final List<PlaylistItem> items;

  factory PlaylistMetadata.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return PlaylistMetadata(
      title: json['title'] as String? ?? 'Untitled playlist',
      totalCount: json['total_count'] as int? ?? 0,
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => PlaylistItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

class PlaylistItem {
  const PlaylistItem({
    required this.title,
    required this.webpageUrl,
    this.thumbnailUrl,
    this.durationSeconds,
  });

  final String title;
  final String webpageUrl;
  final String? thumbnailUrl;
  final int? durationSeconds;

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      title: json['title'] as String? ?? 'Untitled media',
      webpageUrl: json['webpage_url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      durationSeconds: json['duration_seconds'] as int?,
    );
  }
}
