import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

class NexoraNavigationBar extends StatelessWidget {
  const NexoraNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(selectedIndex >= 0 && selectedIndex < _labels.length);

  static const downloadIndex = 0;
  static const downloadsIndex = 1;
  static const historyIndex = 2;
  static const _downloadLabel = 'Download';
  static const _downloadsLabel = 'Downloads';
  static const _historyLabel = 'History';
  static const _settingsLabel = 'Settings';
  static const _labels = <String>[
    _downloadLabel,
    _downloadsLabel,
    _historyLabel,
    _settingsLabel,
  ];

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Material(
        color: colorScheme.surface,
        elevation: 2,
        shadowColor: colorScheme.shadow.withAlpha(12),
        borderRadius: AppRadii.navigation,
        clipBehavior: Clip.antiAlias,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: _downloadLabel,
            ),
            NavigationDestination(
              icon: Icon(Icons.downloading_outlined),
              selectedIcon: Icon(Icons.downloading_rounded),
              label: _downloadsLabel,
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: _historyLabel,
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: _settingsLabel,
            ),
          ],
        ),
      ),
    );
  }
}
