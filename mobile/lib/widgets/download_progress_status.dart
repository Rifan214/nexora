/// Converts existing download state into one consistent, user-facing status.
/// It only changes copy; progress values continue to come from the provider.
String friendlyDownloadStatus({
  required String? backendStatus,
  required int backendProgress,
  required bool isSavingToDevice,
}) {
  if (isSavingToDevice) {
    return 'Saving to device...';
  }

  final normalizedStatus = backendStatus?.trim().toLowerCase();
  if (normalizedStatus == null ||
      normalizedStatus.isEmpty ||
      normalizedStatus == 'pending') {
    return 'Preparing...';
  }

  if (normalizedStatus == 'processing') {
    return backendProgress >= 100
        ? 'Processing media...'
        : 'Downloading media...';
  }

  if (normalizedStatus == 'completed') {
    return 'Saving to device...';
  }

  return 'Processing media...';
}
