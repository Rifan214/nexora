// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_metadata.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

MediaInfoResponse _$MediaInfoResponseFromJson(Map<String, dynamic> json) {
  return _MediaInfoResponse.fromJson(json);
}

/// @nodoc
mixin _$MediaInfoResponse {
  bool get success => throw _privateConstructorUsedError;
  String get message => throw _privateConstructorUsedError;
  MediaMetadata? get data => throw _privateConstructorUsedError;
  ApiErrorPayload? get error => throw _privateConstructorUsedError;

  /// Serializes this MediaInfoResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MediaInfoResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MediaInfoResponseCopyWith<MediaInfoResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MediaInfoResponseCopyWith<$Res> {
  factory $MediaInfoResponseCopyWith(
          MediaInfoResponse value, $Res Function(MediaInfoResponse) then) =
      _$MediaInfoResponseCopyWithImpl<$Res, MediaInfoResponse>;
  @useResult
  $Res call(
      {bool success,
      String message,
      MediaMetadata? data,
      ApiErrorPayload? error});

  $MediaMetadataCopyWith<$Res>? get data;
  $ApiErrorPayloadCopyWith<$Res>? get error;
}

/// @nodoc
class _$MediaInfoResponseCopyWithImpl<$Res, $Val extends MediaInfoResponse>
    implements $MediaInfoResponseCopyWith<$Res> {
  _$MediaInfoResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MediaInfoResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? data = freezed,
    Object? error = freezed,
  }) {
    return _then(_value.copyWith(
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      data: freezed == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as MediaMetadata?,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as ApiErrorPayload?,
    ) as $Val);
  }

  /// Create a copy of MediaInfoResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $MediaMetadataCopyWith<$Res>? get data {
    if (_value.data == null) {
      return null;
    }

    return $MediaMetadataCopyWith<$Res>(_value.data!, (value) {
      return _then(_value.copyWith(data: value) as $Val);
    });
  }

  /// Create a copy of MediaInfoResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ApiErrorPayloadCopyWith<$Res>? get error {
    if (_value.error == null) {
      return null;
    }

    return $ApiErrorPayloadCopyWith<$Res>(_value.error!, (value) {
      return _then(_value.copyWith(error: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$MediaInfoResponseImplCopyWith<$Res>
    implements $MediaInfoResponseCopyWith<$Res> {
  factory _$$MediaInfoResponseImplCopyWith(_$MediaInfoResponseImpl value,
          $Res Function(_$MediaInfoResponseImpl) then) =
      __$$MediaInfoResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool success,
      String message,
      MediaMetadata? data,
      ApiErrorPayload? error});

  @override
  $MediaMetadataCopyWith<$Res>? get data;
  @override
  $ApiErrorPayloadCopyWith<$Res>? get error;
}

/// @nodoc
class __$$MediaInfoResponseImplCopyWithImpl<$Res>
    extends _$MediaInfoResponseCopyWithImpl<$Res, _$MediaInfoResponseImpl>
    implements _$$MediaInfoResponseImplCopyWith<$Res> {
  __$$MediaInfoResponseImplCopyWithImpl(_$MediaInfoResponseImpl _value,
      $Res Function(_$MediaInfoResponseImpl) _then)
      : super(_value, _then);

  /// Create a copy of MediaInfoResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? data = freezed,
    Object? error = freezed,
  }) {
    return _then(_$MediaInfoResponseImpl(
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      data: freezed == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as MediaMetadata?,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as ApiErrorPayload?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MediaInfoResponseImpl implements _MediaInfoResponse {
  const _$MediaInfoResponseImpl(
      {required this.success, required this.message, this.data, this.error});

  factory _$MediaInfoResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$MediaInfoResponseImplFromJson(json);

  @override
  final bool success;
  @override
  final String message;
  @override
  final MediaMetadata? data;
  @override
  final ApiErrorPayload? error;

  @override
  String toString() {
    return 'MediaInfoResponse(success: $success, message: $message, data: $data, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaInfoResponseImpl &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.data, data) || other.data == data) &&
            (identical(other.error, error) || other.error == error));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, success, message, data, error);

  /// Create a copy of MediaInfoResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaInfoResponseImplCopyWith<_$MediaInfoResponseImpl> get copyWith =>
      __$$MediaInfoResponseImplCopyWithImpl<_$MediaInfoResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MediaInfoResponseImplToJson(
      this,
    );
  }
}

abstract class _MediaInfoResponse implements MediaInfoResponse {
  const factory _MediaInfoResponse(
      {required final bool success,
      required final String message,
      final MediaMetadata? data,
      final ApiErrorPayload? error}) = _$MediaInfoResponseImpl;

  factory _MediaInfoResponse.fromJson(Map<String, dynamic> json) =
      _$MediaInfoResponseImpl.fromJson;

  @override
  bool get success;
  @override
  String get message;
  @override
  MediaMetadata? get data;
  @override
  ApiErrorPayload? get error;

  /// Create a copy of MediaInfoResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MediaInfoResponseImplCopyWith<_$MediaInfoResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ApiErrorPayload _$ApiErrorPayloadFromJson(Map<String, dynamic> json) {
  return _ApiErrorPayload.fromJson(json);
}

/// @nodoc
mixin _$ApiErrorPayload {
  String get code => throw _privateConstructorUsedError;
  String get details => throw _privateConstructorUsedError;

  /// Serializes this ApiErrorPayload to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ApiErrorPayload
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ApiErrorPayloadCopyWith<ApiErrorPayload> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ApiErrorPayloadCopyWith<$Res> {
  factory $ApiErrorPayloadCopyWith(
          ApiErrorPayload value, $Res Function(ApiErrorPayload) then) =
      _$ApiErrorPayloadCopyWithImpl<$Res, ApiErrorPayload>;
  @useResult
  $Res call({String code, String details});
}

/// @nodoc
class _$ApiErrorPayloadCopyWithImpl<$Res, $Val extends ApiErrorPayload>
    implements $ApiErrorPayloadCopyWith<$Res> {
  _$ApiErrorPayloadCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ApiErrorPayload
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? details = null,
  }) {
    return _then(_value.copyWith(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      details: null == details
          ? _value.details
          : details // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ApiErrorPayloadImplCopyWith<$Res>
    implements $ApiErrorPayloadCopyWith<$Res> {
  factory _$$ApiErrorPayloadImplCopyWith(_$ApiErrorPayloadImpl value,
          $Res Function(_$ApiErrorPayloadImpl) then) =
      __$$ApiErrorPayloadImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String details});
}

/// @nodoc
class __$$ApiErrorPayloadImplCopyWithImpl<$Res>
    extends _$ApiErrorPayloadCopyWithImpl<$Res, _$ApiErrorPayloadImpl>
    implements _$$ApiErrorPayloadImplCopyWith<$Res> {
  __$$ApiErrorPayloadImplCopyWithImpl(
      _$ApiErrorPayloadImpl _value, $Res Function(_$ApiErrorPayloadImpl) _then)
      : super(_value, _then);

  /// Create a copy of ApiErrorPayload
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? details = null,
  }) {
    return _then(_$ApiErrorPayloadImpl(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      details: null == details
          ? _value.details
          : details // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ApiErrorPayloadImpl implements _ApiErrorPayload {
  const _$ApiErrorPayloadImpl({required this.code, required this.details});

  factory _$ApiErrorPayloadImpl.fromJson(Map<String, dynamic> json) =>
      _$$ApiErrorPayloadImplFromJson(json);

  @override
  final String code;
  @override
  final String details;

  @override
  String toString() {
    return 'ApiErrorPayload(code: $code, details: $details)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ApiErrorPayloadImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.details, details) || other.details == details));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, code, details);

  /// Create a copy of ApiErrorPayload
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ApiErrorPayloadImplCopyWith<_$ApiErrorPayloadImpl> get copyWith =>
      __$$ApiErrorPayloadImplCopyWithImpl<_$ApiErrorPayloadImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ApiErrorPayloadImplToJson(
      this,
    );
  }
}

abstract class _ApiErrorPayload implements ApiErrorPayload {
  const factory _ApiErrorPayload(
      {required final String code,
      required final String details}) = _$ApiErrorPayloadImpl;

  factory _ApiErrorPayload.fromJson(Map<String, dynamic> json) =
      _$ApiErrorPayloadImpl.fromJson;

  @override
  String get code;
  @override
  String get details;

  /// Create a copy of ApiErrorPayload
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ApiErrorPayloadImplCopyWith<_$ApiErrorPayloadImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

MediaMetadata _$MediaMetadataFromJson(Map<String, dynamic> json) {
  return _MediaMetadata.fromJson(json);
}

/// @nodoc
mixin _$MediaMetadata {
  String get platform => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String? get uploader => throw _privateConstructorUsedError;
  @JsonKey(name: 'uploader_url')
  String? get uploaderUrl => throw _privateConstructorUsedError;
  @JsonKey(name: 'thumbnail_url')
  String? get thumbnailUrl => throw _privateConstructorUsedError;
  @JsonKey(name: 'duration_seconds')
  int? get durationSeconds => throw _privateConstructorUsedError;
  @JsonKey(name: 'webpage_url')
  String get webpageUrl => throw _privateConstructorUsedError;
  String get extractor => throw _privateConstructorUsedError;
  @JsonKey(name: 'extractor_key')
  String get extractorKey => throw _privateConstructorUsedError;
  @JsonKey(name: 'upload_date')
  String? get uploadDate => throw _privateConstructorUsedError;
  @JsonKey(name: 'view_count')
  int? get viewCount => throw _privateConstructorUsedError;
  @JsonKey(name: 'like_count')
  int? get likeCount => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  List<MediaFormat> get formats => throw _privateConstructorUsedError;

  /// Serializes this MediaMetadata to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MediaMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MediaMetadataCopyWith<MediaMetadata> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MediaMetadataCopyWith<$Res> {
  factory $MediaMetadataCopyWith(
          MediaMetadata value, $Res Function(MediaMetadata) then) =
      _$MediaMetadataCopyWithImpl<$Res, MediaMetadata>;
  @useResult
  $Res call(
      {String platform,
      String title,
      String? uploader,
      @JsonKey(name: 'uploader_url') String? uploaderUrl,
      @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
      @JsonKey(name: 'duration_seconds') int? durationSeconds,
      @JsonKey(name: 'webpage_url') String webpageUrl,
      String extractor,
      @JsonKey(name: 'extractor_key') String extractorKey,
      @JsonKey(name: 'upload_date') String? uploadDate,
      @JsonKey(name: 'view_count') int? viewCount,
      @JsonKey(name: 'like_count') int? likeCount,
      String? description,
      List<MediaFormat> formats});
}

/// @nodoc
class _$MediaMetadataCopyWithImpl<$Res, $Val extends MediaMetadata>
    implements $MediaMetadataCopyWith<$Res> {
  _$MediaMetadataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MediaMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? platform = null,
    Object? title = null,
    Object? uploader = freezed,
    Object? uploaderUrl = freezed,
    Object? thumbnailUrl = freezed,
    Object? durationSeconds = freezed,
    Object? webpageUrl = null,
    Object? extractor = null,
    Object? extractorKey = null,
    Object? uploadDate = freezed,
    Object? viewCount = freezed,
    Object? likeCount = freezed,
    Object? description = freezed,
    Object? formats = null,
  }) {
    return _then(_value.copyWith(
      platform: null == platform
          ? _value.platform
          : platform // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      uploader: freezed == uploader
          ? _value.uploader
          : uploader // ignore: cast_nullable_to_non_nullable
              as String?,
      uploaderUrl: freezed == uploaderUrl
          ? _value.uploaderUrl
          : uploaderUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      thumbnailUrl: freezed == thumbnailUrl
          ? _value.thumbnailUrl
          : thumbnailUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      webpageUrl: null == webpageUrl
          ? _value.webpageUrl
          : webpageUrl // ignore: cast_nullable_to_non_nullable
              as String,
      extractor: null == extractor
          ? _value.extractor
          : extractor // ignore: cast_nullable_to_non_nullable
              as String,
      extractorKey: null == extractorKey
          ? _value.extractorKey
          : extractorKey // ignore: cast_nullable_to_non_nullable
              as String,
      uploadDate: freezed == uploadDate
          ? _value.uploadDate
          : uploadDate // ignore: cast_nullable_to_non_nullable
              as String?,
      viewCount: freezed == viewCount
          ? _value.viewCount
          : viewCount // ignore: cast_nullable_to_non_nullable
              as int?,
      likeCount: freezed == likeCount
          ? _value.likeCount
          : likeCount // ignore: cast_nullable_to_non_nullable
              as int?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      formats: null == formats
          ? _value.formats
          : formats // ignore: cast_nullable_to_non_nullable
              as List<MediaFormat>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MediaMetadataImplCopyWith<$Res>
    implements $MediaMetadataCopyWith<$Res> {
  factory _$$MediaMetadataImplCopyWith(
          _$MediaMetadataImpl value, $Res Function(_$MediaMetadataImpl) then) =
      __$$MediaMetadataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String platform,
      String title,
      String? uploader,
      @JsonKey(name: 'uploader_url') String? uploaderUrl,
      @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
      @JsonKey(name: 'duration_seconds') int? durationSeconds,
      @JsonKey(name: 'webpage_url') String webpageUrl,
      String extractor,
      @JsonKey(name: 'extractor_key') String extractorKey,
      @JsonKey(name: 'upload_date') String? uploadDate,
      @JsonKey(name: 'view_count') int? viewCount,
      @JsonKey(name: 'like_count') int? likeCount,
      String? description,
      List<MediaFormat> formats});
}

/// @nodoc
class __$$MediaMetadataImplCopyWithImpl<$Res>
    extends _$MediaMetadataCopyWithImpl<$Res, _$MediaMetadataImpl>
    implements _$$MediaMetadataImplCopyWith<$Res> {
  __$$MediaMetadataImplCopyWithImpl(
      _$MediaMetadataImpl _value, $Res Function(_$MediaMetadataImpl) _then)
      : super(_value, _then);

  /// Create a copy of MediaMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? platform = null,
    Object? title = null,
    Object? uploader = freezed,
    Object? uploaderUrl = freezed,
    Object? thumbnailUrl = freezed,
    Object? durationSeconds = freezed,
    Object? webpageUrl = null,
    Object? extractor = null,
    Object? extractorKey = null,
    Object? uploadDate = freezed,
    Object? viewCount = freezed,
    Object? likeCount = freezed,
    Object? description = freezed,
    Object? formats = null,
  }) {
    return _then(_$MediaMetadataImpl(
      platform: null == platform
          ? _value.platform
          : platform // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      uploader: freezed == uploader
          ? _value.uploader
          : uploader // ignore: cast_nullable_to_non_nullable
              as String?,
      uploaderUrl: freezed == uploaderUrl
          ? _value.uploaderUrl
          : uploaderUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      thumbnailUrl: freezed == thumbnailUrl
          ? _value.thumbnailUrl
          : thumbnailUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      webpageUrl: null == webpageUrl
          ? _value.webpageUrl
          : webpageUrl // ignore: cast_nullable_to_non_nullable
              as String,
      extractor: null == extractor
          ? _value.extractor
          : extractor // ignore: cast_nullable_to_non_nullable
              as String,
      extractorKey: null == extractorKey
          ? _value.extractorKey
          : extractorKey // ignore: cast_nullable_to_non_nullable
              as String,
      uploadDate: freezed == uploadDate
          ? _value.uploadDate
          : uploadDate // ignore: cast_nullable_to_non_nullable
              as String?,
      viewCount: freezed == viewCount
          ? _value.viewCount
          : viewCount // ignore: cast_nullable_to_non_nullable
              as int?,
      likeCount: freezed == likeCount
          ? _value.likeCount
          : likeCount // ignore: cast_nullable_to_non_nullable
              as int?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      formats: null == formats
          ? _value._formats
          : formats // ignore: cast_nullable_to_non_nullable
              as List<MediaFormat>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MediaMetadataImpl implements _MediaMetadata {
  const _$MediaMetadataImpl(
      {required this.platform,
      required this.title,
      this.uploader,
      @JsonKey(name: 'uploader_url') this.uploaderUrl,
      @JsonKey(name: 'thumbnail_url') this.thumbnailUrl,
      @JsonKey(name: 'duration_seconds') this.durationSeconds,
      @JsonKey(name: 'webpage_url') required this.webpageUrl,
      required this.extractor,
      @JsonKey(name: 'extractor_key') required this.extractorKey,
      @JsonKey(name: 'upload_date') this.uploadDate,
      @JsonKey(name: 'view_count') this.viewCount,
      @JsonKey(name: 'like_count') this.likeCount,
      this.description,
      final List<MediaFormat> formats = const <MediaFormat>[]})
      : _formats = formats;

  factory _$MediaMetadataImpl.fromJson(Map<String, dynamic> json) =>
      _$$MediaMetadataImplFromJson(json);

  @override
  final String platform;
  @override
  final String title;
  @override
  final String? uploader;
  @override
  @JsonKey(name: 'uploader_url')
  final String? uploaderUrl;
  @override
  @JsonKey(name: 'thumbnail_url')
  final String? thumbnailUrl;
  @override
  @JsonKey(name: 'duration_seconds')
  final int? durationSeconds;
  @override
  @JsonKey(name: 'webpage_url')
  final String webpageUrl;
  @override
  final String extractor;
  @override
  @JsonKey(name: 'extractor_key')
  final String extractorKey;
  @override
  @JsonKey(name: 'upload_date')
  final String? uploadDate;
  @override
  @JsonKey(name: 'view_count')
  final int? viewCount;
  @override
  @JsonKey(name: 'like_count')
  final int? likeCount;
  @override
  final String? description;
  final List<MediaFormat> _formats;
  @override
  @JsonKey()
  List<MediaFormat> get formats {
    if (_formats is EqualUnmodifiableListView) return _formats;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_formats);
  }

  @override
  String toString() {
    return 'MediaMetadata(platform: $platform, title: $title, uploader: $uploader, uploaderUrl: $uploaderUrl, thumbnailUrl: $thumbnailUrl, durationSeconds: $durationSeconds, webpageUrl: $webpageUrl, extractor: $extractor, extractorKey: $extractorKey, uploadDate: $uploadDate, viewCount: $viewCount, likeCount: $likeCount, description: $description, formats: $formats)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaMetadataImpl &&
            (identical(other.platform, platform) ||
                other.platform == platform) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.uploader, uploader) ||
                other.uploader == uploader) &&
            (identical(other.uploaderUrl, uploaderUrl) ||
                other.uploaderUrl == uploaderUrl) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                other.thumbnailUrl == thumbnailUrl) &&
            (identical(other.durationSeconds, durationSeconds) ||
                other.durationSeconds == durationSeconds) &&
            (identical(other.webpageUrl, webpageUrl) ||
                other.webpageUrl == webpageUrl) &&
            (identical(other.extractor, extractor) ||
                other.extractor == extractor) &&
            (identical(other.extractorKey, extractorKey) ||
                other.extractorKey == extractorKey) &&
            (identical(other.uploadDate, uploadDate) ||
                other.uploadDate == uploadDate) &&
            (identical(other.viewCount, viewCount) ||
                other.viewCount == viewCount) &&
            (identical(other.likeCount, likeCount) ||
                other.likeCount == likeCount) &&
            (identical(other.description, description) ||
                other.description == description) &&
            const DeepCollectionEquality().equals(other._formats, _formats));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      platform,
      title,
      uploader,
      uploaderUrl,
      thumbnailUrl,
      durationSeconds,
      webpageUrl,
      extractor,
      extractorKey,
      uploadDate,
      viewCount,
      likeCount,
      description,
      const DeepCollectionEquality().hash(_formats));

  /// Create a copy of MediaMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaMetadataImplCopyWith<_$MediaMetadataImpl> get copyWith =>
      __$$MediaMetadataImplCopyWithImpl<_$MediaMetadataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MediaMetadataImplToJson(
      this,
    );
  }
}

abstract class _MediaMetadata implements MediaMetadata {
  const factory _MediaMetadata(
      {required final String platform,
      required final String title,
      final String? uploader,
      @JsonKey(name: 'uploader_url') final String? uploaderUrl,
      @JsonKey(name: 'thumbnail_url') final String? thumbnailUrl,
      @JsonKey(name: 'duration_seconds') final int? durationSeconds,
      @JsonKey(name: 'webpage_url') required final String webpageUrl,
      required final String extractor,
      @JsonKey(name: 'extractor_key') required final String extractorKey,
      @JsonKey(name: 'upload_date') final String? uploadDate,
      @JsonKey(name: 'view_count') final int? viewCount,
      @JsonKey(name: 'like_count') final int? likeCount,
      final String? description,
      final List<MediaFormat> formats}) = _$MediaMetadataImpl;

  factory _MediaMetadata.fromJson(Map<String, dynamic> json) =
      _$MediaMetadataImpl.fromJson;

  @override
  String get platform;
  @override
  String get title;
  @override
  String? get uploader;
  @override
  @JsonKey(name: 'uploader_url')
  String? get uploaderUrl;
  @override
  @JsonKey(name: 'thumbnail_url')
  String? get thumbnailUrl;
  @override
  @JsonKey(name: 'duration_seconds')
  int? get durationSeconds;
  @override
  @JsonKey(name: 'webpage_url')
  String get webpageUrl;
  @override
  String get extractor;
  @override
  @JsonKey(name: 'extractor_key')
  String get extractorKey;
  @override
  @JsonKey(name: 'upload_date')
  String? get uploadDate;
  @override
  @JsonKey(name: 'view_count')
  int? get viewCount;
  @override
  @JsonKey(name: 'like_count')
  int? get likeCount;
  @override
  String? get description;
  @override
  List<MediaFormat> get formats;

  /// Create a copy of MediaMetadata
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MediaMetadataImplCopyWith<_$MediaMetadataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

MediaFormat _$MediaFormatFromJson(Map<String, dynamic> json) {
  return _MediaFormat.fromJson(json);
}

/// @nodoc
mixin _$MediaFormat {
  @JsonKey(name: 'format_id')
  String get formatId => throw _privateConstructorUsedError;
  String get extension => throw _privateConstructorUsedError;
  String? get resolution => throw _privateConstructorUsedError;
  int? get fps => throw _privateConstructorUsedError;
  int? get filesize => throw _privateConstructorUsedError;
  @JsonKey(name: 'video_codec')
  String? get videoCodec => throw _privateConstructorUsedError;
  @JsonKey(name: 'audio_codec')
  String? get audioCodec => throw _privateConstructorUsedError;

  /// Serializes this MediaFormat to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MediaFormat
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MediaFormatCopyWith<MediaFormat> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MediaFormatCopyWith<$Res> {
  factory $MediaFormatCopyWith(
          MediaFormat value, $Res Function(MediaFormat) then) =
      _$MediaFormatCopyWithImpl<$Res, MediaFormat>;
  @useResult
  $Res call(
      {@JsonKey(name: 'format_id') String formatId,
      String extension,
      String? resolution,
      int? fps,
      int? filesize,
      @JsonKey(name: 'video_codec') String? videoCodec,
      @JsonKey(name: 'audio_codec') String? audioCodec});
}

/// @nodoc
class _$MediaFormatCopyWithImpl<$Res, $Val extends MediaFormat>
    implements $MediaFormatCopyWith<$Res> {
  _$MediaFormatCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MediaFormat
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? formatId = null,
    Object? extension = null,
    Object? resolution = freezed,
    Object? fps = freezed,
    Object? filesize = freezed,
    Object? videoCodec = freezed,
    Object? audioCodec = freezed,
  }) {
    return _then(_value.copyWith(
      formatId: null == formatId
          ? _value.formatId
          : formatId // ignore: cast_nullable_to_non_nullable
              as String,
      extension: null == extension
          ? _value.extension
          : extension // ignore: cast_nullable_to_non_nullable
              as String,
      resolution: freezed == resolution
          ? _value.resolution
          : resolution // ignore: cast_nullable_to_non_nullable
              as String?,
      fps: freezed == fps
          ? _value.fps
          : fps // ignore: cast_nullable_to_non_nullable
              as int?,
      filesize: freezed == filesize
          ? _value.filesize
          : filesize // ignore: cast_nullable_to_non_nullable
              as int?,
      videoCodec: freezed == videoCodec
          ? _value.videoCodec
          : videoCodec // ignore: cast_nullable_to_non_nullable
              as String?,
      audioCodec: freezed == audioCodec
          ? _value.audioCodec
          : audioCodec // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MediaFormatImplCopyWith<$Res>
    implements $MediaFormatCopyWith<$Res> {
  factory _$$MediaFormatImplCopyWith(
          _$MediaFormatImpl value, $Res Function(_$MediaFormatImpl) then) =
      __$$MediaFormatImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'format_id') String formatId,
      String extension,
      String? resolution,
      int? fps,
      int? filesize,
      @JsonKey(name: 'video_codec') String? videoCodec,
      @JsonKey(name: 'audio_codec') String? audioCodec});
}

/// @nodoc
class __$$MediaFormatImplCopyWithImpl<$Res>
    extends _$MediaFormatCopyWithImpl<$Res, _$MediaFormatImpl>
    implements _$$MediaFormatImplCopyWith<$Res> {
  __$$MediaFormatImplCopyWithImpl(
      _$MediaFormatImpl _value, $Res Function(_$MediaFormatImpl) _then)
      : super(_value, _then);

  /// Create a copy of MediaFormat
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? formatId = null,
    Object? extension = null,
    Object? resolution = freezed,
    Object? fps = freezed,
    Object? filesize = freezed,
    Object? videoCodec = freezed,
    Object? audioCodec = freezed,
  }) {
    return _then(_$MediaFormatImpl(
      formatId: null == formatId
          ? _value.formatId
          : formatId // ignore: cast_nullable_to_non_nullable
              as String,
      extension: null == extension
          ? _value.extension
          : extension // ignore: cast_nullable_to_non_nullable
              as String,
      resolution: freezed == resolution
          ? _value.resolution
          : resolution // ignore: cast_nullable_to_non_nullable
              as String?,
      fps: freezed == fps
          ? _value.fps
          : fps // ignore: cast_nullable_to_non_nullable
              as int?,
      filesize: freezed == filesize
          ? _value.filesize
          : filesize // ignore: cast_nullable_to_non_nullable
              as int?,
      videoCodec: freezed == videoCodec
          ? _value.videoCodec
          : videoCodec // ignore: cast_nullable_to_non_nullable
              as String?,
      audioCodec: freezed == audioCodec
          ? _value.audioCodec
          : audioCodec // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MediaFormatImpl implements _MediaFormat {
  const _$MediaFormatImpl(
      {@JsonKey(name: 'format_id') required this.formatId,
      required this.extension,
      this.resolution,
      this.fps,
      this.filesize,
      @JsonKey(name: 'video_codec') this.videoCodec,
      @JsonKey(name: 'audio_codec') this.audioCodec});

  factory _$MediaFormatImpl.fromJson(Map<String, dynamic> json) =>
      _$$MediaFormatImplFromJson(json);

  @override
  @JsonKey(name: 'format_id')
  final String formatId;
  @override
  final String extension;
  @override
  final String? resolution;
  @override
  final int? fps;
  @override
  final int? filesize;
  @override
  @JsonKey(name: 'video_codec')
  final String? videoCodec;
  @override
  @JsonKey(name: 'audio_codec')
  final String? audioCodec;

  @override
  String toString() {
    return 'MediaFormat(formatId: $formatId, extension: $extension, resolution: $resolution, fps: $fps, filesize: $filesize, videoCodec: $videoCodec, audioCodec: $audioCodec)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaFormatImpl &&
            (identical(other.formatId, formatId) ||
                other.formatId == formatId) &&
            (identical(other.extension, extension) ||
                other.extension == extension) &&
            (identical(other.resolution, resolution) ||
                other.resolution == resolution) &&
            (identical(other.fps, fps) || other.fps == fps) &&
            (identical(other.filesize, filesize) ||
                other.filesize == filesize) &&
            (identical(other.videoCodec, videoCodec) ||
                other.videoCodec == videoCodec) &&
            (identical(other.audioCodec, audioCodec) ||
                other.audioCodec == audioCodec));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, formatId, extension, resolution,
      fps, filesize, videoCodec, audioCodec);

  /// Create a copy of MediaFormat
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaFormatImplCopyWith<_$MediaFormatImpl> get copyWith =>
      __$$MediaFormatImplCopyWithImpl<_$MediaFormatImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MediaFormatImplToJson(
      this,
    );
  }
}

abstract class _MediaFormat implements MediaFormat {
  const factory _MediaFormat(
          {@JsonKey(name: 'format_id') required final String formatId,
          required final String extension,
          final String? resolution,
          final int? fps,
          final int? filesize,
          @JsonKey(name: 'video_codec') final String? videoCodec,
          @JsonKey(name: 'audio_codec') final String? audioCodec}) =
      _$MediaFormatImpl;

  factory _MediaFormat.fromJson(Map<String, dynamic> json) =
      _$MediaFormatImpl.fromJson;

  @override
  @JsonKey(name: 'format_id')
  String get formatId;
  @override
  String get extension;
  @override
  String? get resolution;
  @override
  int? get fps;
  @override
  int? get filesize;
  @override
  @JsonKey(name: 'video_codec')
  String? get videoCodec;
  @override
  @JsonKey(name: 'audio_codec')
  String? get audioCodec;

  /// Create a copy of MediaFormat
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MediaFormatImplCopyWith<_$MediaFormatImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
