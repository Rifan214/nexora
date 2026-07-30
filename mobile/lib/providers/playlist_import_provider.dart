import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/playlist_import_session.dart';
import '../repositories/media_repository.dart';

final playlistImportProvider =
    NotifierProvider<PlaylistImportController, PlaylistImportSessionState>(
  PlaylistImportController.new,
);

class PlaylistImportController extends Notifier<PlaylistImportSessionState> {
  var _previewRequestId = 0;

  @override
  PlaylistImportSessionState build() => const PlaylistImportSessionState();

  void updateUrl(String value) {
    if (value == state.url) {
      return;
    }
    state = state.copyWith(url: value, errorMessage: null);
  }

  Future<void> previewPlaylist() async {
    if (state.isLoading) {
      return;
    }

    final url = state.url.trim();
    if (url.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter a playlist URL to continue.');
      return;
    }

    final requestId = ++_previewRequestId;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final playlist = await ref.read(mediaRepositoryProvider).getPlaylistInfo(url);
      if (requestId != _previewRequestId) {
        return;
      }
      state = state.copyWith(
        url: url,
        playlist: playlist,
        selectedUrls: Set.unmodifiable(
          playlist.items.map((item) => item.webpageUrl),
        ),
        errorMessage: null,
      );
    } on ApiException catch (error) {
      if (requestId == _previewRequestId) {
        state = state.copyWith(errorMessage: error.message);
      }
    } catch (_) {
      if (requestId == _previewRequestId) {
        state = state.copyWith(errorMessage: 'Unable to preview this playlist.');
      }
    } finally {
      if (requestId == _previewRequestId) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void toggleItem(String url, bool isSelected) {
    final selectedUrls = Set<String>.of(state.selectedUrls);
    if (isSelected) {
      selectedUrls.add(url);
    } else {
      selectedUrls.remove(url);
    }
    state = state.copyWith(selectedUrls: Set.unmodifiable(selectedUrls));
  }

  void selectAll() {
    final playlist = state.playlist;
    if (playlist == null) {
      return;
    }
    state = state.copyWith(
      selectedUrls: Set.unmodifiable(
        playlist.items.map((item) => item.webpageUrl),
      ),
    );
  }

  void clearSelection() {
    state = state.copyWith(selectedUrls: const <String>{});
  }

  void invertSelection() {
    final playlist = state.playlist;
    if (playlist == null) {
      return;
    }
    final selectedUrls = <String>{};
    for (final item in playlist.items) {
      if (!state.selectedUrls.contains(item.webpageUrl)) {
        selectedUrls.add(item.webpageUrl);
      }
    }
    state = state.copyWith(selectedUrls: Set.unmodifiable(selectedUrls));
  }

  List<String> selectedUrlsInPlaylistOrder() {
    final playlist = state.playlist;
    if (playlist == null) {
      return const [];
    }
    return playlist.items
        .where((item) => state.selectedUrls.contains(item.webpageUrl))
        .map((item) => item.webpageUrl)
        .toList(growable: false);
  }

  void clear() {
    _previewRequestId++;
    state = const PlaylistImportSessionState();
  }
}
