import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/health_check_result.dart';
import '../providers/health_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const routeName = 'home';
  static const routePath = '/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final healthState = ref.watch(healthProvider);
    final isLoading = healthState.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Nexora',
                  style: textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          ref.read(healthProvider.notifier).checkBackend();
                        },
                  child: Text(isLoading ? 'Checking...' : 'Check Backend'),
                ),
                const SizedBox(height: 16),
                _HealthStatus(healthState: healthState),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthStatus extends StatelessWidget {
  const _HealthStatus({required this.healthState});

  final AsyncValue<HealthCheckResult?> healthState;

  @override
  Widget build(BuildContext context) {
    return healthState.when(
      data: (result) {
        if (result == null) {
          return const SizedBox.shrink();
        }

        return _StatusMessage(
          title: result.isHealthy ? '\u2705 Backend Online' : '\u274C Backend Offline',
          message: result.serverMessage,
        );
      },
      error: (error, _) {
        return _StatusMessage(
          title: '\u274C Backend Offline',
          message: error.toString(),
        );
      },
      loading: () {
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      },
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
