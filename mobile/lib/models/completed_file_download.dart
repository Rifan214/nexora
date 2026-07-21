class CompletedFileDownload {
  const CompletedFileDownload({
    required this.filename,
    required this.savedPath,
    required this.savedDirectory,
  });

  final String filename;
  final String savedPath;
  final String savedDirectory;
}
