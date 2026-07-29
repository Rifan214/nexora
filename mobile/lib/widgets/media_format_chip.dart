import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

class MediaFormatChip extends StatelessWidget {
  const MediaFormatChip({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.isSelected,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final String primaryLabel;
  final String? secondaryLabel;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secondaryLabel = this.secondaryLabel;

    return ChoiceChip(
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayFormatLabel(primaryLabel),
            style: textTheme.bodyLarge?.copyWith(
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (secondaryLabel != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              secondaryLabel,
              style: textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? colorScheme.onPrimary.withAlpha(184)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      selected: isSelected,
      onSelected: enabled ? (_) => onSelected() : null,
      showCheckmark: isSelected,
      checkmarkColor: colorScheme.onPrimary,
      selectedColor: colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainer,
      disabledColor: colorScheme.surfaceContainerHigh,
      side: BorderSide(
        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
        width: isSelected ? 2 : 1,
      ),
      elevation: isSelected ? 2 : 0,
      pressElevation: 4,
      selectedShadowColor: colorScheme.primary.withAlpha(72),
      shape: const StadiumBorder(),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
    );
  }
}

String? formatEstimatedFilesize(int? filesize) {
  if (filesize == null || filesize <= 0) {
    return null;
  }

  const bytesPerMegabyte = 1024 * 1024;
  final megabytes = filesize / bytesPerMegabyte;
  return megabytes >= 100
      ? '~ ${megabytes.round()} MB'
      : '~ ${megabytes.toStringAsFixed(1)} MB';
}

String displayFormatLabel(String label) {
  return label.trim().toLowerCase() == 'best' ? 'Best Available' : label;
}
