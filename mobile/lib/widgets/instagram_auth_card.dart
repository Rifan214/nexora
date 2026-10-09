import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../providers/instagram_auth_provider.dart';
import 'instagram_manual_cookie_dialog.dart';

/// Settings card displaying Instagram authentication status and management controls.
class InstagramAuthCard extends ConsumerWidget {
  const InstagramAuthCard({super.key});

  String _formatRemainingDuration(Duration remaining) {
    if (remaining.inSeconds <= 0) {
      return 'Expired';
    }
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    if (hours > 0) {
      return 'Expires in ${hours}h ${minutes}m';
    }
    return 'Expires in ${minutes}m';
  }

  Future<void> _handleManualImport(BuildContext context) async {
    await InstagramManualCookieDialog.show(context);
  }

  Future<void> _handleDisconnect(WidgetRef ref) async {
    await ref.read(instagramAuthProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final authState = ref.watch(instagramAuthProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row with Icon, Title, and Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: AppSizes.touchTarget + AppSpacing.xs,
                  height: AppSizes.touchTarget + AppSpacing.xs,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Instagram Account',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      _buildStatusBadge(context, authState),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Description / Details
            _buildDescription(context, authState),
            const SizedBox(height: AppSpacing.md),

            // Action Buttons
            _buildActionButtons(context, ref, authState),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, InstagramAuthState authState) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    Color backgroundColor;
    Color textColor;
    IconData icon;
    String label;

    if (authState.isRestoring || authState.isAuthenticating) {
      backgroundColor = colorScheme.surfaceContainerHighest;
      textColor = colorScheme.onSurfaceVariant;
      icon = Icons.sync_rounded;
      label = authState.isAuthenticating ? 'Connecting...' : 'Verifying...';
    } else if (authState.isAuthenticated) {
      backgroundColor = colorScheme.primaryContainer;
      textColor = colorScheme.onPrimaryContainer;
      icon = Icons.check_circle_rounded;
      label = 'Connected';
    } else if (authState.isExpired) {
      backgroundColor = colorScheme.errorContainer;
      textColor = colorScheme.onErrorContainer;
      icon = Icons.timer_off_outlined;
      label = 'Session Expired';
    } else {
      backgroundColor = colorScheme.surfaceContainerHighest;
      textColor = colorScheme.onSurfaceVariant;
      icon = Icons.person_outline_rounded;
      label = 'Guest / Not Connected';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadii.badge,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(BuildContext context, InstagramAuthState authState) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    if (authState.isAuthenticated && authState.session != null) {
      final session = authState.session!;
      final expiryText = _formatRemainingDuration(session.remainingDuration);
      return Text(
        'Connected via ephemeral session. $expiryText. Used to download login-required, private, and empty-media Instagram posts/reels.',
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (authState.isExpired) {
      return Text(
        'Your previous Instagram session has expired. Reconnect your account to continue accessing login-required and private posts.',
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Text(
      'Download public Instagram posts freely without login. Connect your account to enable downloads for login-required, private, or age-restricted posts.',
      style: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    InstagramAuthState authState,
  ) {
    if (authState.isRestoring || authState.isAuthenticating) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (authState.isAuthenticated) {
      return OutlinedButton.icon(
        onPressed: () => _handleDisconnect(ref),
        icon: const Icon(Icons.link_off_rounded),
        label: const Text('Disconnect'),
      );
    }

    if (authState.isExpired) {
      return FilledButton.icon(
        onPressed: () => _handleManualImport(context),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Reconnect Instagram Session'),
      );
    }

    return FilledButton.icon(
      onPressed: () => _handleManualImport(context),
      icon: const Icon(Icons.key_rounded),
      label: const Text('Import Instagram Session'),
    );
  }
}
