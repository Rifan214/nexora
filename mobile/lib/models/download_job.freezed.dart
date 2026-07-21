// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'download_job.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

DownloadJobRequest _$DownloadJobRequestFromJson(Map<String, dynamic> json) {
  return _DownloadJobRequest.fromJson(json);
}

/// @nodoc
mixin _$DownloadJobRequest {
  String get url => throw _privateConstructorUsedError;
  @JsonKey(name: 'format_id')
  String get formatId => throw _privateConstructorUsedError;
  String get type => throw _privateConstructorUsedError;

  /// Serializes this DownloadJobRequest to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DownloadJobRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DownloadJobRequestCopyWith<DownloadJobRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DownloadJobRequestCopyWith<$Res> {
  factory $DownloadJobRequestCopyWith(
          DownloadJobRequest value, $Res Function(DownloadJobRequest) then) =
      _$DownloadJobRequestCopyWithImpl<$Res, DownloadJobRequest>;
  @useResult
  $Res call(
      {String url, @JsonKey(name: 'format_id') String formatId, String type});
}

/// @nodoc
class _$DownloadJobRequestCopyWithImpl<$Res, $Val extends DownloadJobRequest>
    implements $DownloadJobRequestCopyWith<$Res> {
  _$DownloadJobRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DownloadJobRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = null,
    Object? formatId = null,
    Object? type = null,
  }) {
    return _then(_value.copyWith(
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      formatId: null == formatId
          ? _value.formatId
          : formatId // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DownloadJobRequestImplCopyWith<$Res>
    implements $DownloadJobRequestCopyWith<$Res> {
  factory _$$DownloadJobRequestImplCopyWith(_$DownloadJobRequestImpl value,
          $Res Function(_$DownloadJobRequestImpl) then) =
      __$$DownloadJobRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String url, @JsonKey(name: 'format_id') String formatId, String type});
}

/// @nodoc
class __$$DownloadJobRequestImplCopyWithImpl<$Res>
    extends _$DownloadJobRequestCopyWithImpl<$Res, _$DownloadJobRequestImpl>
    implements _$$DownloadJobRequestImplCopyWith<$Res> {
  __$$DownloadJobRequestImplCopyWithImpl(_$DownloadJobRequestImpl _value,
      $Res Function(_$DownloadJobRequestImpl) _then)
      : super(_value, _then);

  /// Create a copy of DownloadJobRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = null,
    Object? formatId = null,
    Object? type = null,
  }) {
    return _then(_$DownloadJobRequestImpl(
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      formatId: null == formatId
          ? _value.formatId
          : formatId // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DownloadJobRequestImpl implements _DownloadJobRequest {
  const _$DownloadJobRequestImpl(
      {required this.url,
      @JsonKey(name: 'format_id') required this.formatId,
      required this.type});

  factory _$DownloadJobRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$DownloadJobRequestImplFromJson(json);

  @override
  final String url;
  @override
  @JsonKey(name: 'format_id')
  final String formatId;
  @override
  final String type;

  @override
  String toString() {
    return 'DownloadJobRequest(url: $url, formatId: $formatId, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DownloadJobRequestImpl &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.formatId, formatId) ||
                other.formatId == formatId) &&
            (identical(other.type, type) || other.type == type));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, url, formatId, type);

  /// Create a copy of DownloadJobRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DownloadJobRequestImplCopyWith<_$DownloadJobRequestImpl> get copyWith =>
      __$$DownloadJobRequestImplCopyWithImpl<_$DownloadJobRequestImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DownloadJobRequestImplToJson(
      this,
    );
  }
}

abstract class _DownloadJobRequest implements DownloadJobRequest {
  const factory _DownloadJobRequest(
      {required final String url,
      @JsonKey(name: 'format_id') required final String formatId,
      required final String type}) = _$DownloadJobRequestImpl;

  factory _DownloadJobRequest.fromJson(Map<String, dynamic> json) =
      _$DownloadJobRequestImpl.fromJson;

  @override
  String get url;
  @override
  @JsonKey(name: 'format_id')
  String get formatId;
  @override
  String get type;

  /// Create a copy of DownloadJobRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DownloadJobRequestImplCopyWith<_$DownloadJobRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DownloadJobResponse _$DownloadJobResponseFromJson(Map<String, dynamic> json) {
  return _DownloadJobResponse.fromJson(json);
}

/// @nodoc
mixin _$DownloadJobResponse {
  bool get success => throw _privateConstructorUsedError;
  String get message => throw _privateConstructorUsedError;
  DownloadJobData? get data => throw _privateConstructorUsedError;
  ApiErrorPayload? get error => throw _privateConstructorUsedError;

  /// Serializes this DownloadJobResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DownloadJobResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DownloadJobResponseCopyWith<DownloadJobResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DownloadJobResponseCopyWith<$Res> {
  factory $DownloadJobResponseCopyWith(
          DownloadJobResponse value, $Res Function(DownloadJobResponse) then) =
      _$DownloadJobResponseCopyWithImpl<$Res, DownloadJobResponse>;
  @useResult
  $Res call(
      {bool success,
      String message,
      DownloadJobData? data,
      ApiErrorPayload? error});

  $DownloadJobDataCopyWith<$Res>? get data;
  $ApiErrorPayloadCopyWith<$Res>? get error;
}

/// @nodoc
class _$DownloadJobResponseCopyWithImpl<$Res, $Val extends DownloadJobResponse>
    implements $DownloadJobResponseCopyWith<$Res> {
  _$DownloadJobResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DownloadJobResponse
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
              as DownloadJobData?,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as ApiErrorPayload?,
    ) as $Val);
  }

  /// Create a copy of DownloadJobResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $DownloadJobDataCopyWith<$Res>? get data {
    if (_value.data == null) {
      return null;
    }

    return $DownloadJobDataCopyWith<$Res>(_value.data!, (value) {
      return _then(_value.copyWith(data: value) as $Val);
    });
  }

  /// Create a copy of DownloadJobResponse
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
abstract class _$$DownloadJobResponseImplCopyWith<$Res>
    implements $DownloadJobResponseCopyWith<$Res> {
  factory _$$DownloadJobResponseImplCopyWith(_$DownloadJobResponseImpl value,
          $Res Function(_$DownloadJobResponseImpl) then) =
      __$$DownloadJobResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool success,
      String message,
      DownloadJobData? data,
      ApiErrorPayload? error});

  @override
  $DownloadJobDataCopyWith<$Res>? get data;
  @override
  $ApiErrorPayloadCopyWith<$Res>? get error;
}

/// @nodoc
class __$$DownloadJobResponseImplCopyWithImpl<$Res>
    extends _$DownloadJobResponseCopyWithImpl<$Res, _$DownloadJobResponseImpl>
    implements _$$DownloadJobResponseImplCopyWith<$Res> {
  __$$DownloadJobResponseImplCopyWithImpl(_$DownloadJobResponseImpl _value,
      $Res Function(_$DownloadJobResponseImpl) _then)
      : super(_value, _then);

  /// Create a copy of DownloadJobResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? data = freezed,
    Object? error = freezed,
  }) {
    return _then(_$DownloadJobResponseImpl(
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
              as DownloadJobData?,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as ApiErrorPayload?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DownloadJobResponseImpl implements _DownloadJobResponse {
  const _$DownloadJobResponseImpl(
      {required this.success, required this.message, this.data, this.error});

  factory _$DownloadJobResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$DownloadJobResponseImplFromJson(json);

  @override
  final bool success;
  @override
  final String message;
  @override
  final DownloadJobData? data;
  @override
  final ApiErrorPayload? error;

  @override
  String toString() {
    return 'DownloadJobResponse(success: $success, message: $message, data: $data, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DownloadJobResponseImpl &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.data, data) || other.data == data) &&
            (identical(other.error, error) || other.error == error));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, success, message, data, error);

  /// Create a copy of DownloadJobResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DownloadJobResponseImplCopyWith<_$DownloadJobResponseImpl> get copyWith =>
      __$$DownloadJobResponseImplCopyWithImpl<_$DownloadJobResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DownloadJobResponseImplToJson(
      this,
    );
  }
}

abstract class _DownloadJobResponse implements DownloadJobResponse {
  const factory _DownloadJobResponse(
      {required final bool success,
      required final String message,
      final DownloadJobData? data,
      final ApiErrorPayload? error}) = _$DownloadJobResponseImpl;

  factory _DownloadJobResponse.fromJson(Map<String, dynamic> json) =
      _$DownloadJobResponseImpl.fromJson;

  @override
  bool get success;
  @override
  String get message;
  @override
  DownloadJobData? get data;
  @override
  ApiErrorPayload? get error;

  /// Create a copy of DownloadJobResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DownloadJobResponseImplCopyWith<_$DownloadJobResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DownloadJobData _$DownloadJobDataFromJson(Map<String, dynamic> json) {
  return _DownloadJobData.fromJson(json);
}

/// @nodoc
mixin _$DownloadJobData {
  @JsonKey(name: 'job_id')
  String get jobId => throw _privateConstructorUsedError;

  /// Serializes this DownloadJobData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DownloadJobData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DownloadJobDataCopyWith<DownloadJobData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DownloadJobDataCopyWith<$Res> {
  factory $DownloadJobDataCopyWith(
          DownloadJobData value, $Res Function(DownloadJobData) then) =
      _$DownloadJobDataCopyWithImpl<$Res, DownloadJobData>;
  @useResult
  $Res call({@JsonKey(name: 'job_id') String jobId});
}

/// @nodoc
class _$DownloadJobDataCopyWithImpl<$Res, $Val extends DownloadJobData>
    implements $DownloadJobDataCopyWith<$Res> {
  _$DownloadJobDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DownloadJobData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? jobId = null,
  }) {
    return _then(_value.copyWith(
      jobId: null == jobId
          ? _value.jobId
          : jobId // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DownloadJobDataImplCopyWith<$Res>
    implements $DownloadJobDataCopyWith<$Res> {
  factory _$$DownloadJobDataImplCopyWith(_$DownloadJobDataImpl value,
          $Res Function(_$DownloadJobDataImpl) then) =
      __$$DownloadJobDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({@JsonKey(name: 'job_id') String jobId});
}

/// @nodoc
class __$$DownloadJobDataImplCopyWithImpl<$Res>
    extends _$DownloadJobDataCopyWithImpl<$Res, _$DownloadJobDataImpl>
    implements _$$DownloadJobDataImplCopyWith<$Res> {
  __$$DownloadJobDataImplCopyWithImpl(
      _$DownloadJobDataImpl _value, $Res Function(_$DownloadJobDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of DownloadJobData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? jobId = null,
  }) {
    return _then(_$DownloadJobDataImpl(
      jobId: null == jobId
          ? _value.jobId
          : jobId // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DownloadJobDataImpl implements _DownloadJobData {
  const _$DownloadJobDataImpl({@JsonKey(name: 'job_id') required this.jobId});

  factory _$DownloadJobDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$DownloadJobDataImplFromJson(json);

  @override
  @JsonKey(name: 'job_id')
  final String jobId;

  @override
  String toString() {
    return 'DownloadJobData(jobId: $jobId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DownloadJobDataImpl &&
            (identical(other.jobId, jobId) || other.jobId == jobId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, jobId);

  /// Create a copy of DownloadJobData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DownloadJobDataImplCopyWith<_$DownloadJobDataImpl> get copyWith =>
      __$$DownloadJobDataImplCopyWithImpl<_$DownloadJobDataImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DownloadJobDataImplToJson(
      this,
    );
  }
}

abstract class _DownloadJobData implements DownloadJobData {
  const factory _DownloadJobData(
          {@JsonKey(name: 'job_id') required final String jobId}) =
      _$DownloadJobDataImpl;

  factory _DownloadJobData.fromJson(Map<String, dynamic> json) =
      _$DownloadJobDataImpl.fromJson;

  @override
  @JsonKey(name: 'job_id')
  String get jobId;

  /// Create a copy of DownloadJobData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DownloadJobDataImplCopyWith<_$DownloadJobDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
