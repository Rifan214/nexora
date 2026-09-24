import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config.dart';
import '../services/server_config_service.dart';

final serverConfigServiceProvider = Provider<ServerConfigService>(
  (_) => ServerConfigService(),
);

final serverConfigProvider =
    AsyncNotifierProvider<ServerConfigController, ServerConfig>(
  ServerConfigController.new,
);

/// Synchronously provides the currently active [ServerConfig].
/// Falls back to compile-time [ServerConfig.fromDefault] while loading.
final effectiveServerConfigProvider = Provider<ServerConfig>((ref) {
  final asyncConfig = ref.watch(serverConfigProvider);
  return asyncConfig.valueOrNull ?? ServerConfig.fromDefault();
});

class ServerConfigController extends AsyncNotifier<ServerConfig> {
  @override
  Future<ServerConfig> build() {
    return ref.read(serverConfigServiceProvider).load();
  }

  ServerConfig get currentConfig {
    return state.valueOrNull ?? ServerConfig.fromDefault();
  }

  Future<void> setOverride({
    required String host,
    required int port,
  }) async {
    final current = currentConfig;
    final updated = current.copyWith(
      host: host.trim(),
      port: port,
      isCustomOverride: true,
    );

    state = AsyncData(updated);
    try {
      await ref.read(serverConfigServiceProvider).saveOverride(
            host: host.trim(),
            port: port,
          );
    } catch (_) {
      // In-memory override remains active even if disk write fails
    }
  }

  Future<void> resetToDefault() async {
    final defaultConfig = ServerConfig.fromDefault();
    state = AsyncData(defaultConfig);
    try {
      await ref.read(serverConfigServiceProvider).resetToDefault();
    } catch (_) {
      // In-memory reset remains active even if disk write fails
    }
  }

  Future<ServerConnectionTestResult> testConnection({
    required String host,
    required int port,
  }) {
    final defaultCfg = ServerConfig.fromDefault();
    final candidateUrl = '${defaultCfg.scheme}://${host.trim()}:$port';
    return ref.read(serverConfigServiceProvider).testConnection(candidateUrl);
  }
}
