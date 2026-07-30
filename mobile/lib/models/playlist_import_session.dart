import 'playlist_metadata.dart';

class PlaylistImportSessionState {
  const PlaylistImportSessionState({
    this.url = '',
    this.playlist,
    this.selectedUrls = const <String>{},
    this.errorMessage,
    this.isLoading = false,
  });

  static const _unset = Object();

  final String url;
  final PlaylistMetadata? playlist;
  final Set<String> selectedUrls;
  final String? errorMessage;
  final bool isLoading;

  bool get hasPreview => playlist != null;

  PlaylistImportSessionState copyWith({
    String? url,
    Object? playlist = _unset,
    Set<String>? selectedUrls,
    Object? errorMessage = _unset,
    bool? isLoading,
  }) {
    return PlaylistImportSessionState(
      url: url ?? this.url,
      playlist: identical(playlist, _unset)
          ? this.playlist
          : playlist as PlaylistMetadata?,
      selectedUrls: selectedUrls ?? this.selectedUrls,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
