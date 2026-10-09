abstract final class ApiPaths {
  static const health = '/health';
  static const mediaInfo = '/media/info';
  static const mediaPlaylistInfo = '/media/playlist/info';
  static const mediaDownload = '/media/download';

  static const xAuthSession = '/auth/x/session';

  static String xAuthSessionDetail(String sessionId) {
    return '/auth/x/session/${Uri.encodeComponent(sessionId)}';
  }

  static const tikTokAuthSession = '/auth/tiktok/session';

  static String tikTokAuthSessionDetail(String sessionId) {
    return '/auth/tiktok/session/${Uri.encodeComponent(sessionId)}';
  }

  static const instagramAuthSession = '/auth/instagram/session';

  static String instagramAuthSessionDetail(String sessionId) {
    return '/auth/instagram/session/${Uri.encodeComponent(sessionId)}';
  }

  static String cancelJob(String jobId) {
    return '/jobs/${Uri.encodeComponent(jobId)}/cancel';
  }

  static String jobWebSocket(String jobId) {
    return '/ws/jobs/${Uri.encodeComponent(jobId)}';
  }
}
