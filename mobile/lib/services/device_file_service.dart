import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/network/api_exception.dart';
import '../models/completed_file_download.dart';
import '../models/media_download_type.dart';

final deviceFileServiceProvider = Provider<DeviceFileService>((ref) {
  return const DeviceFileService();
});

class DeviceFileService {
  const DeviceFileService();

  static const _publicStorageChannel = MethodChannel(
    'com.example.nexora/public_storage',
  );

  Future<Directory> prepareTemporaryDownloadDirectory() async {
    final cacheDirectory = await getTemporaryDirectory();
    final downloadDirectory = Directory(_join(cacheDirectory.path, 'nexora-downloads'));
    await downloadDirectory.create(recursive: true);
    return downloadDirectory;
  }

  Future<CompletedFileDownload> publishDownloadedFile({
    required String temporaryFilePath,
    required String filename,
    required MediaDownloadType mediaType,
  }) async {
    final sanitizedFilename = sanitizeFilename(filename);
    if (Platform.isAndroid) {
      return _publishToAndroidDownloads(
        temporaryFilePath: temporaryFilePath,
        filename: sanitizedFilename,
        mediaType: mediaType,
      );
    }

    final directory = await _prepareFallbackDownloadDirectory(mediaType);
    final destinationPath = uniqueFilePath(
      directory: directory,
      filename: sanitizedFilename,
    );
    await File(temporaryFilePath).copy(destinationPath);
    return CompletedFileDownload(
      filename: sanitizedFilename,
      savedPath: destinationPath,
      savedDirectory: directory.path,
    );
  }

  String publicDownloadsRelativePathFor(MediaDownloadType mediaType) {
    return 'Download/Nexora/${_categoryFor(mediaType)}';
  }

  Future<bool> fileExists(String reference) async {
    final trimmedReference = reference.trim();
    if (trimmedReference.isEmpty) {
      return false;
    }
    if (_isContentUri(trimmedReference) && Platform.isAndroid) {
      try {
        return await _publicStorageChannel.invokeMethod<bool>(
              'publicMediaExists',
              {'uri': trimmedReference},
            ) ??
            false;
      } on PlatformException {
        return false;
      }
    }
    return File(trimmedReference).exists();
  }

  Future<void> deleteFileIfPresent(String reference) async {
    final trimmedReference = reference.trim();
    if (trimmedReference.isEmpty) {
      return;
    }
    if (_isContentUri(trimmedReference) && Platform.isAndroid) {
      try {
        await _publicStorageChannel.invokeMethod<void>(
          'deletePublicMedia',
          {'uri': trimmedReference},
        );
      } on PlatformException {
        // A missing or inaccessible public file must not block history cleanup.
      }
      return;
    }

    try {
      if (await File(trimmedReference).exists()) {
        await File(trimmedReference).delete();
      }
    } on FileSystemException {
      // A missing or inaccessible local file must not block history cleanup.
    }
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
    if (_isContentUri(filePath) && Platform.isAndroid) {
      try {
        final opened = await _publicStorageChannel.invokeMethod<bool>(
          'openPublicMedia',
          {'uri': filePath},
        );
        if (opened == true) {
          return;
        }
      } on PlatformException catch (error) {
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          throw ApiException(message);
        }
      }
      throw const ApiException('Unable to open the file.');
    }

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

  Future<CompletedFileDownload> _publishToAndroidDownloads({
    required String temporaryFilePath,
    required String filename,
    required MediaDownloadType mediaType,
  }) async {
    try {
      final result = await _publicStorageChannel.invokeMapMethod<String, dynamic>(
        'saveToDownloads',
        {
          'sourcePath': temporaryFilePath,
          'filename': filename,
          'mimeType': _mimeTypeFor(filename, mediaType),
          'relativePath': '${publicDownloadsRelativePathFor(mediaType)}/',
        },
      );
      final uri = result?['uri'] as String?;
      final directory = result?['relativePath'] as String?;
      if (uri == null || uri.isEmpty || directory == null || directory.isEmpty) {
        throw const ApiException('Unable to save the downloaded file to Downloads.');
      }
      return CompletedFileDownload(
        filename: filename,
        savedPath: uri,
        savedDirectory: directory,
      );
    } on ApiException {
      rethrow;
    } on PlatformException catch (error) {
      final message = error.message?.trim();
      throw ApiException(
        message == null || message.isEmpty
            ? 'Unable to save the downloaded file to Downloads.'
            : message,
      );
    }
  }

  Future<Directory> _prepareFallbackDownloadDirectory(
    MediaDownloadType mediaType,
  ) async {
    Directory? downloadsDirectory;
    try {
      downloadsDirectory = await getDownloadsDirectory();
    } catch (_) {
      // Some non-Android platforms do not expose a downloads directory.
    }
    final baseDirectory = downloadsDirectory ?? await getApplicationDocumentsDirectory();
    final directory = Directory(
      _join(_join(baseDirectory.path, 'Nexora'), _categoryFor(mediaType)),
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _categoryFor(MediaDownloadType mediaType) {
    return switch (mediaType) {
      MediaDownloadType.video => 'Video',
      MediaDownloadType.audio => 'Audio',
    };
  }

  String _mimeTypeFor(String filename, MediaDownloadType mediaType) {
    final extension = _extension(filename).toLowerCase();
    return switch (extension) {
      '.mp3' => 'audio/mpeg',
      '.m4a' => 'audio/mp4',
      '.aac' => 'audio/aac',
      '.ogg' => 'audio/ogg',
      '.opus' => 'audio/opus',
      '.wav' => 'audio/wav',
      '.mp4' => 'video/mp4',
      '.mkv' => 'video/x-matroska',
      '.webm' => mediaType == MediaDownloadType.audio ? 'audio/webm' : 'video/webm',
      _ => 'application/octet-stream',
    };
  }

  bool _isContentUri(String value) => value.startsWith('content://');

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
