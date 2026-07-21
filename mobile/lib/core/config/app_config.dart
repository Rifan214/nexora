abstract final class AppConfig {
  static const _defaultApiBaseUrl = 'http://192.168.1.23:8000';
  static const _defaultWebSocketBaseUrl = 'ws://192.168.1.23:8000';

  static const apiBaseUrl = String.fromEnvironment(
    'NEXORA_API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  static const webSocketBaseUrl = String.fromEnvironment(
    'NEXORA_WS_BASE_URL',
    defaultValue: _defaultWebSocketBaseUrl,
  );

  static const connectTimeout = Duration(
    seconds: int.fromEnvironment(
      'NEXORA_CONNECT_TIMEOUT_SECONDS',
      defaultValue: 15,
    ),
  );

  static const receiveTimeout = Duration(
    seconds: int.fromEnvironment(
      'NEXORA_RECEIVE_TIMEOUT_SECONDS',
      defaultValue: 30,
    ),
  );

  static const sendTimeout = Duration(
    seconds: int.fromEnvironment(
      'NEXORA_SEND_TIMEOUT_SECONDS',
      defaultValue: 30,
    ),
  );
}
