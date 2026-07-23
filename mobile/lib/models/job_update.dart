import '../core/network/api_exception.dart';

class JobUpdate {
  const JobUpdate({
    required this.jobId,
    required this.status,
    required this.progress,
    this.downloadUrl,
    this.error,
  });

  final String jobId;
  final String status;
  final int progress;
  final String? downloadUrl;
  final String? error;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isCancelling => status == 'cancelling';
  bool get isCancelled => status == 'cancelled';
  bool get isTerminal => isCompleted || isFailed || isCancelled;

  factory JobUpdate.fromJson(Map<String, dynamic> json) {
    final jobId = _readString(json['job_id']);
    final status = _readString(json['status']).toLowerCase();

    if (jobId.isEmpty || status.isEmpty) {
      throw const ApiException('Invalid progress update from server.');
    }

    return JobUpdate(
      jobId: jobId,
      status: status,
      progress: _readProgress(json['progress']),
      downloadUrl: _readOptionalString(json['download_url']),
      error: _readOptionalString(json['error'] ?? json['error_message']),
    );
  }

  static String _readString(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  static String? _readOptionalString(Object? value) {
    final text = _readString(value);
    return text.isEmpty ? null : text;
  }

  static int _readProgress(Object? value) {
    final int progress;
    if (value is int) {
      progress = value;
    } else if (value is num) {
      progress = value.round();
    } else if (value is String) {
      progress = double.tryParse(value.trim())?.round() ?? 0;
    } else {
      progress = 0;
    }

    if (progress < 0) {
      return 0;
    }

    if (progress > 100) {
      return 100;
    }

    return progress;
  }
}
