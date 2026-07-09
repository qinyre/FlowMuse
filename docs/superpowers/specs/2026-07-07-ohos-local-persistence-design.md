# OHOS Local Persistence Design

## Goal

Implement persistent local storage for the HarmonyOS target without changing the storage behavior of other platforms.

## Current State

The Flutter app already has an `AppKeyValueStore` abstraction. Non-OHOS platforms use `SharedPreferencesKeyValueStore`, but OHOS currently falls back to `InMemoryKeyValueStore`. The library index provider and whiteboard scene provider also special-case OHOS to in-memory repositories, so notes, notebooks, tags, scene content, theme settings, and guest names can be lost after app restart on HarmonyOS.

## Local HarmonyOS Guidance

The local HarmonyOS guides under `harmonyos-guides/应用框架/ArkData（方舟数据管理）/应用数据持久化/` describe three main persistence options:

- Preferences: lightweight key-value data, fast access, not suitable for large data, string values have size limits.
- KV Store: key-value business data, useful for distributed compatibility, but each value has a smaller size limit.
- RDB Store: relational data and complex queries.

The project currently needs a minimal durable local store and already models library and scene persistence as string key-value operations. A file-backed key-value store in the app sandbox is the smallest compatible step and avoids the current Flutter OHOS plugin registration issue around `shared_preferences`.

## Architecture

Add a native-Dart file-backed implementation of `AppKeyValueStore` for IO platforms. The store writes a JSON object to a single file, supports string keys and values, and performs atomic replace writes through a temporary file. It is only selected when `defaultTargetPlatform == TargetPlatform.ohos`; other platforms continue using `SharedPreferencesKeyValueStore`.

The OHOS library and whiteboard providers stop returning in-memory repositories. They instead use the same repository classes as other platforms, backed by the OHOS file key-value store.

## Storage Location

Production OHOS uses `/data/storage/el2/base/flowmuse/flowmuse_key_value_store.json`, matching HarmonyOS application sandbox guidance. Tests inject a temporary directory through factory parameters so they do not touch real device paths.

## Data Model

The persisted file contains a JSON object:

```json
{
  "flowmuse.library.index.v2": "{\"notes\":[],\"notebooks\":[],\"tags\":[]}",
  "note.excalidraw.scene.note-1": "{\"type\":\"excalidraw\",...}"
}
```

This preserves existing repository serialization and does not change collaboration payloads or Excalidraw/Markdraw scene formats.

## Error Handling

Missing files read as empty storage. Malformed JSON is treated as empty storage so app startup does not crash. The next successful write replaces the malformed file with a valid JSON object.

## Non-Goals

- Do not introduce ArkTS native Preferences bridge in this iteration.
- Do not migrate to RDB/KV Store.
- Do not change non-OHOS storage paths or semantics.
- Do not change sync protocol, whiteboard JSON format, or collaboration behavior.

## Verification

- Unit test `FileKeyValueStore` persists across instances.
- Unit test malformed storage recovery.
- Unit test OHOS key-value factory persists when given the same test directory.
- Unit test OHOS library repository persists notes across repository instances.
- Unit test OHOS whiteboard repository persists scene content across repository instances.
- Analyze changed storage/repository files.
