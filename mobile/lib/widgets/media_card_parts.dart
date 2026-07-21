import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../models/media_download_type.dart';
import '../models/media_metadata.dart';

enum MediaBadgeTone {
  primary,
  neutral,
  success,
}

class NexoraMediaThumbnail extends StatelessWidget {
  const NexoraMediaThumbnail({
    super.key,
    required this.metadata,
    required this.mediaType,
    this.aspectRatio = 1.7777777777777777,
  });

  final MediaMetadata metadata;
  final MediaDownloadType? mediaType;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final thumbnailUrl = metadata.thumbnailUrl?.trim();
    final isAudio = mediaType == MediaDownloadType.audio;

    return ClipRRect(
      borderRadius: AppRadii.input,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailUrl == null || thumbnailUrl.isEmpty)
              _MediaThumbnailPlaceholder(isAudio: isAudio)
            else
              Image.network(
                thumbnailUrl,
                fit: BoxFit.cover,
                semanticLabel: metadata.title,
                errorBuilder: (_, __, ___) {
                  return _MediaThumbnailPlaceholder(isAudio: isAudio);
                },
              ),
            if (metadata.durationSeconds != null)
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.inverseSurface.withAlpha(224),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Text(
                    _formatMediaDuration(metadata.durationSeconds!),
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onInverseSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MediaBadge extends StatelessWidget {
  const MediaBadge({
    super.key,
    required this.label,
    this.tone = MediaBadgeTone.primary,
    this.icon,
  });

  final String label;
  final MediaBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foregroundColor = _foregroundColor(colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor(colorScheme),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: foregroundColor, size: AppSpacing.md),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _backgroundColor(ColorScheme colorScheme) {
    switch (tone) {
      case MediaBadgeTone.primary:
        return colorScheme.secondaryContainer;
      case MediaBadgeTone.neutral:
        return colorScheme.surfaceContainerHigh;
      case MediaBadgeTone.success:
        return colorScheme.tertiaryContainer;
    }
  }

  Color _foregroundColor(ColorScheme colorScheme) {
    switch (tone) {
      case MediaBadgeTone.primary:
        return colorScheme.onSecondaryContainer;
      case MediaBadgeTone.neutral:
        return colorScheme.onSurfaceVariant;
      case MediaBadgeTone.success:
        return colorScheme.onTertiaryContainer;
    }
  }
}

class _MediaThumbnailPlaceholder extends StatelessWidget {
  const _MediaThumbnailPlaceholder({required this.isAudio});

  final bool isAudio;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          isAudio
              ? Icons.audio_file_outlined
              : Icons.image_not_supported_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 40,
        ),
      ),
    );
  }
}

String _formatMediaDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final remainingSeconds =
      duration.inSeconds.remainder(60).toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$minutes:$remainingSeconds';
  }

  return '${duration.inMinutes}:$remainingSeconds';
}
