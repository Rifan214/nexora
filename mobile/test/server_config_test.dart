import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexora/core/config/app_config.dart';
import 'package:nexora/core/network/dio_client.dart';
import 'package:nexora/models/server_config.dart';
import 'package:nexora/providers/server_config_provider.dart';
import 'package:nexora/services/server_config_service.dart';
import 'package:nexora/services/web_socket_service.dart';
import 'package:nexora/utils/server_url_validator.dart';
import 'package:nexora/widgets/server_configuration_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServerUrlValidator', () {
    test('accepts valid IPv4 address without scheme', () {
      final result = ServerUrlValidator.validate(rawHost: '192.168.1.15');
      expect(result.isValid, isTrue);
      expect(result.cleanHost, '192.168.1.15');
      expect(result.cleanPort, 8000);
    });

    test('accepts valid IPv4 address with custom port', () {
      final result = ServerUrlValidator.validate(
        rawHost: '192.168.1.15',
        rawPort: '9000',
      );
      expect(result.isValid, isTrue);
      expect(result.cleanHost, '192.168.1.15');
      expect(result.cleanPort, 9000);
    });

    test('accepts valid inline host:port input', () {
      final result = ServerUrlValidator.validate(rawHost: '192.168.1.15:8080');
      expect(result.isValid, isTrue);
      expect(result.cleanHost, '192.168.1.15');
      expect(result.cleanPort, 8080);
    });

    test('accepts valid hostnames and localhost', () {
      final localResult = ServerUrlValidator.validate(rawHost: 'localhost');
      expect(localResult.isValid, isTrue);
      expect(localResult.cleanHost, 'localhost');

      final domainResult = ServerUrlValidator.validate(rawHost: 'my-laptop.local');
      expect(domainResult.isValid, isTrue);
      expect(domainResult.cleanHost, 'my-laptop.local');
    });

    test('trims whitespace and strips accidental http:// prefix', () {
      final result = ServerUrlValidator.validate(
        rawHost: '   http://192.168.1.20   ',
      );
      expect(result.isValid, isTrue);
      expect(result.cleanHost, '192.168.1.20');
      // Ensure building API URL does not produce double http://
      final config = ServerConfig(host: result.cleanHost!, port: result.cleanPort!);
      expect(config.apiBaseUrl, 'http://192.168.1.20:8000');
      expect(config.apiBaseUrl.startsWith('http://http://'), isFalse);
    });

    test('handles trailing slashes cleanly', () {
      final result = ServerUrlValidator.validate(
        rawHost: '192.168.1.25///',
      );
      expect(result.isValid, isTrue);
      expect(result.cleanHost, '192.168.1.25');
      final config = ServerConfig(host: result.cleanHost!, port: result.cleanPort!);
      expect(config.apiBaseUrl, 'http://192.168.1.25:8000');
    });

    test('rejects empty and whitespace-only input', () {
      final emptyResult = ServerUrlValidator.validate(rawHost: '');
      expect(emptyResult.isValid, isFalse);
      expect(emptyResult.errorMessage, contains('cannot be empty'));

      final spaceResult = ServerUrlValidator.validate(rawHost: '   ');
      expect(spaceResult.isValid, isFalse);
    });

    test('rejects invalid IP addresses', () {
      final result = ServerUrlValidator.validate(rawHost: '999.999.999.999');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Invalid server address'));
    });

    test('rejects invalid port values', () {
      final negativePort = ServerUrlValidator.validate(
        rawHost: '192.168.1.15',
        rawPort: '-1',
      );
      expect(negativePort.isValid, isFalse);

      final overflowPort = ServerUrlValidator.validate(
        rawHost: '192.168.1.15',
        rawPort: '70000',
      );
      expect(overflowPort.isValid, isFalse);
      expect(overflowPort.errorMessage, contains('between 1 and 65535'));
    });

    test('rejects IPv6 addresses with documented limitation', () {
      final result = ServerUrlValidator.validate(rawHost: '2001:0db8:85a3::8a2e:0370:7334');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('IPv6 addresses are not supported'));
    });
  });

  group('ServerConfig & Service Persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('uses default server when no override exists', () async {
      final service = ServerConfigService();
      final config = await service.load();

      expect(config.isCustomOverride, isFalse);
      expect(config.apiBaseUrl, AppConfig.apiBaseUrl);
      expect(config.webSocketBaseUrl, AppConfig.webSocketBaseUrl);
    });

    test('saves and reloads custom server override', () async {
      final service = ServerConfigService();
      await service.saveOverride(host: '192.168.1.50', port: 8080);

      final loaded = await service.load();
      expect(loaded.isCustomOverride, isTrue);
      expect(loaded.host, '192.168.1.50');
      expect(loaded.port, 8080);
      expect(loaded.apiBaseUrl, 'http://192.168.1.50:8080');
      expect(loaded.webSocketBaseUrl, 'ws://192.168.1.50:8080');
    });

    test('persists override across service re-instantiation (simulating app restart)', () async {
      final service1 = ServerConfigService();
      await service1.saveOverride(host: '10.0.2.2', port: 8000);

      // New instance simulates cold launch
      final service2 = ServerConfigService();
      final reloaded = await service2.load();

      expect(reloaded.isCustomOverride, isTrue);
      expect(reloaded.host, '10.0.2.2');
      expect(reloaded.port, 8000);
      expect(reloaded.apiBaseUrl, 'http://10.0.2.2:8000');
    });

    test('resetToDefault restores compile-time configuration', () async {
      final service = ServerConfigService();
      await service.saveOverride(host: '192.168.1.99', port: 9000);

      var config = await service.load();
      expect(config.isCustomOverride, isTrue);

      await service.resetToDefault();
      config = await service.load();
      expect(config.isCustomOverride, isFalse);
      expect(config.apiBaseUrl, AppConfig.apiBaseUrl);
    });
  });

  group('Runtime Server Switching without Restart', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Dio and WebSocket clients dynamically update their base URLs at runtime', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 1. Initially uses default server
      final initialConfig = container.read(effectiveServerConfigProvider);
      expect(initialConfig.isCustomOverride, isFalse);
      expect(container.read(dioProvider).options.baseUrl, AppConfig.apiBaseUrl);

      // 2. User updates server IP via controller
      final controller = container.read(serverConfigProvider.notifier);
      await controller.setOverride(host: '192.168.1.100', port: 8000);

      // 3. Immediately reflects new server in effectiveServerConfigProvider
      final updatedConfig = container.read(effectiveServerConfigProvider);
      expect(updatedConfig.isCustomOverride, isTrue);
      expect(updatedConfig.host, '192.168.1.100');
      expect(updatedConfig.apiBaseUrl, 'http://192.168.1.100:8000');

      // 4. dioProvider produces new Dio instance with the updated baseUrl
      final updatedDio = container.read(dioProvider);
      expect(updatedDio.options.baseUrl, 'http://192.168.1.100:8000');

      // 5. webSocketServiceProvider produces WebSocketService with updated baseUrl
      final updatedWs = container.read(webSocketServiceProvider);
      expect(updatedWs.baseUrl, 'ws://192.168.1.100:8000');

      // 6. Resetting returns to default dynamically
      await controller.resetToDefault();
      final resetConfig = container.read(effectiveServerConfigProvider);
      expect(resetConfig.isCustomOverride, isFalse);
      expect(container.read(dioProvider).options.baseUrl, AppConfig.apiBaseUrl);
      expect(container.read(webSocketServiceProvider).baseUrl, AppConfig.webSocketBaseUrl);
    });
  });

  group('Connection Test Handling', () {
    test('reports success when health check returns 200 with healthy payload', () async {
      final mockDio = Dio();
      final service = ServerConfigService();

      // Intercept request to simulate healthy FastAPI backend
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'message': 'Request successful',
                  'data': {
                    'status': 'healthy',
                    'environment': 'development',
                  },
                },
              ),
            );
          },
        ),
      );

      final result = await service.testConnection('http://192.168.1.15:8000', client: mockDio);
      expect(result.isSuccess, isTrue);
      expect(result.status, 'healthy');
      expect(result.environment, 'development');
      expect(result.message, contains('Connected successfully'));
    });

    test('reports timeout without raw stack trace', () async {
      final mockDio = Dio();
      final service = ServerConfigService();

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
                message: 'Connection timed out',
              ),
            );
          },
        ),
      );

      final result = await service.testConnection('http://192.168.1.15:8000', client: mockDio);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('timed out'));
    });

    test('reports connection refused without raw stack trace', () async {
      final mockDio = Dio();
      final service = ServerConfigService();

      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                message: 'Connection refused',
              ),
            );
          },
        ),
      );

      final result = await service.testConnection('http://192.168.1.15:8000', client: mockDio);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Connection refused'));
    });
  });

  group('ServerConfigurationCard Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders current server address and controls', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ServerConfigurationCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Development Server'), findsOneWidget);
      expect(find.text('Current Active Server'), findsOneWidget);
      expect(find.text('Server Address'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows validation error when server address is empty', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ServerConfigurationCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clear server address field
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.first, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Server address cannot be empty.'), findsOneWidget);
    });

    testWidgets('applies valid IP override and updates active server badge', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ServerConfigurationCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.first, '192.168.1.75');
      await tester.enterText(textFields.last, '8000');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('http://192.168.1.75:8000'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Reset to Default'), findsOneWidget);
    });
  });
}
