import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Parsed X/Twitter authentication credentials extracted from imported cookies.
///
/// Guaranteed to never expose secret token values via [toString].
@immutable
class XCookieCredentials {
  const XCookieCredentials({
    required this.authToken,
    required this.ct0,
  });

  /// The `auth_token` cookie value.
  final String authToken;

  /// The `ct0` CSRF token cookie value.
  final String ct0;

  /// Whether both credentials are non-empty after trimming.
  bool get isValid => authToken.trim().isNotEmpty && ct0.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XCookieCredentials &&
          runtimeType == other.runtimeType &&
          authToken == other.authToken &&
          ct0 == other.ct0;

  @override
  int get hashCode => Object.hash(authToken, ct0);

  @override
  String toString() => 'XCookieCredentials([PROTECTED])';
}

/// Pure Dart parser for extracting official X/Twitter session cookies.
///
/// Supports:
/// 1. Netscape `cookies.txt` (including `#HttpOnly_` lines)
/// 2. JSON cookie export (array of cookie objects)
/// 3. Raw HTTP `Cookie` header string
///
/// Strictly extracts ONLY `auth_token` and `ct0` from allowed X/Twitter domains
/// (`x.com`, `*.x.com`, `twitter.com`, `*.twitter.com`). Discards all other cookies.
abstract final class XCookieParser {
  static const int _maxCredentialLength = 512;

  /// Parses the [rawInput] string and returns validated [XCookieCredentials].
  ///
  /// Throws [FormatException] if either required cookie is missing, empty,
  /// or exceeds maximum allowed length. Never leaks credential values in error messages.
  static XCookieCredentials parse(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Cookie input cannot be empty.');
    }

    String? authToken;
    String? ct0;

    if (_isJsonFormat(trimmed)) {
      final credentials = _parseJson(trimmed);
      authToken = credentials.$1;
      ct0 = credentials.$2;
    } else {
      final credentials = _parseTextLinesOrHeader(trimmed);
      authToken = credentials.$1;
      ct0 = credentials.$2;
    }

    final cleanAuthToken = authToken?.trim();
    final cleanCt0 = ct0?.trim();

    if (cleanAuthToken == null || cleanAuthToken.isEmpty) {
      throw const FormatException(
        'Missing required X session cookie: auth_token.',
      );
    }

    if (cleanCt0 == null || cleanCt0.isEmpty) {
      throw const FormatException(
        'Missing required X session cookie: ct0.',
      );
    }

    if (cleanAuthToken.length > _maxCredentialLength) {
      throw const FormatException(
        'auth_token cookie exceeds maximum allowed length.',
      );
    }

    if (cleanCt0.length > _maxCredentialLength) {
      throw const FormatException(
        'ct0 cookie exceeds maximum allowed length.',
      );
    }

    return XCookieCredentials(
      authToken: cleanAuthToken,
      ct0: cleanCt0,
    );
  }

  /// Attempts to parse [rawInput], returning `null` on failure rather than throwing.
  static XCookieCredentials? tryParse(String? rawInput) {
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

    String? authToken;
    String? ct0;

    for (final item in decoded) {
      if (item is! Map) continue;

      final domain = _findCaseInsensitive(item, 'domain')?.toString();
      final name = _findCaseInsensitive(item, 'name')?.toString().trim();
      final value = _findCaseInsensitive(item, 'value')?.toString().trim();

      if (name == null || value == null || value.isEmpty) continue;

      // If domain is specified, enforce X/Twitter domain boundary
      if (domain != null && domain.trim().isNotEmpty) {
        if (!_isAllowedDomain(domain)) {
          continue;
        }
      }

      if (name == 'auth_token') {
        authToken = _stripQuotes(value);
      } else if (name == 'ct0') {
        ct0 = _stripQuotes(value);
      }
    }

    return (authToken, ct0);
  }

  static (String?, String?) _parseTextLinesOrHeader(String text) {
    String? authToken;
    String? ct0;

    final lines = const LineSplitter().convert(text);

    // If it's a single line without tabs, it could be a raw Cookie header: "auth_token=...; ct0=..."
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
            if (result.$1 == 'auth_token') authToken = result.$2;
            if (result.$1 == 'ct0') ct0 = result.$2;
          }
        }
        continue;
      }

      // Check if line is Netscape format (tab-delimited)
      if (line.contains('\t')) {
        final result = _parseNetscapeLine(line);
        if (result != null) {
          if (result.$1 == 'auth_token') authToken = result.$2;
          if (result.$1 == 'ct0') ct0 = result.$2;
        }
      } else if (line.contains('=')) {
        // Fallback: line might be a header or key=value pair
        final headerResult = _parseCookieHeader(line);
        if (headerResult.$1 != null) authToken = headerResult.$1;
        if (headerResult.$2 != null) ct0 = headerResult.$2;
      }
    }

    return (authToken, ct0);
  }

  static (String, String)? _parseNetscapeLine(String line) {
    final parts = line.split('\t');
    if (parts.length < 7) {
      return null;
    }

    final domain = parts[0].trim();
    final name = parts[5].trim();
    // Cookie value may contain tabs if malformed, join from 6th index
    final value = parts.sublist(6).join('\t').trim();

    if (!_isAllowedDomain(domain)) {
      return null;
    }

    if (name == 'auth_token' || name == 'ct0') {
      return (name, _stripQuotes(value));
    }

    return null;
  }

  static (String?, String?) _parseCookieHeader(String header) {
    String? authToken;
    String? ct0;

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

      if (name == 'auth_token') {
        authToken = _stripQuotes(value);
      } else if (name == 'ct0') {
        ct0 = _stripQuotes(value);
      }
    }

    return (authToken, ct0);
  }

  static bool _isAllowedDomain(String rawDomain) {
    var domain = rawDomain.trim().toLowerCase();
    if (domain.startsWith('#httponly_')) {
      domain = domain.substring('#httponly_'.length);
    }
    if (domain.startsWith('.')) {
      domain = domain.substring(1);
    }

    return domain == 'x.com' ||
        domain.endsWith('.x.com') ||
        domain == 'twitter.com' ||
        domain.endsWith('.twitter.com');
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
