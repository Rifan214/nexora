abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'NEXORA_API_BASE_URL',
  );

  static const webSocketBaseUrl = String.fromEnvironment(
    'NEXORA_WS_BASE_URL',
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
