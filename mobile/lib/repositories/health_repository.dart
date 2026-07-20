import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_paths.dart';
import '../models/health_check_result.dart';
import '../services/api_service.dart';

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository(ref.watch(apiServiceProvider));
});

class HealthRepository {
  const HealthRepository(this._apiService);

  final ApiService _apiService;

  Future<HealthCheckResult> checkHealth() async {
    final response = await _apiService.getJson(ApiPaths.health);
    return HealthCheckResult.fromApiResponse(response);
  }
}
