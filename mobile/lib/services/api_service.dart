import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
    return _sendJson(
      () => _dio.get<Object?>(path),
      requestLabel: 'GET $path',
    );
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    return _sendJson(
      () => _dio.post<Object?>(path, data: data),
      requestLabel: 'POST $path',
    );
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
    Future<Response<Object?>> Function() request, {
    required String requestLabel,
  }) async {
    try {
      final response = await request();
      final data = response.data;

      if (data is Map<String, dynamic>) {
        _logJsonResponse(requestLabel, data);
        return data;
      }

      if (data is Map) {
        final response = Map<String, dynamic>.from(data);
        _logJsonResponse(requestLabel, response);
        return response;
      }

      if (data is String && _looksLikeHtml(data)) {
        throw const ApiException(
          'Backend URL is pointing to the Flutter app. Configure the API base URL to the backend server.',
        );
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
      case DioExceptionType.transformTimeout:
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
      final error = payload['error'];
      if (error is Map) {
        final errorPayload = Map<String, dynamic>.from(error);
        final details = errorPayload['details'];
        if (details is String && details.trim().isNotEmpty) {
          return details.trim();
        }
      }

      final message = payload['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }

    final statusCode = response.statusCode;
    if (statusCode == null) {
      return 'Server unavailable.';
    }

    return 'Server returned status code $statusCode.';
  }

  bool _looksLikeHtml(String value) {
    final normalized = value.trimLeft().toLowerCase();
    return normalized.startsWith('<!doctype html') ||
        normalized.startsWith('<html');
  }

  void _logJsonResponse(String requestLabel, Map<String, dynamic> response) {
    if (kDebugMode) {
      debugPrint('$requestLabel raw JSON response: ${jsonEncode(response)}');
    }
  }
}
