import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_preferences.dart';
import '../services/download_preferences_service.dart';

final downloadPreferencesServiceProvider = Provider<DownloadPreferencesService>(
  (_) => DownloadPreferencesService(),
);

final downloadPreferencesProvider =
    AsyncNotifierProvider<DownloadPreferencesController, DownloadPreferences>(
  DownloadPreferencesController.new,
);

class DownloadPreferencesController extends AsyncNotifier<DownloadPreferences> {
  @override
  Future<DownloadPreferences> build() {
    return ref.read(downloadPreferencesServiceProvider).load();
  }

  Future<void> setVideoQuality(VideoQualityPreference videoQuality) {
    return _save(_currentPreferences.copyWith(videoQuality: videoQuality));
  }

  Future<void> setAudio(AudioPreference audio) {
    return _save(_currentPreferences.copyWith(audio: audio));
  }

  DownloadPreferences get _currentPreferences {
    return state.valueOrNull ?? const DownloadPreferences();
  }

  Future<void> _save(DownloadPreferences preferences) async {
    state = AsyncData(preferences);
    try {
      await ref.read(downloadPreferencesServiceProvider).save(preferences);
    } catch (_) {
      // Keep the selected in-session preference when local storage is unavailable.
    }
  }
}
