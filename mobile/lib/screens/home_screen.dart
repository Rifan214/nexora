import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const routeName = 'home';
  static const routePath = '/';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nexora',
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Backend not connected',
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
