import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_preferences.dart';

class DownloadPreferencesService {
  static const _videoQualityKey = 'download_preferences.video_quality';
  static const _audioKey = 'download_preferences.audio';

  Future<DownloadPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    return DownloadPreferences(
      videoQuality: VideoQualityPreference.fromStorage(
        preferences.getString(_videoQualityKey),
      ),
      audio: AudioPreference.fromStorage(preferences.getString(_audioKey)),
    );
  }

  Future<void> save(DownloadPreferences preferences) async {
    final storage = await SharedPreferences.getInstance();
    await Future.wait([
      storage.setString(_videoQualityKey, preferences.videoQuality.storageValue),
      storage.setString(_audioKey, preferences.audio.storageValue),
    ]);
  }
}
