import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Runs UI mutations after the current overlay/menu route finishes its own
/// close/layout work.
void runAfterUiFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}

/// Runs UI mutations after a route/overlay/menu teardown has had a frame to
/// detach inherited dependencies and overlay render children.
void runAfterUiTeardown(VoidCallback action) {
  runAfterUiFrame(action);
}

/// Runs an async UI mutation after route/overlay teardown.
Future<void> runAfterUiTeardownAsync(FutureOr<void> Function() action) {
  final completer = Completer<void>();
  runAfterUiTeardown(() {
    Future<void>.sync(
      action,
    ).then(completer.complete, onError: completer.completeError);
  });
  return completer.future;
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

/// Runs [action] after a route/overlay teardown if [context] is still mounted.
void runAfterContextTeardown(BuildContext context, VoidCallback action) {
  runAfterUiTeardown(() {
    if (context.mounted) {
      action();
    }
  });
}

/// Runs an async action after route/overlay teardown if [context] is mounted.
Future<void> runAfterContextTeardownAsync(
  BuildContext context,
  FutureOr<void> Function() action,
) {
  return runAfterUiTeardownAsync(() async {
    if (context.mounted) {
      await action();
    }
  });
}

/// Inserts [entry] into [overlay] when it is safe to mutate the overlay tree.
void insertOverlayEntryWhenStable({
  required OverlayState overlay,
  required OverlayEntry entry,
  required bool Function() shouldInsert,
  VoidCallback? onInserted,
}) {
  runWhenUiStable(() {
    if (!shouldInsert()) {
      return;
    }
    overlay.insert(entry);
    onInserted?.call();
  });
}

/// Removes [entry] after the current route/overlay teardown frame.
void removeOverlayEntryAfterTeardown(
  OverlayEntry entry, {
  VoidCallback? onRemoved,
}) {
  runAfterUiTeardown(() {
    entry.remove();
    onRemoved?.call();
  });
}

/// Shows a popup menu anchored to the widget identified by [context].
///
/// This intentionally uses [showMenu], which is backed by a popup route and
/// normal OverlayEntries. It avoids MenuAnchor/OverlayPortal for menus whose
/// content does not need to inherit live state from the anchor subtree.
enum AnchoredPopupPlacement { automatic, below, right, left }

Future<T?> showAnchoredPopupMenu<T extends Object>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  AnchoredPopupPlacement placement = AnchoredPopupPlacement.automatic,
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

  final anchorRect = Rect.fromPoints(
    anchor.localToGlobal(Offset.zero, ancestor: overlay),
    anchor.localToGlobal(anchor.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final position = switch (placement) {
    AnchoredPopupPlacement.automatic => RelativeRect.fromRect(
      anchorRect,
      Offset.zero & overlay.size,
    ),
    AnchoredPopupPlacement.below => RelativeRect.fromLTRB(
      anchorRect.left,
      anchorRect.bottom,
      overlay.size.width - anchorRect.right,
      overlay.size.height - anchorRect.bottom,
    ),
    AnchoredPopupPlacement.right => RelativeRect.fromLTRB(
      anchorRect.right,
      anchorRect.top,
      overlay.size.width - anchorRect.right,
      overlay.size.height - anchorRect.bottom,
    ),
    AnchoredPopupPlacement.left => RelativeRect.fromLTRB(
      anchorRect.left,
      anchorRect.top,
      overlay.size.width - anchorRect.left,
      overlay.size.height - anchorRect.bottom,
    ),
  };

  return showMenu<T>(context: context, position: position, items: items);
}
