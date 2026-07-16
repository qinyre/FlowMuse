# Cross-Platform PDF Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first usable PDF import path that lets FlowMuse pick a PDF, render its pages as images, and insert those pages into the whiteboard without changing the collaboration document format.

**Architecture:** Add a small PDF import domain layer under the whiteboard editor core. A `PdfPageRenderer` converts PDF bytes/path into page images, and `MarkdrawController.importPdfPages(...)` inserts those rendered pages as ordinary `ImageElement`s plus existing image file assets. UI file handling calls the importer from the existing Markdraw file menu.

**Tech Stack:** Flutter/Dart, existing Markdraw editor core, `file_picker`, HarmonyOS ArkTS `PDF Kit` renderer via platform channel, `pdfx` for supported non-OHOS platforms.

**Implementation status (2026-07-08):** Implemented. The final renderer split is:
- HarmonyOS: `PlatformPdfPageRenderer` calls `flow_muse/pdf_import`, implemented in ArkTS with `pdfService.PdfDocument` and PNG page output.
- Android/iOS/macOS/Windows/Web: `PdfxPdfPageRenderer`.
- Linux/Fuchsia: explicit unsupported renderer for now.
- Rejected path: `pdfrx_engine` / `pdfium_dart` was tested and removed because its native-assets hook fails for `ohos` with `Unsupported PDFium platform: ohos`.

## Global Constraints

- Reuse existing image element and scene file store; do not introduce a PDF-specific scene element in this stage.
- Do not change backend collaboration protocol or Excalidraw JSON fields.
- Keep HarmonyOS-specific native work behind an adapter boundary; common whiteboard behavior must stay platform-neutral.
- Follow TDD for production Dart behavior.
- Preserve existing user changes, including the current AndroidManifest diff unless the task explicitly edits that file.

---

### Task 1: PDF Import Model and Controller Insertion

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/pdf/pdf_import.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/io/io.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/markdraw.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/pdf_import_controller_test.dart`

**Interfaces:**
- Produces: `PdfRenderedPage({required Uint8List bytes, required String mimeType, required double width, required double height, required int pageNumber})`
- Produces: `MarkdrawController.importPdfPages(List<PdfRenderedPage> pages, Size canvasSize, {String documentName = 'document.pdf'})`
- Consumes: existing `ImageElement`, `ImageFile`, `AddFileResult`, `AddElementResult`, `SetSelectionResult`

- [x] **Step 1: Write failing controller test**

Create `test/features/whiteboard/editor_core/pdf_import_controller_test.dart` with tests that generate tiny valid PNG images, call `controller.importPdfPages`, and assert:

- two rendered pages become two active `ImageElement`s
- scene file store has two files
- pages are vertically stacked with positive spacing
- selected IDs contain the imported pages

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/pdf_import_controller_test.dart
```

Expected: fail because `PdfRenderedPage` and `importPdfPages` do not exist.

- [x] **Step 3: Implement model and controller method**

Add `PdfRenderedPage` and export it. Add `MarkdrawController.importPdfPages(...)` that decodes each page image, stores it as `ImageFile`, creates one `ImageElement` per page, stacks pages vertically around the current viewport center, pushes history once, and applies a single `CompoundResult`.

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/pdf_import_controller_test.dart
```

Expected: all tests pass.

### Task 2: File Handler PDF Import Flow

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/pdf/pdf_page_renderer.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/pdf/pdf_importer.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/pdf/pdf_import.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/io/io.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/markdraw.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_file_handler.dart`
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/pdf_importer_test.dart`

**Interfaces:**
- Produces: `abstract interface class PdfPageRenderer { Future<List<PdfRenderedPage>> render(PdfImportSource source, PdfRenderOptions options); }`
- Produces: `PdfImporter.importPdf(...)`
- Consumes: `MarkdrawController.importPdfPages(...)`

- [x] **Step 1: Write failing importer test**

Write tests with a fake renderer that returns two page images. Assert `PdfImporter.importPdf` passes the rendered pages to a controller and ignores empty render results.

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/pdf_importer_test.dart
```

Expected: fail because importer and renderer interfaces do not exist.

- [x] **Step 3: Implement importer and renderer boundary**

Add `PdfImportSource`, `PdfRenderOptions`, `PdfPageRenderer`, and `PdfImporter`. Extend `MarkdrawFileHandler` with `importPdf(BuildContext context)` that uses `file_picker` for `.pdf`, reads bytes/path, renders pages, and calls the controller. Keep renderer injectable for tests.

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/pdf_importer_test.dart
```

Expected: all tests pass.

### Task 3: Editor UI Entry

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/hamburger_menu.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/compact_menu.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/desktop_toolbar.dart`
- Test: targeted widget or static callback test if existing structure supports it

**Interfaces:**
- Consumes: `MarkdrawEditor(onImportPdf: VoidCallback?)`
- Produces: a visible menu/toolbar entry for PDF import when callback exists

- [x] **Step 1: Write failing UI test or callback-level widget test**

Assert that rendering the editor/menu with `onImportPdf` exposes an import PDF action.

- [x] **Step 2: Run test to verify it fails**

Run the targeted widget test.

- [x] **Step 3: Add PDF import callback and menu item**

Add `onImportPdf` beside existing `onImportImage`; expose a menu item labeled `瀵煎叆 PDF`. Wire app page file handler to call `importPdf`.

- [x] **Step 4: Run targeted test**

Expected: passes.

### Task 4: Platform Renderer Implementation

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/pdf/pdf_page_renderer_default.dart`
- Optionally modify: `FlowMuse-App/pubspec.yaml`
- Optionally modify: `FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets`
- Optionally modify: `FlowMuse-App/ohos/entry/src/main/module.json5`

**Interfaces:**
- Consumes: `PdfPageRenderer`
- Produces: `createDefaultPdfPageRenderer()`

- [x] **Step 1: Add a default renderer factory**

Implement a factory that can be injected into `MarkdrawFileHandler`. If a mature Flutter renderer package is added, keep it out of controller tests.

- [x] **Step 2: Add HarmonyOS channel boundary**

Implemented native HarmonyOS rendering in this pass with a method channel and ArkTS PDF Kit calls. Non-OHOS supported platforms use `pdfx`; unsupported platforms fail explicitly rather than silently doing nothing.

- [x] **Step 3: Verify analysis**

Run:

```bash
cd FlowMuse-App
dart analyze lib/features/whiteboard/editor_core test/features/whiteboard/editor_core
```

Expected: no issues in touched editor core files.

### Task 5: Final Verification

**Files:** no new files expected.

- [x] **Step 1: Run focused tests**

Run:

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/pdf_import_controller_test.dart test/features/whiteboard/editor_core/pdf_importer_test.dart
```

- [x] **Step 2: Run targeted analysis**

Run:

```bash
cd FlowMuse-App
dart analyze lib/features/whiteboard/editor_core test/features/whiteboard/editor_core
```

- [x] **Step 3: Inspect git diff**

Run:

```bash
git status --short
git diff --stat
```

Confirm changed files match the PDF import scope plus pre-existing user changes.

Final verification commands run after implementation:

```bash
cd FlowMuse-App
flutter test test/features/whiteboard/editor_core/pdf_import_controller_test.dart test/features/whiteboard/editor_core/pdf_importer_test.dart test/features/whiteboard/editor_core/pdf_import_menu_test.dart test/features/whiteboard/editor_core/markdraw_file_handler_pdf_test.dart test/features/whiteboard/editor_core/platform_pdf_page_renderer_test.dart test/features/whiteboard/editor_core/pdf_page_renderer_default_test.dart
dart analyze lib/features/whiteboard/editor_core test/features/whiteboard/editor_core
flutter build hap --debug
flutter build apk --debug
flutter build web --debug
```

