import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

enum NexoraStateTone {
  neutral,
  success,
  error,
}

class NexoraStatePanel extends StatelessWidget {
  const NexoraStatePanel({
    super.key,
    required this.title,
    required this.message,
    this.tone = NexoraStateTone.neutral,
    this.icon,
    this.isLoading = false,
  });

  final String title;
  final String message;
  final NexoraStateTone tone;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = _panelColors(Theme.of(context).colorScheme);

    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: '$title. $message',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: AppSizes.touchTarget,
                  height: AppSizes.touchTarget,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: AppRadii.input,
                  ),
                  child: Center(
                    child: isLoading
                        ? SizedBox(
                            width: AppSpacing.xl,
                            height: AppSpacing.xl,
                            child: CircularProgressIndicator(
                              color: colors.foreground,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Icon(
                            icon ?? _defaultIcon(),
                            color: colors.foreground,
                            size: AppSpacing.xl,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      message,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _defaultIcon() {
    switch (tone) {
      case NexoraStateTone.neutral:
        return Icons.info_outline_rounded;
      case NexoraStateTone.success:
        return Icons.check_circle_outline_rounded;
      case NexoraStateTone.error:
        return Icons.error_outline_rounded;
    }
  }

  _PanelColors _panelColors(ColorScheme colorScheme) {
    switch (tone) {
      case NexoraStateTone.neutral:
        return _PanelColors(
          background: colorScheme.surfaceContainerHigh,
          foreground: colorScheme.primary,
        );
      case NexoraStateTone.success:
        return _PanelColors(
          background: colorScheme.tertiaryContainer,
          foreground: colorScheme.onTertiaryContainer,
        );
      case NexoraStateTone.error:
        return _PanelColors(
          background: colorScheme.errorContainer,
          foreground: colorScheme.onErrorContainer,
        );
    }
  }
}

class _PanelColors {
  const _PanelColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
