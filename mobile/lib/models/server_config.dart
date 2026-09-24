import '../core/config/app_config.dart';

/// Represents the active backend server connection configuration.
class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.port,
    this.isCustomOverride = false,
    this.scheme = 'http',
    this.wsScheme = 'ws',
  });

  /// Hostname or IPv4 address of the backend server.
  final String host;

  /// Port on which the backend server is listening.
  final int port;

  /// Whether this configuration is an active user override rather than compile-time default.
  final bool isCustomOverride;

  /// HTTP scheme ('http' or 'https').
  final String scheme;

  /// WebSocket scheme ('ws' or 'wss').
  final String wsScheme;

  /// Full HTTP base URL for REST API requests (e.g. 'http://192.168.1.15:8000').
  String get apiBaseUrl => '$scheme://$host:$port';

  /// Full WebSocket base URL for realtime progress updates (e.g. 'ws://192.168.1.15:8000').
  String get webSocketBaseUrl => '$wsScheme://$host:$port';

  /// Constructs a [ServerConfig] based on the compile-time [AppConfig].
  factory ServerConfig.fromDefault() {
    final parsedUri = Uri.tryParse(AppConfig.apiBaseUrl);
    final scheme = parsedUri?.scheme.isNotEmpty == true ? parsedUri!.scheme : 'http';
    final host = parsedUri?.host.isNotEmpty == true ? parsedUri!.host : '127.0.0.1';
    final port = parsedUri?.hasPort == true ? parsedUri!.port : 8000;
    final wsScheme = scheme == 'https' ? 'wss' : 'ws';

    return ServerConfig(
      host: host,
      port: port,
      isCustomOverride: false,
      scheme: scheme,
      wsScheme: wsScheme,
    );
  }

  ServerConfig copyWith({
    String? host,
    int? port,
    bool? isCustomOverride,
    String? scheme,
    String? wsScheme,
  }) {
    return ServerConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      isCustomOverride: isCustomOverride ?? this.isCustomOverride,
      scheme: scheme ?? this.scheme,
      wsScheme: wsScheme ?? this.wsScheme,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerConfig &&
        other.host == host &&
        other.port == port &&
        other.isCustomOverride == isCustomOverride &&
        other.scheme == scheme &&
        other.wsScheme == wsScheme;
  }

  @override
  int get hashCode => Object.hash(host, port, isCustomOverride, scheme, wsScheme);

  @override
  String toString() =>
      'ServerConfig(host: $host, port: $port, isCustomOverride: $isCustomOverride, apiBaseUrl: $apiBaseUrl)';
}
