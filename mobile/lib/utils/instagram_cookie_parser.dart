import 'dart:convert';

import '../models/instagram_auth_session.dart';

/// Pure Dart parser for extracting official Instagram session cookies.
///
/// Supports:
/// 1. Netscape `cookies.txt` (including `#HttpOnly_` lines)
/// 2. JSON cookie export (array of cookie objects)
/// 3. Raw HTTP `Cookie` header string
///
/// Strictly extracts `sessionid` (required), and optional companion cookies:
/// `ds_user_id` and `csrftoken` from allowed Instagram domains (`instagram.com`, `*.instagram.com`).
/// Discards all other cookies.
abstract final class InstagramCookieParser {
  static const int _maxCredentialLength = 512;

  /// Parses the [rawInput] string and returns validated [InstagramCookieCredentials].
  ///
  /// Throws [FormatException] if sessionid cookie is missing, empty,
  /// or exceeds maximum allowed length. Never leaks credential values in error messages.
  static InstagramCookieCredentials parse(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Cookie input cannot be empty.');
    }

    String? sessionid;
    String? dsUserId;
    String? csrftoken;

    if (_isJsonFormat(trimmed)) {
      final credentials = _parseJson(trimmed);
      sessionid = credentials.$1;
      dsUserId = credentials.$2;
      csrftoken = credentials.$3;
    } else {
      final credentials = _parseTextLinesOrHeader(trimmed);
      sessionid = credentials.$1;
      dsUserId = credentials.$2;
      csrftoken = credentials.$3;
    }

    final cleanSessionid = sessionid?.trim();
    final cleanDsUserId = dsUserId?.trim();
    final cleanCsrftoken = csrftoken?.trim();

    if (cleanSessionid == null || cleanSessionid.isEmpty) {
      throw const FormatException(
        'Missing required Instagram session cookie: sessionid.',
      );
    }

    if (cleanSessionid.length > _maxCredentialLength) {
      throw const FormatException(
        'sessionid cookie exceeds maximum allowed length.',
      );
    }

    if (cleanDsUserId != null && cleanDsUserId.length > _maxCredentialLength) {
      throw const FormatException(
        'ds_user_id cookie exceeds maximum allowed length.',
      );
    }

    if (cleanCsrftoken != null && cleanCsrftoken.length > _maxCredentialLength) {
      throw const FormatException(
        'csrftoken cookie exceeds maximum allowed length.',
      );
    }

    return InstagramCookieCredentials(
      sessionid: cleanSessionid,
      dsUserId: (cleanDsUserId != null && cleanDsUserId.isNotEmpty) ? cleanDsUserId : null,
      csrftoken: (cleanCsrftoken != null && cleanCsrftoken.isNotEmpty) ? cleanCsrftoken : null,
    );
  }

  /// Attempts to parse [rawInput], returning `null` on failure rather than throwing.
  static InstagramCookieCredentials? tryParse(String? rawInput) {
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

  static (String?, String?, String?) _parseJson(String jsonText) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const FormatException('Invalid JSON cookie format.');
    }

    if (decoded is! List) {
      throw const FormatException('JSON cookie export must be a list of cookie objects.');
    }

    String? sessionid;
    String? dsUserId;
    String? csrftoken;

    for (final item in decoded) {
      if (item is! Map) continue;

      final domain = _findCaseInsensitive(item, 'domain')?.toString();
      if (domain != null && !_isAllowedDomain(domain)) {
        continue;
      }

      final name = _findCaseInsensitive(item, 'name')?.toString().trim().toLowerCase();
      final value = _findCaseInsensitive(item, 'value')?.toString().trim();

      if (name == null || value == null || value.isEmpty) continue;

      if (name == 'sessionid') {
        sessionid = _stripQuotes(value);
      } else if (name == 'ds_user_id') {
        dsUserId = _stripQuotes(value);
      } else if (name == 'csrftoken') {
        csrftoken = _stripQuotes(value);
      }
    }

    return (sessionid, dsUserId, csrftoken);
  }

  static (String?, String?, String?) _parseTextLinesOrHeader(String text) {
    final lines = text.split('\n');
    final isTabSeparated = lines.any((line) => line.contains('\t'));

    if (isTabSeparated) {
      return _parseNetscape(lines);
    }
    return _parseCookieHeader(text);
  }

  static (String?, String?, String?) _parseNetscape(List<String> lines) {
    String? sessionid;
    String? dsUserId;
    String? csrftoken;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') && !line.startsWith('#HttpOnly_')) {
        continue;
      }

      final parts = line.split('\t');
      if (parts.length < 7) {
        continue;
      }

      final domain = parts[0].trim();
      if (!_isAllowedDomain(domain)) {
        continue;
      }

      final name = parts[5].trim().toLowerCase();
      final value = parts[6].trim();

      if (name == 'sessionid') {
        sessionid = _stripQuotes(value);
      } else if (name == 'ds_user_id') {
        dsUserId = _stripQuotes(value);
      } else if (name == 'csrftoken') {
        csrftoken = _stripQuotes(value);
      }
    }

    return (sessionid, dsUserId, csrftoken);
  }

  static (String?, String?, String?) _parseCookieHeader(String headerText) {
    String? sessionid;
    String? dsUserId;
    String? csrftoken;

    final cleaned = headerText.replaceFirst(RegExp(r'^[Cc]ookie:\s*'), '');
    final pairs = cleaned.split(';');

    for (final pair in pairs) {
      final eqIdx = pair.indexOf('=');
      if (eqIdx == -1) continue;

      final name = pair.substring(0, eqIdx).trim().toLowerCase();
      final value = pair.substring(eqIdx + 1).trim();

      if (name == 'sessionid') {
        sessionid = _stripQuotes(value);
      } else if (name == 'ds_user_id') {
        dsUserId = _stripQuotes(value);
      } else if (name == 'csrftoken') {
        csrftoken = _stripQuotes(value);
      }
    }

    return (sessionid, dsUserId, csrftoken);
  }

  static bool _isAllowedDomain(String rawDomain) {
    var domain = rawDomain.trim().toLowerCase();
    if (domain.startsWith('#httponly_')) {
      domain = domain.substring('#httponly_'.length);
    }
    if (domain.startsWith('.')) {
      domain = domain.substring(1);
    }

    return domain == 'instagram.com' || domain.endsWith('.instagram.com');
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
