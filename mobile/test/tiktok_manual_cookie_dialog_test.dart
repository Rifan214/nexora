import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/models/tiktok_auth_session.dart';
import 'package:nexora/providers/tiktok_auth_provider.dart';
import 'package:nexora/services/cookie_file_picker_service.dart';
import 'package:nexora/services/tiktok_auth_storage.dart';
import 'package:nexora/widgets/tiktok_manual_cookie_dialog.dart';

import 'tiktok_auth_storage_test.dart';

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

class MockTikTokAuthNotifier extends TikTokAuthController {
  MockTikTokAuthNotifier({this.shouldSucceed = true, this.customError});

  final bool shouldSucceed;
  final String? customError;

  String? capturedSessionid;
  String? capturedSidTt;
  int authenticateCallCount = 0;

  @override
  TikTokAuthState build() => const TikTokAuthState.unauthenticated();

  @override
  Future<void> authenticateWithCookies({
    required String sessionid,
    String? sidTt,
  }) async {
    authenticateCallCount++;
    capturedSessionid = sessionid;
    capturedSidTt = sidTt;

    if (!shouldSucceed) {
      final error = customError ?? 'Server rejected credentials';
      throw ApiException(error);
    }

    final session = TikTokAuthSession(
      sessionId: 'test_tiktok_session_id_123',
      source: 'user_session',
      status: 'available',
      authenticated: true,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await attachSession(session);
  }
}

Widget createTestWidget({
  MockTikTokAuthNotifier? mockNotifier,
  FakeSecureStorage? fakeStorage,
  CookieFilePickerClient? mockFilePicker,
}) {
  final notifier = mockNotifier ?? MockTikTokAuthNotifier();
  final storage = fakeStorage ?? FakeSecureStorage();
  final filePicker = mockFilePicker ?? const MockCookieFilePickerClient();

  return ProviderScope(
    overrides: [
      tikTokAuthProvider.overrideWith(() => notifier),
      tikTokAuthStorageProvider.overrideWithValue(
        TikTokAuthStorage(storage),
      ),
      cookieFilePickerProvider.overrideWithValue(filePicker),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: TikTokManualCookieDialog(),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TikTokManualCookieDialog Specifications & Security Tests', () {
    testWidgets('1. dialog renders title, fields, and action buttons', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Import TikTok Session'), findsOneWidget);
      expect(find.byKey(const Key('import_cookie_file_button')), findsOneWidget);
      expect(find.byKey(const Key('paste_cookie_text_field')), findsOneWidget);
      expect(find.byKey(const Key('manual_sessionid_field')), findsOneWidget);
      expect(find.byKey(const Key('manual_sid_tt_field')), findsOneWidget);
      expect(find.byKey(const Key('manual_import_cancel_button')), findsOneWidget);
      expect(find.byKey(const Key('manual_import_connect_button')), findsOneWidget);
    });

    testWidgets('2. credential fields are obscured by default', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final sessionidField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_sessionid_field')),
          matching: find.byType(TextField),
        ),
      );
      final sidTtField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_sid_tt_field')),
          matching: find.byType(TextField),
        ),
      );

      expect(sessionidField.obscureText, isTrue);
      expect(sidTtField.obscureText, isTrue);
    });

    testWidgets('3. toggling visibility reveals and obscures fields', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap sessionid visibility toggle
      await tester.tap(find.byKey(const Key('toggle_sessionid_visibility')));
      await tester.pumpAndSettle();

      var sessionidField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_sessionid_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(sessionidField.obscureText, isFalse);

      // Tap again to obscure
      await tester.tap(find.byKey(const Key('toggle_sessionid_visibility')));
      await tester.pumpAndSettle();

      sessionidField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('manual_sessionid_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(sessionidField.obscureText, isTrue);
    });

    testWidgets('4. Empty input validation produces prompt error', (tester) async {
      final mockNotifier = MockTikTokAuthNotifier();
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      // Submit without entering tokens
      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Please import a cookies.txt file, paste cookie text, or enter sessionid.'),
        findsOneWidget,
      );
      expect(mockNotifier.authenticateCallCount, 0);
    });

    testWidgets('5. Direct token input triggers authenticateWithCookies', (tester) async {
      final mockNotifier = MockTikTokAuthNotifier();
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      // Enter sessionid and sid_tt
      await tester.enterText(
        find.byKey(const Key('manual_sessionid_field')),
        'my_secret_sessionid_value',
      );
      await tester.enterText(
        find.byKey(const Key('manual_sid_tt_field')),
        'my_secret_sidtt_value',
      );

      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedSessionid, 'my_secret_sessionid_value');
      expect(mockNotifier.capturedSidTt, 'my_secret_sidtt_value');
    });

    testWidgets('6. Pasting raw cookie text directly parses and authenticates', (tester) async {
      final mockNotifier = MockTikTokAuthNotifier();
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      // Enter Netscape cookie content into paste_cookie_text_field
      await tester.enterText(
        find.byKey(const Key('paste_cookie_text_field')),
        '# Netscape HTTP Cookie File\n'
        '.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tparsed_cookie_session_999\n'
        '.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsid_tt\tparsed_cookie_sid_888\n',
      );

      await tester.tap(find.byKey(const Key('manual_import_connect_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedSessionid, 'parsed_cookie_session_999');
      expect(mockNotifier.capturedSidTt, 'parsed_cookie_sid_888');
    });

    testWidgets('7. File import parses cookie file and authenticates directly', (tester) async {
      final mockNotifier = MockTikTokAuthNotifier();
      const mockFileContent =
          '# Netscape HTTP Cookie File\n'
          '.tiktok.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tfrom_file_session_111\n';
      const filePicker = MockCookieFilePickerClient(contentToReturn: mockFileContent);

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: filePicker,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_cookie_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedSessionid, 'from_file_session_111');
      expect(mockNotifier.capturedSidTt, isNull);
    });

    testWidgets('8. Error mapping never echoes raw credentials or sensitive details', (tester) async {
      final timeoutErr = TikTokManualCookieDialog.mapError('Connection timeout to backend');
      expect(timeoutErr, contains('Could not connect to the server'));
      expect(timeoutErr, isNot(contains('timeout')));

      final genericErr = TikTokManualCookieDialog.mapError('Internal 500 error with sessionid=secret_val');
      expect(genericErr, 'Unable to connect this TikTok session. Please verify the imported cookies and try again.');
      expect(genericErr, isNot(contains('secret_val')));

      final parserErr = TikTokManualCookieDialog.mapParserError('Missing required sessionid in cookie header');
      expect(parserErr, 'sessionid cookie was not found in the imported cookie data.');
    });
  });
}
