import 'media_download_type.dart';
import 'media_metadata.dart';

class TrackedDownload {
  const TrackedDownload({
    required this.jobId,
    required this.metadata,
    required this.mediaType,
    required this.status,
    required this.progress,
    this.selectedVideoQuality,
    this.downloadUrl,
    this.error,
    this.fileDownloadLoading = false,
    this.fileDownloadProgress = 0,
    this.fileDownloadError,
    this.downloadedFilename,
    this.savedFilePath,
    this.savedDirectory,
    this.fileOpenLoading = false,
    this.isRetrying = false,
  });

  static const _unset = Object();

  final String jobId;
  final MediaMetadata metadata;
  final MediaDownloadType mediaType;
  final VideoQuality? selectedVideoQuality;
  final String status;
  final int progress;
  final String? downloadUrl;
  final String? error;
  final bool fileDownloadLoading;
  final int fileDownloadProgress;
  final String? fileDownloadError;
  final String? downloadedFilename;
  final String? savedFilePath;
  final String? savedDirectory;
  final bool fileOpenLoading;
  final bool isRetrying;

  bool get isSavingToDevice {
    if (fileDownloadLoading) {
      return true;
    }

    return status == 'completed' &&
        savedFilePath?.trim().isNotEmpty != true &&
        fileDownloadError?.trim().isNotEmpty != true;
  }

  bool get isFinalized {
    return status == 'completed' && savedFilePath?.trim().isNotEmpty == true;
  }

  bool get isActive {
    return status == 'pending' ||
        status == 'queued' ||
        status == 'processing' ||
        status == 'cancelling' ||
        isSavingToDevice;
  }

  TrackedDownload copyWith({
    String? status,
    int? progress,
    Object? downloadUrl = _unset,
    Object? error = _unset,
    bool? fileDownloadLoading,
    int? fileDownloadProgress,
    Object? fileDownloadError = _unset,
    Object? downloadedFilename = _unset,
    Object? savedFilePath = _unset,
    Object? savedDirectory = _unset,
    bool? fileOpenLoading,
    bool? isRetrying,
  }) {
    return TrackedDownload(
      jobId: jobId,
      metadata: metadata,
      mediaType: mediaType,
      selectedVideoQuality: selectedVideoQuality,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadUrl: identical(downloadUrl, _unset)
          ? this.downloadUrl
          : downloadUrl as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      fileDownloadLoading: fileDownloadLoading ?? this.fileDownloadLoading,
      fileDownloadProgress: fileDownloadProgress ?? this.fileDownloadProgress,
      fileDownloadError: identical(fileDownloadError, _unset)
          ? this.fileDownloadError
          : fileDownloadError as String?,
      downloadedFilename: identical(downloadedFilename, _unset)
          ? this.downloadedFilename
          : downloadedFilename as String?,
      savedFilePath: identical(savedFilePath, _unset)
          ? this.savedFilePath
          : savedFilePath as String?,
      savedDirectory: identical(savedDirectory, _unset)
          ? this.savedDirectory
          : savedDirectory as String?,
      fileOpenLoading: fileOpenLoading ?? this.fileOpenLoading,
      isRetrying: isRetrying ?? this.isRetrying,
    );
  }
}
