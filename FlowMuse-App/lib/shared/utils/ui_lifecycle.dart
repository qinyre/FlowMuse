import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Runs UI mutations after the current overlay/menu route finishes its own
/// close/layout work.
void runAfterUiFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}

/// Runs UI mutations when Flutter is outside build/layout/paint callbacks.
void runWhenUiStable(VoidCallback action) {
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle) {
    action();
  } else {
    runAfterUiFrame(action);
  }
}

/// Runs [action] on a stable UI frame if [context] is still mounted.
void runWhenContextStable(BuildContext context, VoidCallback action) {
  runWhenUiStable(() {
    if (context.mounted) {
      action();
    }
  });
}

/// Shows a popup menu anchored to the widget identified by [context].
///
/// This intentionally uses [showMenu], which is backed by a popup route and
/// normal OverlayEntries. It avoids MenuAnchor/OverlayPortal for menus whose
/// content does not need to inherit live state from the anchor subtree.
Future<T?> showAnchoredPopupMenu<T extends Object>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
}) {
  final anchor = context.findRenderObject();
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  if (anchor is! RenderBox ||
      overlay is! RenderBox ||
      !anchor.attached ||
      !overlay.attached ||
      items.isEmpty) {
    return Future<T?>.value();
  }

  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      anchor.localToGlobal(Offset.zero, ancestor: overlay),
      anchor.localToGlobal(
        anchor.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );

  return showMenu<T>(context: context, position: position, items: items);
}
