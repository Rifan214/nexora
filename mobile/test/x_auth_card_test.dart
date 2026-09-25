import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/x_auth_session.dart';
import 'package:nexora/providers/x_auth_provider.dart';
import 'package:nexora/services/x_auth_storage.dart';
import 'package:nexora/widgets/x_auth_card.dart';

import 'x_auth_storage_test.dart';

class MockXAuthController extends XAuthController {
  MockXAuthController(this.initialState);

  final XAuthState initialState;
  bool logoutCalled = false;

  @override
  XAuthState build() => initialState;

  @override
  Future<void> logout() async {
    logoutCalled = true;
    state = const XAuthState.unauthenticated();
  }
}

Widget createTestWidget({
  required XAuthState state,
  MockXAuthController? mockController,
}) {
  final controller = mockController ?? MockXAuthController(state);

  return ProviderScope(
    overrides: [
      xAuthProvider.overrideWith(() => controller),
      xAuthStorageProvider.overrideWithValue(
        XAuthStorage(FakeSecureStorage()),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: XAuthCard(),
        ),
      ),
    ),
  );
}

void main() {
  group('XAuthCard Widget Tests', () {
    testWidgets('renders Disconnected (Guest) state correctly', (tester) async {
      await tester.pumpWidget(
        createTestWidget(state: const XAuthState.unauthenticated()),
      );
      await tester.pumpAndSettle();

      expect(find.text('X Account'), findsOneWidget);
      expect(find.text('Guest / Not Connected'), findsOneWidget);
      expect(find.text('Connect X Account'), findsOneWidget);
      expect(find.byIcon(Icons.login_rounded), findsOneWidget);

      // Security check: no credentials or raw tokens displayed
      expect(find.textContaining('session_id'), findsNothing);
      expect(find.textContaining('auth_token'), findsNothing);
      expect(find.textContaining('ct0'), findsNothing);
    });

    testWidgets('renders Authenticating / Restoring state correctly',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(state: const XAuthState.authenticating()),
      );
      await tester.pump();

      expect(find.text('Connecting...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Buttons are disabled/hidden during authentication
      expect(find.text('Connect X Account'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('renders Connected state with expiry information',
        (tester) async {
      final session = XAuthSession(
        sessionId: 'opaque_session_xyz_789',
        source: 'user_session',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      );

      await tester.pumpWidget(
        createTestWidget(state: XAuthState.authenticated(session)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.textContaining('Expires in'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      // Security verification: opaque session_id must NEVER be shown to user
      expect(find.textContaining('opaque_session_xyz_789'), findsNothing);
      expect(find.textContaining('session_id'), findsNothing);
      expect(find.textContaining('auth_token'), findsNothing);
      expect(find.textContaining('ct0'), findsNothing);
    });

    testWidgets('tapping Disconnect calls logout and clears session',
        (tester) async {
      final session = XAuthSession(
        sessionId: 'opaque_session_123',
        source: 'user_session',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      final mockController =
          MockXAuthController(XAuthState.authenticated(session));

      await tester.pumpWidget(
        createTestWidget(
          state: XAuthState.authenticated(session),
          mockController: mockController,
        ),
      );
      await tester.pumpAndSettle();

      final disconnectButton = find.text('Disconnect');
      expect(disconnectButton, findsOneWidget);

      await tester.tap(disconnectButton);
      await tester.pumpAndSettle();

      expect(mockController.logoutCalled, isTrue);
    });

    testWidgets('renders Expired state with reconnect prompt', (tester) async {
      await tester.pumpWidget(
        createTestWidget(state: const XAuthState.expired('Session expired.')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Session Expired'), findsOneWidget);
      expect(find.text('Reconnect X Account'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      // Security check: no credential leaks
      expect(find.textContaining('auth_token'), findsNothing);
      expect(find.textContaining('ct0'), findsNothing);
    });
  });
}
