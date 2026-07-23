abstract final class ApiPaths {
  static const health = '/health';
  static const mediaInfo = '/media/info';
  static const mediaDownload = '/media/download';

  static String cancelJob(String jobId) {
    return '/jobs/${Uri.encodeComponent(jobId)}/cancel';
  }

  static String jobWebSocket(String jobId) {
    return '/ws/jobs/${Uri.encodeComponent(jobId)}';
  }
}
