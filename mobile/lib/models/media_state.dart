import 'package:freezed_annotation/freezed_annotation.dart';

import 'media_download_type.dart';
import 'media_metadata.dart';

part 'media_state.freezed.dart';

@freezed
class MediaState with _$MediaState {
  const factory MediaState.idle() = MediaIdle;

  const factory MediaState.loading() = MediaLoading;

  const factory MediaState.success({
    required MediaMetadata metadata,
    VideoQuality? selectedVideoQuality,
    MediaDownloadType? currentMediaType,
    @Default(false) bool downloadLoading,
    @Default(false) bool downloadSuccess,
    String? downloadError,
    String? currentJobId,
    String? currentStatus,
    @Default(0) int currentProgress,
    String? downloadUrl,
    @Default(false) bool fileDownloadLoading,
    @Default(0) int fileDownloadProgress,
    String? fileDownloadError,
    String? downloadedFilename,
    String? savedFilePath,
    String? savedDirectory,
    @Default(false) bool fileOpenLoading,
  }) = MediaSuccess;

  const factory MediaState.error(String message) = MediaError;
}
