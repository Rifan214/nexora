// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$MediaState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() idle,
    required TResult Function() loading,
    required TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)
        success,
    required TResult Function(String message) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? idle,
    TResult? Function()? loading,
    TResult? Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult? Function(String message)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? idle,
    TResult Function()? loading,
    TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaIdle value) idle,
    required TResult Function(MediaLoading value) loading,
    required TResult Function(MediaSuccess value) success,
    required TResult Function(MediaError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaIdle value)? idle,
    TResult? Function(MediaLoading value)? loading,
    TResult? Function(MediaSuccess value)? success,
    TResult? Function(MediaError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaIdle value)? idle,
    TResult Function(MediaLoading value)? loading,
    TResult Function(MediaSuccess value)? success,
    TResult Function(MediaError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MediaStateCopyWith<$Res> {
  factory $MediaStateCopyWith(
          MediaState value, $Res Function(MediaState) then) =
      _$MediaStateCopyWithImpl<$Res, MediaState>;
}

/// @nodoc
class _$MediaStateCopyWithImpl<$Res, $Val extends MediaState>
    implements $MediaStateCopyWith<$Res> {
  _$MediaStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$MediaIdleImplCopyWith<$Res> {
  factory _$$MediaIdleImplCopyWith(
          _$MediaIdleImpl value, $Res Function(_$MediaIdleImpl) then) =
      __$$MediaIdleImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$MediaIdleImplCopyWithImpl<$Res>
    extends _$MediaStateCopyWithImpl<$Res, _$MediaIdleImpl>
    implements _$$MediaIdleImplCopyWith<$Res> {
  __$$MediaIdleImplCopyWithImpl(
      _$MediaIdleImpl _value, $Res Function(_$MediaIdleImpl) _then)
      : super(_value, _then);

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$MediaIdleImpl implements MediaIdle {
  const _$MediaIdleImpl();

  @override
  String toString() {
    return 'MediaState.idle()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$MediaIdleImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() idle,
    required TResult Function() loading,
    required TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)
        success,
    required TResult Function(String message) error,
  }) {
    return idle();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? idle,
    TResult? Function()? loading,
    TResult? Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult? Function(String message)? error,
  }) {
    return idle?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? idle,
    TResult Function()? loading,
    TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (idle != null) {
      return idle();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaIdle value) idle,
    required TResult Function(MediaLoading value) loading,
    required TResult Function(MediaSuccess value) success,
    required TResult Function(MediaError value) error,
  }) {
    return idle(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaIdle value)? idle,
    TResult? Function(MediaLoading value)? loading,
    TResult? Function(MediaSuccess value)? success,
    TResult? Function(MediaError value)? error,
  }) {
    return idle?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaIdle value)? idle,
    TResult Function(MediaLoading value)? loading,
    TResult Function(MediaSuccess value)? success,
    TResult Function(MediaError value)? error,
    required TResult orElse(),
  }) {
    if (idle != null) {
      return idle(this);
    }
    return orElse();
  }
}

abstract class MediaIdle implements MediaState {
  const factory MediaIdle() = _$MediaIdleImpl;
}

/// @nodoc
abstract class _$$MediaLoadingImplCopyWith<$Res> {
  factory _$$MediaLoadingImplCopyWith(
          _$MediaLoadingImpl value, $Res Function(_$MediaLoadingImpl) then) =
      __$$MediaLoadingImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$MediaLoadingImplCopyWithImpl<$Res>
    extends _$MediaStateCopyWithImpl<$Res, _$MediaLoadingImpl>
    implements _$$MediaLoadingImplCopyWith<$Res> {
  __$$MediaLoadingImplCopyWithImpl(
      _$MediaLoadingImpl _value, $Res Function(_$MediaLoadingImpl) _then)
      : super(_value, _then);

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$MediaLoadingImpl implements MediaLoading {
  const _$MediaLoadingImpl();

  @override
  String toString() {
    return 'MediaState.loading()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$MediaLoadingImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() idle,
    required TResult Function() loading,
    required TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)
        success,
    required TResult Function(String message) error,
  }) {
    return loading();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? idle,
    TResult? Function()? loading,
    TResult? Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult? Function(String message)? error,
  }) {
    return loading?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? idle,
    TResult Function()? loading,
    TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaIdle value) idle,
    required TResult Function(MediaLoading value) loading,
    required TResult Function(MediaSuccess value) success,
    required TResult Function(MediaError value) error,
  }) {
    return loading(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaIdle value)? idle,
    TResult? Function(MediaLoading value)? loading,
    TResult? Function(MediaSuccess value)? success,
    TResult? Function(MediaError value)? error,
  }) {
    return loading?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaIdle value)? idle,
    TResult Function(MediaLoading value)? loading,
    TResult Function(MediaSuccess value)? success,
    TResult Function(MediaError value)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading(this);
    }
    return orElse();
  }
}

abstract class MediaLoading implements MediaState {
  const factory MediaLoading() = _$MediaLoadingImpl;
}

/// @nodoc
abstract class _$$MediaSuccessImplCopyWith<$Res> {
  factory _$$MediaSuccessImplCopyWith(
          _$MediaSuccessImpl value, $Res Function(_$MediaSuccessImpl) then) =
      __$$MediaSuccessImplCopyWithImpl<$Res>;
  @useResult
  $Res call(
      {MediaMetadata metadata,
      MediaFormat? selectedFormat,
      bool downloadLoading,
      bool downloadSuccess,
      String? downloadError,
      String? currentJobId});

  $MediaMetadataCopyWith<$Res> get metadata;
  $MediaFormatCopyWith<$Res>? get selectedFormat;
}

/// @nodoc
class __$$MediaSuccessImplCopyWithImpl<$Res>
    extends _$MediaStateCopyWithImpl<$Res, _$MediaSuccessImpl>
    implements _$$MediaSuccessImplCopyWith<$Res> {
  __$$MediaSuccessImplCopyWithImpl(
      _$MediaSuccessImpl _value, $Res Function(_$MediaSuccessImpl) _then)
      : super(_value, _then);

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? metadata = null,
    Object? selectedFormat = freezed,
    Object? downloadLoading = null,
    Object? downloadSuccess = null,
    Object? downloadError = freezed,
    Object? currentJobId = freezed,
  }) {
    return _then(_$MediaSuccessImpl(
      metadata: null == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as MediaMetadata,
      selectedFormat: freezed == selectedFormat
          ? _value.selectedFormat
          : selectedFormat // ignore: cast_nullable_to_non_nullable
              as MediaFormat?,
      downloadLoading: null == downloadLoading
          ? _value.downloadLoading
          : downloadLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      downloadSuccess: null == downloadSuccess
          ? _value.downloadSuccess
          : downloadSuccess // ignore: cast_nullable_to_non_nullable
              as bool,
      downloadError: freezed == downloadError
          ? _value.downloadError
          : downloadError // ignore: cast_nullable_to_non_nullable
              as String?,
      currentJobId: freezed == currentJobId
          ? _value.currentJobId
          : currentJobId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $MediaMetadataCopyWith<$Res> get metadata {
    return $MediaMetadataCopyWith<$Res>(_value.metadata, (value) {
      return _then(_value.copyWith(metadata: value));
    });
  }

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $MediaFormatCopyWith<$Res>? get selectedFormat {
    if (_value.selectedFormat == null) {
      return null;
    }

    return $MediaFormatCopyWith<$Res>(_value.selectedFormat!, (value) {
      return _then(_value.copyWith(selectedFormat: value));
    });
  }
}

/// @nodoc

class _$MediaSuccessImpl implements MediaSuccess {
  const _$MediaSuccessImpl(
      {required this.metadata,
      this.selectedFormat,
      this.downloadLoading = false,
      this.downloadSuccess = false,
      this.downloadError,
      this.currentJobId});

  @override
  final MediaMetadata metadata;
  @override
  final MediaFormat? selectedFormat;
  @override
  @JsonKey()
  final bool downloadLoading;
  @override
  @JsonKey()
  final bool downloadSuccess;
  @override
  final String? downloadError;
  @override
  final String? currentJobId;

  @override
  String toString() {
    return 'MediaState.success(metadata: $metadata, selectedFormat: $selectedFormat, downloadLoading: $downloadLoading, downloadSuccess: $downloadSuccess, downloadError: $downloadError, currentJobId: $currentJobId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaSuccessImpl &&
            (identical(other.metadata, metadata) ||
                other.metadata == metadata) &&
            (identical(other.selectedFormat, selectedFormat) ||
                other.selectedFormat == selectedFormat) &&
            (identical(other.downloadLoading, downloadLoading) ||
                other.downloadLoading == downloadLoading) &&
            (identical(other.downloadSuccess, downloadSuccess) ||
                other.downloadSuccess == downloadSuccess) &&
            (identical(other.downloadError, downloadError) ||
                other.downloadError == downloadError) &&
            (identical(other.currentJobId, currentJobId) ||
                other.currentJobId == currentJobId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, metadata, selectedFormat,
      downloadLoading, downloadSuccess, downloadError, currentJobId);

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaSuccessImplCopyWith<_$MediaSuccessImpl> get copyWith =>
      __$$MediaSuccessImplCopyWithImpl<_$MediaSuccessImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() idle,
    required TResult Function() loading,
    required TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)
        success,
    required TResult Function(String message) error,
  }) {
    return success(metadata, selectedFormat, downloadLoading, downloadSuccess,
        downloadError, currentJobId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? idle,
    TResult? Function()? loading,
    TResult? Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult? Function(String message)? error,
  }) {
    return success?.call(metadata, selectedFormat, downloadLoading,
        downloadSuccess, downloadError, currentJobId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? idle,
    TResult Function()? loading,
    TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (success != null) {
      return success(metadata, selectedFormat, downloadLoading, downloadSuccess,
          downloadError, currentJobId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaIdle value) idle,
    required TResult Function(MediaLoading value) loading,
    required TResult Function(MediaSuccess value) success,
    required TResult Function(MediaError value) error,
  }) {
    return success(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaIdle value)? idle,
    TResult? Function(MediaLoading value)? loading,
    TResult? Function(MediaSuccess value)? success,
    TResult? Function(MediaError value)? error,
  }) {
    return success?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaIdle value)? idle,
    TResult Function(MediaLoading value)? loading,
    TResult Function(MediaSuccess value)? success,
    TResult Function(MediaError value)? error,
    required TResult orElse(),
  }) {
    if (success != null) {
      return success(this);
    }
    return orElse();
  }
}

abstract class MediaSuccess implements MediaState {
  const factory MediaSuccess(
      {required final MediaMetadata metadata,
      final MediaFormat? selectedFormat,
      final bool downloadLoading,
      final bool downloadSuccess,
      final String? downloadError,
      final String? currentJobId}) = _$MediaSuccessImpl;

  MediaMetadata get metadata;
  MediaFormat? get selectedFormat;
  bool get downloadLoading;
  bool get downloadSuccess;
  String? get downloadError;
  String? get currentJobId;

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MediaSuccessImplCopyWith<_$MediaSuccessImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MediaErrorImplCopyWith<$Res> {
  factory _$$MediaErrorImplCopyWith(
          _$MediaErrorImpl value, $Res Function(_$MediaErrorImpl) then) =
      __$$MediaErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$MediaErrorImplCopyWithImpl<$Res>
    extends _$MediaStateCopyWithImpl<$Res, _$MediaErrorImpl>
    implements _$$MediaErrorImplCopyWith<$Res> {
  __$$MediaErrorImplCopyWithImpl(
      _$MediaErrorImpl _value, $Res Function(_$MediaErrorImpl) _then)
      : super(_value, _then);

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$MediaErrorImpl(
      null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$MediaErrorImpl implements MediaError {
  const _$MediaErrorImpl(this.message);

  @override
  final String message;

  @override
  String toString() {
    return 'MediaState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaErrorImplCopyWith<_$MediaErrorImpl> get copyWith =>
      __$$MediaErrorImplCopyWithImpl<_$MediaErrorImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() idle,
    required TResult Function() loading,
    required TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)
        success,
    required TResult Function(String message) error,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? idle,
    TResult? Function()? loading,
    TResult? Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult? Function(String message)? error,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? idle,
    TResult Function()? loading,
    TResult Function(
            MediaMetadata metadata,
            MediaFormat? selectedFormat,
            bool downloadLoading,
            bool downloadSuccess,
            String? downloadError,
            String? currentJobId)?
        success,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaIdle value) idle,
    required TResult Function(MediaLoading value) loading,
    required TResult Function(MediaSuccess value) success,
    required TResult Function(MediaError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaIdle value)? idle,
    TResult? Function(MediaLoading value)? loading,
    TResult? Function(MediaSuccess value)? success,
    TResult? Function(MediaError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaIdle value)? idle,
    TResult Function(MediaLoading value)? loading,
    TResult Function(MediaSuccess value)? success,
    TResult Function(MediaError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class MediaError implements MediaState {
  const factory MediaError(final String message) = _$MediaErrorImpl;

  String get message;

  /// Create a copy of MediaState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MediaErrorImplCopyWith<_$MediaErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
