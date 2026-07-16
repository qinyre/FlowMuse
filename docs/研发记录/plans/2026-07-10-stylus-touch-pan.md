# Stylus Touch Pan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow one-finger touch panning without changing the active tool when a stylus-oriented editor is using any non-hand tool.

**Architecture:** Keep the routing policy in `MarkdrawController`. A touch pointer becomes a temporary viewport-pan owner only when no stylus pointer is active and the selected tool is not the hand tool. Its move events update `ViewportState.pan`; down, up, and cancel never reach the creation or selection tool.

**Tech Stack:** Flutter/Dart, `PointerEvent`, Flutter test.

## Global Constraints

- Do not change the selected tool or create/select elements for temporary touch panning.
- Do not allow touch panning while a stylus or inverted stylus pointer is currently active.
- Preserve normal touch behavior when the hand tool is selected.

---

### Task 1: Route temporary touch panning in the controller

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/controller_content_bounds_test.dart`

**Interfaces:**
- Consumes: `PointerEvent.kind`, `PointerEvent.pointer`, `PointerEvent.delta`, `ViewportState.pan(Offset)`.
- Produces: temporary touch panning through `MarkdrawController.onPointerDown`, `onPointerMove`, `onPointerUp`, and `onPointerCancel`.

- [x] **Step 1: Write the failing tests**

```dart
testWidgets('touch pans while a drawing tool stays selected', (tester) async {
  final controller = MarkdrawController();
  addTearDown(controller.dispose);
  controller.switchTool(ToolType.freedraw);
  controller.onPointerDown(touchDown(pointer: 7));
  controller.onPointerMove(touchMove(pointer: 7, delta: const Offset(40, 20)));
  controller.onPointerUp(touchUp(pointer: 7));

  expect(controller.editorState.activeToolType, ToolType.freedraw);
  expect(controller.editorState.viewport.offset, const Offset(-40, -20));
  expect(controller.editorState.scene.elements, isEmpty);
});

testWidgets('touch does not pan while a stylus stroke is active', (tester) async {
  final controller = MarkdrawController();
  addTearDown(controller.dispose);
  controller.switchTool(ToolType.freedraw);
  controller.onPointerDown(stylusDown(pointer: 1));
  controller.onPointerDown(touchDown(pointer: 7));
  controller.onPointerMove(touchMove(pointer: 7, delta: const Offset(40, 20)));

  expect(controller.editorState.viewport.offset, Offset.zero);
});
```

- [x] **Step 2: Run the focused test to verify it fails**

Run: `rtk flutter test test/features/whiteboard/editor_core/controller_content_bounds_test.dart`

Expected: the temporary-touch test fails because touch events are filtered before viewport panning.

- [x] **Step 3: Implement the minimal controller state and routing**

```dart
int? _touchPanPointerId;
int? _activeStylusPointerId;

bool _shouldStartTemporaryTouchPan(PointerEvent event) =>
    event.kind == PointerDeviceKind.touch &&
    _activeTool is! HandTool &&
    _activeStylusPointerId == null;

// On touch down: store its pointer ID and return.
// On matching touch move: apply UpdateViewportResult(viewport.pan(event.delta)) and return.
// On matching touch up/cancel: clear its pointer ID and return.
// Track stylus/inverted-stylus down/up/cancel and reject touch panning while active.
```

- [x] **Step 4: Run the focused test to verify it passes**

Run: `rtk flutter test test/features/whiteboard/editor_core/controller_content_bounds_test.dart`

Expected: all tests pass, including the new touch-pan and active-stylus cases.

- [x] **Step 5: Run static analysis and the editor-core regression suite**

Run: `rtk flutter analyze lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart test/features/whiteboard/editor_core/controller_content_bounds_test.dart; rtk flutter test test/features/whiteboard/editor_core --reporter compact`

Expected: analyzer reports no issues and the editor-core suite reports all tests passed.
