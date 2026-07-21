import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config/app_config.dart';

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  return const WebSocketService();
});

class WebSocketService {
  const WebSocketService();

  static const _maxReconnectAttempts = 3;

  Stream<Map<String, dynamic>> connectJson(String path) async* {
    final uri = _buildUri(path);
    var reconnectAttempt = 0;

    while (true) {
      WebSocketChannel? channel;

      try {
        channel = WebSocketChannel.connect(uri);
        await channel.ready.timeout(AppConfig.connectTimeout);

        await for (final message in channel.stream) {
          yield _decodeJsonMessage(message);
        }

        return;
      } catch (error) {
        if (error is WebSocketConfigurationException ||
            error is WebSocketMessageException) {
          rethrow;
        }

        reconnectAttempt += 1;
        if (reconnectAttempt > _maxReconnectAttempts) {
          throw WebSocketServiceException(_messageFor(error));
        }

        await Future<void>.delayed(_reconnectDelay(reconnectAttempt));
      } finally {
        await channel?.sink.close();
      }
    }
  }

  Uri _buildUri(String path) {
    final baseUrl = AppConfig.webSocketBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const WebSocketConfigurationException(
        'WebSocket base URL is not configured.',
      );
    }

    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      throw const WebSocketConfigurationException(
        'WebSocket base URL is invalid.',
      );
    }

    if (baseUri.scheme != 'ws' && baseUri.scheme != 'wss') {
      throw const WebSocketConfigurationException(
        'WebSocket base URL must use ws or wss.',
      );
    }

    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final basePath = baseUri.path.isEmpty
        ? '/'
        : baseUri.path.endsWith('/')
            ? baseUri.path
            : '${baseUri.path}/';

    return baseUri.replace(path: '$basePath$normalizedPath');
  }

  Map<String, dynamic> _decodeJsonMessage(Object? message) {
    final String text;
    if (message is String) {
      text = message;
    } else if (message is List<int>) {
      text = utf8.decode(message);
    } else {
      throw const WebSocketMessageException(
        'Invalid progress update from server.',
      );
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      throw const WebSocketMessageException(
        'Invalid progress update from server.',
      );
    }

    throw const WebSocketMessageException(
      'Invalid progress update from server.',
    );
  }

  Duration _reconnectDelay(int attempt) {
    return Duration(milliseconds: 400 * attempt);
  }

  String _messageFor(Object error) {
    if (error is TimeoutException) {
      return 'Connection timed out while opening progress updates.';
    }

    if (error is WebSocketServiceException) {
      return error.message;
    }

    return 'Unable to connect to download progress.';
  }
}

class WebSocketServiceException implements Exception {
  const WebSocketServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebSocketConfigurationException extends WebSocketServiceException {
  const WebSocketConfigurationException(super.message);
}

class WebSocketMessageException extends WebSocketServiceException {
  const WebSocketMessageException(super.message);
}
