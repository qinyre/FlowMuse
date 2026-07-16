# Hand Drawing Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent top-navigation switch that enables one-finger drawing and locks each two-finger gesture to either zooming or panning.

**Architecture:** Store the switch in the existing `EditorPreferences` Riverpod state and apply it to `MarkdrawController`. The controller remains the sole owner of touch dispatch: it bypasses temporary single-finger pan and locks a two-finger gesture to zoom or pan after its initial intent is clear. `MarkdrawEditor` renders the page-owned preference and callback in the top navigation.

**Tech Stack:** Flutter, Riverpod, existing `local_settings`, Flutter pointer and scale gestures.

## Global Constraints

- Default to `false` to preserve existing single-finger pan for saved and new installations.
- Do not add packages, platform branches, scene fields, or collaboration-protocol fields.
- Use the existing `EditorPreferences` persistence path and preserve Excalidraw scene compatibility.
- Run focused tests, `flutter analyze`, and `flutter test` before handoff.

---

### Task 1: Persist the input preference

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/models/editor_preferences.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/view_models/editor_preferences_view_model.dart`
- Modify: `FlowMuse-App/test/features/whiteboard/models/editor_preferences_test.dart`

**Interfaces:**
- Produces `EditorPreferences.fingerDrawingEnabled`, `copyWith(fingerDrawingEnabled: ...)`, JSON key `fingerDrawingEnabled`, and `EditorPreferencesViewModel.setFingerDrawingEnabled(bool)`.
- Consumed by `WhiteboardPage` when applying editor preferences.

- [ ] **Step 1: Write the failing model test**

```dart
final preferences = EditorPreferences(fingerDrawingEnabled: true);
final restored = EditorPreferences.fromJson(preferences.toJson());

expect(restored.fingerDrawingEnabled, isTrue);
expect(EditorPreferences.fromJson({}).fingerDrawingEnabled, isFalse);
```

- [ ] **Step 2: Run the model test to verify failure**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/models/editor_preferences_test.dart`

Expected: compilation failure because `fingerDrawingEnabled` does not exist.

- [ ] **Step 3: Add the minimal persisted field**

```dart
// EditorPreferences constructor, field, copyWith, toJson and fromJson
this.fingerDrawingEnabled = false,
final bool fingerDrawingEnabled;
bool? fingerDrawingEnabled,
'fingerDrawingEnabled': fingerDrawingEnabled,
fingerDrawingEnabled: _bool(json['fingerDrawingEnabled'], false),

// EditorPreferencesViewModel
Future<void> setFingerDrawingEnabled(bool value) =>
    _save(_current.copyWith(fingerDrawingEnabled: value));
```

- [ ] **Step 4: Re-run the model test**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/models/editor_preferences_test.dart`

Expected: PASS.

### Task 2: Make controller touch dispatch match the switch

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Modify: `FlowMuse-App/test/features/whiteboard/editor_core/editor_preferences_controller_test.dart`

**Interfaces:**
- Consumes `fingerDrawingEnabled` in `MarkdrawController.applyEditorPreferences`.
- Produces touch creation when enabled and mutually exclusive two-finger zoom or pan viewports.

- [ ] **Step 1: Write failing controller tests**

```dart
controller.applyEditorPreferences(
  defaultTool: ToolType.freedraw,
  defaultBrush: BrushType.pencil,
  brushStates: const {},
  pressureEnabled: true,
  pressureExponent: 1,
  palmRejectionEnabled: false,
  twoFingerZoomEnabled: false,
  singleFingerPanEnabled: true,
  fingerDrawingEnabled: true,
);
controller.onPointerDown(const PointerDownEvent(
  pointer: 1,
  kind: PointerDeviceKind.touch,
  position: Offset.zero,
));
controller.onPointerUp(const PointerUpEvent(
  pointer: 1,
  kind: PointerDeviceKind.touch,
  position: Offset(8, 8),
));
expect(controller.currentScene.activeElements, isNotEmpty);

controller.onScaleStart(
  const ScaleStartDetails(localFocalPoint: Offset(20, 20)),
);
controller.onScaleUpdate(const ScaleUpdateDetails(
  localFocalPoint: Offset(40, 20), scale: 2, pointerCount: 2,
));
expect(controller.editorState.viewport.zoom, 1);
expect(controller.editorState.viewport.offset, isNot(Offset.zero));
```

- [ ] **Step 2: Run the controller test to verify failure**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/editor_preferences_controller_test.dart`

Expected: compilation failure for the new preference argument.

- [ ] **Step 3: Implement the smallest controller branch**

```dart
bool _fingerDrawingEnabled = false;

// applyEditorPreferences
required bool fingerDrawingEnabled,
_fingerDrawingEnabled = fingerDrawingEnabled;

bool get _usesTemporaryTouchPan =>
    _singleFingerPanEnabled &&
    !_fingerDrawingEnabled &&
    _editorState.activeToolType != ToolType.hand;

// Finger drawing owns two-finger movement, even when the optional
// pinch-to-zoom preference is disabled.
bool get _canHandleTwoFingerGesture =>
    _twoFingerZoomEnabled || _fingerDrawingEnabled;
```

Update `canPanPagedViewportWithTouch` to return false while hand drawing is enabled. In `onScaleStart` and `onScaleUpdate`, use `_canHandleTwoFingerGesture`; when hand drawing is enabled, keep `_pinchStartZoom` rather than multiplying by `details.scale`, so the existing focal-point calculation pans without zooming.

- [ ] **Step 4: Re-run the controller test**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/editor_preferences_controller_test.dart`

Expected: PASS.

### Task 3: Expose the switch in both whiteboard menus

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/hamburger_menu.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/compact_menu.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/hand_drawing_menu_test.dart`

**Interfaces:**
- `MarkdrawEditor` accepts `fingerDrawingEnabled` and `onFingerDrawingEnabledChanged`.
- Both menu widgets consume the value and callback.
- `WhiteboardPage` reads `editorPreferencesProvider` and calls `setFingerDrawingEnabled`.

- [ ] **Step 1: Write the failing menu widget test**

```dart
await tester.pumpWidget(MaterialApp(
  home: Scaffold(
    body: MarkdrawEditor(
      fingerDrawingEnabled: false,
      onFingerDrawingEnabledChanged: values.add,
    ),
  ),
));
await tester.tap(find.byTooltip('菜单'));
await tester.pumpAndSettle();
expect(find.text('手指绘制'), findsOneWidget);
await tester.tap(find.byType(Switch));
expect(values, [true]);
```

- [ ] **Step 2: Run the menu test to verify failure**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/hand_drawing_menu_test.dart`

Expected: compilation failure because the editor properties and switch do not exist.

- [ ] **Step 3: Forward state and render the controls**

```dart
// WhiteboardPage MarkdrawEditor call
fingerDrawingEnabled: preferences?.fingerDrawingEnabled ?? false,
onFingerDrawingEnabledChanged: (value) => unawaited(
  ref.read(editorPreferencesProvider.notifier)
      .setFingerDrawingEnabled(value),
),
```

Add matching optional fields to `MarkdrawEditor` and `_LeftChrome`, then forward them into `HamburgerMenu` and `CompactMenuButton`. Render a `SwitchListTile` labelled `手指绘制` with subtitle `单指使用当前绘图工具，双指平移画布`; its `onChanged` calls the provided callback. The compact menu closes only for commands, not this inline switch.

- [ ] **Step 4: Re-run menu and focused controller tests**

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/editor_core/hand_drawing_menu_test.dart test/features/whiteboard/editor_core/editor_preferences_controller_test.dart`

Expected: PASS.

### Task 4: Synchronize requirements and verify

**Files:**
- Modify: `REQUIREMENTS.md`

- [ ] **Step 1: Document the user-visible gesture behavior**

Add to the editor-gesture requirement: `手指绘制开关关闭时单指平移；开启时单指使用当前绘图工具，双指仅平移画布。`

- [ ] **Step 2: Format and run focused verification**

Run: `cd FlowMuse-App && dart format lib/features/whiteboard/models/editor_preferences.dart lib/features/whiteboard/view_models/editor_preferences_view_model.dart lib/features/whiteboard/views/whiteboard_page.dart lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart lib/features/whiteboard/editor_core/src/ui/hamburger_menu.dart lib/features/whiteboard/editor_core/src/ui/compact_menu.dart test/features/whiteboard/models/editor_preferences_test.dart test/features/whiteboard/editor_core/editor_preferences_controller_test.dart test/features/whiteboard/editor_core/hand_drawing_menu_test.dart`

Run: `cd FlowMuse-App && flutter test test/features/whiteboard/models/editor_preferences_test.dart test/features/whiteboard/editor_core/editor_preferences_controller_test.dart test/features/whiteboard/editor_core/hand_drawing_menu_test.dart`

Expected: formatter exits successfully and all selected tests PASS.

- [ ] **Step 3: Run project validation**

Run: `cd FlowMuse-App && flutter analyze`

Run: `cd FlowMuse-App && flutter test`

Expected: no new analyzer errors and all tests PASS.
