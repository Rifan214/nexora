import 'dart:io';

/// Result of validating a server address and port input.
class ServerValidationResult {
  const ServerValidationResult._({
    required this.isValid,
    this.cleanHost,
    this.cleanPort,
    this.errorMessage,
  });

  const ServerValidationResult.success({
    required String host,
    required int port,
  }) : this._(
          isValid: true,
          cleanHost: host,
          cleanPort: port,
        );

  const ServerValidationResult.failure(String message)
      : this._(
          isValid: false,
          errorMessage: message,
        );

  final bool isValid;
  final String? cleanHost;
  final int? cleanPort;
  final String? errorMessage;
}

/// Validates host, IP address, and port inputs for development server override.
abstract final class ServerUrlValidator {
  static final _hostnameRegex = RegExp(
    r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$',
  );

  /// Validates [rawHost] and optional [rawPort].
  ///
  /// Supports:
  /// - IPv4 addresses (e.g. `192.168.1.15`, `10.0.2.2`)
  /// - Hostnames and local names (e.g. `localhost`, `my-laptop.local`)
  ///
  /// Limitation:
  /// - IPv6 is not currently supported for development server override.
  static ServerValidationResult validate({
    required String rawHost,
    String? rawPort,
    int defaultPort = 8000,
  }) {
    var trimmedHost = rawHost.trim();

    if (trimmedHost.isEmpty) {
      return const ServerValidationResult.failure(
        'Server address cannot be empty.',
      );
    }

    // Strip accidental leading scheme to avoid "http://http://..."
    if (trimmedHost.toLowerCase().startsWith('http://')) {
      trimmedHost = trimmedHost.substring(7);
    } else if (trimmedHost.toLowerCase().startsWith('https://')) {
      trimmedHost = trimmedHost.substring(8);
    }

    // Strip trailing slashes
    while (trimmedHost.endsWith('/')) {
      trimmedHost = trimmedHost.substring(0, trimmedHost.length - 1);
    }

    // Strip trailing path if user accidentally pasted URL path
    final slashIndex = trimmedHost.indexOf('/');
    if (slashIndex != -1) {
      trimmedHost = trimmedHost.substring(0, slashIndex);
    }

    int port = defaultPort;

    // Handle host:port syntax in the host field
    if (trimmedHost.contains(':') && !trimmedHost.startsWith('[')) {
      final parts = trimmedHost.split(':');
      if (parts.length == 2) {
        trimmedHost = parts[0];
        final inlinePort = int.tryParse(parts[1]);
        if (inlinePort == null || inlinePort < 1 || inlinePort > 65535) {
          return const ServerValidationResult.failure(
            'Port must be a valid number between 1 and 65535.',
          );
        }
        port = inlinePort;
      }
    }

    // If explicit port string was provided, it takes precedence
    if (rawPort != null && rawPort.trim().isNotEmpty) {
      final parsedPort = int.tryParse(rawPort.trim());
      if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
        return const ServerValidationResult.failure(
          'Port must be a valid number between 1 and 65535.',
        );
      }
      port = parsedPort;
    }

    // Check for IPv6 limitation
    if (trimmedHost.contains(':') ||
        (InternetAddress.tryParse(trimmedHost)?.type ==
            InternetAddressType.IPv6)) {
      return const ServerValidationResult.failure(
        'IPv6 addresses are not supported. Please use an IPv4 address or hostname.',
      );
    }

    // If the host is all digits and dots (like an IP address), it must be a valid IPv4 address
    final isNumericDotPattern = RegExp(r'^[\d.]+$').hasMatch(trimmedHost);
    if (isNumericDotPattern) {
      final internetAddress = InternetAddress.tryParse(trimmedHost);
      if (internetAddress != null &&
          internetAddress.type == InternetAddressType.IPv4) {
        return ServerValidationResult.success(
          host: trimmedHost,
          port: port,
        );
      }
      return const ServerValidationResult.failure(
        'Invalid server address. Each octet of IPv4 must be between 0 and 255.',
      );
    }

    // Validate hostname (cannot be all-numeric TLD)
    if (_hostnameRegex.hasMatch(trimmedHost)) {
      return ServerValidationResult.success(
        host: trimmedHost,
        port: port,
      );
    }

    return const ServerValidationResult.failure(
      'Invalid server address. Enter a valid IPv4 address (e.g. 192.168.1.15) or hostname.',
    );
  }
}
