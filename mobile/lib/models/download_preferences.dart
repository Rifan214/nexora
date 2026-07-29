import 'media_download_type.dart';
import 'media_metadata.dart';

enum VideoQualityPreference {
  askEveryTime,
  bestAvailable,
  p2160,
  p1440,
  p1080,
  p720,
  p480;

  String get storageValue => name;

  String get label {
    return switch (this) {
      VideoQualityPreference.askEveryTime => 'Ask every time',
      VideoQualityPreference.bestAvailable => 'Best Available',
      VideoQualityPreference.p2160 => '2160p',
      VideoQualityPreference.p1440 => '1440p',
      VideoQualityPreference.p1080 => '1080p',
      VideoQualityPreference.p720 => '720p',
      VideoQualityPreference.p480 => '480p',
    };
  }

  int? get height {
    return switch (this) {
      VideoQualityPreference.p2160 => 2160,
      VideoQualityPreference.p1440 => 1440,
      VideoQualityPreference.p1080 => 1080,
      VideoQualityPreference.p720 => 720,
      VideoQualityPreference.p480 => 480,
      VideoQualityPreference.askEveryTime ||
      VideoQualityPreference.bestAvailable => null,
    };
  }

  static VideoQualityPreference fromStorage(String? value) {
    for (final preference in values) {
      if (preference.storageValue == value) {
        return preference;
      }
    }
    return VideoQualityPreference.askEveryTime;
  }
}

enum AudioPreference {
  askEveryTime,
  mp3;

  String get storageValue => name;

  String get label {
    return this == AudioPreference.mp3 ? 'MP3' : 'Ask every time';
  }

  static AudioPreference fromStorage(String? value) {
    for (final preference in values) {
      if (preference.storageValue == value) {
        return preference;
      }
    }
    return AudioPreference.askEveryTime;
  }
}

class DownloadPreferences {
  const DownloadPreferences({
    this.videoQuality = VideoQualityPreference.askEveryTime,
    this.audio = AudioPreference.askEveryTime,
  });

  final VideoQualityPreference videoQuality;
  final AudioPreference audio;

  DownloadPreferences copyWith({
    VideoQualityPreference? videoQuality,
    AudioPreference? audio,
  }) {
    return DownloadPreferences(
      videoQuality: videoQuality ?? this.videoQuality,
      audio: audio ?? this.audio,
    );
  }
}

class PreferredMediaSelection {
  const PreferredMediaSelection.video(this.videoQuality)
      : mediaType = MediaDownloadType.video;

  const PreferredMediaSelection.audio()
      : mediaType = MediaDownloadType.audio,
        videoQuality = null;

  final MediaDownloadType mediaType;
  final VideoQuality? videoQuality;
}

PreferredMediaSelection? resolvePreferredMediaSelection(
  MediaMetadata metadata,
  DownloadPreferences preferences,
) {
  final videoQuality = _resolveVideoQuality(
    metadata.videoQualities,
    preferences.videoQuality,
  );
  if (videoQuality != null) {
    return PreferredMediaSelection.video(videoQuality);
  }

  if (preferences.audio == AudioPreference.mp3 &&
      metadata.audioOptions.any(
        (option) => option.label.trim().toLowerCase() == 'mp3',
      )) {
    return const PreferredMediaSelection.audio();
  }

  return null;
}

VideoQuality? _resolveVideoQuality(
  List<VideoQuality> qualities,
  VideoQualityPreference preference,
) {
  if (qualities.isEmpty || preference == VideoQualityPreference.askEveryTime) {
    return null;
  }

  final preferredHeight = preference.height;
  if (preferredHeight != null) {
    for (final quality in qualities) {
      if (quality.height == preferredHeight) {
        return quality;
      }
    }
  }

  return _bestAvailableQuality(qualities);
}

VideoQuality? _bestAvailableQuality(List<VideoQuality> qualities) {
  if (qualities.isEmpty) {
    return null;
  }

  for (final quality in qualities) {
    if (quality.label.trim().toLowerCase() == 'best') {
      return quality;
    }
  }

  var bestQuality = qualities.first;
  for (final quality in qualities.skip(1)) {
    if (quality.height > bestQuality.height) {
      bestQuality = quality;
    }
  }
  return bestQuality;
}
