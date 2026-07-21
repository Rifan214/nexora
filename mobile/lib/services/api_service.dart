import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/dio_client.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(dioProvider));
});

class ApiService {
  const ApiService(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> getJson(String path) async {
    return _sendJson(() => _dio.get<Object?>(path));
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    return _sendJson(() => _dio.post<Object?>(path, data: data));
  }

  Future<void> downloadFile(
    String path, {
    required Object savePath,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.download(
        path,
        savePath,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
        deleteOnError: true,
      );
    } on DioException catch (error) {
      throw ApiException(_messageForDioException(error));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Unable to download the file.');
    }
  }

  Future<Map<String, dynamic>> _sendJson(
    Future<Response<Object?>> Function() request,
  ) async {
    try {
      final response = await request();
      final data = response.data;

      if (data is Map<String, dynamic>) {
        return data;
      }

      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }

      throw const ApiException('Invalid response from server.');
    } on DioException catch (error) {
      throw ApiException(_messageForDioException(error));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Unable to contact the backend.');
    }
  }

  String _messageForDioException(DioException error) {
    if (error.error is FileSystemException) {
      return 'Unable to write the downloaded file.';
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please try again.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Network unavailable. Check your connection and backend URL.';
      case DioExceptionType.badResponse:
        return _messageForBadResponse(error.response);
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badCertificate:
        return 'The backend certificate could not be verified.';
    }
  }

  String _messageForBadResponse(Response<dynamic>? response) {
    if (response == null) {
      return 'Server unavailable.';
    }

    final data = response.data;
    if (data is Map) {
      final payload = Map<String, dynamic>.from(data);
      final message = payload['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }

    final statusCode = response.statusCode;
    if (statusCode == null) {
      return 'Server unavailable.';
    }

    return 'Server returned status code $statusCode.';
  }
}
