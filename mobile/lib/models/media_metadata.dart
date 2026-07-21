import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_metadata.freezed.dart';
part 'media_metadata.g.dart';

@freezed
class MediaInfoResponse with _$MediaInfoResponse {
  const factory MediaInfoResponse({
    required bool success,
    required String message,
    MediaMetadata? data,
    ApiErrorPayload? error,
  }) = _MediaInfoResponse;

  factory MediaInfoResponse.fromJson(Map<String, dynamic> json) =>
      _$MediaInfoResponseFromJson(json);
}

@freezed
class ApiErrorPayload with _$ApiErrorPayload {
  const factory ApiErrorPayload({
    required String code,
    required String details,
  }) = _ApiErrorPayload;

  factory ApiErrorPayload.fromJson(Map<String, dynamic> json) =>
      _$ApiErrorPayloadFromJson(json);
}

@freezed
class MediaMetadata with _$MediaMetadata {
  const factory MediaMetadata({
    required String platform,
    required String title,
    String? uploader,
    @JsonKey(name: 'uploader_url') String? uploaderUrl,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    @JsonKey(name: 'duration_seconds') int? durationSeconds,
    @JsonKey(name: 'webpage_url') required String webpageUrl,
    required String extractor,
    @JsonKey(name: 'extractor_key') required String extractorKey,
    @JsonKey(name: 'upload_date') String? uploadDate,
    @JsonKey(name: 'view_count') int? viewCount,
    @JsonKey(name: 'like_count') int? likeCount,
    String? description,
    @JsonKey(name: 'video_qualities')
    @Default(<VideoQuality>[]) List<VideoQuality> videoQualities,
    @JsonKey(name: 'audio_options')
    @Default(<AudioOption>[]) List<AudioOption> audioOptions,
  }) = _MediaMetadata;

  factory MediaMetadata.fromJson(Map<String, dynamic> json) =>
      _$MediaMetadataFromJson(json);
}

@freezed
class VideoQuality with _$VideoQuality {
  const factory VideoQuality({
    required String label,
    required int height,
    required String extension,
    @JsonKey(name: 'estimated_filesize') int? estimatedFilesize,
  }) = _VideoQuality;

  factory VideoQuality.fromJson(Map<String, dynamic> json) =>
      _$VideoQualityFromJson(json);
}

@freezed
class AudioOption with _$AudioOption {
  const factory AudioOption({
    required String label,
    required String extension,
  }) = _AudioOption;

  factory AudioOption.fromJson(Map<String, dynamic> json) =>
      _$AudioOptionFromJson(json);
}
