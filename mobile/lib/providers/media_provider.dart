import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/media_metadata.dart';
import '../models/media_state.dart';
import '../repositories/media_repository.dart';

final mediaProvider = NotifierProvider<MediaController, MediaState>(
  MediaController.new,
);

class MediaController extends Notifier<MediaState> {
  @override
  MediaState build() {
    return const MediaState.idle();
  }

  Future<void> getMediaInfo(String url) async {
    final trimmedUrl = url.trim();
    final validationMessage = _validateUrl(trimmedUrl);
    if (validationMessage != null) {
      state = MediaState.error(validationMessage);
      return;
    }

    state = const MediaState.loading();

    try {
      final metadata = await ref.read(mediaRepositoryProvider).getMediaInfo(trimmedUrl);
      state = MediaState.success(metadata: metadata);
    } on ApiException catch (error) {
      state = MediaState.error(error.message);
    } catch (_) {
      state = const MediaState.error('Unable to retrieve media metadata.');
    }
  }

  void selectFormat(MediaFormat format) {
    state.maybeWhen(
      success: (metadata, _) {
        state = MediaState.success(
          metadata: metadata,
          selectedFormat: format,
        );
      },
      orElse: () {},
    );
  }

  String? _validateUrl(String value) {
    if (value.isEmpty) {
      return 'Enter a media URL.';
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid URL.';
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Enter an HTTP or HTTPS URL.';
    }

    return null;
  }
}
