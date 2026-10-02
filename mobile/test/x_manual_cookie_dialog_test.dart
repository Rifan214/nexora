import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/services/cookie_file_picker_service.dart';
import 'package:nexora/services/x_auth_storage.dart';
import 'package:nexora/widgets/x_manual_cookie_dialog.dart';

import 'x_auth_storage_test.dart';

class MockCookieFilePickerClient implements CookieFilePickerClient {
  const MockCookieFilePickerClient({
    this.contentToReturn,
    this.shouldThrow = false,
  });

  final String? contentToReturn;
  final bool shouldThrow;

  @override
  Future<String?> pickAndReadCookieFile() async {
    if (shouldThrow) {
      throw Exception('Disk read error / access denied');
    }
    return contentToReturn;
  }
}

class MockXAuthNotifier extends XAuthController {
  MockXAuthNotifier({this.shouldSucceed = true, this.customError, this.delay});

  final bool shouldSucceed;
  final String? customError;
  final Duration? delay;

  String? capturedAuthToken;
  String? capturedCt0;
  int authenticateCallCount = 0;

  @override
  XAuthState build() => const XAuthState.unauthenticated();

  @override
  Future<void> authenticateWithCookies({
    required String authToken,
    required String ct0,
  }) async {
    authenticateCallCount++;
    capturedAuthToken = authToken;
    capturedCt0 = ct0;

    if (delay != null) {
      await Future<void>.delayed(delay!);
    }

    if (!shouldSucceed) {
      final error = customError ?? 'Server rejected credentials';
      throw ApiException(error);
    }

    final session = XAuthSession(
      sessionId: 'test_session_id_123',
      source: 'user_session',
      status: 'available',
      authenticated: true,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await attachSession(session);
  }
}

Widget createTestWidget({
  MockXAuthNotifier? mockNotifier,
  FakeSecureStorage? fakeStorage,
  CookieFilePickerClient? mockFilePicker,
}) {
  final notifier = mockNotifier ?? MockXAuthNotifier();
  final storage = fakeStorage ?? FakeSecureStorage();
  final filePicker = mockFilePicker ?? const MockCookieFilePickerClient();

  return ProviderScope(
    overrides: [
      xAuthProvider.overrideWith(() => notifier),
      xAuthStorageProvider.overrideWithValue(
        XAuthStorage(storage),
      ),
      cookieFilePickerProvider.overrideWithValue(filePicker),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: XManualCookieDialog(),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('XManualCookieDialog Specifications & Security Tests', () {
    testWidgets('1. dialog renders both fields and action buttons', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Import X Session'), findsOneWidget);
      expect(find.byKey(const Key('manual_auth_token_field')), findsOneWidget);
      expect(find.byKey(const Key('manual_ct0_field')), findsOneWidget);
      expect(find.byKey(const Key('manual_import_cancel_button')), findsOneWidget);
      expect(find.byKey(const Key('manual_import_connect_button')), findsOneWidget);
    });

    testWidgets('2. fields are obscured by default for privacy', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final authField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_auth_token_field')),
          matching: find.byType(TextField),
        ),
      );
      final ct0Field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_ct0_field')),
          matching: find.byType(TextField),
        ),
      );

      expect(authField.obscureText, isTrue);
      expect(ct0Field.obscureText, isTrue);
    });

    testWidgets('3. toggling visibility reveals and obscures fields', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap auth_token visibility toggle
      await tester.tap(find.byKey(const Key('toggle_auth_token_visibility')));
      await tester.pumpAndSettle();

      var authField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_auth_token_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(authField.obscureText, isFalse);

      // Tap again to obscure
      await tester.tap(find.byKey(const Key('toggle_auth_token_visibility')));
      await tester.pumpAndSettle();

      authField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_auth_token_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(authField.obscureText, isTrue);
    });

    testWidgets('4. empty auth_token rejected with safe validation message',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        'some_ct0_value',
      );
      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter both X session cookies.'), findsOneWidget);
    });

    testWidgets('5. empty ct0 rejected with safe validation message',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        'some_auth_token_value',
      );
      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter both X session cookies.'), findsOneWidget);
    });

    testWidgets('6. whitespace trimming ensures tokens are cleaned before transfer',
        (tester) async {
      final mockNotifier = MockXAuthNotifier();
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        '   SYNTHETIC_AUTH_TOKEN_VALUE   \n',
      );
      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        ' \t  SYNTHETIC_CT0_VALUE   ',
      );

      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.capturedAuthToken, 'SYNTHETIC_AUTH_TOKEN_VALUE');
      expect(mockNotifier.capturedCt0, 'SYNTHETIC_CT0_VALUE');
    });

    testWidgets('7. max length handling limits input length to 512', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final authField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_auth_token_field')),
          matching: find.byType(TextField),
        ),
      );
      final ct0Field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_ct0_field')),
          matching: find.byType(TextField),
        ),
      );

      expect(authField.maxLength, 512);
      expect(ct0Field.maxLength, 512);
    });

    testWidgets('8. paste button behavior: reads clipboard on explicit tap and trims',
        (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': '  COPIED_CLIPBOARD_TOKEN_VALUE  \n'};
          }
          return null;
        },
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('paste_auth_token_button')));
      await tester.pumpAndSettle();

      final authField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_auth_token_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(authField.controller?.text, 'COPIED_CLIPBOARD_TOKEN_VALUE');
    });

    testWidgets('9. connect button disables and shows progress while submitting',
        (tester) async {
      final mockNotifier = MockXAuthNotifier(delay: const Duration(milliseconds: 50));
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        'token_123',
      );
      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        'ct0_456',
      );

      // Trigger tap
      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pump();

      // Progress indicator should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(mockNotifier.authenticateCallCount, 1);
    });

    testWidgets('10. successful session calls existing controller and clears inputs',
        (tester) async {
      final mockNotifier = MockXAuthNotifier();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('open_dialog_btn'),
                onPressed: () => XManualCookieDialog.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      // Wrap in ProviderScope
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            xAuthProvider.overrideWith(() => mockNotifier),
            xAuthStorageProvider.overrideWithValue(
              XAuthStorage(FakeSecureStorage()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  key: const Key('open_dialog_btn'),
                  onPressed: () => XManualCookieDialog.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_dialog_btn')));
      await tester.pumpAndSettle();

      expect(find.byType(XManualCookieDialog), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        'TEST_TOKEN_VAL',
      );
      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        'TEST_CT0_VAL',
      );

      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      // Dialog is closed on success
      expect(find.byType(XManualCookieDialog), findsNothing);
      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedAuthToken, 'TEST_TOKEN_VAL');
      expect(mockNotifier.capturedCt0, 'TEST_CT0_VAL');
    });

    testWidgets(
        '11. backend failure produces safe generic message and raw credentials never appear in error UI',
        (tester) async {
      final mockNotifier = MockXAuthNotifier(
        shouldSucceed: false,
        customError: 'Internal server error with token=SECRET_TOKEN_XYZ and ct0=SECRET_CT0_ABC',
      );

      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        'SECRET_TOKEN_XYZ',
      );
      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        'SECRET_CT0_ABC',
      );

      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      // Must display safe generic error
      expect(find.byKey(const Key('manual_cookie_error_text')), findsOneWidget);
      final errorWidget = tester.widget<Text>(find.byKey(const Key('manual_cookie_error_text')));
      expect(
        errorWidget.data,
        'Unable to connect this X session. Please verify the imported cookies and try again.',
      );

      // Raw server exception string must NOT appear
      expect(find.textContaining('Internal server error'), findsNothing);

      // Secret tokens must NOT appear in error banner
      expect(errorWidget.data, isNot(contains('SECRET_TOKEN_XYZ')));
      expect(errorWidget.data, isNot(contains('SECRET_CT0_ABC')));
    });

    testWidgets('12. cancel button clears inputs and closes dialog', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            xAuthProvider.overrideWith(() => MockXAuthNotifier()),
            xAuthStorageProvider.overrideWithValue(
              XAuthStorage(FakeSecureStorage()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  key: const Key('open_dialog_btn'),
                  onPressed: () => XManualCookieDialog.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_dialog_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        'token_to_discard',
      );
      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        'ct0_to_discard',
      );

      await tester.tap(find.byKey(const Key('manual_import_cancel_button')));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.byType(XManualCookieDialog), findsNothing);
    });

    testWidgets('13. duplicate submission is prevented while submitting', (tester) async {
      final mockNotifier = MockXAuthNotifier(delay: const Duration(milliseconds: 50));
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        'token_123',
      );
      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        'ct0_456',
      );

      // Tap connect
      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pump(); // Start submission

      // Tap connect again while submitting
      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      // Controller should only be called once
      expect(mockNotifier.authenticateCallCount, 1);
    });

    testWidgets('14. security: only session_id is persisted to secure storage', (tester) async {
      final fakeStorage = FakeSecureStorage();
      final mockNotifier = MockXAuthNotifier();

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        fakeStorage: fakeStorage,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        'SUPER_SECRET_AUTH_TOKEN_VALUE',
      );
      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        'SUPER_SECRET_CT0_VALUE',
      );

      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      // Verify what was stored in secure storage
      final storedData = fakeStorage.data;
      expect(storedData.containsKey('nexora.x_auth.session_id'), isTrue);
      expect(storedData['nexora.x_auth.session_id'], 'test_session_id_123');

      // Crucial: auth_token and ct0 must NEVER be in storage
      for (final key in storedData.keys) {
        final val = storedData[key];
        expect(val, isNot(contains('SUPER_SECRET_AUTH_TOKEN_VALUE')));
        expect(val, isNot(contains('SUPER_SECRET_CT0_VALUE')));
      }
      expect(storedData.containsKey('auth_token'), isFalse);
      expect(storedData.containsKey('ct0'), isFalse);
    });
  });

  group('XManualCookieDialog Error Mapping Unit Tests', () {
    test('mapError sanitizes network, storage, and arbitrary server errors', () {
      expect(
        XManualCookieDialog.mapError('SocketException: Connection refused'),
        'Could not connect to the server. Please check your connection and try again.',
      );
      expect(
        XManualCookieDialog.mapError('TimeoutException: network request timed out'),
        'Could not connect to the server. Please check your connection and try again.',
      );
      expect(
        XManualCookieDialog.mapError('Storage failure: session not saved locally'),
        'X session was created, but could not be saved locally.',
      );
      expect(
        XManualCookieDialog.mapError('Invalid X credentials for auth_token=secret_val'),
        'Unable to connect this X session. Please verify the imported cookies and try again.',
      );
      expect(
        XManualCookieDialog.mapError(null),
        'Unable to connect this X session. Please verify the imported cookies and try again.',
      );
      expect(
        XManualCookieDialog.mapError(''),
        'Unable to connect this X session. Please verify the imported cookies and try again.',
      );
    });

    test('mapParserError sanitizes missing tokens, invalid JSON, and errors safely', () {
      expect(
        XManualCookieDialog.mapParserError('Missing required cookie: auth_token'),
        'auth_token cookie was not found in the imported cookie data.',
      );
      expect(
        XManualCookieDialog.mapParserError('Missing required cookie: ct0'),
        'ct0 (CSRF token) cookie was not found in the imported cookie data.',
      );
      expect(
        XManualCookieDialog.mapParserError('Cookie value is empty for auth_token'),
        'Imported cookie data contains empty credential values.',
      );
      expect(
        XManualCookieDialog.mapParserError('Cookie value exceeds 512 characters'),
        'Imported cookie value exceeds maximum allowed length.',
      );
      expect(
        XManualCookieDialog.mapParserError('Invalid JSON array cookie export'),
        'Invalid JSON cookie export format.',
      );
      expect(
        XManualCookieDialog.mapParserError('Some secret token auth_token=abc1234567890'),
        'Could not recognize valid X cookies in the provided input.',
      );
      expect(
        XManualCookieDialog.mapParserError(null),
        'Could not recognize valid X cookies in the provided input.',
      );
    });
  });

  group('Phase 4 — UI Cookie Import Specification & Security Tests', () {
    testWidgets('A. Import valid Netscape cookies.txt -> parses & authenticates',
        (tester) async {
      const netscapeContent =
          "# Netscape HTTP Cookie File\n"
          ".twitter.com\tTRUE\t/\tTRUE\t1799999999\tauth_token\tnetscape_auth_token_999\n"
          ".x.com\tTRUE\t/\tTRUE\t1799999999\tct0\tnetscape_ct0_999\n";

      final mockNotifier = MockXAuthNotifier();
      final mockPicker = const MockCookieFilePickerClient(contentToReturn: netscapeContent);

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: mockPicker,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import_cookie_file_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedAuthToken, 'netscape_auth_token_999');
      expect(mockNotifier.capturedCt0, 'netscape_ct0_999');
    });

    testWidgets('B. Import valid JSON cookie export -> parses & authenticates',
        (tester) async {
      const jsonContent = '''[
        {"name": "auth_token", "value": "json_auth_token_888", "domain": ".x.com"},
        {"name": "ct0", "value": "json_ct0_888", "domain": ".x.com"}
      ]''';

      final mockNotifier = MockXAuthNotifier();
      final mockPicker = const MockCookieFilePickerClient(contentToReturn: jsonContent);

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: mockPicker,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedAuthToken, 'json_auth_token_888');
      expect(mockNotifier.capturedCt0, 'json_ct0_888');
    });

    testWidgets('C. Paste raw Cookie header -> parses & authenticates via Connect',
        (tester) async {
      final mockNotifier = MockXAuthNotifier();

      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('paste_cookie_text_field')),
        'auth_token=header_auth_token_777; ct0=header_ct0_777',
      );

      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedAuthToken, 'header_auth_token_777');
      expect(mockNotifier.capturedCt0, 'header_ct0_777');
    });

    testWidgets('D1. File unreadable -> safe UI error, no backend call',
        (tester) async {
      final mockNotifier = MockXAuthNotifier();
      final mockPicker = const MockCookieFilePickerClient(shouldThrow: true);

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: mockPicker,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 0);
      expect(find.byKey(const Key('manual_cookie_error_text')), findsOneWidget);
      final errorWidget = tester.widget<Text>(find.byKey(const Key('manual_cookie_error_text')));
      expect(errorWidget.data, 'Could not read or process the selected file.');
    });

    testWidgets('D2. File content invalid -> safe UI error, no backend call',
        (tester) async {
      final mockNotifier = MockXAuthNotifier();
      final mockPicker = const MockCookieFilePickerClient(
        contentToReturn: 'random arbitrary text with no cookie structure',
      );

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: mockPicker,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 0);
      expect(find.byKey(const Key('manual_cookie_error_text')), findsOneWidget);
      final errorWidget = tester.widget<Text>(find.byKey(const Key('manual_cookie_error_text')));
      expect(errorWidget.data, isNot(contains('random arbitrary text')));
      expect(errorWidget.data, 'auth_token cookie was not found in the imported cookie data.');
    });

    testWidgets('E. Missing auth_token in imported cookies -> safe error, no backend call',
        (tester) async {
      final mockNotifier = MockXAuthNotifier();
      final mockPicker = const MockCookieFilePickerClient(
        contentToReturn: '.x.com\tTRUE\t/\tTRUE\t1799999999\tct0\tsecret_ct0_token_val\n',
      );

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: mockPicker,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 0);
      expect(find.byKey(const Key('manual_cookie_error_text')), findsOneWidget);
      final errorWidget = tester.widget<Text>(find.byKey(const Key('manual_cookie_error_text')));
      expect(errorWidget.data, 'auth_token cookie was not found in the imported cookie data.');
      expect(errorWidget.data, isNot(contains('secret_ct0_token_val')));
    });

    testWidgets('F. Missing ct0 in imported cookies -> safe error, no backend call',
        (tester) async {
      final mockNotifier = MockXAuthNotifier();
      final mockPicker = const MockCookieFilePickerClient(
        contentToReturn: '.x.com\tTRUE\t/\tTRUE\t1799999999\tauth_token\tsecret_auth_token_val\n',
      );

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: mockPicker,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 0);
      expect(find.byKey(const Key('manual_cookie_error_text')), findsOneWidget);
      final errorWidget = tester.widget<Text>(find.byKey(const Key('manual_cookie_error_text')));
      expect(errorWidget.data, 'ct0 (CSRF token) cookie was not found in the imported cookie data.');
      expect(errorWidget.data, isNot(contains('secret_auth_token_val')));
    });

    testWidgets('G. Backend authentication failure -> UI returns to retry state without leaking credentials',
        (tester) async {
      final mockNotifier = MockXAuthNotifier(
        shouldSucceed: false,
        customError: '401 Unauthorized for token=secret_auth_tok_backend',
      );
      final mockPicker = const MockCookieFilePickerClient(
        contentToReturn:
            '.x.com\tTRUE\t/\tTRUE\t1799999999\tauth_token\tsecret_auth_tok_backend\n'
            '.x.com\tTRUE\t/\tTRUE\t1799999999\tct0\tsecret_ct0_backend\n',
      );

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: mockPicker,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);

      // Verify safe UI message
      final errorWidget = tester.widget<Text>(find.byKey(const Key('manual_cookie_error_text')));
      expect(errorWidget.data, isNot(contains('secret_auth_tok_backend')));
      expect(errorWidget.data, isNot(contains('secret_ct0_backend')));
      expect(
        errorWidget.data,
        'Unable to connect this X session. Please verify the imported cookies and try again.',
      );

      // UI returns to retry state: buttons are enabled again
      final importButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('import_cookie_file_button')),
      );
      final connectButton = tester.widget<FilledButton>(
        find.byKey(const Key('manual_import_connect_button')),
      );
      expect(importButton.onPressed, isNotNull);
      expect(connectButton.onPressed, isNotNull);
    });

    testWidgets('H. Loading state prevents duplicate file import and connect submits',
        (tester) async {
      final mockNotifier = MockXAuthNotifier(delay: const Duration(milliseconds: 100));
      final mockPicker = const MockCookieFilePickerClient(
        contentToReturn:
            '.x.com\tTRUE\t/\tTRUE\t1799999999\tauth_token\tauth_tok_race\n'
            '.x.com\tTRUE\t/\tTRUE\t1799999999\tct0\tct0_race\n',
      );

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: mockPicker,
      ));
      await tester.pumpAndSettle();

      // Trigger first import
      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pump(); // Start async work

      // Buttons are disabled
      var importBtn = tester.widget<OutlinedButton>(find.byKey(const Key('import_cookie_file_button')));
      var connectBtn = tester.widget<FilledButton>(find.byKey(const Key('manual_import_connect_button')));
      expect(importBtn.onPressed, isNull);
      expect(connectBtn.onPressed, isNull);

      // Try tapping again while submitting
      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
    });

    testWidgets('I. Security: raw cookies and credentials do not leak in widget tree or toString',
        (tester) async {
      const secretAuth = 'TOP_SECRET_AUTH_TOKEN_99999';
      const secretCt0 = 'TOP_SECRET_CT0_99999';
      const netscapeData =
          '# Netscape\n.x.com\tTRUE\t/\tTRUE\t1799999999\tauth_token\t$secretAuth\n.x.com\tTRUE\t/\tTRUE\t1799999999\tct0\t$secretCt0\n';

      final mockNotifier = MockXAuthNotifier();
      final mockPicker = const MockCookieFilePickerClient(contentToReturn: netscapeData);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            xAuthProvider.overrideWith(() => mockNotifier),
            xAuthStorageProvider.overrideWithValue(
              XAuthStorage(FakeSecureStorage()),
            ),
            cookieFilePickerProvider.overrideWithValue(mockPicker),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  key: const Key('open_dialog_btn'),
                  onPressed: () => XManualCookieDialog.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_dialog_btn')));
      await tester.pumpAndSettle();

      expect(find.byType(XManualCookieDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      // Ensure tokens were passed to notifier
      expect(mockNotifier.capturedAuthToken, secretAuth);
      expect(mockNotifier.capturedCt0, secretCt0);

      // Dialog is dismissed on success
      expect(find.byType(XManualCookieDialog), findsNothing);

      // No secret string appears in the widget hierarchy
      expect(find.textContaining(secretAuth), findsNothing);
      expect(find.textContaining(secretCt0), findsNothing);

      // toString of widget never exposes secrets
      const dialog = XManualCookieDialog();
      expect(dialog.toString(), isNot(contains(secretAuth)));
      expect(dialog.toString(), isNot(contains(secretCt0)));
    });

    testWidgets('J. Existing manual cookie entry remains working without regression',
        (tester) async {
      final mockNotifier = MockXAuthNotifier();

      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('manual_auth_token_field')),
        'manual_direct_token_val',
      );
      await tester.enterText(
        find.byKey(const Key('manual_ct0_field')),
        'manual_direct_ct0_val',
      );

      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedAuthToken, 'manual_direct_token_val');
      expect(mockNotifier.capturedCt0, 'manual_direct_ct0_val');
    });
  });
}
