import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../models/download_preferences.dart';
import '../providers/download_preferences_provider.dart';
import '../widgets/nexora_state_panel.dart';

class DownloadPreferencesPage extends ConsumerWidget {
  const DownloadPreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencesState = ref.watch(downloadPreferencesProvider);
    final controller = ref.read(downloadPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Download Preferences')),
      body: preferencesState.when(
        data: (preferences) => _PreferencesContent(
          preferences: preferences,
          onVideoQualityChanged: (value) {
            controller.setVideoQuality(value);
          },
          onAudioChanged: (value) {
            controller.setAudio(value);
          },
        ),
        loading: () => const NexoraStatePanel(
          title: 'Loading preferences',
          message: 'Loading preferences saved on this device.',
          isLoading: true,
        ),
        error: (_, __) => _PreferencesContent(
          preferences: const DownloadPreferences(),
          onVideoQualityChanged: (value) {
            controller.setVideoQuality(value);
          },
          onAudioChanged: (value) {
            controller.setAudio(value);
          },
        ),
      ),
    );
  }
}

class _PreferencesContent extends StatelessWidget {
  const _PreferencesContent({
    required this.preferences,
    required this.onVideoQualityChanged,
    required this.onAudioChanged,
  });

  final DownloadPreferences preferences;
  final ValueChanged<VideoQualityPreference> onVideoQualityChanged;
  final ValueChanged<AudioPreference> onAudioChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: AppSpacing.pageHorizontal,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text('Video default quality', style: textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Preferred video quality used when available.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: RadioGroup<VideoQualityPreference>(
            groupValue: preferences.videoQuality,
            onChanged: (value) {
              if (value != null) {
                onVideoQualityChanged(value);
              }
            },
            child: Column(
              children: [
                for (final preference in VideoQualityPreference.values)
                  RadioListTile<VideoQualityPreference>(
                    value: preference,
                    title: Text(preference.label),
                    subtitle: preference == VideoQualityPreference.askEveryTime
                        ? const Text('Choose a format for each download.')
                        : null,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('Audio default', style: textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Preferred audio format used when no video quality is configured.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: RadioGroup<AudioPreference>(
            groupValue: preferences.audio,
            onChanged: (value) {
              if (value != null) {
                onAudioChanged(value);
              }
            },
            child: Column(
              children: [
                for (final preference in AudioPreference.values)
                  RadioListTile<AudioPreference>(
                    value: preference,
                    title: Text(preference.label),
                    subtitle: preference == AudioPreference.askEveryTime
                        ? const Text('Choose an audio format for each download.')
                        : const Text('Use MP3 when audio is the default output.'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}
