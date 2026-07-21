import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

class NexoraBrand extends StatelessWidget {
  const NexoraBrand({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      header: true,
      label: 'Nexora',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed_rounded,
              color: colorScheme.primary,
              size: AppSizes.touchTarget - AppSpacing.xs,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Nexora',
              style: textTheme.headlineMedium?.copyWith(
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
