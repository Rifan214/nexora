import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import 'nexora_brand.dart';

class SettingsContent extends StatelessWidget {
  const SettingsContent({super.key});

  static const _version = 'Version 0.1.0+1';
  static const _repository = 'github.com/Rifan214/nexora';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: AppSpacing.pageHorizontal,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.md),
              const Align(
                alignment: Alignment.centerLeft,
                child: NexoraBrand(),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Settings',
                style: textTheme.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Application information and platform support.',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const _SettingsInformationCard(
                icon: Icons.speed_rounded,
                title: 'Nexora',
                description: _version,
                tone: _SettingsIconTone.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              const _SettingsInformationCard(
                icon: Icons.info_outline_rounded,
                title: 'About Nexora',
                description:
                    'Paste a URL, choose an output, and save media to your device.',
                tone: _SettingsIconTone.neutral,
              ),
              const SizedBox(height: AppSpacing.md),
              const _SettingsInformationCard(
                icon: Icons.code_rounded,
                title: 'GitHub Repository',
                description: _repository,
                tone: _SettingsIconTone.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              const _FutureSupportCard(),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsInformationCard extends StatelessWidget {
  const _SettingsInformationCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String description;
  final _SettingsIconTone tone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final iconColors = _iconColors(colorScheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: AppSizes.touchTarget + AppSpacing.xs,
              height: AppSizes.touchTarget + AppSpacing.xs,
              decoration: BoxDecoration(
                color: iconColors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColors.foreground),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _IconColors _iconColors(ColorScheme colorScheme) {
    switch (tone) {
      case _SettingsIconTone.primary:
        return _IconColors(
          background: colorScheme.secondaryContainer,
          foreground: colorScheme.onSecondaryContainer,
        );
      case _SettingsIconTone.neutral:
        return _IconColors(
          background: colorScheme.surfaceContainerHigh,
          foreground: colorScheme.onSurfaceVariant,
        );
    }
  }
}

class _FutureSupportCard extends StatelessWidget {
  const _FutureSupportCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: AppSizes.touchTarget + AppSpacing.xs,
                  height: AppSizes.touchTarget + AppSpacing.xs,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.public_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Future Support',
                    style: textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.xs),
            const _PlatformSupportRow(
              platform: 'YouTube',
              isAvailable: true,
            ),
            const Divider(),
            const _PlatformSupportRow(platform: 'TikTok'),
            const Divider(),
            const _PlatformSupportRow(platform: 'Instagram'),
            const Divider(),
            const _PlatformSupportRow(platform: 'Facebook'),
            const Divider(),
            const _PlatformSupportRow(platform: 'X / Twitter'),
          ],
        ),
      ),
    );
  }
}

class _PlatformSupportRow extends StatelessWidget {
  const _PlatformSupportRow({
    required this.platform,
    this.isAvailable = false,
  });

  final String platform;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final color =
        isAvailable ? colorScheme.tertiary : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            isAvailable ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: color,
            size: AppSpacing.lg,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(platform, style: textTheme.bodyLarge),
          ),
          Text(
            isAvailable ? 'Available' : 'Coming Soon',
            style: textTheme.bodyMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

enum _SettingsIconTone {
  primary,
  neutral,
}

class _IconColors {
  const _IconColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
