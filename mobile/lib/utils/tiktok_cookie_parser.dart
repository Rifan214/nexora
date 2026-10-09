import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Parsed TikTok authentication credentials extracted from imported cookies.
///
/// Guaranteed to never expose secret token values via [toString].
@immutable
class TikTokCookieCredentials {
  const TikTokCookieCredentials({
    required this.sessionid,
    this.sidTt,
  });

  /// The `sessionid` cookie value.
  final String sessionid;

  /// The optional `sid_tt` cookie value.
  final String? sidTt;

  /// Whether the required sessionid credential is non-empty after trimming.
  bool get isValid => sessionid.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TikTokCookieCredentials &&
          runtimeType == other.runtimeType &&
          sessionid == other.sessionid &&
          sidTt == other.sidTt;

  @override
  int get hashCode => Object.hash(sessionid, sidTt);

  @override
  String toString() => 'TikTokCookieCredentials([PROTECTED])';
}

/// Pure Dart parser for extracting official TikTok session cookies.
///
/// Supports:
/// 1. Netscape `cookies.txt` (including `#HttpOnly_` lines)
/// 2. JSON cookie export (array of cookie objects)
/// 3. Raw HTTP `Cookie` header string
///
/// Strictly extracts ONLY `sessionid` (or alias `sessionid_ss`) and optional `sid_tt`
/// from allowed TikTok domains (`tiktok.com`, `*.tiktok.com`). Discards all other cookies.
abstract final class TikTokCookieParser {
  static const int _maxCredentialLength = 512;

  /// Parses the [rawInput] string and returns validated [TikTokCookieCredentials].
  ///
  /// Throws [FormatException] if sessionid cookie is missing, empty,
  /// or exceeds maximum allowed length. Never leaks credential values in error messages.
  static TikTokCookieCredentials parse(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Cookie input cannot be empty.');
    }

    String? sessionid;
    String? sidTt;

    if (_isJsonFormat(trimmed)) {
      final credentials = _parseJson(trimmed);
      sessionid = credentials.$1;
      sidTt = credentials.$2;
    } else {
      final credentials = _parseTextLinesOrHeader(trimmed);
      sessionid = credentials.$1;
      sidTt = credentials.$2;
    }

    final cleanSessionid = sessionid?.trim();
    final cleanSidTt = sidTt?.trim();

    if (cleanSessionid == null || cleanSessionid.isEmpty) {
      throw const FormatException(
        'Missing required TikTok session cookie: sessionid.',
      );
    }

    if (cleanSessionid.length > _maxCredentialLength) {
      throw const FormatException(
        'sessionid cookie exceeds maximum allowed length.',
      );
    }

    if (cleanSidTt != null && cleanSidTt.length > _maxCredentialLength) {
      throw const FormatException(
        'sid_tt cookie exceeds maximum allowed length.',
      );
    }

    return TikTokCookieCredentials(
      sessionid: cleanSessionid,
      sidTt: (cleanSidTt != null && cleanSidTt.isNotEmpty) ? cleanSidTt : null,
    );
  }

  /// Attempts to parse [rawInput], returning `null` on failure rather than throwing.
  static TikTokCookieCredentials? tryParse(String? rawInput) {
    if (rawInput == null || rawInput.trim().isEmpty) {
      return null;
    }
    try {
      return parse(rawInput);
    } catch (_) {
      return null;
    }
  }

  static bool _isJsonFormat(String text) {
    return text.startsWith('[') && text.endsWith(']');
  }

  static (String?, String?) _parseJson(String jsonText) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw const FormatException('Invalid JSON cookie format.');
    }

    if (decoded is! List) {
      throw const FormatException('JSON cookie export must be an array.');
    }

    String? sessionid;
    String? sessionidSs;
    String? sidTt;

    for (final item in decoded) {
      if (item is! Map) continue;

      final domain = _findCaseInsensitive(item, 'domain')?.toString();
      final name = _findCaseInsensitive(item, 'name')?.toString().trim();
      final value = _findCaseInsensitive(item, 'value')?.toString().trim();

      if (name == null || value == null || value.isEmpty) continue;

      // If domain is specified, enforce TikTok domain boundary
      if (domain != null && domain.trim().isNotEmpty) {
        if (!_isAllowedDomain(domain)) {
          continue;
        }
      }

      if (name == 'sessionid') {
        sessionid = _stripQuotes(value);
      } else if (name == 'sessionid_ss') {
        sessionidSs = _stripQuotes(value);
      } else if (name == 'sid_tt') {
        sidTt = _stripQuotes(value);
      }
    }

    return (sessionid ?? sessionidSs, sidTt);
  }

  static (String?, String?) _parseTextLinesOrHeader(String text) {
    String? sessionid;
    String? sessionidSs;
    String? sidTt;

    final lines = const LineSplitter().convert(text);

    // If it's a single line without tabs, it could be a raw Cookie header: "sessionid=...; sid_tt=..."
    if (lines.length == 1 && !lines.first.contains('\t')) {
      return _parseCookieHeader(lines.first);
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Handle standard comments vs Netscape #HttpOnly_ cookies
      if (line.startsWith('#')) {
        if (line.toLowerCase().startsWith('#httponly_')) {
          final strippedLine = line.substring('#httponly_'.length);
          final result = _parseNetscapeLine(strippedLine);
          if (result != null) {
            if (result.$1 == 'sessionid') sessionid = result.$2;
            if (result.$1 == 'sessionid_ss') sessionidSs = result.$2;
            if (result.$1 == 'sid_tt') sidTt = result.$2;
          }
        }
        continue;
      }

      // Check if line is Netscape format (tab-delimited)
      if (line.contains('\t')) {
        final result = _parseNetscapeLine(line);
        if (result != null) {
          if (result.$1 == 'sessionid') sessionid = result.$2;
          if (result.$1 == 'sessionid_ss') sessionidSs = result.$2;
          if (result.$1 == 'sid_tt') sidTt = result.$2;
        }
      } else if (line.contains('=')) {
        // Fallback: line might be a header or key=value pair
        final headerResult = _parseCookieHeader(line);
        if (headerResult.$1 != null) sessionid = headerResult.$1;
        if (headerResult.$2 != null) sidTt = headerResult.$2;
      }
    }

    return (sessionid ?? sessionidSs, sidTt);
  }

  static (String, String)? _parseNetscapeLine(String line) {
    final parts = line.split('\t');
    if (parts.length < 7) {
      return null;
    }

    final domain = parts[0].trim();
    final name = parts[5].trim();
    final value = parts.sublist(6).join('\t').trim();

    if (!_isAllowedDomain(domain)) {
      return null;
    }

    if (name == 'sessionid' || name == 'sessionid_ss' || name == 'sid_tt') {
      return (name, _stripQuotes(value));
    }

    return null;
  }

  static (String?, String?) _parseCookieHeader(String header) {
    String? sessionid;
    String? sessionidSs;
    String? sidTt;

    var sanitized = header.trim();
    if (sanitized.toLowerCase().startsWith('cookie:')) {
      sanitized = sanitized.substring('cookie:'.length).trim();
    }

    final pairs = sanitized.split(';');
    for (final pair in pairs) {
      final eqIndex = pair.indexOf('=');
      if (eqIndex == -1) continue;

      final name = pair.substring(0, eqIndex).trim();
      final value = pair.substring(eqIndex + 1).trim();

      if (name == 'sessionid') {
        sessionid = _stripQuotes(value);
      } else if (name == 'sessionid_ss') {
        sessionidSs = _stripQuotes(value);
      } else if (name == 'sid_tt') {
        sidTt = _stripQuotes(value);
      }
    }

    return (sessionid ?? sessionidSs, sidTt);
  }

  static bool _isAllowedDomain(String rawDomain) {
    var domain = rawDomain.trim().toLowerCase();
    if (domain.startsWith('#httponly_')) {
      domain = domain.substring('#httponly_'.length);
    }
    if (domain.startsWith('.')) {
      domain = domain.substring(1);
    }

    return domain == 'tiktok.com' || domain.endsWith('.tiktok.com');
  }

  static dynamic _findCaseInsensitive(Map map, String targetKey) {
    for (final entry in map.entries) {
      if (entry.key.toString().toLowerCase() == targetKey.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  static String _stripQuotes(String value) {
    var trimmed = value.trim();
    if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }
}
