import 'package:flutter/widgets.dart';

class AppSpacing {
  const AppSpacing._();

  static const compactPageInset = 20.0;
  static const pageInset = 32.0;
  static const pageTopInset = 32.0;
  static const shellHeaderHeight = 88.0;
  static const shellHeaderIconButtonSize = 32.0;
  static const shellHeaderIconSize = 18.0;
  static const headerToContent = 32.0;
  static const sectionGap = 24.0;
  static const listGap = 12.0;
  static const compactGridCrossGap = 20.0;
  static const compactGridMainGap = 24.0;
  static const gridCrossGap = 28.0;
  static const gridMainGap = 32.0;
  static const sidebarInset = 16.0;
  static const sidebarItemIndent = 20.0;
  static const controlGap = 8.0;
  static const radius = 8.0;

  static EdgeInsets pagePadding({required bool compact}) {
    final horizontal = compact ? compactPageInset : pageInset;
    return EdgeInsets.fromLTRB(horizontal, pageTopInset, horizontal, 0);
  }
}
