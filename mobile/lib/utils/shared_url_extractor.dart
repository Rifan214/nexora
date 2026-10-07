class SharedUrlExtractor {
  const SharedUrlExtractor._();

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  /// Extracts the first valid HTTP or HTTPS URL from [rawText].
  ///
  /// Returns `null` if [rawText] is null, blank, does not contain an HTTP/HTTPS URL,
  /// or if the matched URL candidate is malformed or lacks a valid host.
  static String? extractUrl(String? rawText) {
    if (rawText == null) {
      return null;
    }

    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final match = _urlRegex.firstMatch(trimmed);
    if (match == null) {
      return null;
    }

    var candidate = match.group(0)!;

    // Strip trailing punctuation commonly attached from sentence endings or brackets
    while (candidate.isNotEmpty) {
      final lastChar = candidate[candidate.length - 1];
      if (lastChar == '.' ||
          lastChar == ',' ||
          lastChar == ';' ||
          lastChar == '!' ||
          lastChar == '>' ||
          lastChar == ']') {
        candidate = candidate.substring(0, candidate.length - 1);
      } else if (lastChar == ')') {
        // Strip closing parenthesis only if there is no opening parenthesis in the candidate
        if (!candidate.contains('(')) {
          candidate = candidate.substring(0, candidate.length - 1);
        } else {
          break;
        }
      } else {
        break;
      }
    }

    if (candidate.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }

    return candidate;
  }
}
