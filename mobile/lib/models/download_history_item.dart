import 'media_download_type.dart';

class DownloadHistoryItem {
  const DownloadHistoryItem({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.localFilePath,
    required this.createdAt,
    this.thumbnailUrl,
    this.selectedQuality,
    this.durationSeconds,
  });

  final String id;
  final String title;
  final String? thumbnailUrl;
  final MediaDownloadType mediaType;
  final String? selectedQuality;
  final String localFilePath;
  final DateTime createdAt;
  final int? durationSeconds;

  factory DownloadHistoryItem.fromDatabase(Map<String, Object?> values) {
    return DownloadHistoryItem(
      id: _readText(values['id']),
      title: _readText(values['title']),
      thumbnailUrl: _readOptionalText(values['thumbnail']),
      mediaType: _readMediaType(values['media_type']),
      selectedQuality: _readOptionalText(values['selected_quality']),
      localFilePath: _readText(values['local_file_path']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(values['created_at']),
      ),
      durationSeconds: _readOptionalInt(values['duration_seconds']),
    );
  }

  Map<String, Object?> toDatabase() {
    return {
      'id': id,
      'title': title,
      'thumbnail': thumbnailUrl,
      'media_type': mediaType.requestValue,
      'selected_quality': selectedQuality,
      'local_file_path': localFilePath,
      'created_at': createdAt.millisecondsSinceEpoch,
      'duration_seconds': durationSeconds,
    };
  }

  static MediaDownloadType _readMediaType(Object? value) {
    return value == MediaDownloadType.audio.requestValue
        ? MediaDownloadType.audio
        : MediaDownloadType.video;
  }

  static String _readText(Object? value) {
    return value is String ? value : value?.toString() ?? '';
  }

  static String? _readOptionalText(Object? value) {
    final text = _readText(value).trim();
    return text.isEmpty ? null : text;
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _readOptionalInt(Object? value) {
    if (value == null) {
      return null;
    }
    return _readInt(value);
  }
}
