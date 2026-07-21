// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MediaInfoResponseImpl _$$MediaInfoResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$MediaInfoResponseImpl(
      success: json['success'] as bool,
      message: json['message'] as String,
      data: json['data'] == null
          ? null
          : MediaMetadata.fromJson(json['data'] as Map<String, dynamic>),
      error: json['error'] == null
          ? null
          : ApiErrorPayload.fromJson(json['error'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$MediaInfoResponseImplToJson(
        _$MediaInfoResponseImpl instance) =>
    <String, dynamic>{
      'success': instance.success,
      'message': instance.message,
      'data': instance.data,
      'error': instance.error,
    };

_$ApiErrorPayloadImpl _$$ApiErrorPayloadImplFromJson(
        Map<String, dynamic> json) =>
    _$ApiErrorPayloadImpl(
      code: json['code'] as String,
      details: json['details'] as String,
    );

Map<String, dynamic> _$$ApiErrorPayloadImplToJson(
        _$ApiErrorPayloadImpl instance) =>
    <String, dynamic>{
      'code': instance.code,
      'details': instance.details,
    };

_$MediaMetadataImpl _$$MediaMetadataImplFromJson(Map<String, dynamic> json) =>
    _$MediaMetadataImpl(
      platform: json['platform'] as String,
      title: json['title'] as String,
      uploader: json['uploader'] as String?,
      uploaderUrl: json['uploader_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      webpageUrl: json['webpage_url'] as String,
      extractor: json['extractor'] as String,
      extractorKey: json['extractor_key'] as String,
      uploadDate: json['upload_date'] as String?,
      viewCount: (json['view_count'] as num?)?.toInt(),
      likeCount: (json['like_count'] as num?)?.toInt(),
      description: json['description'] as String?,
      videoQualities: (json['video_qualities'] as List<dynamic>?)
              ?.map((e) => VideoQuality.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <VideoQuality>[],
      audioOptions: (json['audio_options'] as List<dynamic>?)
              ?.map((e) => AudioOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <AudioOption>[],
    );

Map<String, dynamic> _$$MediaMetadataImplToJson(_$MediaMetadataImpl instance) =>
    <String, dynamic>{
      'platform': instance.platform,
      'title': instance.title,
      'uploader': instance.uploader,
      'uploader_url': instance.uploaderUrl,
      'thumbnail_url': instance.thumbnailUrl,
      'duration_seconds': instance.durationSeconds,
      'webpage_url': instance.webpageUrl,
      'extractor': instance.extractor,
      'extractor_key': instance.extractorKey,
      'upload_date': instance.uploadDate,
      'view_count': instance.viewCount,
      'like_count': instance.likeCount,
      'description': instance.description,
      'video_qualities': instance.videoQualities,
      'audio_options': instance.audioOptions,
    };

_$VideoQualityImpl _$$VideoQualityImplFromJson(Map<String, dynamic> json) =>
    _$VideoQualityImpl(
      label: json['label'] as String,
      height: (json['height'] as num).toInt(),
      extension: json['extension'] as String,
      estimatedFilesize: (json['estimated_filesize'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$VideoQualityImplToJson(_$VideoQualityImpl instance) =>
    <String, dynamic>{
      'label': instance.label,
      'height': instance.height,
      'extension': instance.extension,
      'estimated_filesize': instance.estimatedFilesize,
    };

_$AudioOptionImpl _$$AudioOptionImplFromJson(Map<String, dynamic> json) =>
    _$AudioOptionImpl(
      label: json['label'] as String,
      extension: json['extension'] as String,
    );

Map<String, dynamic> _$$AudioOptionImplToJson(_$AudioOptionImpl instance) =>
    <String, dynamic>{
      'label': instance.label,
      'extension': instance.extension,
    };
