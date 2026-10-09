import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/tiktok_auth_session.dart';
import 'package:nexora/providers/tiktok_auth_provider.dart';
import 'package:nexora/services/tiktok_auth_storage.dart';
import 'package:nexora/widgets/tiktok_auth_card.dart';

import 'tiktok_auth_storage_test.dart';

class MockTikTokAuthController extends TikTokAuthController {
  MockTikTokAuthController(this.initialState);

  final TikTokAuthState initialState;
  bool logoutCalled = false;

  @override
  TikTokAuthState build() => initialState;

  @override
  Future<void> logout() async {
    logoutCalled = true;
    state = const TikTokAuthState.unauthenticated();
  }
}

Widget createTestWidget({
  required TikTokAuthState state,
  MockTikTokAuthController? mockController,
}) {
  final controller = mockController ?? MockTikTokAuthController(state);

  return ProviderScope(
    overrides: [
      tikTokAuthProvider.overrideWith(() => controller),
      tikTokAuthStorageProvider.overrideWithValue(
        TikTokAuthStorage(FakeSecureStorage()),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TikTokAuthCard(),
        ),
      ),
    ),
  );
}

void main() {
  group('TikTokAuthCard Widget Tests', () {
    testWidgets('renders Disconnected (Guest) state correctly', (tester) async {
      await tester.pumpWidget(
        createTestWidget(state: const TikTokAuthState.unauthenticated()),
      );
      await tester.pumpAndSettle();

      expect(find.text('TikTok Account'), findsOneWidget);
      expect(find.text('Guest / Not Connected'), findsOneWidget);
      expect(find.text('Import TikTok Session'), findsOneWidget);
      expect(find.byIcon(Icons.key_rounded), findsOneWidget);

      // Security check: no credentials or raw tokens displayed
      expect(find.textContaining('session_id'), findsNothing);
      expect(find.textContaining('sessionid'), findsNothing);
      expect(find.textContaining('sid_tt'), findsNothing);
    });

    testWidgets('renders Authenticating / Restoring state correctly', (tester) async {
      await tester.pumpWidget(
        createTestWidget(state: const TikTokAuthState.authenticating()),
      );
      await tester.pump();

      expect(find.text('Connecting...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Buttons are disabled/hidden during authentication
      expect(find.text('Import TikTok Session'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('renders Connected state with expiry information', (tester) async {
      final session = TikTokAuthSession(
        sessionId: 'opaque_tiktok_session_xyz_789',
        source: 'user_session',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      );

      await tester.pumpWidget(
        createTestWidget(state: TikTokAuthState.authenticated(session)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.textContaining('Expires in'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      // Security verification: opaque session_id and credentials must NEVER be shown to user
      expect(find.textContaining('opaque_tiktok_session_xyz_789'), findsNothing);
      expect(find.textContaining('session_id'), findsNothing);
      expect(find.textContaining('sessionid'), findsNothing);
      expect(find.textContaining('sid_tt'), findsNothing);
    });

    testWidgets('tapping Disconnect calls logout and clears session', (tester) async {
      final session = TikTokAuthSession(
        sessionId: 'opaque_tt_session_123',
        source: 'user_session',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      final mockController = MockTikTokAuthController(TikTokAuthState.authenticated(session));

      await tester.pumpWidget(
        createTestWidget(
          state: TikTokAuthState.authenticated(session),
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
        createTestWidget(state: const TikTokAuthState.expired('Session expired.')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Session Expired'), findsOneWidget);
      expect(find.text('Reconnect TikTok Session'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      // Security check: no credential leaks
      expect(find.textContaining('sessionid'), findsNothing);
      expect(find.textContaining('sid_tt'), findsNothing);
    });
  });
}
