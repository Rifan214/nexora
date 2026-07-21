import 'package:flutter/widgets.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double heroTop = 112;
  static const double heroTopCompact = 48;
  static const double panelTop = 88;
  static const double panelTopCompact = 48;

  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets actionPanel = EdgeInsets.all(xl);
}

abstract final class AppRadii {
  static const BorderRadius duration = BorderRadius.all(Radius.circular(8));
  static const BorderRadius badge = BorderRadius.all(Radius.circular(12));
  static const BorderRadius input = BorderRadius.all(Radius.circular(16));
  static const BorderRadius card = BorderRadius.all(Radius.circular(24));
  static const BorderRadius actionPanel = BorderRadius.all(Radius.circular(32));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
  static const BorderRadius navigation = BorderRadius.vertical(
    top: Radius.circular(24),
  );
}

abstract final class AppDurations {
  static const Duration short = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 220);
}

abstract final class AppSizes {
  static const double touchTarget = 48;
  static const double primaryButtonHeight = 56;
  static const double navigationHeight = 80;
  static const double heroIconContainer = 128;
  static const double heroIcon = 64;
  static const double mediaPlaceholderIcon = 40;
  static const double compactThumbnailWidth = 160;
  static const double contentMaxWidth = 560;
  static const double actionPanelMaxWidth = 520;
}
