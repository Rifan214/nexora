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
      success: (metadata, _, __, ___, ____, _____) {
        state = MediaState.success(
          metadata: metadata,
          selectedFormat: format,
        );
      },
      orElse: () {},
    );
  }

  Future<void> createDownloadJob() async {
    MediaMetadata? currentMetadata;
    MediaFormat? currentFormat;
    var isDownloadLoading = false;

    state.maybeWhen(
      success: (
        metadata,
        selectedFormat,
        downloadLoading,
        _,
        __,
        ___,
      ) {
        currentMetadata = metadata;
        currentFormat = selectedFormat;
        isDownloadLoading = downloadLoading;
      },
      orElse: () {},
    );

    final metadata = currentMetadata;
    if (metadata == null || isDownloadLoading) {
      return;
    }

    final selectedFormat = currentFormat;
    if (selectedFormat == null) {
      state = MediaState.success(
        metadata: metadata,
        downloadError: 'Select a format before downloading.',
      );
      return;
    }

    final validationMessage = _validateUrl(metadata.webpageUrl);
    if (validationMessage != null) {
      state = MediaState.success(
        metadata: metadata,
        selectedFormat: selectedFormat,
        downloadError: validationMessage,
      );
      return;
    }

    state = MediaState.success(
      metadata: metadata,
      selectedFormat: selectedFormat,
      downloadLoading: true,
    );

    try {
      final job = await ref.read(mediaRepositoryProvider).createDownloadJob(
            mediaUrl: metadata.webpageUrl,
            format: selectedFormat,
          );
      state = MediaState.success(
        metadata: metadata,
        selectedFormat: selectedFormat,
        downloadSuccess: true,
        currentJobId: job.jobId,
      );
    } on ApiException catch (error) {
      state = MediaState.success(
        metadata: metadata,
        selectedFormat: selectedFormat,
        downloadError: error.message,
      );
    } catch (_) {
      state = MediaState.success(
        metadata: metadata,
        selectedFormat: selectedFormat,
        downloadError: 'Unable to create download job.',
      );
    }
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
