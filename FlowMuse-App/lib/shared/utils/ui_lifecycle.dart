import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../widgets/anchored_panel.dart';
import 'app_haptics.dart';

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
/// 统一走 [AnchoredPanelRoute]：纸面容器 + 从锚点侧展开的方向性动画。
/// 仍然渲染调用方传入的 [PopupMenuEntry]，菜单项语义与既有测试不变。
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
    anchor.localToGlobal(
      anchor.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  );
  final belowPosition = RelativeRect.fromLTRB(
    anchorRect.left,
    anchorRect.bottom + 4,
    overlay.size.width - anchorRect.right,
    overlay.size.height - anchorRect.bottom - 4,
  );
  final position = switch (placement) {
    AnchoredPopupPlacement.automatic => RelativeRect.fromRect(
      anchorRect,
      Offset.zero & overlay.size,
    ),
    AnchoredPopupPlacement.below => belowPosition,
    AnchoredPopupPlacement.right => RelativeRect.fromLTRB(
      anchorRect.right + 4,
      anchorRect.bottom + 4,
      overlay.size.width - anchorRect.right - 4,
      overlay.size.height - anchorRect.bottom - 4,
    ),
    AnchoredPopupPlacement.left => RelativeRect.fromLTRB(
      anchorRect.left,
      anchorRect.bottom + 4,
      overlay.size.width - anchorRect.left,
      overlay.size.height - anchorRect.bottom - 4,
    ),
  };
  final growth = switch (placement) {
    AnchoredPopupPlacement.automatic ||
    AnchoredPopupPlacement.below => AnchoredPanelGrowth.down,
    AnchoredPopupPlacement.right => AnchoredPanelGrowth.right,
    AnchoredPopupPlacement.left => AnchoredPanelGrowth.left,
  };

  return _showAnchoredPanel<T>(
    context: context,
    position: position,
    items: items,
    growth: growth,
  );
}

/// 按调用方计算的屏幕坐标弹出统一面板（长按上下文菜单等没有按钮锚点的场景）。
Future<T?> showAnchoredPopupMenuAt<T extends Object>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  AnchoredPanelGrowth growth = AnchoredPanelGrowth.down,
}) {
  if (items.isEmpty) return Future<T?>.value();
  return _showAnchoredPanel<T>(
    context: context,
    position: position,
    items: items,
    growth: growth,
  );
}

/// 值选择面板：替代 DropdownButton / 设置行 PopupMenuButton 的弹出部分。
/// 当前值显示为勾选项；触发器外观由调用方保持。
Future<T?> showAnchoredValuePicker<T extends Object>({
  required BuildContext context,
  required T? value,
  required Iterable<T> options,
  required String Function(T option) label,
  AnchoredPopupPlacement placement = AnchoredPopupPlacement.below,
}) {
  return showAnchoredPopupMenu<T>(
    context: context,
    placement: placement,
    items: [
      for (final option in options)
        CheckedPopupMenuItem<T>(
          value: option,
          checked: option == value,
          child: Text(label(option)),
        ),
    ],
  );
}

Future<T?> _showAnchoredPanel<T extends Object>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  required AnchoredPanelGrowth growth,
}) {
  final navigator = Navigator.of(context);
  AppHaptics.panelOpen();
  return navigator.push(
    AnchoredPanelRoute<T>(
      position: position,
      items: items,
      growth: growth,
      capturedThemes: InheritedTheme.capture(from: context, to: null),
    ),
  );
}
