enum MediaDownloadType {
  video('video'),
  audio('audio');

  const MediaDownloadType(this.requestValue);

  final String requestValue;
}
