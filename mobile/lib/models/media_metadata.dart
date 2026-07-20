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
    @Default(<MediaFormat>[]) List<MediaFormat> formats,
  }) = _MediaMetadata;

  factory MediaMetadata.fromJson(Map<String, dynamic> json) =>
      _$MediaMetadataFromJson(json);
}

@freezed
class MediaFormat with _$MediaFormat {
  const factory MediaFormat({
    @JsonKey(name: 'format_id') required String formatId,
    required String extension,
    String? resolution,
    int? fps,
    int? filesize,
    @JsonKey(name: 'video_codec') String? videoCodec,
    @JsonKey(name: 'audio_codec') String? audioCodec,
  }) = _MediaFormat;

  factory MediaFormat.fromJson(Map<String, dynamic> json) =>
      _$MediaFormatFromJson(json);
}
