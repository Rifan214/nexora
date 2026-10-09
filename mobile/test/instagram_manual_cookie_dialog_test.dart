import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/network/api_exception.dart';
import 'package:nexora/core/theme/app_theme.dart';
import 'package:nexora/models/instagram_auth_session.dart';
import 'package:nexora/providers/instagram_auth_provider.dart';
import 'package:nexora/services/cookie_file_picker_service.dart';
import 'package:nexora/services/instagram_auth_storage.dart';
import 'package:nexora/widgets/instagram_manual_cookie_dialog.dart';

import 'instagram_auth_storage_test.dart';

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

class MockInstagramAuthNotifier extends InstagramAuthController {
  MockInstagramAuthNotifier({this.shouldSucceed = true, this.customError});

  final bool shouldSucceed;
  final String? customError;

  String? capturedSessionid;
  String? capturedDsUserId;
  String? capturedCsrftoken;
  int authenticateCallCount = 0;

  @override
  InstagramAuthState build() => const InstagramAuthState.unauthenticated();

  @override
  Future<void> authenticateWithCookies({
    required String sessionid,
    String? dsUserId,
    String? csrftoken,
  }) async {
    authenticateCallCount++;
    capturedSessionid = sessionid;
    capturedDsUserId = dsUserId;
    capturedCsrftoken = csrftoken;

    if (!shouldSucceed) {
      final error = customError ?? 'Server rejected credentials';
      throw ApiException(error);
    }

    final session = InstagramAuthSession(
      sessionId: 'test_ig_session_id_123',
      source: 'user_session',
      status: 'available',
      authenticated: true,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await attachSession(session);
  }
}

Widget createTestWidget({
  MockInstagramAuthNotifier? mockNotifier,
  FakeSecureStorage? fakeStorage,
  CookieFilePickerClient? mockFilePicker,
}) {
  final notifier = mockNotifier ?? MockInstagramAuthNotifier();
  final storage = fakeStorage ?? FakeSecureStorage();
  final filePicker = mockFilePicker ?? const MockCookieFilePickerClient();

  return ProviderScope(
    overrides: [
      instagramAuthProvider.overrideWith(() => notifier),
      instagramAuthStorageProvider.overrideWithValue(
        InstagramAuthStorage(storage),
      ),
      cookieFilePickerProvider.overrideWithValue(filePicker),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: InstagramManualCookieDialog(),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstagramManualCookieDialog Specifications & Security Tests', () {
    testWidgets('1. dialog renders title, fields, and action buttons', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Instagram Cookie Authentication'), findsOneWidget);
      expect(find.byKey(const Key('instagram_import_file_button')), findsOneWidget);
      expect(find.byKey(const Key('instagram_cookie_text_field')), findsOneWidget);
      expect(find.byKey(const Key('instagram_sessionid_field')), findsOneWidget);
      expect(find.byKey(const Key('instagram_ds_user_id_field')), findsOneWidget);
      expect(find.byKey(const Key('instagram_cancel_button')), findsOneWidget);
      expect(find.byKey(const Key('instagram_connect_button')), findsOneWidget);
    });

    testWidgets('2. credential fields are obscured by default', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final sessionidField = tester.widget<TextField>(
        find.byKey(const Key('instagram_sessionid_field')),
      );
      final dsUserIdField = tester.widget<TextField>(
        find.byKey(const Key('instagram_ds_user_id_field')),
      );

      expect(sessionidField.obscureText, isTrue);
      expect(dsUserIdField.obscureText, isTrue);
    });

    testWidgets('3. toggling visibility reveals and obscures fields', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap sessionid visibility toggle
      await tester.tap(find.byKey(const Key('instagram_toggle_sessionid_visibility')));
      await tester.pumpAndSettle();

      var sessionidField = tester.widget<TextField>(
        find.byKey(const Key('instagram_sessionid_field')),
      );
      expect(sessionidField.obscureText, isFalse);

      // Tap again to obscure
      await tester.tap(find.byKey(const Key('instagram_toggle_sessionid_visibility')));
      await tester.pumpAndSettle();

      sessionidField = tester.widget<TextField>(
        find.byKey(const Key('instagram_sessionid_field')),
      );
      expect(sessionidField.obscureText, isTrue);
    });

    testWidgets('4. Empty input validation produces prompt error', (tester) async {
      final mockNotifier = MockInstagramAuthNotifier();
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      // Submit without entering tokens
      await tester.tap(find.byKey(const Key('instagram_connect_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Please import a cookies.txt file, paste cookie text, or enter sessionid.'),
        findsOneWidget,
      );
      expect(mockNotifier.authenticateCallCount, 0);
    });

    testWidgets('5. Direct token input triggers authenticateWithCookies', (tester) async {
      final mockNotifier = MockInstagramAuthNotifier();
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      // Enter sessionid and ds_user_id
      await tester.enterText(
        find.byKey(const Key('instagram_sessionid_field')),
        'my_secret_sessionid%3Avalue',
      );
      await tester.enterText(
        find.byKey(const Key('instagram_ds_user_id_field')),
        '123456789',
      );

      await tester.tap(find.byKey(const Key('instagram_connect_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedSessionid, 'my_secret_sessionid%3Avalue');
      expect(mockNotifier.capturedDsUserId, '123456789');
    });

    testWidgets('6. Pasting raw cookie text directly parses and authenticates', (tester) async {
      final mockNotifier = MockInstagramAuthNotifier();
      await tester.pumpWidget(createTestWidget(mockNotifier: mockNotifier));
      await tester.pumpAndSettle();

      // Enter Netscape cookie content into paste field
      await tester.enterText(
        find.byKey(const Key('instagram_cookie_text_field')),
        '# Netscape HTTP Cookie File\n'
        '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tparsed_ig_session_999%3Axyz\n'
        '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tds_user_id\t987654321\n',
      );

      await tester.tap(find.byKey(const Key('instagram_connect_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedSessionid, 'parsed_ig_session_999%3Axyz');
      expect(mockNotifier.capturedDsUserId, '987654321');
    });

    testWidgets('7. File import parses cookie file and authenticates directly', (tester) async {
      final mockNotifier = MockInstagramAuthNotifier();
      const mockFileContent =
          '# Netscape HTTP Cookie File\n'
          '.instagram.com\tTRUE\t/\tTRUE\t1790000000\tsessionid\tfrom_file_ig_session_111\n';
      const filePicker = MockCookieFilePickerClient(contentToReturn: mockFileContent);

      await tester.pumpWidget(createTestWidget(
        mockNotifier: mockNotifier,
        mockFilePicker: filePicker,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('instagram_import_file_button')));
      await tester.pumpAndSettle();

      expect(mockNotifier.authenticateCallCount, 1);
      expect(mockNotifier.capturedSessionid, 'from_file_ig_session_111');
      expect(mockNotifier.capturedDsUserId, isNull);
    });

    testWidgets('8. Error mapping never echoes raw credentials or sensitive details', (tester) async {
      final timeoutErr = InstagramManualCookieDialog.mapError('Connection timeout to backend');
      expect(timeoutErr, contains('Could not connect to the server'));
      expect(timeoutErr, isNot(contains('timeout')));

      final genericErr = InstagramManualCookieDialog.mapError('Internal 500 error with sessionid=secret_val');
      expect(genericErr, 'Unable to connect this Instagram session. Please verify the imported cookies and try again.');
      expect(genericErr, isNot(contains('secret_val')));

      final parserErr = InstagramManualCookieDialog.mapParserError('Missing required sessionid in cookie header');
      expect(parserErr, 'sessionid cookie was not found in the imported cookie data.');
    });

    testWidgets('9. Regression: dialog opens via show() under AppTheme without BoxConstraints infinite width exception', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instagramAuthProvider.overrideWith(() => MockInstagramAuthNotifier()),
            instagramAuthStorageProvider.overrideWithValue(
              InstagramAuthStorage(FakeSecureStorage()),
            ),
            cookieFilePickerProvider.overrideWithValue(const MockCookieFilePickerClient()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('open_dialog_button'),
                  onPressed: () => InstagramManualCookieDialog.show(context),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_dialog_button')));
      await tester.pumpAndSettle();

      // Verify no layout exceptions or BoxConstraints infinite width errors occurred
      final layoutErrors = errors.where(
        (e) => e.toString().contains('infinite width') ||
            e.toString().contains('BoxConstraints') ||
            e.toString().contains('hasSize'),
      );
      expect(layoutErrors, isEmpty);

      // Verify title and input sections are rendered
      expect(find.text('Instagram Cookie Authentication'), findsOneWidget);
      expect(find.byKey(const Key('instagram_import_file_button')), findsOneWidget);
      expect(find.byKey(const Key('instagram_cookie_text_field')), findsOneWidget);
      expect(find.byKey(const Key('instagram_sessionid_field')), findsOneWidget);
      expect(find.byKey(const Key('instagram_ds_user_id_field')), findsOneWidget);

      // Verify Cancel and Connect buttons render with valid finite bounds
      final cancelButton = find.byKey(const Key('instagram_cancel_button'));
      final connectButton = find.byKey(const Key('instagram_connect_button'));
      expect(cancelButton, findsOneWidget);
      expect(connectButton, findsOneWidget);

      final cancelSize = tester.getSize(cancelButton);
      expect(cancelSize.width.isFinite, isTrue);
      expect(cancelSize.width, greaterThan(0));

      final connectSize = tester.getSize(connectButton);
      expect(connectSize.width.isFinite, isTrue);
      expect(connectSize.width, greaterThan(0));

      // Verify Cancel button can be pressed and dismisses dialog
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      expect(find.text('Instagram Cookie Authentication'), findsNothing);
    });

    testWidgets('10. Regression: dialog layout remains valid on narrow screen without horizontal overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instagramAuthProvider.overrideWith(() => MockInstagramAuthNotifier()),
            instagramAuthStorageProvider.overrideWithValue(
              InstagramAuthStorage(FakeSecureStorage()),
            ),
            cookieFilePickerProvider.overrideWithValue(const MockCookieFilePickerClient()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('open_dialog_button_narrow'),
                  onPressed: () => InstagramManualCookieDialog.show(context),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_dialog_button_narrow')));
      await tester.pumpAndSettle();

      expect(find.text('Instagram Cookie Authentication'), findsOneWidget);
      expect(find.byKey(const Key('instagram_cancel_button')), findsOneWidget);
      expect(find.byKey(const Key('instagram_connect_button')), findsOneWidget);

      // Content has scrollable view to prevent height overflow
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      await tester.tap(find.byKey(const Key('instagram_cancel_button')));
      await tester.pumpAndSettle();
    });
  });
}
