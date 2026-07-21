import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/network/api_exception.dart';

final deviceFileServiceProvider = Provider<DeviceFileService>((ref) {
  return const DeviceFileService();
});

class DeviceFileService {
  const DeviceFileService();

  Future<Directory> prepareDownloadDirectory() async {
    final baseDirectory = await _resolveBaseDirectory();
    final downloadDirectory = Directory(_join(baseDirectory.path, 'downloads'));

    await _requestStoragePermissionIfRequired(downloadDirectory);
    await downloadDirectory.create(recursive: true);

    return downloadDirectory;
  }

  String sanitizeFilename(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^\.+'), '');

    if (sanitized.isEmpty) {
      return 'download';
    }

    if (sanitized.length > 180) {
      return sanitized.substring(0, 180).trim();
    }

    return sanitized;
  }

  String? filenameFromContentDisposition(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    String? fallbackFilename;
    for (final part in value.split(';')) {
      final trimmedPart = part.trim();
      final lowerPart = trimmedPart.toLowerCase();

      if (lowerPart.startsWith('filename*=')) {
        final encodedValue = _stripQuotes(trimmedPart.substring(10).trim());
        final filename = _decodeEncodedFilename(encodedValue);
        if (filename != null && filename.isNotEmpty) {
          return sanitizeFilename(filename);
        }
      }

      if (lowerPart.startsWith('filename=')) {
        fallbackFilename = _stripQuotes(trimmedPart.substring(9).trim());
      }
    }

    if (fallbackFilename == null || fallbackFilename.trim().isEmpty) {
      return null;
    }

    return sanitizeFilename(fallbackFilename);
  }

  String uniqueFilePath({
    required Directory directory,
    required String filename,
  }) {
    final sanitizedFilename = sanitizeFilename(filename);
    final basename = _basenameWithoutExtension(sanitizedFilename);
    final extension = _extension(sanitizedFilename);
    var candidate = _join(directory.path, sanitizedFilename);
    var copyIndex = 1;

    while (File(candidate).existsSync()) {
      final copyFilename = extension.isEmpty
          ? '$basename ($copyIndex)'
          : '$basename ($copyIndex)$extension';
      candidate = _join(directory.path, copyFilename);
      copyIndex += 1;
    }

    return candidate;
  }

  String filenameFromPath(String path) {
    final normalizedPath = path.replaceAll('\\', '/');
    final segments = normalizedPath.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  Future<void> openFile(String filePath) async {
    final result = await OpenFilex.open(filePath);
    if (result.type == ResultType.done) {
      return;
    }

    final message = result.message.trim();
    if (message.isNotEmpty) {
      throw ApiException(message);
    }

    throw ApiException(_messageForOpenResult(result.type));
  }

  Future<Directory> _resolveBaseDirectory() async {
    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        return externalDirectory;
      }
    }

    try {
      final downloadsDirectory = await getDownloadsDirectory();
      if (downloadsDirectory != null) {
        return downloadsDirectory;
      }
    } catch (_) {
      // Some platforms do not expose a downloads directory through path_provider.
    }

    return getApplicationDocumentsDirectory();
  }

  Future<void> _requestStoragePermissionIfRequired(Directory directory) async {
    if (!_requiresStoragePermission(directory)) {
      return;
    }

    final status = await Permission.storage.status;
    if (status.isGranted) {
      return;
    }

    final requestedStatus = await Permission.storage.request();
    if (!requestedStatus.isGranted) {
      throw const ApiException('Storage permission denied.');
    }
  }

  bool _requiresStoragePermission(Directory directory) {
    if (!Platform.isAndroid) {
      return false;
    }

    final normalizedPath = directory.path.replaceAll('\\', '/').toLowerCase();
    return !normalizedPath.contains('/android/data/');
  }

  String _join(String parent, String child) {
    final separator = Platform.pathSeparator;
    if (parent.endsWith(separator)) {
      return '$parent$child';
    }

    return '$parent$separator$child';
  }

  String _stripQuotes(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }

    return value;
  }

  String? _decodeEncodedFilename(String value) {
    final markerIndex = value.indexOf("''");
    final encodedValue =
        markerIndex >= 0 ? value.substring(markerIndex + 2) : value;

    try {
      return Uri.decodeComponent(encodedValue);
    } catch (_) {
      return encodedValue;
    }
  }

  String _basenameWithoutExtension(String filename) {
    final extension = _extension(filename);
    if (extension.isEmpty) {
      return filename;
    }

    return filename.substring(0, filename.length - extension.length);
  }

  String _extension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == filename.length - 1) {
      return '';
    }

    return filename.substring(dotIndex);
  }

  String _messageForOpenResult(ResultType type) {
    switch (type) {
      case ResultType.fileNotFound:
        return 'The downloaded file could not be found.';
      case ResultType.noAppToOpen:
        return 'No app is available to open this file.';
      case ResultType.permissionDenied:
        return 'Permission denied while opening the file.';
      case ResultType.error:
        return 'Unable to open the file.';
      case ResultType.done:
        return 'File opened.';
    }
  }
}
