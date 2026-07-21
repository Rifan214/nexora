// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_job.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DownloadJobRequestImpl _$$DownloadJobRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$DownloadJobRequestImpl(
      url: json['url'] as String,
      mediaType: json['media_type'] as String,
      qualityHeight: (json['quality_height'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$DownloadJobRequestImplToJson(
        _$DownloadJobRequestImpl instance) =>
    <String, dynamic>{
      'url': instance.url,
      'media_type': instance.mediaType,
      if (instance.qualityHeight case final value?) 'quality_height': value,
    };

_$DownloadJobResponseImpl _$$DownloadJobResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$DownloadJobResponseImpl(
      success: json['success'] as bool,
      message: json['message'] as String,
      data: json['data'] == null
          ? null
          : DownloadJobData.fromJson(json['data'] as Map<String, dynamic>),
      error: json['error'] == null
          ? null
          : ApiErrorPayload.fromJson(json['error'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$DownloadJobResponseImplToJson(
        _$DownloadJobResponseImpl instance) =>
    <String, dynamic>{
      'success': instance.success,
      'message': instance.message,
      'data': instance.data,
      'error': instance.error,
    };

_$DownloadJobDataImpl _$$DownloadJobDataImplFromJson(
        Map<String, dynamic> json) =>
    _$DownloadJobDataImpl(
      jobId: json['job_id'] as String,
    );

Map<String, dynamic> _$$DownloadJobDataImplToJson(
        _$DownloadJobDataImpl instance) =>
    <String, dynamic>{
      'job_id': instance.jobId,
    };
