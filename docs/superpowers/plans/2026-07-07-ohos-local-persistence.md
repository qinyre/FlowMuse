# OHOS Local Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent local storage for HarmonyOS while preserving existing non-OHOS storage behavior.

**Architecture:** Add a file-backed `AppKeyValueStore` selected only for `TargetPlatform.ohos`. Remove OHOS in-memory repository special cases so library and whiteboard repositories use the persistent store.

**Tech Stack:** Flutter, Dart IO, Riverpod providers, existing `AppKeyValueStore`, `LibraryRepository`, and `WhiteboardSceneRepository`.

## Global Constraints

- Only OHOS storage behavior changes.
- Non-OHOS platforms continue using `SharedPreferencesKeyValueStore`.
- Existing library index JSON and whiteboard scene JSON formats stay unchanged.
- No ArkTS native bridge is added in this iteration.
- Tests must use temporary directories, not real device paths.

---

### Task 1: File-backed key-value store

**Files:**
- Create: `FlowMuse-App/lib/shared/storage/app_key_value_store_base.dart`
- Create: `FlowMuse-App/lib/shared/storage/file_key_value_store.dart`
- Create: `FlowMuse-App/lib/shared/storage/app_key_value_store_ohos_io.dart`
- Create: `FlowMuse-App/lib/shared/storage/app_key_value_store_ohos_stub.dart`
- Modify: `FlowMuse-App/lib/shared/storage/app_key_value_store.dart`
- Test: `FlowMuse-App/test/shared/storage/file_key_value_store_test.dart`

**Interfaces:**
- Produces: `FileKeyValueStore({required File file})`
- Produces: `createOhosPersistentKeyValueStore({String? baseDirectoryPath})`
- Produces: `createAppKeyValueStore({TargetPlatform? platform, String? ohosStorageDirectoryPath})`

- [ ] **Step 1: Write the failing tests**

```dart
test('persists strings across store instances', () async {
  final dir = await Directory.systemTemp.createTemp('flowmuse_store_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/store.json');

  await FileKeyValueStore(file: file).setString('alpha', 'one');

  final reloaded = FileKeyValueStore(file: file);
  expect(await reloaded.getString('alpha'), 'one');
});

test('recovers from malformed json on next write', () async {
  final dir = await Directory.systemTemp.createTemp('flowmuse_store_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/store.json');
  await file.writeAsString('{broken');

  final store = FileKeyValueStore(file: file);
  expect(await store.getString('missing'), isNull);
  await store.setString('alpha', 'one');

  expect(await FileKeyValueStore(file: file).getString('alpha'), 'one');
});

test('OHOS factory uses injected persistent directory', () async {
  final dir = await Directory.systemTemp.createTemp('flowmuse_store_test_');
  addTearDown(() => dir.delete(recursive: true));

  final store = createAppKeyValueStore(
    platform: TargetPlatform.ohos,
    ohosStorageDirectoryPath: dir.path,
  );
  await store.setString('alpha', 'one');

  final reloaded = createAppKeyValueStore(
    platform: TargetPlatform.ohos,
    ohosStorageDirectoryPath: dir.path,
  );
  expect(await reloaded.getString('alpha'), 'one');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test\shared\storage\file_key_value_store_test.dart`
Expected: FAIL because `file_key_value_store.dart` does not exist and `createAppKeyValueStore` does not accept OHOS test parameters.

- [ ] **Step 3: Implement minimal file store**

Create a JSON-backed `FileKeyValueStore`, split the existing storage base types into `app_key_value_store_base.dart`, and use a conditional OHOS factory so web/non-IO builds do not import `dart:io`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test\shared\storage\file_key_value_store_test.dart`
Expected: PASS.

### Task 2: Repository factories use OHOS persistent storage

**Files:**
- Modify: `FlowMuse-App/lib/features/library/repositories/library_repository.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/view_models/whiteboard_view_model.dart`
- Test: `FlowMuse-App/test/features/library/library_repository_persistence_test.dart`
- Test: `FlowMuse-App/test/features/whiteboard/whiteboard_scene_repository_persistence_test.dart`

**Interfaces:**
- Consumes: `createAppKeyValueStore({TargetPlatform? platform, String? ohosStorageDirectoryPath})`
- Produces: `createLibraryRepository({TargetPlatform? platform, String? ohosStorageDirectoryPath})`
- Produces: `createWhiteboardSceneRepository({TargetPlatform? platform, String? ohosStorageDirectoryPath})`

- [ ] **Step 1: Write the failing tests**

```dart
test('OHOS library repository persists notes across repository instances', () async {
  final dir = await Directory.systemTemp.createTemp('flowmuse_library_test_');
  addTearDown(() => dir.delete(recursive: true));

  final first = createLibraryRepository(
    platform: TargetPlatform.ohos,
    ohosStorageDirectoryPath: dir.path,
  );
  final note = await first.createNote();
  await first.renameNote(note.id, '持久化笔记');

  final second = createLibraryRepository(
    platform: TargetPlatform.ohos,
    ohosStorageDirectoryPath: dir.path,
  );
  final index = await second.loadIndex();
  expect(index.notes.single.title, '持久化笔记');
});

test('OHOS whiteboard repository persists scenes across repository instances', () async {
  final dir = await Directory.systemTemp.createTemp('flowmuse_scene_test_');
  addTearDown(() => dir.delete(recursive: true));

  final first = createWhiteboardSceneRepository(
    platform: TargetPlatform.ohos,
    ohosStorageDirectoryPath: dir.path,
  );
  await first.saveScene('note-1', '{"type":"excalidraw","elements":[1]}');

  final second = createWhiteboardSceneRepository(
    platform: TargetPlatform.ohos,
    ohosStorageDirectoryPath: dir.path,
  );
  expect(await second.loadScene('note-1'), '{"type":"excalidraw","elements":[1]}');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test\features\library\library_repository_persistence_test.dart test\features\whiteboard\whiteboard_scene_repository_persistence_test.dart`
Expected: FAIL because repository factory helpers do not exist.

- [ ] **Step 3: Implement repository factories**

Add `createLibraryRepository` and `createWhiteboardSceneRepository`. Providers call these helpers with default platform values. OHOS returns the existing repository classes backed by `createAppKeyValueStore`; non-OHOS behavior remains `SharedPreferences`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test\shared\storage\file_key_value_store_test.dart test\features\library\library_repository_persistence_test.dart test\features\whiteboard\whiteboard_scene_repository_persistence_test.dart`
Expected: PASS.

### Task 3: Final verification and commit

**Files:**
- Verify all files changed in Tasks 1 and 2.

- [ ] **Step 1: Analyze changed files**

Run: `dart analyze lib\shared\storage lib\features\library\repositories\library_repository.dart lib\features\whiteboard\repositories\whiteboard_scene_repository.dart lib\features\whiteboard\view_models\whiteboard_view_model.dart test\shared\storage\file_key_value_store_test.dart test\features\library\library_repository_persistence_test.dart test\features\whiteboard\whiteboard_scene_repository_persistence_test.dart`
Expected: `No issues found!`

- [ ] **Step 2: Run targeted tests**

Run: `flutter test test\shared\storage\file_key_value_store_test.dart test\features\library\library_repository_persistence_test.dart test\features\whiteboard\whiteboard_scene_repository_persistence_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-07-ohos-local-persistence-design.md docs/superpowers/plans/2026-07-07-ohos-local-persistence.md FlowMuse-App/lib/shared/storage FlowMuse-App/lib/features/library/repositories/library_repository.dart FlowMuse-App/lib/features/whiteboard/view_models/whiteboard_view_model.dart FlowMuse-App/test/shared/storage FlowMuse-App/test/features/library/library_repository_persistence_test.dart FlowMuse-App/test/features/whiteboard/whiteboard_scene_repository_persistence_test.dart
git commit -m "实现鸿蒙端本地持久化存储"
```

## Self-Review

- Spec coverage: the tasks cover OHOS key-value persistence, library repository persistence, whiteboard scene persistence, non-OHOS preservation, tests, analysis, and commit.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: factory names and parameters match between tasks.
