import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/batch_import.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';
import '../repositories/media_repository.dart';
import 'active_downloads_provider.dart';

final batchImportProvider =
    NotifierProvider<BatchImportController, BatchImportState>(
  BatchImportController.new,
);

class BatchImportController extends Notifier<BatchImportState> {
  @override
  BatchImportState build() => const BatchImportState();

  void clearBatch() {
    state = const BatchImportState();
  }

  void updateUrlInput(String value) {
    if (value != state.urlInput) {
      state = state.copyWith(urlInput: value);
    }
  }

  Future<void> analyzeUrls(Iterable<String> lines) async {
    if (state.isAnalyzing || state.isSubmitting) {
      return;
    }

    final validation = validateBatchUrlLines(lines);
    if (validation.hasInvalidUrls) {
      return;
    }

    final urls = normalizeBatchUrls(validation.validUrls);
    if (urls.isEmpty) {
      return;
    }

    state = BatchImportState(
      urlInput: state.urlInput,
      items: [
        for (final url in urls)
          BatchImportItem(url: url, status: BatchImportItemStatus.pending),
      ],
      isAnalyzing: true,
    );

    for (var index = 0; index < urls.length; index++) {
      final url = urls[index];
      _updateItem(
        url,
        (item) => item.copyWith(status: BatchImportItemStatus.analyzing),
      );
      state = state.copyWith(currentUrl: url, currentTitle: null);

      try {
        final metadata = await ref.read(mediaRepositoryProvider).getMediaInfo(url);
        _updateItem(
          url,
          (item) => item.copyWith(
            status: BatchImportItemStatus.ready,
            metadata: metadata,
            error: null,
          ),
        );
        state = state.copyWith(currentTitle: metadata.title);
      } on ApiException catch (error) {
        _updateItem(
          url,
          (item) => item.copyWith(
            status: BatchImportItemStatus.analysisFailed,
            error: error.message,
          ),
        );
      } catch (_) {
        _updateItem(
          url,
          (item) => item.copyWith(
            status: BatchImportItemStatus.analysisFailed,
            error: 'Failed to analyze this URL.',
          ),
        );
      } finally {
        state = state.copyWith(analysisCompletedCount: index + 1);
      }
    }

    state = state.copyWith(
      isAnalyzing: false,
      currentUrl: null,
      currentTitle: null,
    );
  }

  void selectVideoQuality(String url, VideoQuality quality) {
    if (state.isAnalyzing || state.isSubmitting) {
      return;
    }

    _updateItem(
      url,
      (item) => item.status != BatchImportItemStatus.ready
          ? item
          : item.copyWith(
              mediaType: MediaDownloadType.video,
              selectedVideoQuality: quality,
              selectedAudioOptionLabel: null,
            ),
    );
  }

  void selectAudioOption(String url, AudioOption option) {
    if (state.isAnalyzing || state.isSubmitting) {
      return;
    }

    _updateItem(
      url,
      (item) => item.status != BatchImportItemStatus.ready
          ? item
          : item.copyWith(
              mediaType: MediaDownloadType.audio,
              selectedVideoQuality: null,
              selectedAudioOptionLabel: option.label,
            ),
    );
  }

  void removeItem(String url) {
    if (state.isAnalyzing || state.isSubmitting) {
      return;
    }

    BatchImportItem? item;
    for (final candidate in state.items) {
      if (candidate.url == url) {
        item = candidate;
        break;
      }
    }
    if (item == null || item.status == BatchImportItemStatus.submitted) {
      return;
    }

    state = state.copyWith(
      items: state.items.where((item) => item.url != url).toList(),
    );
  }

  Future<void> submitSelectedDownloads() async {
    if (state.isAnalyzing || state.isSubmitting) {
      return;
    }

    final selectedItems = state.items
        .where(
          (item) =>
              item.status == BatchImportItemStatus.ready && item.hasSelection,
        )
        .toList(growable: false);
    if (selectedItems.isEmpty) {
      return;
    }

    state = state.copyWith(isSubmitting: true);
    final repository = ref.read(mediaRepositoryProvider);
    final activeDownloads = ref.read(activeDownloadsProvider.notifier);

    for (final item in selectedItems) {
      final metadata = item.metadata;
      final mediaType = item.mediaType;
      if (metadata == null || mediaType == null) {
        continue;
      }

      _updateItem(
        item.url,
        (current) => current.copyWith(
          status: BatchImportItemStatus.submitting,
          error: null,
        ),
      );

      try {
        final job = await repository.createDownloadJob(
          mediaUrl: metadata.webpageUrl,
          mediaType: mediaType,
          videoQuality: item.selectedVideoQuality,
        );
        activeDownloads.trackDownload(
          jobId: job.jobId,
          metadata: metadata,
          mediaType: mediaType,
          selectedVideoQuality: item.selectedVideoQuality,
        );
        _updateItem(
          item.url,
          (current) => current.copyWith(
            status: BatchImportItemStatus.submitted,
            error: null,
          ),
        );
      } on ApiException catch (error) {
        _updateItem(
          item.url,
          (current) => current.copyWith(
            status: BatchImportItemStatus.submissionFailed,
            error: error.message,
          ),
        );
      } catch (_) {
        _updateItem(
          item.url,
          (current) => current.copyWith(
            status: BatchImportItemStatus.submissionFailed,
            error: 'Failed to create the download job.',
          ),
        );
      }
    }

    final completedState = state.copyWith(isSubmitting: false);
    if (completedState.items.isNotEmpty &&
        completedState.items.every(
          (item) => item.status == BatchImportItemStatus.submitted,
        )) {
      clearBatch();
      return;
    }
    state = completedState;
  }

  void _updateItem(
    String url,
    BatchImportItem Function(BatchImportItem item) update,
  ) {
    state = state.copyWith(
      items: [
        for (final item in state.items) if (item.url == url) update(item) else item,
      ],
    );
  }
}
