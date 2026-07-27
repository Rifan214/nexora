import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

SnackBar buildNexoraFloatingNotification(
  BuildContext context, {
  required String title,
  String? message,
  String? semanticLabel,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final notificationMessage = message?.trim();
  final hasMessage =
      notificationMessage != null && notificationMessage.isNotEmpty;

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
    margin: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    padding: const EdgeInsets.all(AppSpacing.sm),
    backgroundColor: colorScheme.surfaceContainerHigh,
    elevation: 2,
    shape: const RoundedRectangleBorder(borderRadius: AppRadii.input),
    content: Semantics(
      liveRegion: true,
      label: semanticLabel ?? (hasMessage ? '$title $notificationMessage' : title),
      excludeSemantics: true,
      child: Row(
        children: [
          Container(
            width: AppSizes.touchTarget,
            height: AppSizes.touchTarget,
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: AppRadii.input,
            ),
            child: Icon(
              Icons.check_rounded,
              color: colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (hasMessage ? textTheme.labelMedium : textTheme.titleMedium)
                      ?.copyWith(
                        color: hasMessage
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurface,
                        fontWeight: hasMessage ? FontWeight.w600 : null,
                      ),
                ),
                if (hasMessage) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    notificationMessage!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
