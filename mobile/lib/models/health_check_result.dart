import '../core/network/api_exception.dart';

class HealthCheckResult {
  const HealthCheckResult({
    required this.serverMessage,
    required this.status,
    required this.environment,
  });

  final String serverMessage;
  final String status;
  final String environment;

  bool get isHealthy => status.toLowerCase() == 'healthy';

  factory HealthCheckResult.fromApiResponse(Map<String, dynamic> json) {
    final success = json['success'];
    final serverMessage = _readString(json['message']);

    if (success != true) {
      throw ApiException(
        serverMessage.isEmpty ? 'Backend health check failed.' : serverMessage,
      );
    }

    final data = json['data'];
    if (data is! Map) {
      throw const ApiException('Invalid response from server.');
    }

    final payload = Map<String, dynamic>.from(data);
    final status = _readString(payload['status']);
    final environment = _readString(payload['environment']);

    if (status.isEmpty) {
      throw const ApiException('Invalid response from server.');
    }

    return HealthCheckResult(
      serverMessage: serverMessage.isEmpty ? 'Request successful' : serverMessage,
      status: status,
      environment: environment,
    );
  }

  static String _readString(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }
}
