import 'package:flutter/material.dart';

/// Runs UI mutations after the current overlay/menu route finishes its own
/// close/layout work.
void runAfterUiFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
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
