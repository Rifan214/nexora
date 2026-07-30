import 'dart:collection';

import 'media_download_type.dart';
import 'media_metadata.dart';

enum BatchImportItemStatus {
  pending,
  analyzing,
  ready,
  analysisFailed,
  submitting,
  submitted,
  submissionFailed,
}

class BatchImportItem {
  const BatchImportItem({
    required this.url,
    required this.status,
    this.metadata,
    this.mediaType,
    this.selectedVideoQuality,
    this.selectedAudioOptionLabel,
    this.error,
  });

  static const _unset = Object();

  final String url;
  final BatchImportItemStatus status;
  final MediaMetadata? metadata;
  final MediaDownloadType? mediaType;
  final VideoQuality? selectedVideoQuality;
  final String? selectedAudioOptionLabel;
  final String? error;

  bool get hasSelection {
    return switch (mediaType) {
      MediaDownloadType.video => selectedVideoQuality != null,
      MediaDownloadType.audio => selectedAudioOptionLabel != null,
      null => false,
    };
  }

  BatchImportItem copyWith({
    BatchImportItemStatus? status,
    Object? metadata = _unset,
    Object? mediaType = _unset,
    Object? selectedVideoQuality = _unset,
    Object? selectedAudioOptionLabel = _unset,
    Object? error = _unset,
  }) {
    return BatchImportItem(
      url: url,
      status: status ?? this.status,
      metadata: identical(metadata, _unset) ? this.metadata : metadata as MediaMetadata?,
      mediaType: identical(mediaType, _unset)
          ? this.mediaType
          : mediaType as MediaDownloadType?,
      selectedVideoQuality: identical(selectedVideoQuality, _unset)
          ? this.selectedVideoQuality
          : selectedVideoQuality as VideoQuality?,
      selectedAudioOptionLabel: identical(selectedAudioOptionLabel, _unset)
          ? this.selectedAudioOptionLabel
          : selectedAudioOptionLabel as String?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class BatchImportState {
  const BatchImportState({
    this.urlInput = '',
    this.items = const [],
    this.isAnalyzing = false,
    this.isSubmitting = false,
    this.analysisCompletedCount = 0,
    this.currentUrl,
    this.currentTitle,
  });

  static const _unset = Object();

  final String urlInput;
  final List<BatchImportItem> items;
  final bool isAnalyzing;
  final bool isSubmitting;
  final int analysisCompletedCount;
  final String? currentUrl;
  final String? currentTitle;

  int get totalCount => items.length;

  bool get hasSession => urlInput.trim().isNotEmpty || items.isNotEmpty;

  int get selectedReadyCount {
    return items
        .where(
          (item) =>
              item.status == BatchImportItemStatus.ready && item.hasSelection,
        )
        .length;
  }

  BatchImportState copyWith({
    String? urlInput,
    List<BatchImportItem>? items,
    bool? isAnalyzing,
    bool? isSubmitting,
    int? analysisCompletedCount,
    Object? currentUrl = _unset,
    Object? currentTitle = _unset,
  }) {
    return BatchImportState(
      urlInput: urlInput ?? this.urlInput,
      items: items ?? this.items,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      analysisCompletedCount:
          analysisCompletedCount ?? this.analysisCompletedCount,
      currentUrl: identical(currentUrl, _unset)
          ? this.currentUrl
          : currentUrl as String?,
      currentTitle: identical(currentTitle, _unset)
          ? this.currentTitle
          : currentTitle as String?,
    );
  }
}

class BatchInvalidUrl {
  const BatchInvalidUrl({required this.lineNumber, required this.value});

  final int lineNumber;
  final String value;
}

class BatchUrlValidationResult {
  const BatchUrlValidationResult({
    required this.validUrls,
    required this.invalidUrls,
  });

  final List<String> validUrls;
  final List<BatchInvalidUrl> invalidUrls;

  bool get hasInvalidUrls => invalidUrls.isNotEmpty;
}

BatchUrlValidationResult validateBatchUrlLines(Iterable<String> lines) {
  final validUrls = <String>[];
  final invalidUrls = <BatchInvalidUrl>[];
  final urlScheme = RegExp(r'https?://', caseSensitive: false);

  for (var index = 0; index < lines.length; index++) {
    final rawLine = lines.elementAt(index);
    final value = rawLine.trim();
    if (value.isEmpty) {
      continue;
    }

    final schemeMatches = urlScheme.allMatches(rawLine).toList(growable: false);
    final hasOnlyOneUrl = schemeMatches.length == 1;
    final hasOnlyWhitespaceBeforeUrl = hasOnlyOneUrl &&
        rawLine.substring(0, schemeMatches.single.start).trim().isEmpty;
    final hasWhitespaceInsideUrl = value.contains(RegExp(r'\s'));
    final uri = Uri.tryParse(value);
    final hasSupportedUri = uri != null &&
        uri.isAbsolute &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.host.isNotEmpty;

    if (!hasOnlyOneUrl ||
        !hasOnlyWhitespaceBeforeUrl ||
        hasWhitespaceInsideUrl ||
        !hasSupportedUri) {
      invalidUrls.add(BatchInvalidUrl(lineNumber: index + 1, value: rawLine));
      continue;
    }

    validUrls.add(value);
  }

  return BatchUrlValidationResult(
    validUrls: List.unmodifiable(validUrls),
    invalidUrls: List.unmodifiable(invalidUrls),
  );
}

List<String> normalizeBatchUrls(Iterable<String> lines) {
  final urls = LinkedHashSet<String>();
  for (final line in lines) {
    final url = line.trim();
    if (url.isNotEmpty) {
      urls.add(url);
    }
  }
  return urls.toList(growable: false);
}
