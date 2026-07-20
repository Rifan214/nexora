import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/health_check_result.dart';
import '../repositories/health_repository.dart';

final healthProvider = AsyncNotifierProvider<HealthController, HealthCheckResult?>(
  HealthController.new,
);

class HealthController extends AsyncNotifier<HealthCheckResult?> {
  @override
  FutureOr<HealthCheckResult?> build() {
    return null;
  }

  Future<void> checkBackend() async {
    state = const AsyncValue.loading();

    try {
      final result = await ref.read(healthRepositoryProvider).checkHealth();
      state = AsyncValue.data(result);
    } on ApiException catch (error, stackTrace) {
      state = AsyncValue.error(error.message, stackTrace);
    } catch (_, stackTrace) {
      state = AsyncValue.error('Unable to contact the backend.', stackTrace);
    }
  }
}
