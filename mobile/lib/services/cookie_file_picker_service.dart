import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstraction for picking and reading cookie files (cookies.txt or JSON export).
abstract class CookieFilePickerClient {
  /// Prompts user to pick a cookie file and reads its content directly into memory.
  ///
  /// Returns the file text, or `null` if cancelled or unreadable.
  Future<String?> pickAndReadCookieFile();
}

/// Standard implementation using the file_picker plugin.
class SystemCookieFilePickerClient implements CookieFilePickerClient {
  const SystemCookieFilePickerClient();

  @override
  Future<String?> pickAndReadCookieFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'json'],
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}

final cookieFilePickerProvider = Provider<CookieFilePickerClient>((ref) {
  return const SystemCookieFilePickerClient();
});
