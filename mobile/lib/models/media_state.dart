import 'package:freezed_annotation/freezed_annotation.dart';

import 'media_metadata.dart';

part 'media_state.freezed.dart';

@freezed
class MediaState with _$MediaState {
  const factory MediaState.idle() = MediaIdle;

  const factory MediaState.loading() = MediaLoading;

  const factory MediaState.success(MediaMetadata metadata) = MediaSuccess;

  const factory MediaState.error(String message) = MediaError;
}
