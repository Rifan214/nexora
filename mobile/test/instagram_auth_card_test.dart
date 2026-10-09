import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/instagram_auth_session.dart';
import 'package:nexora/providers/instagram_auth_provider.dart';
import 'package:nexora/services/instagram_auth_storage.dart';
import 'package:nexora/widgets/instagram_auth_card.dart';

import 'instagram_auth_storage_test.dart';

class MockInstagramAuthController extends InstagramAuthController {
  MockInstagramAuthController(this.initialState);

  final InstagramAuthState initialState;
  bool logoutCalled = false;

  @override
  InstagramAuthState build() => initialState;

  @override
  Future<void> logout() async {
    logoutCalled = true;
    state = const InstagramAuthState.unauthenticated();
  }
}

Widget createTestWidget({
  required InstagramAuthState state,
  MockInstagramAuthController? mockController,
}) {
  final controller = mockController ?? MockInstagramAuthController(state);

  return ProviderScope(
    overrides: [
      instagramAuthProvider.overrideWith(() => controller),
      instagramAuthStorageProvider.overrideWithValue(
        InstagramAuthStorage(FakeSecureStorage()),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InstagramAuthCard(),
        ),
      ),
    ),
  );
}

void main() {
  group('InstagramAuthCard Widget Tests', () {
    testWidgets('renders Disconnected (Guest) state correctly', (tester) async {
      await tester.pumpWidget(
        createTestWidget(state: const InstagramAuthState.unauthenticated()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Instagram Account'), findsOneWidget);
      expect(find.text('Guest / Not Connected'), findsOneWidget);
      expect(find.text('Import Instagram Session'), findsOneWidget);
      expect(find.byIcon(Icons.key_rounded), findsOneWidget);

      // Security check: no credentials or raw tokens displayed
      expect(find.textContaining('session_id'), findsNothing);
      expect(find.textContaining('sessionid'), findsNothing);
      expect(find.textContaining('ds_user_id'), findsNothing);
      expect(find.textContaining('csrftoken'), findsNothing);
    });

    testWidgets('renders Authenticating / Restoring state correctly', (tester) async {
      await tester.pumpWidget(
        createTestWidget(state: const InstagramAuthState.authenticating()),
      );
      await tester.pump();

      expect(find.text('Connecting...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Buttons are disabled/hidden during authentication
      expect(find.text('Import Instagram Session'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('renders Connected state with expiry information', (tester) async {
      final session = InstagramAuthSession(
        sessionId: 'opaque_ig_session_xyz_789',
        source: 'user_session',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      );

      await tester.pumpWidget(
        createTestWidget(state: InstagramAuthState.authenticated(session)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.textContaining('Expires in'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      // Security verification: opaque session_id and credentials must NEVER be shown to user
      expect(find.textContaining('opaque_ig_session_xyz_789'), findsNothing);
      expect(find.textContaining('session_id'), findsNothing);
      expect(find.textContaining('sessionid'), findsNothing);
      expect(find.textContaining('ds_user_id'), findsNothing);
    });

    testWidgets('tapping Disconnect calls logout and clears session', (tester) async {
      final session = InstagramAuthSession(
        sessionId: 'opaque_ig_session_123',
        source: 'user_session',
        status: 'available',
        authenticated: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      final mockController = MockInstagramAuthController(InstagramAuthState.authenticated(session));

      await tester.pumpWidget(
        createTestWidget(
          state: InstagramAuthState.authenticated(session),
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
        createTestWidget(state: const InstagramAuthState.expired('Session expired.')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Session Expired'), findsOneWidget);
      expect(find.text('Reconnect Instagram Session'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      // Security check: no credential leaks
      expect(find.textContaining('sessionid'), findsNothing);
      expect(find.textContaining('ds_user_id'), findsNothing);
    });
  });
}
