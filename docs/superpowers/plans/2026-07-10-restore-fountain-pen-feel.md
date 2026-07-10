# Restore Fountain Pen Feel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the pre-merge pressure response of the default fountain pen without changing other brush presets or input modeling.

**Architecture:** Keep the brush preset routing introduced by main. Special-case only the fountain pen's real-pressure thinning calculation so it retains the pre-merge minimum response; simulated-pressure, smoothing, streamline, and every non-fountain preset remain unchanged.

**Tech Stack:** Flutter, Dart, perfect_freehand, flutter_test.

## Global Constraints

- Do not modify `StrokeInputModeler`, tool selection, or non-fountain brush parameters.
- Verify behavior through the real `FreedrawRenderer.buildOutline` API.

---

### Task 1: Lock the fountain pen's minimum pressure response

**Files:**
- Modify: `FlowMuse-App/test/features/whiteboard/editor_core/freedraw_renderer_test.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart`

**Interfaces:**
- Consumes: `FreedrawRenderer.buildOutline(..., pressures:, pressureSensitivity:, brushType:)`.
- Produces: A fountain-pen outline that still responds to distinct real-pressure samples when sensitivity is zero, matching the pre-merge baseline term.

- [x] **Step 1: Write the failing test**

```dart
test('fountain pen preserves minimum real-pressure response at zero sensitivity', () {
  final lowPressure = FreedrawRenderer.buildOutline(
    points,
    strokeWidth: 4,
    pressures: const [0.1, 0.1, 0.1, 0.1],
    pressureSensitivity: 0,
    brushType: BrushType.fountainPen,
  );
  final highPressure = FreedrawRenderer.buildOutline(
    points,
    strokeWidth: 4,
    pressures: const [1, 1, 1, 1],
    pressureSensitivity: 0,
    brushType: BrushType.fountainPen,
  );
  expect(highPressure, isNot(equals(lowPressure)));
});
```

- [x] **Step 2: Run the focused test and verify it fails**

Run: `rtk flutter test test/features/whiteboard/editor_core/freedraw_renderer_test.dart --reporter compact`

Expected: the new test fails because current fountain-pen thinning is zero when sensitivity is zero.

- [x] **Step 3: Implement the smallest compatible calculation**

```dart
thinning: hasPressure
    ? brush.realPressureThinning(pressureSensitivity)
    : brush.simulatedThinning,
```

The fountain implementation returns `0.05 + sensitivity.clamp(0, 1) * 0.9`; other brushes retain their existing multiplication behavior.

- [x] **Step 4: Run the focused test and verify it passes**

Run: `rtk flutter test test/features/whiteboard/editor_core/freedraw_renderer_test.dart --reporter compact`

Expected: all renderer tests pass.
