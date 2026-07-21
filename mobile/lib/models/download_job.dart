import 'package:freezed_annotation/freezed_annotation.dart';

import 'media_metadata.dart';

part 'download_job.freezed.dart';
part 'download_job.g.dart';

@freezed
class DownloadJobRequest with _$DownloadJobRequest {
  const factory DownloadJobRequest({
    required String url,
    @JsonKey(name: 'media_type') required String mediaType,
    @JsonKey(name: 'quality_height', includeIfNull: false) int? qualityHeight,
  }) = _DownloadJobRequest;

  factory DownloadJobRequest.fromJson(Map<String, dynamic> json) =>
      _$DownloadJobRequestFromJson(json);
}

@freezed
class DownloadJobResponse with _$DownloadJobResponse {
  const factory DownloadJobResponse({
    required bool success,
    required String message,
    DownloadJobData? data,
    ApiErrorPayload? error,
  }) = _DownloadJobResponse;

  factory DownloadJobResponse.fromJson(Map<String, dynamic> json) =>
      _$DownloadJobResponseFromJson(json);
}

@freezed
class DownloadJobData with _$DownloadJobData {
  const factory DownloadJobData({
    @JsonKey(name: 'job_id') required String jobId,
  }) = _DownloadJobData;

  factory DownloadJobData.fromJson(Map<String, dynamic> json) =>
      _$DownloadJobDataFromJson(json);
}
