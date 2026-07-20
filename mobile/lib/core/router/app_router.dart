import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../screens/home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter();
  ref.onDispose(router.dispose);
  return router;
});

GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: HomeScreen.routePath,
    routes: [
      GoRoute(
        path: HomeScreen.routePath,
        name: HomeScreen.routeName,
        builder: (_, __) => const HomeScreen(),
      ),
    ],
  );
}
