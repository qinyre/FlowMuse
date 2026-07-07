import 'package:flutter/widgets.dart';

/// Runs UI mutations after the current overlay/menu route finishes its own
/// close/layout work.
void runAfterUiFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}
